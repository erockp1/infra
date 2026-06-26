Jump box — fixing SSH access when my IP changes
Symptom: SSH to the jump VM hangs or times out (no response). That means the NSG is dropping my connection because my current egress IP no longer matches the allowed /32.
(If instead it prompts for my SSH key and then rejects it — that's a key problem, not this. This note only applies when the connection hangs at the network layer.)
Why it happens: the jump's NSG rule only allows inbound SSH from my IP. On the corporate VPN, that egress IP changes when the VPN connects/disconnects or rotates gateways. When it changes, the firewall no longer recognizes me.
The fix (two steps):

Find my current egress IP:

curl -s https://ifconfig.me
(or curl -s https://api.ipify.org)

Update the rule with it:

terraform apply -var="home_ip_cidr=<new-ip>/32"
This updates only the NSG rule — a few seconds, nothing rebuilds. SSH works again.
To check before assuming: run the curl line and compare to the home_ip_cidr value in my tfvars. If they differ, that's the cause.
If this happens often (VPN rotates between several gateway IPs): stop chasing single IPs — widen the rule to the VPN's egress range once:
terraform apply -var="home_ip_cidr=<range>/29"
Get the published egress range from IT, or watch what ifconfig.me returns across a few sessions and cover them. (Use whatever CIDR size matches the pool — /29, /28, etc.)
Note: home_ip_cidr is really "admin source IP" — it's my VPN's exit address, shared by everyone on that VPN, not unique to me. Fine for this throwaway rig (SSH is still key-only), just don't mistake it for a personal identifier.
