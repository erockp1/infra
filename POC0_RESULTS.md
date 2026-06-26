# POC 0 — Results, Teardown, and Proven-vs-Pending

A self-contained Azure rig proving the **POC 0 mechanism** from Cloud Port: a
stateless, scale-to-zero, **non-domain-joined** Container App performing an **LDAPS
simple bind** against a domain controller **across a simulated hybrid boundary**, built
as portable Terraform so the corporate version is a `terraform.tfvars` swap.

Built and validated 2026-06-26. Subscription `13ea9848-…` (personal/free-tier), region
`eastus`, realm `poc0.lab`.

---

## What is proven (green)

- **LDAPS-bind auth mechanism.** A container in the cloud VNet binds over TLS/636 to the
  DC and authenticates users. Valid creds succeed; wrong creds fail cleanly and
  distinguishably.
- **CA trust + cert SAN.** Own Root CA + DC cert (SAN `dc01.poc0.lab`), CA baked into the
  app trust store. The app pins the server name (`valid_names`), so a SAN/host mismatch
  fails — the same failure shape corporate's internal-CA DC would exhibit.
- **Cross-boundary DNS.** The app resolves the DC **by name** (`dc01.poc0.lab`) via the
  VNet DNS (the DC) across the peering — verified in isolation with a throwaway cloud-VNet
  probe (container resolved `dc01.poc0.lab → 10.60.1.10`) and again end-to-end by the app.
- **The NSG path.** Least-privilege: the cloud reaches the DC only on 636 (LDAPS) + 53
  (DNS); SSH only via the jump from the home IP; on-prem initiates nothing toward the
  cloud; everything else default-denied.
- **The IaC itself.** Remote state, pinned providers, explicit RP registration, a $5
  budget guardrail, three lifecycle-split RGs with a `create_resource_groups` flag, and a
  fully parameterized variable surface — the corporate port is values, not edits.

## Validation matrix (post-hardening)

Run: `ALICE_PW=… BOB_PW=… ./validate/matrix.sh`

| Test | Result |
|---|---|
| valid user + correct password (alice, bob) → bind succeeds | ✅ PASS |
| valid user + wrong password → fails cleanly (`invalid credentials`, not a TLS error) | ✅ PASS |
| service-account `/check` reads `userAccountControl` (by-name + cert trust) | ✅ PASS (`512`) |
| DC resolved **by name** across the peering (not by IP) | ✅ PASS |

LDAPS failure signatures (know them against the real DC): SAN mismatch and untrusted
issuer both surface as `ldap_sasl_bind(SIMPLE): Can't contact LDAP server (-1)`;
`openssl s_client -connect <fqdn>:636 -CAfile ca.pem` distinguishes them
(`verify error:num=62:hostname mismatch` = SAN).

## DC NSG — least privilege (effective)

| Prio | Dir | Access | Proto | Ports | Source |
|---|---|---|---|---|---|
| 100 | In | Allow | TCP | 22 | mgmt subnet (jump) |
| 110 | In | Allow | TCP | 636 | app subnet (the cloud bind path) |
| 120 | In | Allow | UDP+TCP | 53 | app subnet (by-name DNS) |
| 130 | In | Allow | UDP+TCP | 53, 636 | mgmt subnet (jump validation) |
| 4000 | In | **Deny** | * | * | VirtualNetwork (everything else) |
| 4000 | Out | **Deny** | * | * | → app subnet (DC initiates nothing toward cloud) |

> Note: DNS/53 is part of the narrow inbound path because the cross-boundary **by-name**
> requirement depends on the cloud resolving the DC via the VNet's DNS (the DC). "Only 636"
> in the spec is shorthand; 53 is legitimately required and is itself a cloud→on-prem path.

---

## Cost & teardown hygiene

