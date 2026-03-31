#!/bin/bash
# ============================================================
# Claude Code Secure Practices — One-line Installer
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/ehudmelzer/claude-code-secure-practices/main/install.sh | bash
#
# What it does:
#   1. Downloads all config files from the repo
#   2. MERGES them with existing config (never overwrites your rules)
#   3. Installs gitleaks (secret scanner) if missing
#   4. Verifies the installation
#
# By Pluto Security — https://pluto.security/
# ============================================================
set -e

REPO_RAW="https://raw.githubusercontent.com/ehudmelzer/claude-code-secure-practices/main"
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

echo ""
echo "🔒 Claude Code Secure Practices — Installer"
echo "   by Pluto Security (https://pluto.security/)"
echo ""

# ── 1. Create directories ───────────────────────────────────
echo "📁 Creating directories..."
mkdir -p ~/.claude/hooks

# ── 2. Download files to temp ────────────────────────────────
echo "📥 Downloading configuration files..."

download() {
  if curl -fsSL "$REPO_RAW/$1" -o "$TMPDIR/$2" 2>/dev/null; then
    echo "  ✅ Downloaded $1"
  else
    echo "  ❌ Failed to download $1"
    return 1
  fi
}

download "CLAUDE.md"                                "CLAUDE.md"
download ".claude/settings.json"                    "settings.json"
download ".claude/mcp_servers.json"                 "mcp_servers.json"
download ".claude/hooks/pre-commit-secret-scan.sh"  "pre-commit-secret-scan.sh"

# ── 3. Merge CLAUDE.md (append if exists) ────────────────────
echo ""
echo "📝 Installing CLAUDE.md..."

if [ -f ~/.claude/CLAUDE.md ]; then
  # Check if our rules are already present
  if grep -q "Anti-Prompt Injection — HIGHEST PRIORITY" ~/.claude/CLAUDE.md 2>/dev/null; then
    echo "  ⏭️  CLAUDE.md already contains Pluto security rules — skipping"
  else
    cp ~/.claude/CLAUDE.md ~/.claude/CLAUDE.md.backup.$(date +%s)
    echo "" >> ~/.claude/CLAUDE.md
    echo "# ── Pluto Security Rules (added by installer) ──────────────" >> ~/.claude/CLAUDE.md
    echo "" >> ~/.claude/CLAUDE.md
    cat "$TMPDIR/CLAUDE.md" >> ~/.claude/CLAUDE.md
    echo "  ✅ Appended security rules to existing CLAUDE.md"
  fi
else
  cp "$TMPDIR/CLAUDE.md" ~/.claude/CLAUDE.md
  echo "  ✅ Installed CLAUDE.md (new file)"
fi

# ── 4. Merge settings.json (merge arrays & objects) ──────────
echo ""
echo "⚙️  Installing settings.json..."

# Helper: strip JSONC comments to valid JSON
strip_jsonc() {
  node -e '
    const fs = require("fs");
    const raw = fs.readFileSync(process.env.JSONC_FILE, "utf8");
    let result = "", inString = false, esc = false;
    for (let i = 0; i < raw.length; i++) {
      const c = raw[i];
      if (esc) { result += c; esc = false; continue; }
      if (inString) { if (c === "\\") { result += c; esc = true; continue; } if (c === "\"") inString = false; result += c; continue; }
      if (c === "\"") { inString = true; result += c; continue; }
      if (c === "/" && raw[i+1] === "/") { while (i < raw.length && raw[i] !== "\n") i++; result += "\n"; continue; }
      result += c;
    }
    process.stdout.write(result.replace(/,(\s*[}\]])/g, "$1"));
  '
}

