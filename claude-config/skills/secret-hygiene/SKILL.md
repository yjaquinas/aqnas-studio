---
name: secret-hygiene
description: Defines the AQNAS discipline for handling secrets when sharing diagnostics, logs, or system state — with Claude, in screenshots, in support tickets, in chat threads, or anywhere outside a secure local context. Covers what to redact (API tokens, private keys, OAuth tokens, JWTs, basic-auth strings, server IPs, session IDs, database URLs with credentials), which commands commonly leak secrets in their default output (journalctl with --environ, systemctl show, env/printenv, cat of /etc/default/*, /etc/systemd/system/*.service.d/*, ~/.bashrc, ~/.zshrc, deploy scripts), and concrete redaction patterns using grep, sed, and awk. Includes the emergency procedure if a secret is accidentally exposed: treat as compromised, rotate immediately, document in findings. Use when the user is about to share command output, log excerpts, config files, or any text that may have been generated from a system with live credentials. Auto-load when the conversation involves debugging, sharing diagnostics, log analysis, troubleshooting deploys, or pasting output from journalctl, systemctl, env, or similar.
---

# secret-hygiene

How to share diagnostics without leaking secrets.

## Why this exists

`commit-git` protects secrets from landing in commits. This skill covers a different surface: secrets in transit — pasted into chat, screenshotted into a ticket, dropped into a debugging conversation with Claude or anyone else. The pattern "paste the full output of {diagnostic command}" is common and often safe, but a single careless paste can expose a credential that took five minutes to generate and an hour to rotate.

The discipline: redact before sharing, every time.

## What never to share, regardless of context

- **Private keys** — anything between `-----BEGIN OPENSSH PRIVATE KEY-----` and `-----END OPENSSH PRIVATE KEY-----`, or the RSA/DSA equivalents. Same for `.pem`, `.key`, `.p12`. Even partial keys are sensitive.
- **API tokens** — patterns like `cfut_*` (Cloudflare User Token), `ghp_*` / `ghs_*` / `gho_*` (GitHub), `sk-*` (OpenAI/Anthropic), `xoxb-*` (Slack bot), `Bearer eyJ*` (JWTs).
- **OAuth tokens, refresh tokens, session tokens** — anywhere you see `Authorization:`, `access_token=`, `refresh_token=`, `session=`.
- **Basic-auth strings** — `Authorization: Basic <base64>` decodes to `user:password`. Both halves leak.
- **Database URLs with credentials** — `postgres://user:pass@host/db`, `mysql://...`, MongoDB connection strings. Credentials are in the URL itself.
- **Server IPs and DNS names** — the production host's address is in `~/.ssh/config` and CI secrets only. Never in commits, never in pastes.
- **`.env` contents** — the whole point of `.env` is that it's never seen. If you paste it, you've defeated the design.

## Commands that commonly leak secrets

These are useful for diagnostics but their default output is dangerous to paste verbatim:

| Command | Why it's dangerous |
|---|---|
| `journalctl -u <service>` | systemd services log env vars via `--environ` flag. Caddy does this by default — its journal includes `CLOUDFLARE_API_TOKEN=cfut_...` on every restart. |
| `systemctl show <service>` | Prints the unit's full `Environment=` lines including secret values. |
| `cat /etc/systemd/system/*.service.d/override.conf` | Drop-ins commonly contain `Environment=` lines with raw tokens. |
| `cat /etc/default/<service>` | Older sysv-style env files. Same hazard. |
| `env` / `printenv` | Dumps the current shell's full environment. If you sourced anything from `.env`, it's in here. |
| `cat ~/.bashrc` / `~/.zshrc` / `~/.profile` | Some people put tokens in shell config. |
| `cat /opt/{project}/.env` | The production env file. Mode 600 keeps the file private, but printing it defeats that. |
| `ps aux` / `ps -ef` | Process listings can show tokens passed as command-line args (common mistake). |
| Web server access logs | Some requests embed tokens in URLs or `Authorization` headers. Caddy's default log format redacts headers; not all servers do. |

## Redaction patterns

Before pasting any of the above, filter the output. Pick the pattern that fits.

### Strip lines containing specific tokens

```sh
# Remove any line with CLOUDFLARE_API_TOKEN, GITHUB_TOKEN, SECRET, etc.
journalctl -u caddy -n 100 | grep -v -iE 'token|secret|password|api_key'
```

`-v` inverts the match (keep lines NOT matching); `-i` is case-insensitive; `-E` enables extended regex.

### Substitute specific values

```sh
# Replace your production IP with <redacted>
journalctl -u caddy -n 100 | sed 's/140\.245\.71\.141/<redacted-prod-ip>/g'

# Replace any cfut_* token
some_command | sed -E 's/cfut_[a-zA-Z0-9]{40,}/<redacted-cf-token>/g'
```

### Filter env-var dumps specifically

```sh
# Pipe through grep -v on `=` patterns that look secret
env | grep -v -iE '_(TOKEN|KEY|SECRET|PASSWORD|API)='
```

### Compose patterns

For the Caddy case specifically (the one that bit during hello-aqnas Phase 3):

```sh
# Safe Caddy journal share: strip the env dump entirely, keep the actual log
sudo journalctl -u caddy -n 100 --no-pager \
  | grep -v -iE '_(TOKEN|KEY|SECRET|PASSWORD|API)=' \
  | sed 's/140\.245\.71\.141/<redacted-prod-ip>/g'
```

## How to share logs safely

1. Run the diagnostic command into a temp file:
   ```sh
   sudo journalctl -u caddy -n 100 > /tmp/diag.log
   ```
2. Open the file in an editor or pager — `less /tmp/diag.log` — and scan for anything sensitive.
3. Pipe through a redaction filter if needed:
   ```sh
   < /tmp/diag.log grep -v -iE 'token|secret|password' > /tmp/diag-clean.log
   ```
4. Review the *cleaned* file before sharing: `less /tmp/diag-clean.log`.
5. Paste the cleaned content. Mention briefly that you redacted credentials so the receiver knows the output isn't literal.
6. Delete the temp files when done: `rm /tmp/diag*.log`.

If you're sharing a screenshot, redact in the image editor (black-out rectangle over the sensitive region) — don't trust that the screenshot is "too small to read." Vision models read small text.

## Emergency procedure: a secret leaked

If a secret value (token, key, password) was exposed — pasted into chat, committed to a repo, screenshotted, anywhere — treat it as **compromised**. Don't wait to see if anyone used it; rotate immediately.

1. **Rotate the secret in its source.** Generate a new token, key, or password. Cloudflare API tokens rotate via the dashboard. GitHub PATs and deploy keys are revoke-and-recreate. SSH keys are remove-from-`authorized_keys` and replace.
2. **Update every consumer.** systemd drop-ins, `EnvironmentFile`, GitHub secrets, anywhere the old value was referenced. `systemctl daemon-reload && systemctl restart <service>` for each.
3. **Verify the old value no longer works.** Try authenticating with it; expect failure. If it still works, rotation didn't take effect.
4. **Document in `docs/findings.md`** — add an entry with date, what leaked, how it leaked, what was rotated. Future-you will want the history. Don't include the old value in the entry.

Don't rationalize ("it was only visible briefly"). Don't assume goodwill ("nobody saw it"). The cost of rotation is minutes; the cost of a compromised credential operating in your systems is open-ended.

## What this skill never does

- It doesn't replace `commit-git`'s gitleaks scan for in-repo secrets. That's a different surface.
- It doesn't enforce — there's no pre-paste hook. The discipline is yours to apply.
- It doesn't help with secrets at rest. Use `.env` mode 600, systemd `EnvironmentFile`, and `/etc/sudoers.d/` for that.

## See also

- `commit-git` — secrets in commits
- `caddy-config` — Caddy's `--environ` journal behavior and the override.conf pattern
- `deploy-procedure` — `.env` ownership model on the production host
