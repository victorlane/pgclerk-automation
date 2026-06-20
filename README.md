# pgclerk-automation

Source of truth for the infrastructure code pgclerk runs against customer
clusters — Ansible roles and playbooks for OS hardening, PostgreSQL
installation, day-2 tasks, and Terraform modules for cloud
provisioning.

This repo is consumed by the pgclerk operator app: Semaphore syncs
templates from `ansible/playbooks/` and the UI reads `meta/catalogue.yml`
to know what each playbook does. **The operator app does not embed
playbooks** — it always points at a checkout of this repo.

## Layout

```
ansible/
  playbooks/
    install/         # Cluster bootstrap (atoms + composites)
    maintenance/     # Day-2 operations
    observability/   # Exporter installs + dashboards
    managed/         # Provision Postgres on RDS/Aurora/Cloud SQL/Flex
  roles/             # All composable units (postgresql, patroni, etcd, …)
  inventories/
    production/      # Real customer inventories (git-crypt'd)
    staging/         # CI + sandbox
  group_vars/        # Shared variables (CIDRs, ports, defaults)
  host_vars/         # Host-specific overrides
  collections/       # `requirements.yml` for ansible-galaxy install
terraform/
  environments/
    production/      # `customers/<slug>/` per-customer state
    staging/         # Disposable dev environments
  modules/
    compute/         # EC2 / GCE / Azure VM
    network/         # VPC, peering, private endpoints
    managed-postgres/# RDS, Aurora, Cloud SQL, Flexible Server
meta/
  catalogue.yml      # Operator-app metadata. SOURCE OF TRUTH for the
                     # playbook list shown in the UI.
scripts/             # CI helpers, dev shortcuts
```

## How the operator UI consumes this repo

1. **Semaphore sync** clones this repo into the Semaphore worker FS.
2. **Catalogue refresh** reads `meta/catalogue.yml` — every entry maps a
   UI label to a playbook path, a category (`install` / `maintenance` /
   `observability` / `managed`), an OS scope (`linux` / `rhel` /
   `debian` / `n/a`), and a `destructive` flag.
3. **Playbook list page** filters by `(category, surface, destructive)`.
4. **Dispatch** invokes Semaphore with the template id pointing at the
   playbook path.

To add a new playbook, edit `meta/catalogue.yml` (validated in CI). The
UI auto-picks it up after the next Semaphore sync.

## Autotune

PostgreSQL autotuning (memory, WAL, I/O, autovacuum, parallelism) is
imperative-only:

```sh
ansible-playbook ansible/playbooks/maintenance/autotune.yml --limit pg-1
```

Storage class, CPU, RAM, and cloud provider are discovered on the
host; nothing has to be declared in inventory. Experimental knobs
(`jit_above_cost`, `recovery_prefetch`, `io_method=worker`, …) are
reported in the run summary but only applied when an operator opts
in via `postgresql_experimental_enabled`. See
[`ansible/roles/postgresql/README.md`](ansible/roles/postgresql/README.md)
for the full list and the precedence rules.

## Conventions

- Roles never call other roles directly — composition happens at the
  playbook layer (`include_role`).
- Defaults in `roles/<x>/defaults/main.yml` document every variable. If
  it isn't in defaults, it isn't a public knob.
- Variables that travel cross-role live in `group_vars/all.yml`.
- Idempotency is mandatory. CI runs every play twice and diff-fails on a
  change in the second run.
- Destructive playbooks (anything dropping data) must have
  `destructive: true` in `meta/catalogue.yml` AND require an explicit
  confirmation extra-var (`confirm_destructive=yes`).

## Local development

```sh
pip install -r requirements.txt              # ansible-core
ansible-galaxy install -r ansible/collections/requirements.yml
ansible-lint ansible/playbooks/
molecule test -s default                     # role tests
terragrunt run-all plan --working-dir terraform/environments/staging
```

## Releases

Tagged versions only. The operator app pins to a tag via the Semaphore
project's git ref — never `main`.
