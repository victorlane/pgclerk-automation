# konnectivity_agent

Install the `pgclerk-konnectivity` agent (server or worker mode) on a
Linux host. Outbound-only HTTPS long-poll telemetry; no inbound ports.

Multi-OS by design: RHEL family (EL8/EL9, Oracle Linux, Rocky, Alma),
Debian / Ubuntu, and Amazon Linux 2023. The role mirrors the pattern
used by `roles/node_exporter` (variant dispatch via
`_kn_os_variant = Amazon | RedHat | Debian`).

## Required vars

| Var                            | Description |
|--------------------------------|-------------|
| `konnectivity_server_url`      | Base URL of the pgclerk central server (or the CNC FQDN that fronts it). |
| `konnectivity_bootstrap_token` | Single-use, cluster-scoped bootstrap token; self-burns on first registration. |
| `konnectivity_cluster`         | Konnectivity-cluster slug to register the agent into. |
| `konnectivity_mode`            | `server` (default) or `worker`. |
| `konnectivity_worker_probe`    | Required when `mode=worker`: `host:port` the worker should probe. |

## Optional vars

See [`defaults/main.yml`](defaults/main.yml). The defaults are sane.
Common overrides:

- `konnectivity_version: v0.4.1` — pin to a tag instead of tracking
  `latest`.
- `konnectivity_labels: "az=eu-west-1a,role=primary"` — surfaces in the
  pgclerk UI.
- `konnectivity_allow_exec: 1` — opt in to the experimental operator-
  driven exec channel. Leave at `0` unless you mean it.

## Typical use

Through the atom playbook (driven by Semaphore):

```bash
ansible-playbook playbooks/atoms/konnectivity-agent.yml \
  -i inventories/dev \
  -l konnectivity_targets \
  -e konnectivity_server_url=https://pgclerk.example.com \
  -e konnectivity_bootstrap_token=pgm_bs_… \
  -e konnectivity_cluster=acme-prod \
  -e konnectivity_mode=server
```

Or composed into a larger play, alongside `os_baseline` and `postgresql`:

```yaml
- hosts: postgres_servers
  become: true
  roles:
  - role: os_baseline
  - role: postgresql
  - role: konnectivity_agent
    vars:
      konnectivity_mode: server
```
