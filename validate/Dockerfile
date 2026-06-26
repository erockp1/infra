# POC 0 LDAPS-bind test app. The rig CA is baked into the OS trust store so the
# app trusts the DC's LDAPS cert without Key Vault (test-only; corporate sources
# trust from the internal CA). openssl + ldap-utils are included for in-container
# debugging (openssl s_client splits cert-trust from SAN from network).
FROM python:3.12-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates openssl ldap-utils \
    && rm -rf /var/lib/apt/lists/*

# Bake the rig Root CA into the trust store (ca.pem is written from the Chunk-4
# terraform output into this build context before build).
COPY ca.pem /usr/local/share/ca-certificates/poc0-rig-ca.crt
RUN update-ca-certificates

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py .

EXPOSE 8080
CMD ["python", "app.py"]
