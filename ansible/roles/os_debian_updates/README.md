# updates

Manage OS package updates on Debian-family hosts. Two modes:

- `manual` (default): role is a no-op on a normal run. A maintenance playbook
  invokes `tasks/run-now.yml` to apply updates on demand via `apt-get
  upgrade` (or `unattended-upgrade -v` for the security-only scope).
- `automatic`: installs `unattended-upgrades`, deploys
  `/etc/apt/apt.conf.d/50unattended-upgrades`, enables
  `apt.conf.d/20auto-upgrades`, and overrides the
  `apt-daily-upgrade.timer` schedule.

## Variables

| Name                          | Type    | Default                   | Meaning                                                                |
|-------------------------------|---------|---------------------------|------------------------------------------------------------------------|
| `updates_mode`                | string  | `manual`                  | `manual` or `automatic`                                                 |
| `updates_apply`               | string  | `security`                | `security` (security origin only) or `default` (security + updates)     |
| `updates_reboot`              | bool    | `false`                   | Reboot when updates require it                                          |
| `updates_email_to`            | string  | `""`                      | If set, unattended-upgrades mails reports here                          |
| `updates_email_only_on_error` | bool    | `true`                    | Suppress success mails, only mail on failure                            |
| `updates_timer_oncalendar`    | string  | `daily`                   | Systemd `OnCalendar=` for `apt-daily-upgrade.timer`                     |

## On-demand usage

In your maintenance playbook:

```yaml
- name: Patch hosts now
  hosts: postgres_servers
  become: true
  tasks:
  - ansible.builtin.include_role:
      name: updates
      tasks_from: run-now
    vars:
      updates_apply: security
      updates_reboot: true
```

## Automatic usage

```yaml
- hosts: postgres_servers
  become: true
  roles:
  - role: updates
    vars:
      updates_mode: automatic
      updates_apply: security
      updates_timer_oncalendar: "Sun *-*-* 03:00:00"
```
