# updates

Manage OS package updates on RHEL-family hosts. Two modes:

- `manual` (default): role is a no-op on a normal run. A maintenance playbook
  invokes `tasks/run-now.yml` to apply updates on demand.
- `automatic`: installs `dnf-automatic`, deploys `/etc/dnf/automatic.conf`,
  and enables the systemd timer.

## Variables

| Name                       | Type    | Default                   | Meaning                                           |
|----------------------------|---------|---------------------------|---------------------------------------------------|
| `updates_mode`             | string  | `manual`                  | `manual` or `automatic`                            |
| `updates_apply`            | string  | `security`                | `security` or `default` (all)                      |
| `updates_reboot`           | bool    | `false`                   | Reboot when updates require it                     |
| `updates_email_to`         | string  | `""`                      | If set, emit dnf-automatic reports by email        |
| `updates_email_from`       | string  | `root@<fqdn>`             | dnf-automatic from-address                         |
| `updates_email_host`       | string  | `localhost`               | dnf-automatic SMTP relay                           |
| `updates_timer_oncalendar` | string  | `daily`                   | Systemd `OnCalendar=` for `dnf-automatic.timer`    |

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