if [ -f ~/.claude/settings.json ]; then
  cp ~/.claude/settings.json ~/.claude/settings.json.backup.$(date +%s)

  if command -v node &>/dev/null && command -v jq &>/dev/null; then
    # Parse both files
    EXISTING=$(JSONC_FILE=~/.claude/settings.json strip_jsonc)
    NEW=$(JSONC_FILE="$TMPDIR/settings.json" strip_jsonc)

    # Merge with jq: combine arrays (deduplicate), merge objects
    MERGED=$(jq -n \
      --argjson existing "$EXISTING" \
      --argjson new "$NEW" '
      # Merge env: new keys added, existing keys preserved
      ($existing.env // {}) + ($new.env // {}) as $merged_env |

      # Merge permissions.allow: union of both arrays
      (($existing.permissions.allow // []) + ($new.permissions.allow // []) | unique) as $merged_allow |

      # Merge permissions.deny: union of both arrays
      (($existing.permissions.deny // []) + ($new.permissions.deny // []) | unique) as $merged_deny |

      # Merge hooks.PreToolUse: concatenate arrays
      (($existing.hooks.PreToolUse // []) + ($new.hooks.PreToolUse // [])) as $merged_pre_tool |

      # Merge hooks.SessionStart: concatenate arrays
      (($existing.hooks.SessionStart // []) + ($new.hooks.SessionStart // [])) as $merged_session_start |

      # Build merged config
      $existing * $new |
      .env = $merged_env |
      .permissions.allow = $merged_allow |
      .permissions.deny = $merged_deny |
      .hooks.PreToolUse = $merged_pre_tool |
      (if ($merged_session_start | length) > 0 then .hooks.SessionStart = $merged_session_start else . end)
    ')

    echo "$MERGED" | jq '.' > ~/.claude/settings.json
    echo "  ✅ Merged settings.json (your existing rules preserved)"

    # Show what was added
    EXISTING_DENY_COUNT=$(echo "$EXISTING" | jq '.permissions.deny // [] | length')
    MERGED_DENY_COUNT=$(echo "$MERGED" | jq '.permissions.deny | length')
    ADDED_DENY=$((MERGED_DENY_COUNT - EXISTING_DENY_COUNT))
    if [ "$ADDED_DENY" -gt 0 ]; then
      echo "     Added $ADDED_DENY new deny rules"
    fi

    EXISTING_ALLOW_COUNT=$(echo "$EXISTING" | jq '.permissions.allow // [] | length')
    MERGED_ALLOW_COUNT=$(echo "$MERGED" | jq '.permissions.allow | length')
    ADDED_ALLOW=$((MERGED_ALLOW_COUNT - EXISTING_ALLOW_COUNT))
    if [ "$ADDED_ALLOW" -gt 0 ]; then
      echo "     Added $ADDED_ALLOW new allow rules"
    fi
  else
    echo "  ⚠️  node and jq required for merge. Skipping settings.json merge."
    echo "     Install both, then re-run. Or manually merge $TMPDIR/settings.json"
  fi
else
  JSONC_FILE="$TMPDIR/settings.json" strip_jsonc | jq '.' > ~/.claude/settings.json 2>/dev/null || cp "$TMPDIR/settings.json" ~/.claude/settings.json
  echo "  ✅ Installed settings.json (new file)"
fi

# ── 5. Install mcp_servers.json (only if missing) ───────────
echo ""
echo "🌐 Installing mcp_servers.json..."

if [ -f ~/.claude/mcp_servers.json ]; then
  echo "  ⏭️  mcp_servers.json already exists — skipping (see README for MCP security rules)"
else
  cp "$TMPDIR/mcp_servers.json" ~/.claude/mcp_servers.json
  echo "  ✅ Installed mcp_servers.json (new file)"
fi

# ── 6. Install hook script (always overwrite) ────────────────
echo ""
echo "🪝 Installing secret scanning hook..."
cp "$TMPDIR/pre-commit-secret-scan.sh" ~/.claude/hooks/pre-commit-secret-scan.sh
chmod +x ~/.claude/hooks/pre-commit-secret-scan.sh
echo "  ✅ Installed pre-commit-secret-scan.sh"

# ── 7. Install gitleaks if missing ──────────────────────────
echo ""
echo "🔧 Checking prerequisites..."

if command -v jq &>/dev/null; then
  echo "  ✅ jq is installed"
else
  echo "  ⚠️  jq is not installed (required by secret scanning hook and installer merge)"
  echo "     Install: brew install jq"
fi

if command -v node &>/dev/null; then
  echo "  ✅ node is installed"
else
  echo "  ⚠️  node is not installed (required for JSONC parsing)"
fi

if command -v gitleaks &>/dev/null; then
  echo "  ✅ gitleaks is installed"
elif command -v trufflehog &>/dev/null; then
  echo "  ✅ trufflehog is installed (fallback scanner)"
else
  echo "  📦 Installing gitleaks..."
  if command -v brew &>/dev/null; then
    brew install gitleaks
    echo "  ✅ gitleaks installed"
  else
    echo "  ⚠️  Homebrew not found. Install gitleaks manually:"
    echo "     https://github.com/gitleaks/gitleaks#installing"
  fi
fi

# ── 8. Quick verification ───────────────────────────────────
echo ""
echo "🧪 Verifying installation..."

PASS=0
TOTAL=0

check() {
  TOTAL=$((TOTAL+1))
  if [ "$1" = "true" ]; then
    echo "  ✅ $2"
    PASS=$((PASS+1))
  else
    echo "  ❌ $2"
  fi
}

check "$([ -f ~/.claude/CLAUDE.md ] && echo true)" "CLAUDE.md installed"
check "$(grep -q 'Anti-Prompt Injection' ~/.claude/CLAUDE.md 2>/dev/null && echo true)" "CLAUDE.md contains security rules"
check "$([ -f ~/.claude/settings.json ] && echo true)" "settings.json installed"
check "$([ -f ~/.claude/mcp_servers.json ] && echo true)" "mcp_servers.json installed"
check "$([ -x ~/.claude/hooks/pre-commit-secret-scan.sh ] && echo true)" "Secret scan hook installed and executable"
check "$(command -v jq &>/dev/null && echo true)" "jq available"
check "$( (command -v gitleaks &>/dev/null || command -v trufflehog &>/dev/null) && echo true)" "Secret scanner available"

echo ""
echo "=== $PASS/$TOTAL checks passed ==="

# ── 9. Next steps ───────────────────────────────────────────
echo ""
echo "📋 Next steps:"
echo ""
echo "  1. Edit ~/.claude/settings.json:"
echo "     - Replace OTEL_EXPORTER_OTLP_ENDPOINT with your collector URL"
echo "     - Uncomment the account restriction hook (SessionStart)"
echo "       and set your email domain"
echo ""
echo "  2. For per-project rules, download the template:"
echo "     curl -fsSL $REPO_RAW/CLAUDE.project-template.md -o /path/to/your/project/CLAUDE.md"
echo ""
echo "  3. Restart Claude Code for changes to take effect."
echo ""
echo "🔒 Done! Your Claude Code endpoint is now hardened."
echo "   Learn more: https://github.com/ehudmelzer/claude-code-secure-practices"
echo ""
