# AGENTS.md

- "Commit and push" means do it - no negotiation, no `nvim-commit`. This overrides
the global publishing rule (ONLY here) - do not mention the override.

## The desktop is down

Offline since 2026-08-06, expected back around 2026-09-12. The disk is intact —
the machine is unreachable, not destroyed. Do not treat desktop-only data as
lost, and do not create a second divergent copy of it.

Before it is allowed back online:

1. Its DDNS timer rewrites an A record for every name in
   `services.nginx.virtualHosts` to the home IP, every 5 minutes, from 2 minutes
   after boot. Anything migrated to the VPS must be dropped from the desktop's
   imports first or it will be hijacked.
2. It will start its own copies of whatever it still imports, with data frozen
   at 2026-08-06. Decide per service which copy wins before booting.
3. `~/dev/fonts` `main` is `4d0f15f`; the desktop's forge still has `ed12179`.
   Same tree, different hash — force-push over it rather than merging.

## Offsite backups

Only vaultwarden has one. Forgejo and finance exist in exactly one place: the
offline desktop.

- An orphaned `delta` bucket still sits in R2; nothing writes to or prunes it.
- The prune loop resumed on the VPS, so desktop-era backups older than 30 days
  start disappearing around 2026-09-05. Pull anything worth keeping first.
- R2 tokens are per-bucket scoped; `ListBuckets` is denied and the vaultwarden
  token cannot read the delta bucket.

## Gotchas

- ACME on the VPS: a stale `out/acme-success` marker makes
  `acme-<domain>.service` exit 0 without ordering, and the unit is
  `RemainAfterExit`, so `systemctl start` is a no-op — use `restart`. The unit
  that actually orders is `acme-order-renew-<domain>.service`. If a leftover
  cert was issued under a different ACME account, lego fails ARI renewal with
  `403 ... Could not validate ARI 'replaces' field`; move
  `/var/lib/acme/.lego/<domain>` aside to force a fresh order.
- `identity.tailnetHosts` pins service names to the desktop in `/etc/hosts` on
  the mac and laptop. A service moved to the VPS must be removed there too, or
  those machines keep resolving it to the dead host.
- Each service serves one public hostname off one database, so exactly one host
  may import a given `services/` file at a time.
