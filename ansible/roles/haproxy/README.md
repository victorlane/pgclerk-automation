# haproxy

## Purpose

Patroni-aware floating-port load balancer. Routes the read-write port to
whichever cluster member currently answers `200 OK` on Patroni's REST
`/master` endpoint, and (optionally) routes a read-only port across any
member answering `200 OK` on `/replica`.

Clients connect to `haproxy_host:5432` as if it were a single Postgres
instance; HAProxy hides the leader-replica topology entirely. After a
Patroni failover, HAProxy notices the role change on its next health
poll (1s by default) and shifts traffic to the new leader without any
client-side reconnect logic.

## Topology

Typical placements (pick one):

| Layout                        | Inventory placement                                | Trade-off                                         |
|-------------------------------|----------------------------------------------------|---------------------------------------------------|
| Standalone HAProxy node(s)    | Host in `haproxy_servers` only                     | LB scales / fails independently of the cluster    |
| Co-located on the PG nodes    | Host in both `postgres_servers` and `haproxy_servers` | One fewer VM; HAProxy dies with the host         |
| HAProxy + keepalived VIP      | Two `haproxy_servers` nodes, VIP managed externally | Removes HAProxy itself as a SPOF (out of scope)   |

pgBouncer can sit either **in front of** HAProxy (rare -- means
pgbouncer clients reconnect on each PG failover, defeating the point) or
**behind** HAProxy (common -- HAProxy fronts the cluster, pgbouncer is
co-located on each PG node with `host: 127.0.0.1` in its
`pgbouncer_databases` and clients reach the pool through HAProxy's
floating port). The latter is the MSP default.

## Inventory

```ini
[postgres_primary]
db1 ansible_host=10.0.0.10

[postgres_replicas]
db2 ansible_host=10.0.0.11
db3 ansible_host=10.0.0.12

[postgres_servers:children]
postgres_primary
postgres_replicas

[haproxy_servers]
lb1 ansible_host=10.0.0.20
lb2 ansible_host=10.0.0.21
```

## Defaults

| Variable                       | Default              | Notes                                                                              |
|--------------------------------|----------------------|------------------------------------------------------------------------------------|
| `haproxy_floating_port`        | `5432`               | Read-write port. Clients connect here.                                             |
| `haproxy_readonly_port`        | `5433`               | Read-only port (when `haproxy_enable_readonly: true`).                             |
| `haproxy_enable_readonly`      | `true`               | Set `false` to skip the read-only listener entirely.                               |
| `haproxy_stats_port`           | `7000`               | Plain-HTTP stats dashboard. Front it with the OS firewall.                         |
| `haproxy_patroni_rest_port`    | `8008`               | Must match `patroni_restapi_port` on the cluster.                                  |
| `haproxy_check_interval_ms`    | `1000`               | How often HAProxy probes Patroni REST.                                             |
| `haproxy_check_timeout_ms`     | `500`                | Per-probe timeout.                                                                 |
| `haproxy_inter_check_ms`       | `1000`               | `default-server inter` attribute.                                                  |
| `haproxy_cluster_group`        | `postgres_servers`   | Inventory group whose members are the Patroni cluster to balance.                  |

## Why `option httpchk OPTIONS /master`

This is the canonical Patroni health check. Patroni's REST API answers
`GET /master` with `200` only on the current leader (and `503` on any
replica), and `GET /replica` with `200` only on a healthy replica that
Patroni considers eligible for promotion. By probing those endpoints
on every backend, HAProxy outsources the "who is the leader right now"
decision to Patroni rather than racing it -- there is no scenario where
HAProxy routes to a backend that Patroni does not currently consider
the leader.

`fall 3 rise 2` debounces transient probe failures: three consecutive
fails to mark a backend down, two successes to mark it back up. With
the default 1s interval that gives ~3s detection of a real outage.

## Example play

```yaml
- name: HAProxy in front of Patroni cluster
  hosts: haproxy_servers
  become: true
  roles:
  - role: os_baseline
    vars:
      os_baseline_firewall_rules:
      - { port: 5432, sources: ['10.0.0.0/8'] }   # floating port
      - { port: 5433, sources: ['10.0.0.0/8'] }   # read-only port
      - { port: 7000, sources: ['10.0.0.0/24'] }  # stats -- ops subnet only
  - role: haproxy
```

## Per-OS install

- **RHEL 8/9**: `haproxy` lives in EPEL. The role assumes EPEL (or CRB
  on RHEL 9 derivatives) is already enabled on the host -- typically
  via the `os_rhel_packages` role earlier in the play, or via an
  upstream subscription. EPEL enablement is a customer-policy decision
  (which mirror, which signing key) so this role does not silently
  enable it.
- **Amazon Linux 2023**: `haproxy` is in the main repo, no extra
  repository needed.
- **Debian 12 / Ubuntu 22.04+24.04**: `haproxy` is in main, no extra
  repository needed.

## Stats dashboard

```bash
curl -s http://<haproxy>:7000/ | less
# Or in a browser if the port is firewall-reachable.
```

The dashboard shows per-listener and per-backend state -- particularly
useful right after a failover to confirm HAProxy noticed the role
change.

## What this role deliberately does NOT do

- Manage a VIP / keepalived for HAProxy itself. Two-HAProxy-node VIP
  failover is a separate concern (`keepalived`, AWS NLB, Hetzner
  floating IP, etc.) and varies wildly by environment.
- Configure TLS termination. v1 ships TCP-mode passthrough; clients
  use Postgres-native SSL to the backend.
- Authenticate the stats listener. Bind it to a management subnet and
  let the OS firewall be the gate.
- Touch the Patroni or PostgreSQL config. HAProxy only reads Patroni's
  REST API; the cluster need not know HAProxy exists.
