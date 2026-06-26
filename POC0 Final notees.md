POC0 Final notees

⏺ Both VMs are deallocated — compute billing stopped; you keep only the cheap disks. The $5 budget guardrail stays live
as the backstop.

Final state

- Rig: parked. vm-altop-dc + vm-altop-jump deallocated; all networking, DNS, certs, ACR, ACA env, and the bind app
  remain in place (free/near-free).
- POC 0: proven and recorded. All 6 chunks green; POC0_RESULTS.md holds the validation matrix, NSG table, teardown,
  and the honest proven-vs-pending statement + RBAC manifest.
- Resumable. POC0-memory (+ MEMORY.md index) captures how to bring it back in any future conversation.

To wake it next time

az vm start -g rg-altop-onprem -n vm-altop-dc
az vm start -g rg-altop-onprem -n vm-altop-jump

# then: check chronyc tracking on the DC (LDAPS is time-sensitive), then ./validate/matrix.sh

The Samba domain re-provisions idempotently, so restart is clean.

One thing worth doing while it's fresh

The repo + its state are the deliverable and currently live only on this laptop. When you can, commit altop-infra to
durable source control — .gitignore already excludes state, secrets, and \*.pem, so it's safe — so the rig (disposable)
can be rebuilt from a clean checkout (the code is not).

You set out to de-risk the scariest unknown in the Cloud Port migration — can a cloud workload authenticate against
on-site AD over LDAPS — and it's now answered with a working, parked artifact and an honest map of what's left for the
corporate apply. That's exactly what POC 0 was for.
