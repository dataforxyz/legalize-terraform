#!/bin/bash
set -euo pipefail

LOG="/var/log/legalize-startup.log"
exec > >(tee -a "$LOG") 2>&1

MARKER="/var/lib/legalize-startup-done"
DEV_USER="${dev_username}"
DEV_HOME="/home/$DEV_USER"
export HOME="/root"

if [ -f "$MARKER" ]; then
    echo "==> Startup already completed, skipping. Delete $MARKER to re-run."
    exit 0
fi

echo "=========================================="
echo "Legalize Server — VM Startup Script"
echo "$(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo "=========================================="

# ── 1. System packages ─────────────────────────────────────────────────

echo "==> Installing system packages..."
apt-get update -qq
apt-get install -y -qq \
    apt-transport-https ca-certificates curl gnupg lsb-release \
    git make build-essential unzip wget jq software-properties-common \
    tmux

echo "==> Installing GitHub CLI (gh)..."
mkdir -p -m 755 /etc/apt/keyrings
out=$(mktemp) && wget -nv -O"$out" https://cli.github.com/packages/githubcli-archive-keyring.gpg \
  && cat "$out" | tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null \
  && chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
  && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
  && apt-get update -qq && apt-get install -y -qq gh

# ── 2. Docker ──────────────────────────────────────────────────────────

echo "==> Installing Docker..."
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
  > /etc/apt/sources.list.d/docker.list

apt-get update -qq
apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

systemctl enable docker
systemctl start docker

echo "==> Docker version: $(docker --version)"

# ── 3. Create dev user ─────────────────────────────────────────────────

echo "==> Creating dev user '$DEV_USER'..."
if ! id "$DEV_USER" &>/dev/null; then
    useradd -m -s /bin/bash "$DEV_USER"
fi
usermod -aG docker "$DEV_USER"

# Passwordless sudo
echo "$DEV_USER ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$DEV_USER"
chmod 0440 "/etc/sudoers.d/$DEV_USER"

# ── 4. Node.js 20 LTS (for Claude Code + Codex CLI) ───────────────────

echo "==> Installing Node.js 20 LTS..."
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt-get install -y -qq nodejs

echo "==> Node version: $(node --version)"
echo "==> npm version: $(npm --version)"

# ── 5. Claude Code ─────────────────────────────────────────────────────

echo "==> Installing Claude Code..."
npm install -g @anthropic-ai/claude-code || echo "  (Claude Code install failed, can retry manually)"

# ── 6. OpenAI Codex CLI ────────────────────────────────────────────────

echo "==> Installing OpenAI Codex CLI..."
npm install -g @openai/codex || echo "  (Codex CLI install failed, can retry manually)"

# ── 7. Tool auto-update cron ───────────────────────────────────────────

echo "==> Setting up tool auto-update..."
UPDATE_SCRIPT="$DEV_HOME/vm-files/update-tools.sh"
UPDATE_LOG_DIR="$DEV_HOME/.tool-updates"

METADATA_URL="http://metadata.google.internal/computeMetadata/v1/instance/attributes"
METADATA_HEADER="Metadata-Flavor: Google"

mkdir -p "$DEV_HOME/vm-files"
curl -sf -H "$METADATA_HEADER" "$METADATA_URL/update-tools-sh" > "$UPDATE_SCRIPT"
chmod +x "$UPDATE_SCRIPT"
chown -R "$DEV_USER:$DEV_USER" "$DEV_HOME/vm-files"
mkdir -p "$UPDATE_LOG_DIR"
chown "$DEV_USER:$DEV_USER" "$UPDATE_LOG_DIR"

# Install in root crontab so it can sudo npm install -g without prompts
CRON_UPDATE="0 6 * * * $UPDATE_SCRIPT all >> $UPDATE_LOG_DIR/cron.log 2>&1"
(crontab -l 2>/dev/null | grep -v 'update-tools.sh' ; echo "$CRON_UPDATE") | crontab -
echo "==> Cron job installed: daily 6:00 AM UTC tool update"

# ── 8. uv (Python package manager — handy for the pipeline) ───────────

echo "==> Installing uv..."
curl -LsSf https://astral.sh/uv/install.sh | sh
cp /root/.local/bin/uv /usr/local/bin/uv
cp /root/.local/bin/uvx /usr/local/bin/uvx
echo "==> uv version: $(uv --version)"

# ── 9. Clone legalize-pipeline ─────────────────────────────────────────

echo "==> Cloning legalize-pipeline..."
LEGALIZE_TARGET="$DEV_HOME/legalize-pipeline"
GIT_BRANCH="${git_branch}"

if [ -d "$LEGALIZE_TARGET" ]; then
    echo "==> $LEGALIZE_TARGET already exists, skipping clone."
else
    sudo -u "$DEV_USER" git clone -b "$GIT_BRANCH" "${legalize_repo_url}" "$LEGALIZE_TARGET" \
      || echo "WARNING: Failed to clone legalize-pipeline (may need SSH key on first manual run)"
fi

# ── 10. Extract VM Makefile from metadata ─────────────────────────────

echo "==> Extracting VM Makefile from metadata..."
curl -sf -H "$METADATA_HEADER" "$METADATA_URL/vm-makefile" > "$DEV_HOME/Makefile"
chown "$DEV_USER:$DEV_USER" "$DEV_HOME/Makefile"

# ── 11. Shell environment ──────────────────────────────────────────────

echo "==> Configuring shell environment..."

cat > "$DEV_HOME/.legalize-env" << 'ENVEOF'
# Legalize Server — API keys (auto-generated by Terraform)
export ANTHROPIC_API_KEY="${anthropic_api_key}"
export OPENAI_API_KEY="${openai_api_key}"
ENVEOF
chmod 600 "$DEV_HOME/.legalize-env"
chown "$DEV_USER:$DEV_USER" "$DEV_HOME/.legalize-env"

cat >> "$DEV_HOME/.bashrc" << 'BASHEOF'

# ── Legalize Server Environment ───────────────────────────────────────
export PATH=/usr/local/bin:/usr/bin:$HOME/.local/bin:$PATH

[ -f "$HOME/.legalize-env" ] && source "$HOME/.legalize-env"

alias claude-legalize='cd ~/legalize-pipeline && claude --dangerously-skip-permissions'
alias codex-legalize='cd ~/legalize-pipeline && codex --dangerously-bypass-approvals-and-sandbox'
alias logs='sudo tail -f /var/log/legalize-startup.log'
alias dps='docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"'
BASHEOF
chown "$DEV_USER:$DEV_USER" "$DEV_HOME/.bashrc"

# ── 12. Fix ownership ─────────────────────────────────────────────────

chown -R "$DEV_USER:$DEV_USER" "$DEV_HOME"

# ── 13. Mark complete ─────────────────────────────────────────────────

touch "$MARKER"

echo "=========================================="
echo "Legalize Server startup complete!"
echo "$(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo "=========================================="
