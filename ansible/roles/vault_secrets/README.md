# vault_secrets

Fetch pgclerk runtime secrets from HashiCorp Vault (KV v2) and expose
them as Ansible facts. This is a drop-in replacement for the file-based
`-e @secrets.yml` pattern documented in the top-level README.

## Why

The default secrets flow ships passwords in a (git-ignored) YAML file
passed via `-e @secrets.yml`. That works for solo development but does
not scale to a multi-tenant MSP: rotation requires editing a file on
every operator's laptop, there is no audit trail of who read what, and
the file inevitably gets emailed.

This role swaps that out for short-lived AppRole tokens against a
central Vault. Every fact the role registers carries `no_log: true`,
so secret values do not appear in `--check`/`--diff` output, nor in
Semaphore task logs.

## Variables

| Name                | Type   | Default      | Meaning                                                                  |
|---------------------|--------|--------------|--------------------------------------------------------------------------|
| `vault_addr`        | string | `""`         | Vault endpoint, e.g. `https://vault.example.com:8200`. Required.         |
| `vault_role_id`     | string | `""`         | AppRole role_id. Safe to keep in inventory.                              |
| `vault_secret_id`   | string | `""`         | AppRole secret_id. Inject per-run; never commit.                         |
| `vault_namespace`   | string | `""`         | Vault Enterprise namespace. Leave empty for Vault OSS.                   |
| `vault_mount_point` | string | `"secret"`   | KV v2 engine mount point.                                                |
| `vault_secrets`     | list   | `[]`         | Entries to fetch. See shape below.                                       |

Each `vault_secrets[]` item:

```yaml
- name: appuser                    # label used in debug output
  path: pgclerk/dev/appuser      # KV v2 path under vault_mount_point
  field: password                  # key inside the KV v2 data blob
  register_var: appuser_password   # Ansible fact name to set
  no_log: true                     # default true; only set false to debug
```

## Replacing -e @secrets.yml

Before (file-based):

```bash
ansible-playbook site.yml -e @secrets.yml
```

with `secrets.yml`:

```yaml
appuser_password: "super-secret"
patroni_admin_password: "another-secret"
pgbackrest_s3_key: "AKIA..."
```

After (Vault-backed) -- add the role to your play before any role that
consumes the facts:

```yaml
- name: Standalone PG with Vault-backed secrets
  hosts: postgres_servers
  become: true
  vars:
    vault_addr: "https://vault.example.com:8200"
    vault_role_id: "{{ pgclerk_vault_role_id }}"
    vault_mount_point: secret
    vault_secrets:
    - { name: "appuser",       path: "pgclerk/dev/appuser",       field: "password", register_var: "appuser_password" }
    - { name: "patroni admin", path: "pgclerk/dev/patroni",       field: "admin",    register_var: "patroni_admin_password" }
    - { name: "pgbackrest S3", path: "pgclerk/dev/pgbackrest-s3", field: "key",      register_var: "pgbackrest_s3_key" }
  roles:
  - role: vault_secrets
  - role: postgresql
  - role: pgbackrest
```

Run it as:

```bash
ansible-playbook site.yml -e vault_secret_id=$VAULT_SECRET_ID
```

The rest of the role / template files continue to reference
`{{ appuser_password }}`, `{{ patroni_admin_password }}` etc. -- they
do not care that the value came from Vault.

## Vault setup (one-time)

```sh
# Enable KV v2 at secret/ (default).
vault secrets enable -path=secret kv-v2

# Write a secret.
vault kv put secret/pgclerk/dev/appuser password='super-secret'

# Enable AppRole and create a role.
vault auth enable approle
vault policy write pgclerk-dev - <<'EOF'
path "secret/data/pgclerk/dev/*" {
  capabilities = ["read"]
}
EOF
vault write auth/approle/role/pgclerk-dev \
  token_policies=pgclerk-dev \
  token_ttl=10m token_max_ttl=30m

# Read the role_id (commit to inventory) and a secret_id (inject at run time).
vault read     auth/approle/role/pgclerk-dev/role-id
vault write -f auth/approle/role/pgclerk-dev/secret-id
```

## Dependencies

- `community.hashi_vault` (>= 6.0.0) -- declared in the top-level
  `requirements.yml`. The role aborts if the collection is missing.
- A reachable Vault that speaks KV v2 with AppRole auth enabled.
