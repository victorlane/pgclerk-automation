# postgresql

## Purpose

Installs PostgreSQL (15 / 16 / 17 / 18) from PGDG (RHEL/Debian) or the
native AL2023 repo on Amazon Linux, renders `postgresql.conf` and
`pg_hba.conf`, provisions databases / roles, and -- when explicitly
invoked -- derives memory, WAL, I/O, autovacuum, and parallelism knobs
from on-host discovery.

In `postgresql_ha_mode: patroni`, the role stops after package install
and locale setup: Patroni owns config, `initdb`, and the systemd unit
from that point on. In `standalone` the role owns the lot.

## Autotune

Autotune is **imperative-only**. It never runs on a normal `site.yml`
invocation because changing memory or WAL settings on a live cluster
is a DBA decision that may require a restart. Two entry points:

```sh
# Dedicated playbook (preferred -- refuses to run without --limit)
ansible-playbook ansible/playbooks/maintenance/autotune.yml --limit pg-1

# Or the role's own tag (equivalent)
ansible-playbook site.yml --tags autotune --limit pg-1
```

Both paths set `postgresql_autotune=true`, run `tasks/autotune.yml`,
re-render `postgresql.conf`, and -- if the cluster is up -- issue
`pg_reload_conf()`. Restart-required keys (e.g. `shared_buffers`,
`huge_pages`) surface a DBA notice; the role does **not** restart on
its own.

### What gets discovered automatically

| Fact                       | Source                                                         |
|----------------------------|----------------------------------------------------------------|
| vCPUs / RAM / architecture | `ansible_facts` (memtotal_mb, processor_vcpus, architecture)   |
| Cloud provider             | `/sys/class/dmi/id/sys_vendor` (Amazon / Google / Microsoft)   |
| Data-dir mountpoint        | `findmnt -T <postgresql_data_dir>`                             |
| Backing block device       | `lsblk -no PKNAME <source>` (walks LVM / partitions to parent) |
| Storage class              | NVMe via device-name prefix, SSD/HDD via `/sys/block/<dev>/queue/rotational` |
| PostgreSQL major           | `postgresql_version` (string -> int)                           |

