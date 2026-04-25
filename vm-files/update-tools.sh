#!/bin/bash
set -euo pipefail

LOG_DIR="/home/dev/.tool-updates"
CLAUDE_LOG="$LOG_DIR/claude.log"
CODEX_LOG="$LOG_DIR/codex.log"

usage() {
    echo "Usage: update-tools.sh <all|claude|codex> [--revert <version>] [--log]"
    echo ""
    echo "Commands:"
    echo "  all                     Update Claude Code and Codex CLI"
    echo "  claude                  Update only Claude Code"
    echo "  codex                   Update only Codex CLI"
    echo "  claude --revert 1.2.3   Pin Claude Code to a specific version"
    echo "  codex  --revert 0.5.0   Pin Codex CLI to a specific version"
    echo "  all    --log            Show update history for all tools"
    exit 1
}

log_update() {
    local log_file="$1" old_ver="$2" new_ver="$3"
    echo "$(date -u '+%Y-%m-%d %H:%M:%S UTC') | $old_ver -> $new_ver" >> "$log_file"
}

get_claude_version() {
    npm list -g @anthropic-ai/claude-code --depth=0 2>/dev/null | grep claude-code | sed 's/.*@//' || echo "unknown"
}

get_codex_version() {
    npm list -g @openai/codex --depth=0 2>/dev/null | grep codex | sed 's/.*@//' || echo "unknown"
}

update_tool() {
    local tool="$1" package="$2" log_file="$3" version="${4:-latest}"

    local old_ver
    if [ "$tool" = "claude" ]; then
        old_ver=$(get_claude_version)
    else
        old_ver=$(get_codex_version)
    fi

    echo "==> Updating $tool (current: $old_ver) to $version..."
    sudo npm install -g "$package@$version"

    local new_ver
    if [ "$tool" = "claude" ]; then
        new_ver=$(get_claude_version)
    else
        new_ver=$(get_codex_version)
    fi

    if [ "$old_ver" != "$new_ver" ]; then
        log_update "$log_file" "$old_ver" "$new_ver"
        echo "==> $tool updated: $old_ver -> $new_ver"
    else
        echo "==> $tool already at $new_ver, no change."
    fi
}

show_log() {
    local tool="$1" log_file="$2"
    echo "=== $tool update history (last 20) ==="
    if [ -f "$log_file" ]; then
        tail -20 "$log_file"
    else
        echo "  (no history yet)"
    fi
    echo ""
}

# --- Main ---

[ $# -lt 1 ] && usage

TARGET="$1"
shift

case "$TARGET" in
    all|claude|codex) ;;
    *) usage ;;
esac

if [ "${1:-}" = "--log" ]; then
    case "$TARGET" in
        all)
            show_log "Claude Code" "$CLAUDE_LOG"
            show_log "Codex CLI" "$CODEX_LOG"
            ;;
        claude) show_log "Claude Code" "$CLAUDE_LOG" ;;
        codex)  show_log "Codex CLI" "$CODEX_LOG" ;;
    esac
    exit 0
fi

if [ "${1:-}" = "--revert" ]; then
    VERSION="${2:-}"
    if [ -z "$VERSION" ]; then
        echo "Error: --revert requires a version number"
        exit 1
    fi
    case "$TARGET" in
        claude) update_tool "claude" "@anthropic-ai/claude-code" "$CLAUDE_LOG" "$VERSION" ;;
        codex)  update_tool "codex" "@openai/codex" "$CODEX_LOG" "$VERSION" ;;
        all)
            echo "Error: --revert must target a specific tool (claude or codex), not 'all'"
            exit 1
            ;;
    esac
    exit 0
fi

case "$TARGET" in
    all)
        update_tool "claude" "@anthropic-ai/claude-code" "$CLAUDE_LOG"
        update_tool "codex" "@openai/codex" "$CODEX_LOG"
        ;;
    claude) update_tool "claude" "@anthropic-ai/claude-code" "$CLAUDE_LOG" ;;
    codex)  update_tool "codex" "@openai/codex" "$CODEX_LOG" ;;
esac
