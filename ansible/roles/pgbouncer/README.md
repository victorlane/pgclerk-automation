# pgbouncer

Install and configure [pgbouncer](https://www.pgbouncer.org/) for
transaction-mode pooling in front of a PostgreSQL cluster.

## Topologies

Topology is driven by inventory placement -- no role var to set.

| Topology     | Inventory placement                                    | Backend host in `pgbouncer_databases[*].host` |
|--------------|--------------------------------------------------------|-----------------------------------------------|
| Standalone   | Host in `pgbouncer_servers` only                       | Private IP of the PG primary / VIP            |
| Co-located   | Host in both `postgres_servers` and `pgbouncer_servers`| `127.0.0.1`                                   |

Standalone is the MSP default: the pooler scales independently and
survives PG restarts. Co-located is fine for small single-node setups.

## Inventory

```ini
[postgres_primary]
db1 ansible_host=10.0.0.10

[postgres_servers:children]
postgres_primary

[pgbouncer_servers]
pool1 ansible_host=10.0.0.20
pool2 ansible_host=10.0.0.21
```

## Defaults

| Variable                          | Default       | Notes |
|-----------------------------------|---------------|-------|
| `pgbouncer_listen_address`        | `0.0.0.0`     | Firewall is the gate; loopback path covers co-located. |
| `pgbouncer_listen_port`           | `6432`        | pgbouncer convention. |
| `pgbouncer_pool_mode`             | `transaction` | `transaction` / `session` / `statement`. |
| `pgbouncer_max_client_conn`       | `1000`        | Cap on total client connections. |
| `pgbouncer_default_pool_size`     | `25`          | Server-side connections per `(user, db)` pool. |
| `pgbouncer_min_pool_size`         | `0`           | Warm connections per pool. |
| `pgbouncer_reserve_pool_size`     | `5`           | Extra slots when a pool is exhausted. |
| `pgbouncer_reserve_pool_timeout`  | `3`           | Seconds before reserve kicks in. |
| `pgbouncer_server_idle_timeout`   | `600`         | Drop idle backends after N seconds. |
| `pgbouncer_query_timeout`         | `0`           | Disabled by default; set per-customer. |
| `pgbouncer_admin_users`           | `['postgres']`| PAUSE / RESUME / RELOAD via admin console. |
| `pgbouncer_stats_users`           | `['stats']`   | Read-only `SHOW STATS` / `SHOW POOLS`. |
| `pgbouncer_auth_type`             | `scram-sha-256` | |
| `pgbouncer_databases`             | `[]`          | List of backend db specs (see below). |
| `pgbouncer_users`                 | `[]`          | List of `{name, password}` (SCRAM hash). |

## The auth-user flow (read this once)

This is where operators trip up most. Two pieces fit together:

1. **userlist.txt** is a flat file with one `"<user>" "<hash>"` per
   line. Every user that pgbouncer ever has to authenticate against the
   listener must appear here. Hashes are extracted from a PG node:

   ```sql
   SELECT rolname, rolpassword FROM pg_authid WHERE rolname IN ('appuser','pgbouncer_auth');
   ```

   Feed the result verbatim into `pgbouncer_users`:

   ```yaml
   pgbouncer_users:
   - name: appuser
     password: "SCRAM-SHA-256$4096:...:..."
   - name: pgbouncer_auth
     password: "SCRAM-SHA-256$4096:...:..."
   ```

2. **auth_user** on a `[databases]` entry tells pgbouncer: "if a client
   shows up with a username I don't know, connect to PG as this user
   and `SELECT usename, passwd FROM pg_shadow WHERE usename=$1` to find
   their hash." That keeps userlist.txt small.

   The `auth_user` itself **must still be in userlist.txt** -- pgbouncer
   authenticates the auth_user against the listener too. The auth_user
   must also exist in PG with `pg_shadow` read permission (via the
   `pgbouncer_get_auth(text)` SECURITY DEFINER function pattern).

   **The `postgresql` role installs that function automatically** when
   any host is in the `pgbouncer_servers` inventory group: it creates
   the SQL role `pgbouncer_auth` (override with
   `postgresql_pgbouncer_auth_user`) in every database listed in
   `postgresql_databases`, defines `public.pgbouncer_get_auth(text)`
   as a `SECURITY DEFINER` function owned by the postgres superuser,
   and grants execute on it to the auth user (no other role can read
   pg_shadow via this path). The operator must supply
   `postgresql_pgbouncer_auth_password` (no default) and add the
   corresponding `pgbouncer_auth` entry to `pgbouncer_users` with the
   SCRAM hash pulled from `pg_authid`. Set the
   `auth_user: pgbouncer_auth` field on each `pgbouncer_databases`
   entry and the handshake works.

If you skip `auth_user`, every client user must be in `pgbouncer_users`.
That's fine for small deploys.

## Example: standalone pooler in front of one PG node

```yaml
# group_vars/pgbouncer_servers.yml
pgbouncer_databases:
- name: appdb
  host: 10.0.0.10           # PG primary's private IP
  port: 5432
  dbname: appdb
  pool_size: 50
  auth_user: pgbouncer_auth

pgbouncer_users:
- name: appuser
  password: "SCRAM-SHA-256$4096:abc...:def..."
- name: pgbouncer_auth
  password: "SCRAM-SHA-256$4096:ghi...:jkl..."
- name: postgres
  password: "SCRAM-SHA-256$4096:mno...:pqr..."
```

Then in a play:

```yaml
- hosts: pgbouncer_servers
  become: true
  roles:
  - role: os_baseline
    vars:
      os_baseline_firewall_rules:
      - { port: 6432, sources: ['10.0.0.0/8'] }
  - role: pgbouncer
```

## Example: co-located on the PG node

Same `pgbouncer_databases` entry, just `host: 127.0.0.1`. Put the host
in both inventory groups and the existing `site.yml` postgres play
plus a `hosts: pgbouncer_servers` play does the rest.

## Manual ops cheat sheet

The pgbouncer "admin console" is a virtual database named `pgbouncer`:

```bash
# Connect as an admin user (must be in pgbouncer_admin_users AND userlist.txt)
psql -h <pool-host> -p 6432 -U postgres pgbouncer

# Inside the console:
SHOW POOLS;            -- per-pool client / server connection counts
SHOW CLIENTS;          -- every active client connection
SHOW SERVERS;          -- every active backend connection
SHOW STATS;            -- traffic counters per pool
SHOW DATABASES;        -- the parsed [databases] block

RELOAD;                -- reread pgbouncer.ini + userlist.txt (no restart)
PAUSE <dbname>;        -- stop dispatching new transactions to a pool
                       -- (e.g. before failover)
RESUME <dbname>;       -- undo PAUSE
KILL <dbname>;         -- drop all server connections for a db
SHUTDOWN;              -- exit cleanly (systemd will restart it)
```

`RELOAD` is the day-to-day knob for re-reading config after the Ansible
role runs -- the role's handler does it automatically.

## Failover dance (standalone topology)

The pooler does not know when the backend primary changes. With a
Patroni VIP this is transparent. Without a VIP, after a failover:

```bash
# Update group_vars to point at the new primary, then:
ansible-playbook -i inventories/<env> playbooks/pool.yml --tags config
# or directly: change pgbouncer_databases[*].host and rerun the role.
```

The handler reloads pgbouncer; clients see a few-second blip.

## What this role deliberately does NOT do

- Compute SCRAM hashes. The operator pulls them from `pg_shadow` and
  pastes them into `pgbouncer_users`. Generating hashes in Ansible would
  require carrying client passwords around in plaintext, which we won't.
- Manage TLS in v1. The defaults expose `pgbouncer_client_tls_enabled`
  and `pgbouncer_server_tls_enabled` as placeholders only.
- Run PgCat. That's a different pooler (different config language,
  L7 routing); separate role in a separate pass.
- Touch the `postgresql` or `patroni` roles.
- Configure firewalling -- handle that via the `os_baseline` role's
  `os_baseline_firewall_rules` pass-through.
