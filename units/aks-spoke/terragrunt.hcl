# Generic wrapper around modules/aks-spoke of cloud-platform-modules-example: one AKS
# stamp (spoke VNet peered to the region's hub, AKS, workload identities,
# optional ACR and monitoring), wired to the hub, the network platform, the
# public DNS zones and the environment's Key Vault.
#
# Consumers never include this file; they instantiate it through a `unit`
# block (see README), which generates a directory containing a terragrunt.hcl
# that points here plus a terragrunt.values.hcl. Everything consumer-specific
# arrives through `values`, which use the key names of the platform's env.hcl
# and region.hcl so a consumer can pass `merge(env, region, {...})`.
#
# The consumer's tree must provide root.hcl (remote_state + provider).

include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  enable_avnm = try(values.enable_avnm, false)
}

terraform {
  # Double slash: the module uses a sibling source (../workload-identity), so
  # the whole repository must be fetched. Bump the ref to adopt a new module
  # release, then cut a new catalog tag.
  source = "git::https://github.com/traviscloud-com/cloud-platform-modules-example.git//modules/aks-spoke?ref=aks-spoke/v1.0.0"
}

dependency "hub" {
  config_path = try(values.hub_path, "../hub")

  # Mocks let init/validate/plan run before the hub exists (fresh clone, CI).
  # Shape must match modules/hub/outputs.tf of the tag pinned by units/hub.
  mock_outputs = {
    dns_resolver_inbound_ip = null
    firewall_private_ip     = null
    location                = "mockregion"
    resource_group_name     = "mock-rg-hub"
    vnet_id                 = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock-rg-hub/providers/Microsoft.Network/virtualNetworks/mock-vnet-hub"
    vnet_name               = "mock-vnet-hub"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

dependency "platform_network" {
  config_path = try(values.platform_network_path, "../../../platform/network")

  # Shape must match the consumer's platform-network outputs exactly
  # (cloud-platform-infra-example modules/platform-network/outputs.tf). Empty pool
  # map = static addressing, which is also what enable_avnm = false yields.
  mock_outputs = {
    ipam_pool_ids        = {}
    ipam_pool_prefixes   = {}
    network_group_ids    = {}
    network_manager_id   = null
    private_dns_zone_ids = {}
    root_pool_ids        = {}
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

dependency "public_dns" {
  config_path = try(values.public_dns_path, "../../../platform/dns")

  # Shape must match the consumer's public-dns outputs exactly
  # (cloud-platform-infra-example modules/public-dns/outputs.tf). Empty = no public
  # zone, which is also what enable_public_dns = false yields.
  mock_outputs = {
    env_zone_ids        = {}
    env_zone_names      = {}
    parent_name_servers = []
    parent_zone_id      = null
    parent_zone_name    = null
    resource_group_name = null
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

dependency "keyvault" {
  config_path = try(values.keyvault_path, "../../keyvault")

  # Shape must match modules/key-vault/outputs.tf of the tag pinned by
  # units/key-vault. Null = no vault, which also disables the
  # external-secrets identity.
  mock_outputs = {
    managed_secret_names  = []
    name                  = null
    operator_secret_names = []
    resource_group_name   = null
    resource_id           = null
    tenant_id             = null
    uri                   = null
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

exclude {
  if      = try(values.excluded, false)
  actions = ["all"]
}

inputs = {
  environment  = values.environment
  location     = values.location
  region_short = values.region_short
  name_prefix  = values.name_prefix
  # "" for the first stamp of a region, "-2" for the second, ...
  stamp_suffix = try(values.stamp_suffix, "")

  # Static fallback = the first /<stamp_prefix_length> of this region's stamp
  # pool; with enable_avnm the VNet is allocated from the pool instead.
  spoke_address_space = [cidrsubnet(values.stamp_pool_prefix, try(values.stamp_prefix_length, 22) - tonumber(split("/", values.stamp_pool_prefix)[1]), 0)]
  stamp_prefix_length = try(values.stamp_prefix_length, 22)
  ipam_pool_id        = lookup(lookup(dependency.platform_network.outputs.ipam_pool_ids, values.environment, {}), values.region_short, null)

  hub_vnet_id   = dependency.hub.outputs.vnet_id
  hub_vnet_name = dependency.hub.outputs.vnet_name
  # try(): Terraform omits null-valued outputs from state, so with the
  # firewall off the hub has no firewall_private_ip output at all.
  firewall_private_ip = try(dependency.hub.outputs.firewall_private_ip, null)
  # With the AVNM mesh on, east-west goes direct over the connected group; a
  # 10/8 UDR to the firewall would override that route, so none is added.
  firewall_routed_cidrs = local.enable_avnm ? [] : ["10.0.0.0/8"]
  outbound_type         = try(values.aks_outbound_type, "loadBalancer")
  avnm_routing          = local.enable_avnm && try(values.enable_avnm_routing, false)

  # Service discovery: zone from the platform (null when the env has it off),
  # external-dns identity, API server VNet integration.
  private_dns_zone_id          = try(values.enable_private_dns, false) ? lookup(dependency.platform_network.outputs.private_dns_zone_ids, values.environment, null) : null
  public_dns_zone_id           = lookup(dependency.public_dns.outputs.env_zone_ids, values.environment, null)
  enable_external_dns_identity = try(values.enable_external_dns_identity, false)
  enable_cert_manager_identity = try(values.enable_cert_manager_identity, false)
  # The vault may not exist yet (first plan of an environment, mocked
  # dependency): the identity then waits for the next plan after the vault
  # is applied instead of failing the module's validation.
  key_vault_id                       = try(dependency.keyvault.outputs.resource_id, null)
  enable_external_secrets_identity   = try(values.enable_external_secrets_identity, false) && try(dependency.keyvault.outputs.resource_id, null) != null
  enable_api_server_vnet_integration = try(values.enable_api_server_vnet_integration, false)

  kubernetes_version              = try(values.kubernetes_version, null)
  aks_sku_tier                    = try(values.aks_sku_tier, "Free")
  private_cluster_enabled         = try(values.private_cluster_enabled, false)
  api_server_authorized_ip_ranges = try(values.api_server_authorized_ip_ranges, [])
  admin_group_object_ids          = try(values.admin_group_object_ids, [])
  cluster_admin_principal_ids     = try(values.cluster_admin_principal_ids, [])
  system_node_pool                = try(values.system_node_pool, {})
  user_node_pools                 = try(values.user_node_pools, {})
  network_policy                  = try(values.network_policy, null)

  enable_acr                = try(values.enable_acr, true)
  acr_sku                   = try(values.acr_sku, "Basic")
  enable_log_analytics      = try(values.enable_log_analytics, false)
  log_retention_days        = try(values.log_retention_days, 30)
  enable_container_insights = try(values.enable_container_insights, false)
  enable_managed_prometheus = try(values.enable_managed_prometheus, false)
  enable_defender           = try(values.enable_defender, false)
  enable_azure_policy       = try(values.enable_azure_policy, false)
  enable_telemetry          = try(values.enable_telemetry, false)

  tags = try(values.tags, {})
}
