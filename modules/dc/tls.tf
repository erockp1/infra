# ===========================================================================
# Chunk 4 — LDAPS material. Issue our own CA + DC cert with the `tls` provider
# so we control the SAN (the #1 LDAPS failure) and the trust chain. Private keys
# live only in Terraform state (encrypted backend) and on the DC (delivered via
# the extension's protected settings) — never in the repo.
# ===========================================================================

# --- Root CA ---------------------------------------------------------------
resource "tls_private_key" "ca" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "tls_self_signed_cert" "ca" {
  private_key_pem   = tls_private_key.ca.private_key_pem
  is_ca_certificate = true

  subject {
    common_name  = "POC0 Rig Root CA"
    organization = "POC0 Rig"
  }

  validity_period_hours = 87600 # 10 years
  allowed_uses = [
    "cert_signing",
    "crl_signing",
  ]
}

# --- DC certificate (SAN must match the FQDN the app connects by) ----------
resource "tls_private_key" "dc" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_cert_request" "dc" {
  private_key_pem = tls_private_key.dc.private_key_pem

  subject {
    common_name  = local.dc_fqdn
    organization = "POC0 Rig"
  }

  # SAN: the connect FQDN (load-bearing) plus the bare realm for good measure.
  dns_names = [local.dc_fqdn, var.domain_realm]
}

resource "tls_locally_signed_cert" "dc" {
  cert_request_pem   = tls_cert_request.dc.cert_request_pem
  ca_private_key_pem = tls_private_key.ca.private_key_pem
  ca_cert_pem        = tls_self_signed_cert.ca.cert_pem

  validity_period_hours = 8760 # 1 year
  allowed_uses = [
    "server_auth",
    "key_encipherment",
    "digital_signature",
  ]
}
