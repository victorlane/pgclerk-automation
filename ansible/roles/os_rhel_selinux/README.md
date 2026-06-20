# selinux

SELinux helpers: optional mode change, persistent file contexts with
`restorecon` on change, and persistent booleans. Always installs the
Python bindings needed by `sefcontext` and `seboolean`. No-op when
SELinux is `disabled`.

## Variables

| Variable | Type | Default | Meaning |
|---|---|---|---|
| `selinux_state` | string | `""` | One of `enforcing`, `permissive`, `disabled`. Empty leaves the mode alone. |
| `selinux_fcontexts` | list[dict] | `[]` | Each `{ target: regex, setype: type, state: present\|absent (default present) }`. Triggers `restorecon -Rv` on the directory prefix when changed. |
| `selinux_booleans` | dict | `{}` | `name: on/off` pairs applied persistently. |

## Usage

```yaml
- hosts: db
  become: true
  roles:
  - role: selinux
    vars:
      selinux_fcontexts:
      - { target: "/var/lib/pgsql/16/data(/.*)?", setype: postgresql_db_t }
      - { target: "/var/log/postgresql(/.*)?",   setype: postgresql_log_t }
      selinux_booleans:
        httpd_can_network_connect: on
```
