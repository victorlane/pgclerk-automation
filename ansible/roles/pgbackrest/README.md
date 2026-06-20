# pgbackrest

Install and configure [pgBackRest](https://pgbackrest.org/) for PostgreSQL on
EL8/EL9 hosts. Supports two repository modes that can be used independently
**or together** (best practice: a local server repo for fast restores plus an
offsite S3 repo for disaster recovery).

## Repository modes

| Mode     | Where backups live                             | Who initiates backup        |
|----------|------------------------------------------------|-----------------------------|
| `server` | Dedicated host in the `backup_servers` group   | Backup server (pull, via SSH) |
| `s3`     | S3-compatible bucket                           | PG primary (direct push)    |

Both are expressed as entries in `pgbackrest_repos`. The role emits
`repo1-*`, `repo2-*`, ... lines in `pgbackrest.conf` in list order, so any
combination is supported.

## Inventory groups

The role expects these inventory groups (only the ones you use are required):

- `postgres_servers` -- every PG node (primary + replicas).
- `postgres_primary` -- a single-host group naming the primary (optional, used
  to target stanza-create in `s3`-only mode and to order `pgN-*` entries).
- `backup_servers` -- one or more dedicated backup hosts. Only required when
  any repo has `type: server`.

## Defaults

| Variable                            | Default                          | Notes |
|-------------------------------------|----------------------------------|-------|
| `pgbackrest_stanza`                 | `main`                           | Logical cluster name. |
| `pgbackrest_repo_path`              | `/var/lib/pgbackrest`            | Default path for server repos. |
| `pgbackrest_log_path`               | `/var/log/pgbackrest`            | |
| `pgbackrest_spool_path`             | `/var/spool/pgbackrest`          | Async archive spool on PG nodes. |
| `pgbackrest_process_max`            | `2`                              | Parallel I/O processes. |
| `pgbackrest_repos`                  | `[]`                             | List of repo specs (see below). |
| `pgbackrest_manage_ssh_trust`       | `true`                           | Set up postgres-user SSH trust. |
| `pgbackrest_manage_archive_command` | `true`                           | Standalone only -- emits a warning under Patroni. |
| `pgbackrest_schedule`               | `true`                           | Install systemd timers on backup server. |
| `pgbackrest_schedule_full`          | `Sun *-*-* 02:00:00`             | OnCalendar for full backups. |
| `pgbackrest_schedule_diff`          | `Mon..Sat *-*-* 02:00:00`        | OnCalendar for diff backups. |

## Example configurations

### Server-only (dedicated backup host)

```yaml
# group_vars/all/pgbackrest.yml
pgbackrest_repos:
  - type: server
    host: backup-01.prod.example.com
    path: /var/lib/pgbackrest
    retention_full: 4
    retention_diff: 14
```

### S3-only

```yaml
pgbackrest_repos:
  - type: s3
    endpoint: s3.eu-west-1.amazonaws.com
    bucket: acme-postgres-backups
    region: eu-west-1
    key: "{{ pgbackrest_s3_key }}"
    key_secret: "{{ pgbackrest_s3_key_secret }}"
    path: /pgbackrest
    retention_full: 2
    retention_diff: 7
```

Real credentials belong in a separate `secrets.yml` (loaded via `-e @secrets.yml`)
or an external secret store, never in role defaults.

### Both at once (recommended)

```yaml
pgbackrest_repos:
  - type: server
    host: backup-01.prod.example.com
    retention_full: 2
    retention_diff: 7
  - type: s3
    endpoint: s3.eu-west-1.amazonaws.com
    bucket: acme-postgres-backups
    region: eu-west-1
    key: "{{ pgbackrest_s3_key }}"
    key_secret: "{{ pgbackrest_s3_key_secret }}"
    retention_full: 6
    retention_diff: 30
```

## Stanza initialization

The role runs `pgbackrest stanza-create` (idempotent) and `pgbackrest check`
automatically:

- For any `server`-type repo: from the backup server.
- For an `s3`-only configuration: from the primary PG node
  (`groups['postgres_primary']`, falling back to the first
  `postgres_servers` host).

## Manual cheat sheet

```bash
# Take an ad-hoc full backup (run as postgres on the host that owns the repo)
pgbackrest --stanza=main backup --type=full

# Take a diff backup
pgbackrest --stanza=main backup --type=diff

# List backups across all repos
pgbackrest --stanza=main info

# Restore in-place (DESTRUCTIVE -- PG must be stopped first)
systemctl stop postgresql-18
pgbackrest --stanza=main restore --delta

# Point-in-time restore
pgbackrest --stanza=main restore \
  --delta \
  --type=time \
  --target='2026-06-15 14:30:00+00'
```

## Patroni interop

When `postgresql_ha_mode == 'patroni'` this role will NOT touch
`postgresql.conf` -- Patroni owns it via DCS. The role prints the parameters
you need and exits the PG-config step cleanly. Add them to your Patroni
configuration:

```yaml
bootstrap:
  dcs:
    postgresql:
      parameters:
        archive_mode: 'on'
        archive_command: "pgbackrest --stanza=main archive-push %p"
        archive_timeout: 60
        wal_level: replica
        max_wal_senders: 10
```

For a running cluster, apply with `patronictl edit-config` and reload.

## What this role deliberately does NOT do

- Restore. Restore is an out-of-band operation -- see the cheat sheet above.
- Manage backup credentials in defaults. S3 keys must come from inventory.
- Touch the `postgresql` or `patroni` roles.
- Configure firewalling for the SSH/S3 paths -- handle that via the
  `os_baseline` wrapper role's `firewall_rules` pass-through.
