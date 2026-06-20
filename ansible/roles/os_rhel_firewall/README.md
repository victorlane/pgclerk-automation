# firewall

firewalld wrapper. Detects whether firewalld is active and, if so, opens
named services and port rules (with optional source-CIDR restrictions).
If firewalld is not active the role is a no-op via `meta: end_host`-equivalent
short-circuit on the loop guards.

## Variables

| Variable | Type | Default | Meaning |
|---|---|---|---|
| `firewall_rules` | list[dict] | `[]` | Port rules. Each item: `{ port, protocol (default tcp), sources (default ['0.0.0.0/0']), zone (default firewall_default_zone) }`. |
| `firewall_services` | list[str] | `[]` | Named firewalld services to open (e.g. `ssh`, `http`). |
| `firewall_default_zone` | string | `public` | Zone applied when a rule does not specify one. |

## Usage

```yaml
- hosts: db
  become: true
  roles:
  - role: firewall
    vars:
      firewall_services: [ssh]
      firewall_rules:
      - port: 5432
        sources: [10.0.0.0/8, 192.168.10.0/24]
      - port: 9100
        sources: [10.0.50.0/24]
```
