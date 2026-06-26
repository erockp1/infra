output "rg_net_name" {
  value = local.rg_name
}

output "rg_net_location" {
  value = local.rg_location
}

output "cloud_vnet_id" {
  value = azurerm_virtual_network.cloud.id
}

output "cloud_vnet_name" {
  value = azurerm_virtual_network.cloud.name
}

output "onprem_vnet_id" {
  value = azurerm_virtual_network.onprem.id
}

output "onprem_vnet_name" {
  value = azurerm_virtual_network.onprem.name
}

output "app_subnet_id" {
  value = azurerm_subnet.app.id
}

output "dc_subnet_id" {
  value = azurerm_subnet.dc.id
}

output "mgmt_subnet_id" {
  value = azurerm_subnet.mgmt.id
}

output "dc_nsg_id" {
  value = azurerm_network_security_group.dc.id
}

output "dc_nsg_name" {
  value = azurerm_network_security_group.dc.name
}

output "mgmt_nsg_id" {
  value = azurerm_network_security_group.mgmt.id
}

output "mgmt_nsg_name" {
  value = azurerm_network_security_group.mgmt.name
}

output "app_nsg_id" {
  value = azurerm_network_security_group.app.id
}

output "app_nsg_name" {
  value = azurerm_network_security_group.app.name
}

output "private_dns_zone_name" {
  value = azurerm_private_dns_zone.realm.name
}

output "peering_ids" {
  value = {
    cloud_to_onprem = azurerm_virtual_network_peering.cloud_to_onprem.id
    onprem_to_cloud = azurerm_virtual_network_peering.onprem_to_cloud.id
  }
}
