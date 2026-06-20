# selinux

**Intentional no-op on Debian-family hosts.**

AppArmor is the default Linux Security Module on Debian and Ubuntu, not
SELinux, so the SELinux helpers in [`os_rhel_selinux`](../os_rhel_selinux)
do not apply here. This role exists only so the `os_baseline` wrapper can
include `os_debian_selinux` unconditionally; on Debian it ends immediately
with `meta: end_role`.

The same-named variables (`selinux_state`, `selinux_fcontexts`,
`selinux_booleans`) are defined in `defaults/main.yml` purely for shape
parity -- they are accepted but ignored.

A dedicated `apparmor` role for managing AppArmor profiles on Debian is
on the roadmap; track that work rather than extending this stub.
