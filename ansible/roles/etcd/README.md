# etcd

Installs and configures a 3-or-5 node etcd v3 cluster on RHEL 8/9 to act as the
DCS (distributed config store) for Patroni. Binaries are pulled from the
upstream GitHub release tarball (PGDG does not ship etcd, EPEL is too old). The
role is topology-agnostic: it runs etcd on whatever hosts it is invoked on, and
builds its peer list from `groups[etcd_inventory_group]` in inventory order.

## Topologies

The choice between **embedded** and **external** DCS is made at the playbook
layer, not by this role:

- **Embedded** -- etcd colocates with PostgreSQL. Apply this role to
  `postgres_servers` and set `etcd_inventory_group: postgres_servers`.
- **External** -- etcd runs on a dedicated group `etcd_servers`. Apply this
  role to `etcd_servers` and set `etcd_inventory_group: etcd_servers`.

## Variables

| Name | Type | Default | Meaning |
|------|------|---------|---------|
| `etcd_version` | string | `3.5.16` | etcd release to install (pinned). |
| `etcd_arch` | string | derived | `amd64` or `arm64`, computed from `ansible_facts.architecture`. |
| `etcd_inventory_group` | string | `postgres_servers` | Inventory group whose members form the cluster. |
| `etcd_install_dir` | path | `/opt/etcd-<version>` | Where the tarball is extracted. |
| `etcd_data_dir` | path | `/var/lib/etcd` | etcd data directory. Mode 0700, owned by `etcd:etcd`. |
| `etcd_config_dir` | path | `/etc/etcd` | Holds `etcd.conf.yaml`. |
| `etcd_user` / `etcd_group` | string | `etcd` | System user + group, no login shell. |
| `etcd_client_port` | int | `2379` | Client traffic. |
| `etcd_peer_port` | int | `2380` | Peer traffic. |
| `etcd_listen_ip` | string | `ansible_facts.default_ipv4.address` | Bind address per host. |
| `etcd_advertise_ip` | string | `{{ etcd_listen_ip }}` | Address other peers/clients use to reach this host. |
| `etcd_cluster_token` | string | `pgclerk-etcd` | Cluster identity token. |
| `etcd_download_url` | url | upstream GitHub release | Override to use an internal mirror. |
| `etcd_enable_tls` | bool | `false` | TLS placeholder. v1 deploys plaintext. TODO. |

## Usage

### Embedded (etcd on the postgres hosts)

```yaml
- hosts: postgres_servers
  become: true
  vars:
    etcd_inventory_group: postgres_servers
  roles:
  - etcd
  - postgresql
  - patroni
```

### External (dedicated etcd hosts)

```yaml
- hosts: etcd_servers
  become: true
  vars:
    etcd_inventory_group: etcd_servers
  roles:
  - etcd

- hosts: postgres_servers
  become: true
  vars:
    patroni_etcd_hosts: "{{ groups['etcd_servers'] }}"
  roles:
  - postgresql
  - patroni
```

## Firewall

This role does **not** manage firewalld or SELinux. The consumer play must open
TCP 2379 (client) and 2380 (peer) between the etcd peers and from any client
that talks to the DCS (e.g. Patroni). Use the `os_baseline` wrapper for that.

## Manual operations

```sh
export ETCDCTL_API=3
etcdctl --endpoints=http://<peer>:2379 member list
etcdctl --endpoints=http://<peer>:2379 endpoint health --cluster
etcdctl --endpoints=http://<peer>:2379 get / --prefix --keys-only
```