You don't pass IOPS or throughput -- they aren't on the host (the
cloud API knows, the kernel doesn't), and the derived ceilings
(`effective_io_concurrency=256` NVMe / `200` SSD / `2` HDD) already
cap usefully. Override `postgresql_storage_class` only when the
detection is wrong (e.g. RAID-on-HDD reporting non-rotational).

### Workload profile

`postgresql_workload_profile` shifts `work_mem`, parallelism, and
`default_statistics_target`:

| Profile | When                                                                                   | Effect                                                |
|---------|----------------------------------------------------------------------------------------|-------------------------------------------------------|
| `oltp`  | Many short-lived connections, lots of small transactions (SaaS, web)                   | Smaller `work_mem`, modest parallelism                |
| `mixed` | The safe middle ground -- the default                                                  | Balanced                                              |
| `dw`    | Few long analytical queries, batch jobs                                                | Larger `work_mem`, bigger `default_statistics_target`, more parallel workers per gather |

### Safe knobs applied by default

These are well-understood, low-risk improvements over PG's stock
defaults on a dedicated MSP-managed host. All are derived; any can be
overridden by setting `postgresql_<knob>` explicitly.

| Knob                                  | Value                                                                     |
|---------------------------------------|---------------------------------------------------------------------------|
| `shared_buffers`                      | 25% RAM, capped at 40 GB                                                  |
| `effective_cache_size`                | 75% RAM (planner hint, not allocation)                                    |
| `maintenance_work_mem`                | 5% RAM, capped at 2 GB                                                    |
| `work_mem`                            | (free RAM) / (`max_connections` * 6/3/2 for oltp/mixed/dw)                |
| `wal_buffers`                         | `shared_buffers` / 32, capped at 16 MB                                    |
| `min_wal_size` / `max_wal_size`       | `RAM/16` clamped 2-16 GB (32 GB ceiling on NVMe)                          |
| `max_slot_wal_keep_size`              | 2 * `max_wal_size` (stops a dead slot from filling the WAL volume)        |
| `checkpoint_completion_target`        | 0.9                                                                       |
| `random_page_cost`                    | 1.05 (NVMe) / 1.1 (SSD) / 4.0 (HDD)                                       |
| `effective_io_concurrency`            | 256 / 200 / 2                                                             |
| `maintenance_io_concurrency` (PG13+)  | 64 / 50 / 2 (lower than `effective_io_concurrency` so VACUUM can't starve queries) |
| `default_statistics_target`           | 100 (oltp/mixed) / 500 (dw)                                               |
| `max_worker_processes`                | vCPUs                                                                     |
| `max_parallel_workers`                | vCPUs                                                                     |
| `max_parallel_workers_per_gather`     | min(vCPU/2, 4) for oltp/mixed; min(vCPU/2, 8) for dw                      |
| `max_parallel_maintenance_workers`    | min(vCPU/2, 4)                                                            |
| `huge_pages`                          | `try` (use them when reserved, otherwise fall back -- never break start)  |
| `jit` (PG12+)                         | `on` (PG default, made explicit)                                          |
| `wal_compression`                     | `lz4` on PG15+, `on` (pglz) on PG13/14, `off` below                       |
| `track_io_timing`                     | `on` (cheap on modern kernels, needed for pg_stat_statements I/O columns) |
| `autovacuum_vacuum_cost_limit`        | 2000 on SSD/NVMe (default 200 throttles vacuum on busy SSD-backed tables) |
| `autovacuum_naptime`                  | 30s on >=16 vCPU, 60s otherwise                                           |
| `log_autovacuum_min_duration`         | 1000ms                                                                    |
| `idle_in_transaction_session_timeout` | 10min (idle txns block VACUUM and wedge replicas via `hot_standby_feedback`) |
| `bgwriter_lru_maxpages`               | 1000 on SSD/NVMe, 100 otherwise                                           |
| `bgwriter_delay`                      | 100ms on SSD/NVMe, 200ms otherwise                                        |
| `hot_standby_feedback`                | `on` when `postgresql_ha_mode == patroni`, `off` otherwise                |

### Experimental knobs (reported, NOT applied)

Each autotune run prints an "EXPERIMENTAL CANDIDATES" section listing
knobs the host is eligible for, with the recommended value and a
short reason. Nothing is written to `postgresql.conf` unless the
operator opts in by slug.

```yaml
# In group_vars / host_vars / -e extra-vars
postgresql_experimental_enabled:
  - jit_above_cost              # Lower it for DW-style plans
  - recovery_prefetch           # PG15+: replica replay prefetch
  - enable_partitionwise_join   # Big win on partitioned schemas
```

Recognised slugs:

| Slug                              | Recommended value                   | PG min | What it does                                                                                          |
|-----------------------------------|-------------------------------------|--------|-------------------------------------------------------------------------------------------------------|
| `jit_above_cost`                  | `50000` (dw) / `100000` (others)    | 12     | Lower threshold surfaces JIT for medium-cost analytical plans. Helps DW, can pessimise OLTP.          |
| `parallel_leader_participation`   | `off`                               | 11     | Frees the leader to merge worker results. Analytics win, OLTP loss.                                   |
| `enable_partitionwise_join`       | `on`                                | 11     | Large planner win on partitioned schemas. Planner cost grows with partition count.                    |
| `enable_partitionwise_aggregate`  | `on`                                | 11     | Same family as partitionwise_join, slightly more planner work, similar pay-off for analytic GROUP BY. |
| `recovery_prefetch`               | `try`                               | 15     | Replica replay prefetches referenced pages using `effective_io_concurrency`. Big win on async replicas behind a write-heavy primary. |
| `io_method`                       | `worker`                            | 18     | Async I/O. Moves I/O submission off backends to dedicated workers -- improves tail latency on bursty workloads. |
| `checkpoint_flush_after`          | `256kB`                             | 9      | Asks the kernel to flush dirty writeback every 256 kB during a checkpoint -- smoother I/O on busy hosts. |
| `backend_flush_after`             | `512kB`                             | 9      | Per-backend variant for large bulk writes (COPY, CREATE INDEX). Rarely needed when bgwriter is tuned. |
| `wal_init_zero`                   | `off`                               | 12     | Skip pre-zeroing of new WAL segments. **Only safe on CoW filesystems (ZFS, btrfs).**                  |

The version filter is enforced in the template: an opt-in slug that
the running PG major doesn't support is silently skipped. The
tuning-summary line still appears so the operator sees that the
host is on too-old a major.

### Reading the tuning summary

```
============================================================
PG autotune  host=pg-1
             cloud=aws  arch=x86_64  vCPU=8  RAM=32768MB
             data_dir=/var/lib/pgsql/18/data
             device=/dev/nvme1n1  fstype=xfs
             storage_class=nvme  (operator override: no -- autodetected)
             profile=mixed  ha=patroni  pg=18
------------------------------------------------------------
APPLIED -- safe knobs
  shared_buffers                     = 8192MB
  ...
------------------------------------------------------------
EXPERIMENTAL CANDIDATES (NOT applied -- opt in via postgresql_experimental_enabled)
  - jit_above_cost = 100000
    Lower jit_above_cost surfaces JIT for medium-cost analytical plans. ...
  - recovery_prefetch = try   [APPLIED]
    Replica replay prefetches referenced pages using effective_io_concurrency. ...
============================================================
```

The `[APPLIED]` marker tags experimental slugs the operator has
already opted into.

## Managed branches

`playbooks/maintenance/autotune.yml` also handles RDS, Aurora,
Cloud SQL, and AlloyDB. The autotune math is the same; only the
push mechanism differs:

| Topology         | How values are pushed                                                                                                    |
|------------------|--------------------------------------------------------------------------------------------------------------------------|
| `aws-rds`        | `amazon.aws.rds_instance_param_group` -- static keys apply on next reboot                                                |
| `aws-aurora`     | `amazon.aws.rds_cluster_param_group` -- same reboot story                                                                |
| `cloudsql`       | `gcloud sql instances patch --database-flags ... --async`                                                                |
| `alloydb`        | `gcloud alloydb instances update --database-flags ...`                                                                   |

The managed branches never auto-reboot. The playbook surfaces a DBA
notice telling the operator how to schedule one through the
maintenance window or the cloud CLI.

## Variables (selected -- see `defaults/main.yml` for the full list)

| Variable                                    | Default            | Notes                                                       |
|---------------------------------------------|--------------------|-------------------------------------------------------------|
| `postgresql_version`                        | `"18"`             | One of 15 / 16 / 17 / 18                                    |
| `postgresql_ha_mode`                        | `standalone`       | `standalone` or `patroni`                                   |
| `postgresql_workload_profile`               | `mixed`            | `oltp` / `mixed` / `dw`                                     |
| `postgresql_storage_class`                  | `""` (autodetect)  | `""` / `nvme` / `ssd` / `hdd` -- override only when wrong   |
| `postgresql_autotune`                       | `false`            | Flipped to `true` by the autotune entry points              |
| `postgresql_experimental_enabled`           | `[]`               | List of experimental slugs to apply -- see table above      |
| `postgresql_<knob>`                         | `""`               | Explicit override for any autotuned knob; empty = autotuned |
| `postgresql_pgaudit_enabled`                | `false`            | When true, installs the per-major `pgaudit` package and adds it to `shared_preload_libraries` |
| `postgresql_apply_hardened_template`        | `false`            | Provisions a REVOKE-on-public template DB                   |

## Knob precedence

```
explicit postgresql_<knob>  >  autotune-derived value  >  empty (PG default)
```

Empty values cause the template to omit the line entirely, so PG
falls back to its own default. This means: removing an explicit
override does NOT immediately restore the autotuned value -- you
need to re-run autotune so the empty slot gets re-derived.
