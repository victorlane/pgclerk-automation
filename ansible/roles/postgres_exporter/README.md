# postgres_exporter

Installs and configures `prometheus-postgres-exporter` (the prometheus-community
exporter) on RHEL 8/9, Amazon Linux 2023, and Debian/Ubuntu. Creates a dedicated
SQL role with `pg_monitor` + `pg_read_all_stats`, connects via the local Unix
socket, and listens on `127.0.0.1:9187` by default. Pair with the `postgresql`
role on the same host; scraping is wired up elsewhere (Alloy / Grafana Agent /
Prometheus).

## Per-OS install paths

- **RHEL 8/9** -- `prometheus-postgres-exporter` from PGDG (same repo the
  `postgresql` role configures), binary at `/usr/bin/postgres_exporter`.
- **Debian / Ubuntu** -- `prometheus-postgres-exporter` from main, binary at
  `/usr/bin/prometheus-postgres-exporter`. The role disables the package's
  shipped systemd unit and lays down its own.
- **Amazon Linux 2023** -- upstream tarball from the GitHub release at the
  pinned `postgres_exporter_version`, extracted to
  `/opt/postgres_exporter-<ver>/`, symlinked to `/usr/local/bin/postgres_exporter`.

Set `postgres_exporter_install_from_tarball: true` to force the tarball path on
RHEL/Debian too (useful when the distro package lags upstream).

## Variables

| Name | Type | Default | Meaning |
|------|------|---------|---------|
| `postgres_exporter_version` | string | `0.15.0` | Upstream version. Tarball-only platforms always honour this. |
| `postgres_exporter_install_from_tarball` | bool | `false` | Force the tarball install path on RHEL/Debian. |
| `postgres_exporter_listen_address` | string | `127.0.0.1:9187` | host:port the exporter binds to. |
| `postgres_exporter_user` | string | `postgres_exporter` | System user the exporter runs as. |
| `postgres_exporter_group` | string | `postgres_exporter` | System group. |
| `postgres_exporter_install_dir` | path | `/opt/postgres_exporter-<ver>` | Tarball install dir. |
| `postgres_exporter_bin_path` | path | `/usr/local/bin/postgres_exporter` | Symlink for tarball installs. |
| `postgres_exporter_config_dir` | path | `/etc/postgres_exporter` | Holds the env file. |
| `postgres_exporter_env_file` | path | `<config_dir>/postgres_exporter.env` | EnvironmentFile= for the unit. Mode 0640. |
| `postgres_exporter_sql_role` | string | `postgres_exporter` | PostgreSQL role the exporter logs in as. |
| `postgres_exporter_password` | string | `changeme-exporter` | Password for the SQL role. **Override in production.** |
| `postgres_exporter_data_source_name` | string | derived | libpq DSN. Defaults to Unix socket on `/var/run/postgresql`. |
| `postgres_exporter_extra_flags` | list | `[]` | Extra CLI flags appended to ExecStart. |

## Usage

```yaml
- hosts: postgres_servers
  become: true
  vars:
    postgres_exporter_password: "{{ pg_exporter_password }}"  # from secrets.yml
  roles:
  - role: postgresql
  - role: postgres_exporter
```

Expose the exporter to a remote scraper by overriding the listen address and
opening the firewall via the `os_baseline` wrapper:

```yaml
- hosts: postgres_servers
  become: true
  vars:
    postgres_exporter_listen_address: "0.0.0.0:9187"
  roles:
  - role: os_baseline
    vars:
      os_baseline_firewall_rules:
      - { port: 9187, sources: ['10.0.0.0/8'] }
  - role: postgresql
  - role: postgres_exporter
```

## Manual operations

```sh
systemctl status postgres_exporter
systemctl restart postgres_exporter
journalctl -u postgres_exporter -e

curl -s http://127.0.0.1:9187/metrics | head -40
curl -sS http://127.0.0.1:9187/metrics | grep '^pg_up'

# Verify the SQL role works without using the exporter:
sudo -u postgres psql -c "\du postgres_exporter"
PGPASSWORD=... psql -h /var/run/postgresql -U postgres_exporter postgres -c "SELECT 1"
```

## Notes

- The role does **not** open the firewall. Use `os_baseline_firewall_rules` in
  the consumer play if the exporter must be reachable off-box.
- `pg_stat_statements` query metrics require the extension to be loaded in
  `shared_preload_libraries` (the `postgresql` role does this by default) and
  `CREATE EXTENSION pg_stat_statements` in each target database. Loading is
  sufficient for cluster-wide views; per-DB stats need the extension in that DB.
- The role does **not** wire up scraping. Add the Prometheus/Alloy scrape
  config in a separate layer.
