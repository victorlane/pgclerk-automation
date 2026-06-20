# os_baseline

OS-family-agnostic baseline wrapper. Includes the right `os_rhel_*` or
`os_debian_*` roles for each host based on `ansible_facts['os_family']`,
so the consumer's play stays clean and uniform across mixed-OS inventories.

## Variables

All `os_baseline_*` vars are pass-throughs to the underlying per-family roles.

| Name                            | Type | Default | Forwards to                                |
|---------------------------------|------|---------|--------------------------------------------|
| `os_baseline_packages_extra`    | list | `[]`    | `packages_extra` of the family's packages role |
| `os_baseline_firewall_rules`    | list | `[]`    | `firewall_rules`                            |
| `os_baseline_firewall_services` | list | `[]`    | `firewall_services`                         |
| `os_baseline_selinux_fcontexts` | list | `[]`    | `selinux_fcontexts` (no-op on Debian)       |
| `os_baseline_selinux_booleans`  | dict | `{}`    | `selinux_booleans` (no-op on Debian)        |

## Usage

```yaml
- hosts: postgres_servers
  become: true
  roles:
  - role: os_baseline
    vars:
      os_baseline_firewall_rules:
      - { port: 5432, sources: ['10.0.0.0/8'] }
      os_baseline_selinux_fcontexts:
      - { target: "/u01/app/postgres(/.*)?", setype: postgresql_db_t }
```

On RHEL family the selinux entries take effect; on Debian they are simply
not forwarded by the wrapper (the os_debian_selinux role exits cleanly).
