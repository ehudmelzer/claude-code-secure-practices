# Claude Code — Secure Endpoint Configuration Bundle

A hardened configuration template for running Claude Code safely on an enterprise
or security-conscious endpoint. Covers behavioral rules, tool permissions, MCP server
policy, and prompt injection defenses.

---

## Files in This Bundle

```
claude-code-secure/
├── README.md                        ← you are here
├── CLAUDE.md                        ← global behavioral rules (copy to ~/.claude/)
├── CLAUDE.project-template.md       ← per-repo template (copy to <project>/CLAUDE.md)
└── .claude/
    ├── settings.json                ← tool permission allowlist/denylist
    └── mcp_servers.json             ← MCP server configuration
```

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

## Threat Model: What This Protects Against

### 1. Prompt Injection via File/Repo Content
An attacker embeds instructions in source code, README, test data, or config files.
Claude reads the file as part of a task and executes the embedded instruction.

**Mitigations:** `CLAUDE.md` anti-injection rules; explicit content-vs-instruction
distinction enforced in every session.

### 2. Sensitive Data Exfiltration
Claude is tricked (or accidentally) reads secrets, credentials, or PII and sends
them to an external endpoint, logs them, or includes them in output.

**Mitigations:** `settings.json` denylist blocks reading `.env`, `*.pem`, `*.key`,
`~/.aws/credentials`, etc. `CLAUDE.md` bans transmitting file contents to URLs
found in untrusted content.

### 3. Destructive Actions on Cloud/Infra Resources
A task causes Claude to run `terraform destroy`, `kubectl delete`, or similar
without the user realizing the scope.

**Mitigations:** `settings.json` denies cloud-mutating commands. `CLAUDE.md` requires
explicit resource-name confirmation before any infra action.

### 4. Privilege Escalation
Claude runs `sudo`, installs system packages, or modifies cron/launchd to persist
malicious behavior.

**Mitigations:** `settings.json` denies `sudo`, `su`, `crontab`, `launchctl`,
`systemctl`, and global package installs.

### 5. MCP Server as Attack Vector
A connected MCP server returns a response containing instructions. Claude treats
the MCP response as operator-level instruction and executes it.

**Mitigations:** MCP config ships empty. `CLAUDE.md` explicitly classifies tool
results as untrusted data. Each server must be manually reviewed and added.

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

- [Claude Code Docs](https://docs.anthropic.com/en/docs/claude-code/overview)
- [Claude Code Settings Reference](https://docs.anthropic.com/en/docs/claude-code/settings)
- [MCP Security Best Practices](https://modelcontextprotocol.io/docs/concepts/security)
- OWASP LLM Top 10 — LLM01: Prompt Injection
