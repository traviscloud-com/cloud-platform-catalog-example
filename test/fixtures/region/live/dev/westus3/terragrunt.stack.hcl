# Consumer side: one region of an environment, a hub and one AKS stamp, from
# the catalog's hub and aks-spoke units. The units must land at
# live/dev/westus3/hub and live/dev/westus3/aks-spoke.
# scripts/test-fixture.sh sets CATALOG_SOURCE_PREFIX / CATALOG_SOURCE_SUFFIX
# (working tree, or a pushed ref with CATALOG_REF); a real consumer hard-codes
# the pinned git URLs (see README).
locals {
  # Stands in for merge(env.hcl, region.hcl, { tags }) of a real consumer.
  settings = {
    environment  = "dev"
    name_prefix  = "demo"
    location     = "westus3"
    region_short = "wus3"

    hub_address_space   = ["10.0.0.0/22"]
    stamp_pool_prefix   = "10.16.0.0/16"
    stamp_prefix_length = 22
    enable_avnm         = true

    enable_external_dns_identity     = true
    enable_cert_manager_identity     = true
    enable_external_secrets_identity = true

    tags = { Environment = "dev", ManagedBy = "Terragrunt" }
  }
}

unit "hub" {
  source                  = "${get_env("CATALOG_SOURCE_PREFIX")}units/hub${get_env("CATALOG_SOURCE_SUFFIX", "")}"
  path                    = "hub"
  no_dot_terragrunt_stack = true

  values = local.settings
}

unit "aks_spoke" {
  source                  = "${get_env("CATALOG_SOURCE_PREFIX")}units/aks-spoke${get_env("CATALOG_SOURCE_SUFFIX", "")}"
  path                    = "aks-spoke"
  no_dot_terragrunt_stack = true

  values = local.settings
}
