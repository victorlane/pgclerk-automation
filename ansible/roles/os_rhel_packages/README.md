# packages

Enables EPEL and CodeReady Builder / PowerTools and installs a common
package set on EL hosts. Designed to be used both as a top-level role and
as an inner helper invoked by other roles that need extra packages.

## Variables

| Variable | Type | Default | Meaning |
|---|---|---|---|
| `packages_enable_epel` | bool | `true` | Install `epel-release`. |
| `packages_enable_crb` | bool | `true` | Enable CRB on EL9, PowerTools on EL8. |
| `packages_common` | list[str] | bash-completion, vim-enhanced, tar, unzip, jq, python3-pip, lsof, tcpdump, bind-utils | Base package set. |
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
- name: Pull in glibc-langpack-en before initdb
  ansible.builtin.include_role:
    name: packages
  vars:
    packages_extra:
    - glibc-langpack-en
    packages_common: []  # skip the common set if you only want the extras
```
