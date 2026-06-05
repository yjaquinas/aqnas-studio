# AQNAS Studio — Quickstart

Your first project, zero to deployed. Assumes the studio is already set up (`./setup.sh` ran cleanly, `aqnas-prod` SSH alias configured per the README).

For daily development, debugging, rollback, modifying infra config, or converting existing non-studio projects — see [how-to-use.md](how-to-use.md).

## 1. Scaffold the project

The studio is `pwd`-agnostic. README recommends `~/dev/` for code; pick whatever works.

```sh
mkdir -p ~/dev/my-project
cd ~/dev/my-project
claude
```

Inside Claude Code:

```
/start-new-app
```

Optional flags:

- `--no-mobile` — skip Hyperview templates and `mobile-client/`
- `--no-web` — skip HTMX templates (rare; mobile-only setups)

The skill prompts you to confirm:

- Display name (default: title-cased directory name)
- Domain (default: `<project>.aqnas.xyz`)

Then it allocates a port from the studio registry, populates the directory with the canonical scaffold, runs `uv sync`, installs the gitleaks pre-commit hook, and makes the initial commit.

## 2. Verify locally

```sh
./run.sh
```

Expect: a "Tailwind watcher running" line, then uvicorn on `127.0.0.1:8000`.

In another terminal:

```sh
curl -sS http://127.0.0.1:8000/health   # expect: ok
```

If either fails, fix locally before continuing. Don't push to GitHub or bootstrap the server until `./run.sh` boots cleanly.

## 3. Follow MANUAL-TASKS.md

The skill generated `MANUAL-TASKS.md` in your project root. Open it and work top-to-bottom — it walks you through:

1. **GitHub setup** — create the repo, configure the deploy SSH key, add `SSH_HOST` + `SSH_PRIVATE_KEY` secrets
2. **First push** (expected to fail — server isn't bootstrapped yet)
3. **Server bootstrap** — run `bootstrap-project.sh` over SSH, edit `/opt/<project>/.env`, add DNS in Cloudflare, start the service
4. **CI/CD verification** — push a marker commit and confirm end-to-end deploy works

The file has checkboxes — track your progress. It's gitignored (per-operator state, not project content).

If you delete `MANUAL-TASKS.md` and need it back, scaffold an empty test directory with `/start-new-app` and copy the file across.

## 4. After your first deploy

Daily loop:

```sh
cd ~/dev/my-project
git pull
./run.sh                                # local dev :8000
# Make changes, test locally
git push origin main                    # auto-triggers CI deploy
```

Watch all your projects at a glance:

```sh
cd ~/dev/aqnas-studio
./scripts/studio-status                 # streams over SSH to your server
```

Use `/commit-git` inside Claude Code instead of `git commit` directly — it scans for secrets and writes a conventional commit message.

## Where to go next

- **Feature work guided by Claude**: README → "Add a feature to an existing project" (the 4-step meeting loop)
- **Debug, rollback, modify infra config**: [how-to-use.md](how-to-use.md)
- **Convert an existing non-studio project**: [how-to-use.md](how-to-use.md) → Convert section
- **Stuck**: [findings.md](findings.md) for known issues and design decisions
