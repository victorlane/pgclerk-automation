# mount

Apply a declarative list of filesystem mounts on Debian-family hosts. Installs
`nfs-common` automatically when any mount has an NFS-family `fstype`. Creates
mount-point directories before mounting.

## Variables

| Name                  | Type   | Default      | Meaning                                       |
|-----------------------|--------|--------------|-----------------------------------------------|
| `mounts`              | list   | `[]`         | List of mount specs (see below)                |
| `mount_default_owner` | string | `root`       | Default owner of the mount-point directory     |
| `mount_default_group` | string | `root`       | Default group of the mount-point directory     |
| `mount_default_mode`  | string | `"0755"`     | Default mode of the mount-point directory      |

Each `mounts` entry:

| Field    | Required | Default     | Meaning                                |
|----------|----------|-------------|----------------------------------------|
| `src`    | yes      | -           | Source (e.g. `nfs.example.com:/data`)   |
| `path`   | yes      | -           | Mount-point on this host                |
| `fstype` | yes      | -           | `nfs`, `nfs4`, `ext4`, `xfs`, ...       |
| `opts`   | no       | `defaults`  | `mount(8)` options                      |
| `state`  | no       | `mounted`   | Passed to `ansible.posix.mount`         |
| `dump`   | no       | `0`         | `/etc/fstab` dump column                |
| `passno` | no       | `0`         | `/etc/fstab` passno column              |
| `owner`  | no       | `root`      | Override mount-point owner              |
| `group`  | no       | `root`      | Override mount-point group              |
| `mode`   | no       | `"0755"`    | Override mount-point mode               |

## Example

```yaml
- hosts: backup_servers
  become: true
  roles:
  - role: mount
    mounts:
    - src: nfs.example.com:/srv/backups
      path: /mnt/backups
      fstype: nfs4
      opts: rw,nfsvers=4,hard,timeo=600
      owner: postgres
      group: postgres
      mode: "0750"
```
