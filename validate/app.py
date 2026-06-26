"""
POC 0 — LDAPS bind test app (stateless, non-domain-joined).

Two endpoints prove the POC-0 mechanism:
  POST /bind   {username, password} -> LDAPS simple bind as that user (password check)
  POST /check  {username}           -> service-account bind, read userAccountControl
                                       (account policy: disabled/locked/expired)
  GET  /healthz                     -> liveness

TLS: the rig CA is baked into the OS trust store at build time. We pin the
acceptable server name to DC_FQDN via ldap3 Tls(valid_names=...), so connecting
by anything other than the cert SAN (e.g. by IP) fails — exactly the SAN failure
mode documented in Chunk 4. The app connects by FQDN, resolved via the VNet DNS
(the DC) across the peering.
"""
import os
import ssl

from flask import Flask, request, jsonify
from ldap3 import Server, Connection, Tls, ALL, SUBTREE
from ldap3.core.exceptions import LDAPException, LDAPBindError

app = Flask(__name__)

DC_FQDN = os.environ["DC_FQDN"]
BASE_DN = os.environ["BASE_DN"]
REALM = os.environ.get("REALM") or DC_FQDN.split(".", 1)[1]
BIND_DN = os.environ.get("BIND_DN", "")
BIND_PW = os.environ.get("BIND_PW", "")
CA_FILE = os.environ.get("CA_FILE", "/etc/ssl/certs/ca-certificates.crt")
LDAP_PORT = int(os.environ.get("LDAP_PORT", "636"))

# userAccountControl bit flags (subset we surface)
UAC = {
    "normal_account": 0x0200,
    "disabled": 0x0002,
    "locked": 0x0010,
    "password_expired": 0x800000,
    "dont_expire_password": 0x10000,
}


def make_server():
    # validate=CERT_REQUIRED -> chain must verify against the baked CA.
    # valid_names=[DC_FQDN]  -> server cert SAN must include the FQDN we dialed.
    tls = Tls(ca_certs_file=CA_FILE, validate=ssl.CERT_REQUIRED, valid_names=[DC_FQDN])
    return Server(DC_FQDN, port=LDAP_PORT, use_ssl=True, tls=tls, get_info=ALL)


def to_upn(username):
    if "@" in username or "=" in username:
        return username
    return f"{username}@{REALM}"


@app.get("/healthz")
def healthz():
    return jsonify(status="ok", dc=DC_FQDN), 200


@app.post("/bind")
def bind():
    data = request.get_json(force=True, silent=True) or {}
    username = (data.get("username") or "").strip()
    password = data.get("password") or ""
    if not username or not password:
        return jsonify(result="error", reason="username and password required"), 400
    try:
        # auto_bind=True performs the LDAPS simple bind; success here == valid password.
        conn = Connection(make_server(), user=to_upn(username), password=password, auto_bind=True)
        # "Who am I?" (RFC 4532) is optional — Samba AD DC doesn't advertise it, so
        # treat its absence as non-fatal; the bind already succeeded.
        try:
            whoami = conn.extend.standard.who_am_i()
        except LDAPException:
            whoami = None
        conn.unbind()
        return jsonify(result="success", bound_as=to_upn(username), whoami=whoami), 200
    except LDAPBindError as e:
        return jsonify(result="failure", reason="invalid credentials", detail=str(e)), 401
    except LDAPException as e:
        # TLS/cert/SAN/network errors land here — distinguishable from auth failure.
        return jsonify(result="error", reason="ldap/tls error", detail=str(e)), 502


@app.post("/check")
def check():
    data = request.get_json(force=True, silent=True) or {}
    username = (data.get("username") or "").strip()
    if not username:
        return jsonify(result="error", reason="username required"), 400
    if not BIND_DN or not BIND_PW:
        return jsonify(result="error", reason="service account not configured"), 500
    try:
        conn = Connection(make_server(), user=BIND_DN, password=BIND_PW, auto_bind=True)
        found = conn.search(
            BASE_DN,
            f"(sAMAccountName={username})",
            search_scope=SUBTREE,
            attributes=["sAMAccountName", "userAccountControl", "distinguishedName"],
        )
        if not found or not conn.entries:
            conn.unbind()
            return jsonify(result="not_found", username=username), 404
        entry = conn.entries[0]
        uac = int(entry.userAccountControl.value)
        dn = str(entry.distinguishedName.value)
        conn.unbind()
        flags = {name: bool(uac & mask) for name, mask in UAC.items()}
        return jsonify(result="success", username=username, dn=dn,
                       userAccountControl=uac, flags=flags), 200
    except LDAPException as e:
        return jsonify(result="error", reason="ldap/tls error", detail=str(e)), 502


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", "8080")))
