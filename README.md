# cloud-platform-catalog-example

> **Example repository.** This is a sanitized public copy of a pattern that runs in a private
> setup. Every hostname, organisation, tenant, subscription, client ID, vault, registry and
> storage name is a placeholder (`example.com`, `demo`, `your-org`, all-zero GUIDs); nothing here
> points at a real deployment, and it contains no secrets. Where the text says a repo is private,
> that describes the original setup. Companion repos:
> [manifests](https://github.com/traviscloud-com/cloud-platform-manifests-example),
> [infra](https://github.com/traviscloud-com/cloud-platform-infra-example),
> [catalog](https://github.com/traviscloud-com/cloud-platform-catalog-example),
> [modules](https://github.com/traviscloud-com/cloud-platform-modules-example),
> [ouroboros](https://github.com/traviscloud-com/ouroboros-example).

Reusable Terragrunt **units** and **stacks** for the example platform. The
catalog wraps the Terraform modules in
[`cloud-platform-modules-example`](https://github.com/traviscloud-com/cloud-platform-modules-example)
(pinned by tag) so that a consumer repo such as `cloud-platform-infra-example` only
declares *where* something lives and *which values* it gets, not how it is
wired.

Consumers supply their own `root.hcl` (remote state backend, provider
generation, subscription selection). The catalog never contains backend or
credential configuration.

## Layout

```
units/local-cluster/terragrunt.hcl           generic wrapper around modules/local-cluster; pins the module tag
stacks/local-cluster/terragrunt.stack.hcl    stack with one unit, passes values through
units/key-vault/terragrunt.hcl               generic wrapper around modules/key-vault; pins the module tag
stacks/key-vault/terragrunt.stack.hcl        stack with one unit, passes values through
units/hub/terragrunt.hcl                     generic wrapper around modules/hub; pins the module tag
units/aks-spoke/terragrunt.hcl               generic wrapper around modules/aks-spoke; wires hub, network platform, DNS and Key Vault
test/fixtures/<case>/                        miniature consumer trees used by the offline test
scripts/                                     install-tools.sh, lint.sh, test-fixture.sh
.github/workflows/                           ci.yml, gitleaks.yml, release.yml
```

## `local-cluster` values

Everything consumer-specific arrives through `values`; nothing is hard-coded in
the unit. Defaults equal the module's own defaults.

| value | type | required | default |
| --- | --- | --- | --- |
| `environment` | string | yes | - (1-12 lowercase alphanumerics, e.g. `rancherlocal`) |
| `location` | string | yes | - |
| `name_prefix` | string | no | `"demo"` |
| `dns_principals_path` | string | no | `"../../../platform/dns-principals"` (relative to the generated unit directory) |
| `secret_rotation_days` | number | no | `730` |
| `owner_service_principal_names` | list(string) | no | `["gh-cloud-platform-deploy"]` |
| `enable_acr` | bool | no | `false` |
| `acr_push_repositories` | map(object({repository, subject_prefix, subjects})) | no | `{}` |
| `acr_pull_repositories` | list(string) or null | no | `null` (= keys of `acr_push_repositories`) |
| `enable_storage` | bool | no | `false` |
| `storage_containers` | list(string) | no | `[]` (blob containers; the cluster's storage principal can write to these only) |
| `storage_retention_days` | number | no | `90` (`0` keeps blobs forever) |
| `tags` | map(string) | no | `{}` |
| `unit_source` | string | stack only, yes | - (pinned URL of `units/local-cluster`, see Versions) |

The three `dns_*` module inputs are derived from the `dns_principals`
dependency (looked up by `environment`); the dependency carries mock outputs
for `init`, `validate` and `plan`, so the unit validates before dns-principals
is applied.

## `key-vault` values

An environment's secret store: one RBAC-mode vault with its resource group,
generated secrets and operator-set placeholders. Defaults equal the module's
own defaults.

| value | type | required | default |
| --- | --- | --- | --- |
| `name` | string | yes | - (globally unique vault name, e.g. `kv-demo-dev`) |
| `location` | string | yes | - |
| `resource_group_name` | string | yes | - |
| `create_resource_group` | bool | no | `true` (`false` when the caller owns the group) |
| `officer_service_principal_names` | list(string) | no | `["gh-cloud-platform-deploy"]` (Key Vault Secrets Officer, next to the applying identity) |
| `reader_service_principal_names` | list(string) | no | `["gh-cloud-platform-plan"]` (Key Vault Secrets User, so plans can refresh secrets) |
| `additional_officer_principal_ids` | set(string) | no | `[]` |
| `secrets_user_principals` | map(object({principal_id, principal_type, description})) | no | `{}` |
| `generated_secrets` | map(string) | no | `{}` (key = stable name, value = vault secret name; a random 32-character value is generated once) |
| `operator_managed_secret_names` | list(string) | no | `[]` (placeholders an operator fills with `az keyvault secret set`) |
| `purge_protection_enabled` | bool | no | `false` |
| `soft_delete_retention_days` | number | no | `7` |
| `tags` | map(string) | no | `{}` |
| `unit_source` | string | stack only, yes | - (pinned URL of `units/key-vault`, see Versions) |

The module's `managed_secrets` / `managed_secret_values` are deliberately not
exposed: values are written to `terragrunt.values.hcl` in plain text, so a
secret value must never travel through them.

Consumer, `live/dev/terragrunt.stack.hcl` (unit generated at
`live/dev/keyvault`, state key `dev/keyvault/terraform.tfstate`):

```hcl
stack "keyvault" {
  source                  = "git::https://github.com/traviscloud-com/cloud-platform-catalog-example.git//stacks/key-vault?ref=v1.2.0"
  path                    = "keyvault"
  no_dot_terragrunt_stack = true

  values = {
    unit_source         = "git::https://github.com/traviscloud-com/cloud-platform-catalog-example.git//units/key-vault?ref=v1.2.0"
    name                = "kv-demo-dev"
    resource_group_name = "rg-demo-dev-secrets"
    location            = "westus3"
  }
}
```

## `hub` and `aks-spoke` values

A region of an environment is one hub and one or more AKS stamps. These two
units have no stack wrapper: a consumer's `terragrunt.stack.hcl` names them
directly in `unit` blocks, one per directory, because a region holds several
units that share almost all of their values.

Values use the key names of the platform's `env.hcl` and `region.hcl`, so a
consumer passes `merge(env, region, { tags = ... })` to every unit and spells
out only the differences. Keys a unit does not know are ignored. Defaults
equal the modules' own defaults.

Both units:

| value | type | required | default |
| --- | --- | --- | --- |
| `environment`, `location`, `region_short` | string | yes | - |
| `enable_private_dns` | bool | no | `false` (link to the environment's central private zone) |
| `aks_outbound_type` | string | no | `"loadBalancer"` (`userDefinedRouting` = egress through the hub firewall) |
| `enable_telemetry` | bool | no | `false` |
| `platform_network_path` | string | no | `"../../../platform/network"` (relative to the generated unit directory) |
| `excluded` | bool | no | `false` (`true` keeps the unit out of every run) |
| `tags` | map(string) | no | `{}` |

`hub` only:

| value | type | required | default |
| --- | --- | --- | --- |
| `hub_address_space` | list(string) | yes | - |
| `enable_firewall`, `firewall_sku_tier` | bool, string | no | `false`, `"Basic"` |
| `firewall_route_entries` | list(object({name, address_prefix, next_hop_ip_address})) | no | `[]` |
| `enable_dns_resolver`, `enable_bastion`, `bastion_sku` | bool, bool, string | no | `false`, `false`, `"Basic"` |
| `peer_hub_path` | string | no | unset (path of another hub unit to peer with; declare it on one side only) |

`aks-spoke` only:

| value | type | required | default |
| --- | --- | --- | --- |
| `name_prefix` | string | yes | - |
| `stamp_pool_prefix` | string | yes | - (the region's stamp pool; the static address space is its first `/<stamp_prefix_length>`) |
| `stamp_prefix_length` | number | no | `22` |
| `stamp_suffix` | string | no | `""` (`"-2"` for a second stamp in the region, generated at `aks-spoke-2`) |
| `enable_avnm`, `enable_avnm_routing` | bool | no | `false` |
| `enable_external_dns_identity`, `enable_cert_manager_identity`, `enable_external_secrets_identity`, `enable_api_server_vnet_integration` | bool | no | `false` |
| `kubernetes_version`, `aks_sku_tier`, `private_cluster_enabled`, `api_server_authorized_ip_ranges`, `admin_group_object_ids`, `cluster_admin_principal_ids`, `system_node_pool`, `user_node_pools`, `network_policy` | as in the module | no | module defaults |
| `enable_acr`, `acr_sku`, `enable_log_analytics`, `log_retention_days`, `enable_container_insights`, `enable_managed_prometheus`, `enable_defender`, `enable_azure_policy` | as in the module | no | module defaults |
| `hub_path`, `public_dns_path`, `keyvault_path` | string | no | `"../hub"`, `"../../../platform/dns"`, `"../../keyvault"` |

The dependency blocks carry mock outputs for `init`, `validate` and `plan`, so
a region validates before its hub, the network platform, the DNS zones or the
vault exist. The `hub` and `keyvault` mocks must match the outputs of the
module tags pinned here; the `platform_network` and `public_dns` mocks must
match the consumer's modules.

Consumer, `live/dev/westus3/terragrunt.stack.hcl` (units generated at
`live/dev/westus3/hub`, `.../aks-spoke` and `.../aks-spoke-2`):

```hcl
locals {
  env      = read_terragrunt_config("${get_terragrunt_dir()}/../env.hcl").locals
  region   = read_terragrunt_config("${get_terragrunt_dir()}/region.hcl").locals
  settings = merge(local.env, local.region, { tags = { Environment = local.env.environment } })
}

unit "hub" {
  source                  = "git::https://github.com/traviscloud-com/cloud-platform-catalog-example.git//units/hub?ref=v1.2.0"
  path                    = "hub"
  no_dot_terragrunt_stack = true
  values                  = local.settings
}

unit "aks_spoke" {
  source                  = "git::https://github.com/traviscloud-com/cloud-platform-catalog-example.git//units/aks-spoke?ref=v1.2.0"
  path                    = "aks-spoke"
  no_dot_terragrunt_stack = true
  values                  = local.settings
}

unit "aks_spoke_2" {
  source                  = "git::https://github.com/traviscloud-com/cloud-platform-catalog-example.git//units/aks-spoke?ref=v1.2.0"
  path                    = "aks-spoke-2"
  no_dot_terragrunt_stack = true
  values                  = merge(local.settings, { stamp_suffix = "-2" })
}
```

The whole of `env.hcl` and `region.hcl` ends up in the generated
`terragrunt.values.hcl`; keep those files gitignored in the consumer.

## Adopting a unit without changing its path or state key

State keys come from `path_relative_to_include()`, and the subscription is
chosen from `basename` of the unit path, so the generated unit must land at the
exact directory the hand-written one occupies. Verified with terragrunt
v1.1.1: a `stack` block with `no_dot_terragrunt_stack = true` flattens the
stack directory, and the catalog stack uses `path = "."` for its unit so no
extra level appears.

Consumer, `live/dev/rancherlocal/terragrunt.stack.hcl`:

```hcl
stack "local_cluster" {
  source                  = "git::https://github.com/traviscloud-com/cloud-platform-catalog-example.git//stacks/local-cluster?ref=v1.1.0"
  path                    = "local-cluster"
  no_dot_terragrunt_stack = true

  values = {
    unit_source = "git::https://github.com/traviscloud-com/cloud-platform-catalog-example.git//units/local-cluster?ref=v1.1.0"

    environment = "rancherlocal"
    location    = "westus3"
    # name_prefix, enable_acr, acr_push_repositories, ... see the table above
  }
}
```

Result: `live/dev/rancherlocal/local-cluster/{terragrunt.hcl,terragrunt.values.hcl,.terragrunt-stack-manifest}`,
state key `dev/rancherlocal/local-cluster/terraform.tfstate` as before.

Gotchas (all observed on v1.1.1):

- Without `no_dot_terragrunt_stack = true` on the **consumer's** `stack` block
  the unit lands in `.terragrunt-stack/local-cluster/...` (state key changes).
- Without `path = "."` (and `no_dot_terragrunt_stack`) on the **unit inside the
  catalog stack** it lands in `local-cluster/local-cluster` (state key changes).
  Consequently a catalog stack that must stay path-compatible has one unit.
- `path = "."` on the consumer's `stack` block overwrites the consumer's own
  `terragrunt.stack.hcl`. Do not use it.
- Generation fails if the target directory already holds a hand-written
  `terragrunt.hcl` ("contains both terragrunt.hcl and terragrunt.stack.hcl").
  Remove it (and `include`-based envcommon wiring) in the adoption change.
  A committed `.terraform.lock.hcl` in the directory is left untouched.
- `terragrunt stack clean` does not remove directories generated with
  `no_dot_terragrunt_stack`; delete the generated files by hand if needed.
- A stack fetched from a remote ref is copied alone, so it cannot use relative
  paths to its sibling `units/` directory and cannot know its own ref. That is
  why `unit_source` is a value.
- Fallback that also works: skip the stack and put a `unit` block with
  `source = ".../units/local-cluster?ref=..."`, `path = "local-cluster"`,
  `no_dot_terragrunt_stack = true` and the same `values` (minus `unit_source`)
  directly in `live/dev/rancherlocal/terragrunt.stack.hcl`.

Generated files should be committed or gitignored deliberately: either commit
the generated unit directory (reviewable, `terragrunt run --all` works without
a generate step) or gitignore `terragrunt.hcl`, `terragrunt.values.hcl` and
`.terragrunt-stack-manifest` under those directories and run
`terragrunt stack generate` first in CI and locally.

## Versions

```
cloud-platform-modules-example  tag <module>/vX.Y.Z        pinned in units/<module>/terragrunt.hcl
        |
cloud-platform-catalog-example  tag vX.Y.Z (whole catalog) pinned by consumers: ?ref= on stack AND unit_source
```

To roll out a module release: change the `ref=` in the unit, merge, run the
`release` workflow with the next catalog version, then bump the two `?ref=`
values in the consumer. Keep the stack and `unit_source` refs identical.

## Testing the adoption offline

`scripts/test-fixture.sh` runs one case per fixture. Each copies
`test/fixtures/<case>` (a miniature consumer: local-backend `root.hcl`, the
consuming `terragrunt.stack.hcl`, and stubs for the units it depends on) to a
temp dir, runs `terragrunt stack generate`, asserts the unit directories and
that `path_relative_to_include()` and the backend key match them, then runs
`terragrunt validate` on each unit (with mocked dependency outputs) and cleans
up.

| case | units generated at | state keys |
| --- | --- | --- |
| `local-cluster` | `live/dev/rancherlocal/local-cluster` | `dev/rancherlocal/local-cluster` |
| `key-vault` | `live/dev/keyvault` | `dev/keyvault` |
| `region` | `live/dev/westus3/hub`, `live/dev/westus3/aks-spoke` | `dev/westus3/hub`, `dev/westus3/aks-spoke` |

```sh
scripts/install-tools.sh terragrunt          # pinned + checksum-verified (terraform 1.15.8 from .tool-versions)
scripts/test-fixture.sh                      # all cases, working tree (CATALOG_ROOT defaults to this repo)
scripts/test-fixture.sh key-vault            # one case
CATALOG_REF=v1.2.0 scripts/test-fixture.sh   # a pushed ref instead of the working tree
scripts/lint.sh                              # terragrunt hcl fmt --check + trivy config
```

No Azure access or `ARM_*` credentials are used (the script unsets them). It
does need the network for `terraform init`: the modules repo, the AVM modules
it pins and the Terraform providers. A stale `.terragrunt-cache` can cause confusing failures; the
script works on a fresh copy for that reason. The module source uses the `//`
form because `modules/local-cluster` and `modules/aks-spoke` have sibling
relative sources.

## Security

This is the public example copy: names, hosts and identifiers are placeholders.
Secrets and credentials are never committed: state files, `.env` and `*.tfvars` are gitignored, and gitleaks runs
in CI (`gitleaks.yml`, plus a weekly full-history sweep).

- Tool versions are pinned: Terraform in `.tool-versions` and CI; terragrunt,
  trivy and gitleaks in `scripts/install-tools.sh`, which verifies their sha256
  checksums. Third-party GitHub Actions are pinned by full commit SHA.
- Module sources are pinned by tag; consumers pin the catalog by tag.
- HIGH/CRITICAL `trivy config` findings fail CI; accepted exceptions live in
  `.trivyignore`, each with a justification.
- Workflows run with least-privilege `GITHUB_TOKEN` permissions; only the
  release job gets `contents: write`; checkouts use `persist-credentials: false`
  except where the job pushes.
