# node_exporter

Installs and configures `prometheus-node-exporter` (the prometheus project
host-level exporter) on RHEL 8/9, Amazon Linux 2023, and Debian/Ubuntu. Runs as
a dedicated `node_exporter` system user listening on `127.0.0.1:9100` by
default, with the textfile collector pointed at
`/var/lib/node_exporter/textfile_collector` so custom scripts can drop `.prom`
files in. Pair with any other role on the same host; scraping is wired up
elsewhere.

## Per-OS install paths

- **RHEL 8/9** -- `prometheus-node-exporter` from EPEL or pgdg-common,
  binary at `/usr/bin/node_exporter`.
- **Debian / Ubuntu** -- `prometheus-node-exporter` from main, binary at
  `/usr/bin/prometheus-node-exporter`. The role disables the package's
  shipped systemd unit and lays down its own.
- **Amazon Linux 2023** -- upstream tarball from the GitHub release at the
  pinned `node_exporter_version`, extracted to
  `/opt/node_exporter-<ver>/`, symlinked to `/usr/local/bin/node_exporter`.

Set `node_exporter_install_from_tarball: true` to force the tarball path on
RHEL/Debian too.

## Variables

| Name | Type | Default | Meaning |
|------|------|---------|---------|
| `node_exporter_version` | string | `1.8.2` | Upstream version. Tarball-only platforms always honour this. |
| `node_exporter_install_from_tarball` | bool | `false` | Force the tarball install path on RHEL/Debian. |
| `node_exporter_listen_address` | string | `127.0.0.1:9100` | host:port the exporter binds to. |
| `node_exporter_user` | string | `node_exporter` | System user the exporter runs as. |
| `node_exporter_group` | string | `node_exporter` | System group. |
| `node_exporter_install_dir` | path | `/opt/node_exporter-<ver>` | Tarball install dir. |
| `node_exporter_bin_path` | path | `/usr/local/bin/node_exporter` | Symlink for tarball installs. |
| `node_exporter_textfile_dir` | path | `/var/lib/node_exporter/textfile_collector` | Textfile collector directory. Mode 0775. |
| `node_exporter_enable_textfile_collector` | bool | `true` | Toggle the textfile collector and its directory. |
| `node_exporter_extra_flags` | list | `[]` | Extra CLI flags appended to ExecStart (e.g. `--collector.systemd`). |

## Usage

```yaml
- hosts: postgres_servers
  become: true
  roles:
  - role: node_exporter
```

Expose the exporter to a remote scraper by overriding the listen address and
opening the firewall via the `os_baseline` wrapper:

```yaml
- hosts: postgres_servers
  become: true
  vars:
    node_exporter_listen_address: "0.0.0.0:9100"
  roles:
  - role: os_baseline
    vars:
      os_baseline_firewall_rules:
      - { port: 9100, sources: ['10.0.0.0/8'] }
  - role: node_exporter
```

## Textfile collector

Sidecar scripts (cron, systemd timers, anything) can drop `<name>.prom` files
into `/var/lib/node_exporter/textfile_collector` and node_exporter will scrape
them on the next request:

```sh
sudo -u root tee /var/lib/node_exporter/textfile_collector/example.prom <<EOF
# HELP my_custom_metric Example metric
# TYPE my_custom_metric gauge
my_custom_metric 42
EOF
```

Mode 0775 + group `node_exporter` keeps it writable by anyone in that group
without requiring root for routine drops.

## Manual operations

```sh
systemctl status node_exporter
systemctl restart node_exporter
journalctl -u node_exporter -e

curl -s http://127.0.0.1:9100/metrics | head -40
curl -sS http://127.0.0.1:9100/metrics | grep '^node_textfile_scrape_error'
```

## Notes

- The role does **not** open the firewall. Use `os_baseline_firewall_rules` in
  the consumer play if the exporter must be reachable off-box.
- The role does **not** wire up scraping. Add the Prometheus/Alloy scrape
  config in a separate layer.
