# packages

Refreshes the apt cache and installs a common package set on Debian-family
hosts. Designed to be used both as a top-level role and as an inner helper
invoked by other roles that need extra packages.

EPEL and CRB / PowerTools toggles from the RHEL counterpart do not apply
here -- Debian ships everything we need from the main repositories.

## Variables

| Variable | Type | Default | Meaning |
|---|---|---|---|
| `packages_apt_cache_valid_time` | int | `3600` | Seconds before apt cache is considered stale and refreshed. Set to 0 to always refresh. |
| `packages_common` | list[str] | bash-completion, vim, tar, unzip, jq, python3-pip, lsof, tcpdump, dnsutils | Base package set. |
| `packages_extra` | list[str] | `[]` | Site-/caller-specific additions appended to the install. |

## Usage

Top-level:

```yaml
- hosts: all
  become: true
  roles:
  - packages
```

As a helper from another role -- pass `packages_extra` to declare extra
package needs without owning the install plumbing:

```yaml
- name: Pull in locales before initdb
  ansible.builtin.include_role:
    name: packages
  vars:
    packages_extra:
    - locales
    packages_common: []  # skip the common set if you only want the extras
```
