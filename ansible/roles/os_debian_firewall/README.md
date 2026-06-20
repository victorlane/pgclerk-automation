# firewall

ufw wrapper. Mirrors the variable shape of [`os_rhel_firewall`](../os_rhel_firewall).
Detects whether ufw is installed (optionally installing it) and, if so,
opens application profiles and port rules with optional source-CIDR
restrictions. If ufw is not present and `firewall_enable_ufw` is `false`,
the role is a no-op.

## Variables

| Variable | Type | Default | Meaning |
|---|---|---|---|
| `firewall_enable_ufw` | bool | `false` | If true, install the `ufw` package before configuring. |
| `firewall_ufw_default_incoming` | string | `deny` | Default incoming policy when ufw is active. |
| `firewall_ufw_default_outgoing` | string | `allow` | Default outgoing policy when ufw is active. |
| `firewall_ufw_logging` | string | `low` | ufw logging level (`off`, `low`, `medium`, `high`, `full`). |
| `firewall_rules` | list[dict] | `[]` | Port rules. Each item: `{ port, protocol (default tcp), sources (default ['any']) }`. |
| `firewall_services` | list[str] | `[]` | Named ufw application profiles to allow (e.g. `OpenSSH`). |

## Usage

```yaml
- hosts: db
  become: true
  roles:
  - role: firewall
    vars:
      firewall_enable_ufw: true
      firewall_services: [OpenSSH]
      firewall_rules:
      - port: 5432
        sources: [10.0.0.0/8, 192.168.10.0/24]
      - port: 9100
        sources: [10.0.50.0/24]
```

## Note on `sources`

For parity with the RHEL role, leave `sources` at its default to mean "any
source" (no CIDR restriction). The RHEL role uses `['0.0.0.0/0']` for this
sentinel because firewalld doesn't have a wildcard; here we use the more
ufw-natural `['any']`.