**Real cost = the two VMs** (`vm-altop-dc`, `vm-altop-jump`). Everything else is free or
near-free (VNets, peering, private DNS, NSGs, scale-to-zero Container App in the free
grant, ACR Basic, Log Analytics). The day-one **$5 subscription budget** (`budget-altop-poc0`,
alerts at 80% actual / 100% forecast → erockp1@gmail.com) is the backstop.

**Deallocate between sessions** (compute billing stops; you keep only cheap disk):
```sh
az vm deallocate -g rg-altop-onprem -n vm-altop-dc
az vm deallocate -g rg-altop-onprem -n vm-altop-jump
# restart next session:
az vm start -g rg-altop-onprem -n vm-altop-dc
az vm start -g rg-altop-onprem -n vm-altop-jump
```
> The VMs are `Standard_D2als_v7` (GP), not burstable B-series — this sub's eastus catalog
> has no B-series and a hard **4-vCPU regional quota** (DC+jump = 4/4). Deallocate-between-
> sessions matters for both cost and leaving room to maneuver.

**Full teardown** (destroys everything; state backend in `bootstrap/` survives):
```sh
terraform destroy   # uses terraform.tfvars
# optional: tear down the remote-state backend too
terraform -chdir=bootstrap destroy
```

Nothing in the rig holds real secrets or data — it is empty infrastructure with
throwaway test credentials only.

---

## Proven vs pending (keep this honest in the writeup)

**Proven** against a Samba-AD stand-in DC: the LDAPS-bind mechanism, CA-trust + cert-SAN
handling, cross-boundary DNS (by-name), the least-privilege NSG path, and the Terraform/IaC.

**Pending** (not provable in a separate personal tenant with simulated transport):
- Corporate **RBAC** and **Azure Policy** (you are Owner here; corporate will deny what
  this rig never hits — see "RBAC manifest" below).
- Reachability to the **real Windows `ALTOP-DC01`** over the **real hybrid link**
  (VPN/ExpressRoute), vs. this rig's VNet peering.
- Windows-AD-specific surface: cert **auto-enrollment**, schema/attribute and **GPO**
  nuances. Samba-AD is a faithful stand-in for the *bind itself*; this is the larger gap.

---

## Porting to corporate (what changes — and what doesn't)

**tfvars swaps only:** subscription/tenant IDs, region, RG names + `create_resource_groups=false`
(reference RGs you're handed), address spaces, tags, `name_prefix`, `domain_realm`/`base_dn`/
bind DN, and the **CA trust** (corporate internal CA instead of the rig CA).

**Two structural swaps (not a rewrite):** the **peering** becomes the real hybrid link
(owned by corporate networking); your **Samba-AD stand-in** becomes the real
`ALTOP-DC01` — you create no DC, you point at theirs (`dc_fqdn`).

**Unchanged by the swap:** the bind code, cert-trust handling, DNS path, and NSG rules.

**RBAC manifest the rig surfaces** (declare as explicit resources so the corporate apply
fails loudly on missing grants): the `AcrPull` role assignment for the app's user-assigned
identity, the data-plane `Storage Blob Data Contributor` needed for the AAD-auth state
backend, resource-provider registrations (corporate often pre-registers and may deny the
action), and — for the corporate port — **Key Vault** for the bind secret + CA trust
(this rig keeps test-only secrets in state/tfvars; **never reuse that pattern with real
credentials**).

---

## Environment deviations from the spec (and why)

| Spec | Rig reality | Why |
|---|---|---|
| Small B-series VMs | `Standard_D2als_v7` (cheapest current-gen GP) | This sub's eastus offers no B-series (capacity 409); B-series stays the module default, overridden in tfvars |
| JIT VM access | Jump VM, home-IP `/32` locked | JIT needs paid Defender for Servers (not free-tier); `enable_jit` left as a seam |
| `az acr build` (server-side) | Local `docker build --platform linux/amd64` + push | ACR Tasks blocked on this sub (`TasksOperationsNotAllowed`) |
| Consumption-only env (`/23`) | Workload-profiles env + Consumption profile (`/27`) | Current ACA default; smaller subnet, same free grant |
