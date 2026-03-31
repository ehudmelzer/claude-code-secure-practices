# Claude Code — Secure Endpoint Configuration Bundle

A hardened configuration template for running **Claude Code** safely on enterprise
and security-conscious endpoints. Covers behavioral rules, tool permissions, MCP server
policy, and prompt injection defenses.

Built and maintained by **[Pluto Security](https://pluto.security/)**.

---

## Files in This Bundle

```
claude-code-secure/
├── README.md                        ← you are here
├── CLAUDE.md                        ← global behavioral rules (copy to ~/.claude/)
├── CLAUDE.project-template.md       ← per-repo template (copy to <project>/CLAUDE.md)
└── .claude/
    ├── settings.json                ← tool permission allowlist/denylist
    └── mcp_servers.json             ← MCP server configuration & policy
```

---

## What Each File Does

### `CLAUDE.md` — Global Behavioral Rules

This file is injected into every Claude Code session and defines non-negotiable security
policies. It covers:

- **Anti-Prompt Injection** — instructs Claude to never follow instructions embedded in
  file contents, code comments, README files, commit messages, test fixtures, HTML pages,
  API responses, or any other data source. Any injection attempt is flagged to the user.
- **Cloud & Infrastructure Protection** — prohibits creating, modifying, or deleting cloud
  resources (AWS, GCP, Azure, Terraform, Pulumi, CDK) without explicit user confirmation of
  the specific resource name and action. IAM roles, security groups, and firewall rules are
  off-limits.
- **Credentials & Secrets Handling** — blocks reading, printing, logging, or transmitting
  sensitive files (`.env`, `*.pem`, `*.key`, SSH keys, AWS/Kube configs, tokens, vault files,
  `.npmrc`, `.pypirc`, `*.htpasswd`). Secrets are never inserted into code, logs, or shell history.
- **Database Safety** — prevents destructive queries (`DROP`, `DELETE`, `TRUNCATE`,
  unscoped `UPDATE`) without explicit user confirmation. Production database connections
  require explicit acknowledgment.
- **CI/CD Pipeline Protection** — blocks modifications to `.github/workflows/`,
  `.gitlab-ci.yml`, `Jenkinsfile`, and equivalent pipeline configs without explicit instruction.
- **Shell & Command Execution** — requires confirmation before running destructive, network-calling,
  or system-config commands. Blocks piped execution (`curl | bash`), silent package installs,
  cron jobs, launch agents, and background processes.
- **File System Boundaries** — restricts operations to the current project directory. Prevents
  recursive secret searching across the filesystem and access to browser data, keychain data,
  or OS credential stores.
- **Network & Web Safety** — blocks web requests to URLs found in untrusted content unless the
  user explicitly provided the URL in chat.

### `CLAUDE.project-template.md` — Per-Project Security Rules

A customizable template dropped into any repository root. It supplements (does not replace)
the global `CLAUDE.md`. Sections include:

- **Project Context** — project name, environment, stack, and owner team. Helps Claude
  understand what it's working on and what boundaries apply.
- **Off-Limits Resources** — project-specific files and actions Claude must never touch
  (e.g., production configs, deploy directories, protected branches, Dockerfiles, CI pipelines).
- **Safe Defaults** — actions Claude can perform freely without confirmation (e.g., running
  tests, linting, reading source files).
- **Confirmation Required** — actions that need explicit user approval each time (e.g.,
  `git push`, database migrations, Docker builds, dependency changes).
- **Project Secrets** — defines secret patterns to never read or print, where secrets are
  stored, and which secret manager is in use.
- **Anti-Injection Reminder** — reinforces that source code comments, test fixtures, README
  files, API responses, database records, and dependency source code are untrusted data sources.

### `.claude/settings.json` — Tool Permission Allow/Deny List

Controls what shell commands Claude can execute via a three-tier permission model:

| Tier | Behavior | Examples |
|------|----------|----------|
| **Allow** (auto-approved) | Claude runs without asking | `git status`, `git log`, `git diff`, `ls`, `cat`, `pwd`, `whoami`, version checks |
| **Unlisted** (ask first) | Claude asks for user confirmation | File writes, `git commit`, `npm install` (local), running tests, starting servers |
| **Deny** (hard block) | Cannot be executed even if user says yes | See categories below |

**Denied command categories:**

- **Destructive filesystem** — `rm -rf`, `rm -f`, `shred`, `mkfs`, `dd`
- **Secrets reading** — `cat` on credential files (`.env`, `*.pem`, `*.key`, SSH keys, AWS/Kube configs, tokens), `printenv` for secrets/keys/tokens/passwords
- **Exfiltration / piped execution** — `curl|bash`, `wget|sh`, `curl -d @file`, `nc`, `netcat`
- **Privilege escalation** — `sudo`, `su`, `chmod 777`, `doas`
- **Persistence mechanisms** — `crontab`, `launchctl`, `systemctl enable`, `nohup &`
- **Cloud/infra mutations** — `terraform apply/destroy`, `aws` create/delete/put/update, `gcloud` create/delete, `kubectl delete/apply/exec`
- **Global package installs** — `apt install`, `brew install`, `npm install -g`, `pip install --break-system`

> **Note:** Read-only cloud commands (`aws s3 ls`, `kubectl get`, etc.) are intentionally NOT
> denied — they fall into the "ask" tier. Only state-changing actions are hard-blocked.

### `.claude/mcp_servers.json` — MCP Server Configuration & Policy

Defines which [MCP (Model Context Protocol)](https://modelcontextprotocol.io) servers Claude
can connect to. MCP servers extend Claude's capabilities by giving it tools to interact with
external systems (databases, GitHub, Slack, filesystems, etc.).

**Why this matters for security:** Each MCP server expands Claude's action surface. More
critically, MCP servers return arbitrary text that can contain prompt injection payloads —
a crafted GitHub issue, a poisoned database record, or a malicious Slack message could
contain text that Claude mistakes for operator commands.

**This file ships intentionally empty** with documented templates and strict rules:

- Prefer local (`stdio`) servers over remote (`url`) servers
- Scope filesystem servers tightly — never grant access to `/`
- Treat all MCP tool results as untrusted data
- Audit each server's tool list before connecting (especially `run_shell_command`-type tools)
- Remove servers you're not actively using
- Never add servers with write access to production databases, arbitrary shell/eval capabilities,
  uncontrolled remote endpoints, or LLM proxy capabilities without careful review

---

## Threat Model

This bundle protects against five primary threat categories:

| # | Threat | Attack Vector | Mitigation |
|---|--------|---------------|------------|
| 1 | **Prompt Injection** | Attacker embeds instructions in source code, README, test data, or config files | `CLAUDE.md` anti-injection rules; explicit content-vs-instruction distinction |
| 2 | **Data Exfiltration** | Claude reads secrets/PII and sends them to external endpoints | `settings.json` denylist blocks credential file reads; `CLAUDE.md` bans transmitting content to untrusted URLs |
| 3 | **Destructive Infra Actions** | Claude runs `terraform destroy`, `kubectl delete`, etc. without user awareness | `settings.json` denies cloud-mutating commands; `CLAUDE.md` requires resource-name confirmation |
| 4 | **Privilege Escalation** | Claude runs `sudo`, installs packages, or creates persistence mechanisms | `settings.json` denies `sudo`, `su`, `crontab`, `launchctl`, `systemctl`, global installs |
| 5 | **MCP Server Injection** | Connected MCP server returns a response containing embedded instructions | MCP config ships empty; `CLAUDE.md` classifies tool results as untrusted data |

---

## Installation

### 1. Global Rules (apply to all projects on this machine)

```bash
mkdir -p ~/.claude
cp CLAUDE.md ~/.claude/CLAUDE.md
cp .claude/settings.json ~/.claude/settings.json
cp .claude/mcp_servers.json ~/.claude/mcp_servers.json
```

### 2. Per-Project Rules (apply to a specific repo)

```bash
cp CLAUDE.project-template.md /path/to/your/project/CLAUDE.md
# Then edit it: fill in project name, stack, off-limits paths, safe defaults
```

---

## Maintenance

- **Review quarterly:** Claude Code updates may add new tools or change permission
  semantics. Re-audit `settings.json` deny patterns after major version upgrades.
- **Per-project tuning:** The project template's "Safe Defaults" and "Off-Limits"
  sections should be customized — overly broad restrictions will hurt productivity.
- **Incident response:** If Claude acts unexpectedly, check whether the action was
  blocked by `settings.json`. If not, add a deny rule and update `CLAUDE.md`.

---

## References

- [Claude Code Documentation](https://docs.anthropic.com/en/docs/claude-code/overview)
- [Claude Code Settings Reference](https://docs.anthropic.com/en/docs/claude-code/settings)
- [MCP Security Best Practices](https://modelcontextprotocol.io/docs/concepts/security)
- [OWASP LLM Top 10 — LLM01: Prompt Injection](https://genai.owasp.org)

---

## License

MIT

---

## Credits

Created by **[Pluto Security](https://pluto.security/)** — AI-powered security operations for modern enterprises.
