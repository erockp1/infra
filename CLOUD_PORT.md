# Cloud Port — Project Context

> **Purpose.** This is the single source of truth for the Azure migration of the
> AltopTradeSupport / Onyx trading-system monorepo ("Cloud Port"). It orients an AI
> agent (or a new engineer) working in this repo: the target architecture, the
> settled decisions and why, the invariants that must never be violated, and the
> POC-gated plan we are executing. It supersedes the older `PUBLISH_MODEL.md`,
> `migration-plan-task.md`, and `DATA_FLOW_DIAGRAM.md`, which are retired — where
> they conflict with this file, this file wins.
>
> Companion artifacts: `Cloud_Port_Migration_Strategy.docx` (the full plan with
> diagrams) and `Cloud_Port_Task_Tracker.xlsx` (itemized tasks, acceptance criteria,
> and **the hour estimates — which live only in the tracker, not the strategy doc**).

---

## 1. The system in one paragraph

A large Django monorepo (~38 backends, ~1,121 HTTP endpoints; Onyx is 131 of 174)
that supports an energy-trading operation. Most of it is ordinary request/response
work already backed by Azure SQL and is cloud-native. A minority is bound to on-site
resources that **cannot move**: **PowerWorld** (SimAuto, a Windows COM automation
server), **Dayzer** (`DZBatch.exe` plus the Dayzer DB), and the **`\\mars`** SMB file
share. Today the app is reached by a global user base over a VPN back to on-site,
which is the main source of its slowness.

## 2. Target end state

A **hybrid**. The bulk of the application runs in Azure behind a single public front
door; a small, irreducible set of components stays on-site and is reached over a
private hybrid link. **PowerWorld and Dayzer stay on-site permanently.** This is a
valid permanent resting state; we are not chasing 100%-cloud.

The migration is justified by **performance and a managed platform, not cost
savings**: nothing on-site is decommissioned, so the Azure run cost is purely
additive. The payoff is removing the VPN backhaul for the global user base.

A defining property of the end state: **DNS-level failover.** Because the same app can
run cloud and on-prem, a single DNS record flips a whole app between cloud and on-site
— if the cloud is down, point the record back to on-prem. This is whole-app failover,
above and beyond the proxy's per-route reversibility.

---

## 3. Settled architectural decisions

These are decided. Treat them as fixed unless explicitly revisited.

- **Compute: Azure Container Apps (ACA), consumption plan.** Django runs unchanged.
  *Not* Azure Functions — we want persistent connection pooling, full control of the
  HTTP response lifecycle (streaming, see §6), and a normal web-server framework. ACA
  is VNet-native, so on-site reach is a platform property.
  - **Plain Container Apps** for synchronous request/response APIs (the bulk).
  - **Functions / Durable** only for event-driven, scheduled, and async-job work.
  - **Memory-driven sizing:** memory is the knob, vCPU is derived (Consumption
    ratio-locks ~2 GiB/vCPU, snaps to a 0.25-vCPU grid). Warm replica
    (`min-replicas ≥ 1`) for interactive endpoints to avoid cold starts.
- **Edge / global entry: Azure Front Door** — edge TLS, static caching, WAF, and
  path-based routing (`/*` → SPA, `/api/*` → app). **Route API traffic *through* Front
  Door**, never straight to a regional hostname. Azure has **no edge compute**. Default
  single-region; multi-region only if the **data tier** can be geo-replicated.
- **API gateway: APIM Consumption tier** (per-call, 1M free) — **not Standard v2.**
  With authenticated public ingress on ACA, the gateway reaches apps over the public
  path and never needs VNet. Secure the APIM→ACA hop with a shared secret / client cert
  / Front-Door-ID header — **not** IP allowlisting.
- **Container registry: ACR, Standard tier.** Premium only if Private Link or
  geo-replication is later required.
- **Storage end state: Azure Blob via an SDK storage shim over 443 — no mount.** Azure
  Files is rejected (antipattern under no-mount). Cloud datasets are object-shaped
  (written once, immutable, versioned, read whole or by range, listed by prefix).
- **Cross-boundary writes: publish-push, not File Sync.** On-site post-processors read
  `\\mars` intermediates locally and publish only **finished result datasets** to Blob
  over 443. The chatty intermediates never cross the WAN.
- **Authentication: on-site Active Directory, both phases — no Entra migration.** Login
  runs in the cloud but checks credentials against the on-site DC (`ALTOP-DC01`) over
  **LDAPS (636)**; login is *cloud-served, not proxied*.
