# Stack wrapper around units/local-cluster: passes its values through.
#
# Consumer snippet (live/<env>/<name>/terragrunt.stack.hcl) - see README:
#   stack "local_cluster" {
#     source                  = "git::https://github.com/traviscloud-com/cloud-platform-catalog-example.git//stacks/local-cluster?ref=v1.1.0"
#     path                    = "local-cluster"
#     no_dot_terragrunt_stack = true
#     values = {
#       unit_source = "git::https://github.com/traviscloud-com/cloud-platform-catalog-example.git//units/local-cluster?ref=v1.1.0"
#       ...
#     }
#   }
#
# Why `unit_source` is a value: terragrunt copies only this stack file into the
# consumer tree, so a relative path to ../../units no longer resolves, and a
# stack file cannot know the ref it was fetched at. The consumer passes the
# unit's URL, pinned to the same ref as the stack (see README "Versions").
#
# Why path = ".": the consumer's stack block (path = "local-cluster",
# no_dot_terragrunt_stack = true) already creates the directory
# <dir>/local-cluster. A nested unit with path "local-cluster" would land one
# level deeper (<dir>/local-cluster/local-cluster) and change the state key;
# path "." (with no_dot_terragrunt_stack) generates the unit into the stack's
# own directory instead.
# Consequence: this stack must contain exactly one unit.

unit "local_cluster" {
  source = values.unit_source
  path   = "."

  # Generate into <stack dir>/<path>, not <stack dir>/.terragrunt-stack/<path>.
  no_dot_terragrunt_stack = true

  values = {
    dns_principals_path           = try(values.dns_principals_path, "../../../platform/dns-principals")
    environment                   = values.environment
    location                      = values.location
    name_prefix                   = try(values.name_prefix, "demo")
    secret_rotation_days          = try(values.secret_rotation_days, 730)
    owner_service_principal_names = try(values.owner_service_principal_names, ["gh-cloud-platform-deploy"])
    enable_acr                    = try(values.enable_acr, false)
    acr_push_repositories         = try(values.acr_push_repositories, {})
    acr_pull_repositories         = try(values.acr_pull_repositories, null)
    enable_storage                = try(values.enable_storage, false)
    storage_containers            = try(values.storage_containers, [])
    storage_retention_days        = try(values.storage_retention_days, 90)
    tags                          = try(values.tags, {})
  }
}
