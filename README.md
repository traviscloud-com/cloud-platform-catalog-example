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
test/fixtures/local-cluster/                 miniature consumer tree used by the offline test
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
cloud-platform-modules-example  tag local-cluster/vX.Y.Z   pinned in units/local-cluster/terragrunt.hcl
        |
cloud-platform-catalog-example  tag vX.Y.Z (whole catalog) pinned by consumers: ?ref= on stack AND unit_source
```

To roll out a module release: change the `ref=` in the unit, merge, run the
`release` workflow with the next catalog version, then bump the two `?ref=`
values in the consumer. Keep the stack and `unit_source` refs identical.

## Testing the adoption offline

`scripts/test-fixture.sh` copies `test/fixtures/local-cluster` (a miniature
consumer: local-backend `root.hcl`, stub `dns-principals`, and the consuming
`terragrunt.stack.hcl`) to a temp dir, runs `terragrunt stack generate`,
asserts the unit is at `live/dev/rancherlocal/local-cluster` and that
`path_relative_to_include()` and the backend key are
`dev/rancherlocal/local-cluster`, then runs `terragrunt validate` with mocked
dependency outputs and cleans up.

```sh
scripts/install-tools.sh terragrunt          # pinned + checksum-verified (terraform 1.15.8 from .tool-versions)
scripts/test-fixture.sh                      # tests the working tree (CATALOG_ROOT defaults to this repo)
CATALOG_STACK_SOURCE='git::https://...//stacks/local-cluster?ref=v1.1.0' \
CATALOG_UNIT_SOURCE='git::https://...//units/local-cluster?ref=v1.1.0' scripts/test-fixture.sh   # a pushed ref
scripts/lint.sh                              # terragrunt hcl fmt --check + trivy config
```

No Azure access or `ARM_*` credentials are used (the script unsets them). It
does need the network for `terraform init`: the modules repo, the AVM modules
it pins and the Terraform providers. A stale `.terragrunt-cache` can cause confusing failures; the
script works on a fresh copy for that reason. The module source uses the `//`
form because `modules/local-cluster` has sibling relative sources.

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