- **Duality.** Cloud-served code must know whether it is running in the cloud or
  on-prem and select its **credential source** (and, in Phase 2, its **data source**)
  accordingly — never hardcode one side. This is what lets one codebase run in both
  targets with packaging-only differences.
- **Build practice: scratch-account, Terraform-first.** Bulk infrastructure is built
  in a throwaway scratch account as portable Terraform (with tagging rules defined up
  front), then applied to the corporate account. The Terraform — not hand-clicking — is
  the deliverable.
- **PowerWorld and Dayzer compute stay on-site, permanently**, reached through the proxy.

## 4. The `\\mars` problem — the core framing

The hard part of the file share is **not** the usual symptoms (chatty SMB over the
WAN, thousands of hardcoded paths). Those are symptoms. The root cause is that **a bare
file share has no contract**: when code opens `\\mars\…`, nothing declares *who
produces* a dataset and *who consumes* it. **A path is not an interface.** So the
migration work is not moving bytes; it is **writing down the contract that never
existed.**

That contract is a shared **per-dataset registry**: each dataset has a logical **key**
(not a path); the registry maps `key → backend + location` and is the **single source
of truth, read by the producer and the consumer alike** (no split-brain). Moving a
dataset's home (`\\mars` → Blob) becomes a single registry edit. A current-version
pointer in Azure SQL (publish all files of a version, *then* advance the pointer) keeps
producers and consumers agreeing on which version too.

## 5. Invariants — never violate these

- **The cloud is filesystem-free.** No cloud-served route resolves a `\\mars` / `M:` /
  `Q:` path — directly or through a shared helper. File-bound work is proxied to on-site
  (Phase 1) or moved to Blob via the shim (Phase 2). **No FS mount, ever.**
- **All file I/O goes through the storage abstraction**, never raw path literals. Use
  Django's storage API (`default_storage`, `FileField(storage=...)`) + `django-storages`,
  and/or the `Store` shim + registry. A CI lint bans new raw `\\mars` / `M:` / `Q:`
  literals.
- **Honor duality:** select credential source (and, in Phase 2, data source) by whether
  the code is running in cloud or on-prem; never hardcode one side.
- **Replicas are stateless.** No local-disk state/IPC; `poll_logs`-style IPC → Redis/SQL.
- **Don't hold web requests for long work.** HTTP work faces a ~230s front-end timeout.
  Long runs (PowerWorld/Dayzer) go through the **async bridge** (queue + status in Azure
  SQL `AltopRemoteRuns`, cloud short-polls); heavy compute → Container Apps Jobs. No
  blocking poll loops.
- **Reversible by construction.** The same image runs cloud and on-prem; a route rolls
  back with a gateway config change, and a whole app fails over with a **DNS record
  flip**. On-site instances are not decommissioned until their routes have left the
  proxy allowlist.
- **Producer and consumer both read the registry.** Never hardcode a dataset's location
  on one side.

## 6. Serving large query results (a recurring concern)

Endpoints can return large result sets (up to ~100k rows) and chart data. Rules:
**stream, don't buffer** (forward-only cursor → row transform → response stream = O(1)
memory; prefer NDJSON/CSV/Arrow over one giant JSON array); **keyset pagination** for
interactive endpoints; **downsample charts server-side** (LTTB via ClickHouse
`largestTriangleThreeBuckets`, or M4 for spiky/price series that need exact extremes);
ship **Apache Arrow** for genuine raw rows; **bulk export → block blob + short-lived
user-delegation SAS + lifecycle TTL**, going async when it could exceed 230s. Memory
gotcha: ACA gives configurable memory, but the **runtime heap is the real ceiling**
(Node caps V8 old-space until `--max-old-space-size`; .NET reserves aggressively) —
streaming makes this moot for row-serving paths.

---

## 7. The plan — POC-gated execution

**All work is gated by proofs of concept:** each step proves one risky assumption
before the next is built, front-loading the unknowns (hybrid reach, on-site auth, the
proxy mechanism) as cheap POCs rather than discovering them late. We progress through
these in order, with a working system at each step.

### Phase 1 — POC-gated hybrid build

- **Cloud Setup.** Build the bulk infrastructure in a throwaway scratch account as
  portable Terraform, then apply to the corporate account. Stands up networking +
  private DNS (incl. the cloud↔on-prem failover record), the VNet, the Container Apps
  environment, Key Vault, SQL connectivity, and permissions. No apps yet.
