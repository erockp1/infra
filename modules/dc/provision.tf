# ===========================================================================
# Chunk 3 — provision the Samba-AD domain via a CustomScript extension. The
# script (with embedded test passwords) is delivered in protected_settings so
# it is encrypted at rest. The script is idempotent, so the extension can
# re-run safely if its content changes.
# ===========================================================================
resource "azurerm_virtual_machine_extension" "dc_setup" {
  name                       = "dc-setup"
  virtual_machine_id         = azurerm_linux_virtual_machine.dc.id
  publisher                  = "Microsoft.Azure.Extensions"
  type                       = "CustomScript"
  type_handler_version       = "2.1"
  auto_upgrade_minor_version = true

  protected_settings = jsonencode({
    script = base64encode(templatefile("${path.root}/scripts/dc-setup.sh.tftpl", {
      realm_upper    = upper(var.domain_realm)
      realm_lower    = lower(var.domain_realm)
      domain_netbios = var.domain_netbios
      base_dn        = var.base_dn
      ou_name        = var.ou_name
      dc_ip          = var.dc_static_ip
      dns_forwarder  = var.dns_forwarder
      admin_password = var.domain_admin_password
      bind_cn        = var.bind_account_cn
      bind_password  = var.bind_account_password
      test_users     = var.test_users
      dc_fqdn        = local.dc_fqdn

      # Chunk 4 — LDAPS material (CA + DC cert + DC key). Delivered in protected
      # settings so the private key is encrypted in transit/at rest.
      ca_cert_pem = tls_self_signed_cert.ca.cert_pem
      dc_cert_pem = tls_locally_signed_cert.dc.cert_pem
      dc_key_pem  = tls_private_key.dc.private_key_pem
    }))
  })

  depends_on = [azurerm_virtual_machine_data_disk_attachment.dc_data]
}
