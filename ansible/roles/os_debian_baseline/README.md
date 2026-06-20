# baseline

OS baseline for a database host: timezone, chrony, sysctl tuning, ulimits,
THP defrag disable, and optional `/etc/hosts` hygiene. Debian-family build;
shares the variable shape of [`os_rhel_baseline`](../os_rhel_baseline)
with apt + Debian paths underneath.

## Variables

| Variable | Type | Default | Meaning |
|---|---|---|---|
| `baseline_timezone` | string | `UTC` | Passed to `timedatectl`. |
| `baseline_chrony_servers` | list[str] | `[]` | NTP servers. Empty leaves the distro `/etc/chrony/chrony.conf` untouched. |
| `baseline_chrony_pools` | list[str] | `[]` | NTP pools (e.g. `pool.ntp.org`). |
| `baseline_chrony_options` | list[str] | `['iburst']` | Per-server/pool options. |
| `baseline_sysctl_defaults` | dict | DB-friendly defaults | Built-in defaults; do not edit. |
| `baseline_sysctl` | dict | `{}` | Overrides merged on top of `baseline_sysctl_defaults`. |
| `baseline_sysctl_file` | string | `/etc/sysctl.d/90-pgclerk.conf` | Where to write sysctls. |
| `baseline_db_user` | string | `postgres` | Owner of the ulimits drop-in. |
| `baseline_limits` | list[dict] | nofile=65536, nproc=4096 | `pam_limits` entries. |
| `baseline_disable_thp` | bool | `true` | Install + enable `disable-thp.service`. |
| `baseline_manage_hosts` | bool | `false` | If true, ensure FQDN line in `/etc/hosts`. |
| `baseline_hosts_ip` | string | `ansible_default_ipv4.address` | IP for the FQDN entry. |
| `baseline_hosts_fqdn` | string | `ansible_fqdn` | FQDN to anchor. |
| `baseline_hosts_aliases` | list[str] | `[]` | Extra aliases on the FQDN line. |

## Usage

```yaml
- hosts: db
  become: true
  roles:
  - role: baseline
    vars:
      baseline_timezone: Europe/Amsterdam
      baseline_chrony_servers: [10.0.0.1, 10.0.0.2]
      baseline_sysctl: { vm.swappiness: 5 }
```