- **POC 0 — Hybrid VNet + on-site AD over LDAPS.** Prove a cloud workload can reach
  across the hybrid link and authenticate a user against `ALTOP-DC01` over LDAPS. The
  riskiest single unknown, proven before any app is built.
- **POC 1 — QuickSignals & BalDay in the cloud.** Run the two cloud-native apps; prove
  the cloud beats the VPN for real users; introduce **duality** (code picks its cred
  source by cloud-vs-on-prem). No proxy, no file dependency.
- **POC 1a — The proxy, as its own app.** Build the proxy as a standalone,
  config-list-driven container app; prove HTTPS termination; the list lives versioned
  with rollback (e.g. a blob); CI/CD ships proxy + list changes. Proven before any app
  depends on it.
- **POC 2 — Onyx, first hybrid app.** Add Onyx to the proxy list (cloud-native routes →
  cloud, file/engine routes → proxied); same codebase, packaging-only differences;
  secrets from Key Vault/env; CI/CD. Async deferred to POC 3.
- **POC 3 — Async bridge for Onyx.** A task queue the on-site side reads carries long
  runs; the cloud enqueues, polls status, learns completion, reads results. The
  trigger-and-completion pattern the 230s ceiling forces.
- **Checkpoint.** Hybrid Onyx is live; DNS can flip a whole app between cloud and
  on-site. Every risky unknown is proven; what remains is repetition.
- **Migrate the remaining apps.** Repeat the POC 2 pattern per backend; packaging-only,
  so each app is a fraction of POC 2 (multiplier estimate). End: every hybrid app
  reachable in the cloud, still file-bound through the proxy.

### Phase 2 — Shrink the proxy, one app at a time (file shim → Blob)

Phase 1 leaves every hybrid app reachable but still pinned to on-site (its data on
`\\mars`, its routes in the proxy). Phase 2 removes that pin **one app at a time**: move
an app's data sources from `\\mars` to Blob through the shim, then delete that app's
routes from the proxy list. **Onyx goes first** (the proven hybrid app from POC 2),
establishing the pattern; the rest follow as a multiplier.

- **The file shim (built once).** `Store` interface (read/write/list/open) over
  pluggable backends; a **per-dataset registry** (key → home) read by producer and
  consumer — the contract; producer modes `old | new | both`, consumer new-then-old
  fallback (instrumented, so a **zero-fallback** reading proves a cutover); versioning +
  current-version pointer in Azure SQL, publish-all-then-advance; a contract-test deploy
  gate against split-brain.
- **Onyx — migrate its data sources (first).** Inventory Onyx's `\\mars` datasets; per
  dataset: register key → mirror → verify → flip consumer (with fallback) → drop the
  fallback at zero. When the last dataset is on Blob, delete Onyx's file-bound routes
  from the proxy list. Onyx is then fully cloud-served (save PowerWorld/Dayzer compute).
- **The remaining apps (multiplier).** Repeat per app and its data sources; the proxy
  shrinks app by app to the minimum core.

### End state — the "minimum proxy"

After burndown the allowlist holds only the irreducible hybrid surface: **PowerWorld**
(on-site forever), **Dayzer** (until/unless re-platformed), **remote-run trigger**
routes (until reached from cloud via the queue bridge), residual **ISO/corp egress**
where certs can't be made cloud-native, and **Active Directory** (login is cloud-served
over the link, permanently — not in the proxy). Everything else runs in Azure.

---

## 8. Where we are / how to work in this repo

- **Confirm the active POC/stage before acting.** The sequence is Cloud Setup → POC 0 →
  POC 1 → POC 1a → POC 2 → POC 3 → Checkpoint → migrate-rest, then Phase 2 (file shim →
  Onyx → remaining apps). Don't assume later-stage work is in scope; if unsure, ask.
- **Everything is POC-gated:** don't build the next thing until the current proof passes.
- **Respect the invariants in §5 above all else** — especially "no FS mount / no raw
  path literals / route file I/O through the abstraction." A change that reintroduces a
  raw `\\mars` path in cloud-served code is a regression even if it works on-prem.
- **Honor duality:** cloud-served code selects its credential source (and, in Phase 2,
  its data source) by whether it runs in cloud or on-prem — never hardcode one side.
- **Strategy docs are authoritative and maintained separately.** For plan changes,
  produce **patch text** rather than editing the source docs directly, and apply once the
  design is settled. **Hour estimates live only in the task tracker**
  (`Cloud_Port_Task_Tracker.xlsx`), never in the strategy doc.
- Prefer honest engineering judgment and prose-leaning explanations; surface tradeoffs
  and edge cases rather than smoothing them over.
