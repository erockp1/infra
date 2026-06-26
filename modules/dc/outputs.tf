output "rg_onprem_name" {
  value = local.rg_name
}

output "dc_private_ip" {
  value = azurerm_network_interface.dc.private_ip_address
}

output "dc_fqdn" {
  value = local.dc_fqdn
}

output "dc_vm_id" {
  value = azurerm_linux_virtual_machine.dc.id
}

output "dc_vm_name" {
  value = azurerm_linux_virtual_machine.dc.name
}

output "jump_public_ip" {
  value = azurerm_public_ip.jump.ip_address
}

output "jump_vm_name" {
  value = azurerm_linux_virtual_machine.jump.name
}

output "ssh_proxyjump_hint" {
  description = "How to reach the DC through the jump."
  value       = "ssh -i ~/.ssh/altop-poc0-ed25519 -J ${var.admin_username}@${azurerm_public_ip.jump.ip_address} ${var.admin_username}@${var.dc_static_ip}"
}

# Chunk 4 — the CA cert (public) for Chunk 5 to bake into the app trust store.
output "ca_cert_pem" {
  description = "Rig Root CA certificate (PEM). Trust anchor for the LDAPS DC cert."
  value       = tls_self_signed_cert.ca.cert_pem
}

output "ldaps_fqdn" {
  description = "FQDN the app must connect by (matches the DC cert SAN)."
  value       = local.dc_fqdn
}
