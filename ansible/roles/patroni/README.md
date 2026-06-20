# patroni

## Purpose

Deploys [Patroni](https://patroni.readthedocs.io/) 3.x on top of a PostgreSQL
installation produced by the sibling `postgresql` role. Patroni takes
ownership of `initdb`, `postgresql.conf`, `pg_hba.conf`, and the systemd
unit; the PGDG `postgresql-<version>.service` is masked so it cannot race
Patroni for `PGDATA`. The role assumes an etcd quorum is reachable on
port 2379 (plaintext) at the hosts in `groups[patroni_dcs_inventory_group]`.

## Topology

```
postgres_primary[0]     -- bootstraps the cluster (writes /service/<scope>/initialize)
postgres_replicas[*]    -- clone via pg_basebackup once they see a leader
patroni_dcs_inventory_group -- etcd quorum (embedded on PG hosts, or external)
```

Bootstrap ordering is the consumer's responsibility -- run the play with
`serial: 1` (or at least primary-first) for the very first run so the
leader exists in DCS before replicas try to clone. After bootstrap, the
order no longer matters; Patroni re-elects on its own.

For an external etcd, set `patroni_dcs_inventory_group: etcd_servers` and
populate that group in inventory.

## Sync vs async replication

| Mode                                                                       | `patroni_synchronous_mode` | `patroni_synchronous_mode_strict` |
|----------------------------------------------------------------------------|----------------------------|------------------------------------|
| Async (default) -- best availability, possible data loss on failover       | `false`                    | `false`                            |
| Sync, fall back to async if no replica is healthy -- balanced              | `true`                     | `false`                            |
| Strict sync -- refuse writes when no sync standby is up (RTO over RPO=0)   | `true`                     | `true`                             |

Switch with a single var; no `initdb` rerun is needed because Patroni
applies these through the DCS.

## Data-loss budget preset

Setting the three sync knobs by hand (`patroni_synchronous_mode`,
`patroni_synchronous_mode_strict`, `patroni_max_lag_on_failover`)
forces every operator to re-derive the same trade-off from first
principles. The `patroni_data_loss_budget` var packages four named
opinions so the conversation can be "what's our data-loss budget?"
instead of "which lag threshold pairs with strict sync?".

| Budget    | `synchronous_mode` | `synchronous_mode_strict` | `maximum_lag_on_failover` | Plain English                                                                                                                                              |
|-----------|--------------------|---------------------------|---------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `none`    | `false`            | `false`                   | `1048576` (1 MiB)         | **Default.** Async streaming. Maximum throughput. Possible (small) data loss on autofailover if the new leader was lagging when the old one died.          |
| `minimal` | `true`             | `false`                   | `1048576` (1 MiB)         | Sync when a healthy replica is available; falls back to async if all replicas are offline. Catches most failover data loss without write-stalling the primary when nobody can ack. |
| `low`     | `true`             | `false`                   | `16384`   (16 KiB)        | Same as `minimal` plus a tight lag ceiling -- failover only considers near-zero-lag replicas. Fewer eligible candidates means longer failover when the closest replica is also down. |
| `zero`    | `true`             | `true`                    | `0`                       | RPO=0 in the failover window. Primary REFUSES writes when no sync standby is healthy -- a sync standby outage IS a write outage. Use only when the business has explicitly chosen RTO over RPO. |

How to pick:

- **Web/SaaS, multi-tenant, "best-effort durability"** -> `none`.
  Async is fine; backups are the durability story, not sync replication.
- **Customer-facing transactional workload, "small data loss is bad
  but the business won't accept write outages"** -> `minimal`.
  Sync when we can, async when we can't.
- **Regulated workload, "we don't want to lose more than the last
  16 KiB of WAL"** -> `low`.
- **RPO=0 contractual obligation, "we accept write outages to
  preserve durability"** -> `zero`.

The preset overrides the individual knobs at task-run scope. If you
need to deviate from a preset on one knob, set
`patroni_data_loss_budget: none` and configure the three knobs by
hand.

## Variables

| Variable                              | Default                | Notes                                                              |
|---------------------------------------|------------------------|--------------------------------------------------------------------|
| `patroni_version`                     | `3.3.2`                | Pip-installed into `patroni_venv`                                  |
| `patroni_scope`                       | `pgclerk`            | etcd key prefix; one cluster per scope                             |
| `patroni_dcs_inventory_group`         | `postgres_servers`     | Group whose members run etcd                                       |
| `patroni_synchronous_mode`            | `false`                | See table above                                                    |
| `patroni_synchronous_mode_strict`     | `false`                | Only honored when sync mode is on                                  |
| `patroni_data_loss_budget`            | `none`                 | `none` / `minimal` / `low` / `zero` -- preset over the three knobs |
| `patroni_venv`                        | `/opt/patroni/venv`    | Virtualenv root                                                    |
| `patroni_admin_password`              | `changeme-admin`       | Patroni-managed superuser bootstrap                                |
| `patroni_replicator_password`         | `changeme-replicator`  | Streaming-replication account                                      |
| `patroni_superuser_password`          | `changeme-superuser`   | Patroni-internal `postgres` superuser                              |
| `patroni_rewind_password`             | `changeme-rewind`      | Used by `pg_rewind` after failover                                 |
| `patroni_restapi_port`                | `8008`                 | `patronictl`, HAProxy, monitoring all hit this                     |
| `patroni_replication_cidr`            | `10.0.0.0/8`           | Allowed source CIDR for `host replication replicator ... md5`      |
| `patroni_ttl`                         | `30`                   | Leader-lock TTL in seconds                                         |
| `patroni_loop_wait`                   | `10`                   | Patroni HA loop interval                                           |
| `patroni_retry_timeout`               | `10`                   | DCS retry budget                                                   |
| `patroni_max_lag_on_failover`         | `1048576`              | Bytes of lag past which a replica is ineligible                    |
| `patroni_wait_for_cluster_retries`    | `30`                   | Primary-only post-bootstrap poll count                             |
| `patroni_wait_for_cluster_delay`      | `10`                   | Seconds between polls                                              |

Override the `changeme-*` passwords before any non-dev deploy.

## Maintenance cheat-sheet

```bash
# Cluster state
patronictl -c /etc/patroni/patroni.yml list

# Controlled, planned handover (no data loss when sync mode is on)
patronictl -c /etc/patroni/patroni.yml switchover

# Forced failover (use when the leader is unreachable)
patronictl -c /etc/patroni/patroni.yml failover

# Restart a member (e.g. after changing GUCs that require it)
patronictl -c /etc/patroni/patroni.yml restart <cluster> <member>

# Rebuild a replica from scratch
patronictl -c /etc/patroni/patroni.yml reinit <cluster> <replica>
```

## Why `postgresql-<version>.service` is masked

PGDG packages enable their own systemd unit by default. If left enabled,
two things race for `PGDATA`: Patroni's own `pg_ctl` invocations and
systemd's. The result is at best a startup loop and at worst data
corruption. This role explicitly `disabled` *and* `masked` the unit --
`masked` is what prevents a future `systemctl enable postgresql-18` from
silently re-arming the race condition. Patroni is the sole entry point for
controlling Postgres on these hosts; use `patronictl` (or `systemctl
restart patroni`) and never `systemctl start postgresql-*`.
