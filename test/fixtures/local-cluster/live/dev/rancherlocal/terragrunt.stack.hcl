# Consumer side. CATALOG_ROOT (local working tree) or CATALOG_STACK_SOURCE /
# CATALOG_UNIT_SOURCE (e.g. git::...?ref=) override the source; a real consumer
# hard-codes the pinned git URL instead (see README).
#
# Consumer side: instantiates the catalog's local-cluster stack so that the
# unit lands at live/dev/rancherlocal/local-cluster (state key unchanged).
stack "local_cluster" {
  source = get_env("CATALOG_STACK_SOURCE", "${get_env("CATALOG_ROOT", "")}/stacks/local-cluster")
  path   = "local-cluster"

  no_dot_terragrunt_stack = true

  values = {
    unit_source = get_env("CATALOG_UNIT_SOURCE", "${get_env("CATALOG_ROOT", "")}/units/local-cluster")

    environment = "rancherlocal"
    location    = "westus3"
    name_prefix = "demo"

    enable_acr = true
    acr_push_repositories = {
      sampleapp = {
        repository     = "your-org/sampleapp"
        subject_prefix = ""
        subjects       = ["ref:refs/heads/master"]
      }
    }
    acr_pull_repositories = ["sampleapp"]

    enable_storage     = true
    storage_containers = ["argo-workflows"]

    tags = { Environment = "rancherlocal", ManagedBy = "Terragrunt" }
  }
}
