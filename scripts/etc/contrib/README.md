# contrib/

Reference implementations for optional developer tooling.

---

## statusline.sh — Claude Code Enhanced Status Line

Displays live session and usage information in the Claude Code terminal status bar.

**Shows:** model | git repo@branch | context window | session cost | 5h limit | 7d limit | extra usage

### Requirements

- `jq` — `brew install jq` (macOS) or `apt-get install jq` (Linux)
- Claude Code with a Max or Pro plan (usage limit data requires OAuth API access)

### Manual Setup

1. Copy the script to a stable location:
   ```bash
   cp scripts/etc/contrib/statusline.sh ~/.claude/statusline.sh
   chmod +x ~/.claude/statusline.sh
   ```

2. Add to `~/.claude/settings.json`:
   ```json
   {
     "statusCommand": "~/.claude/statusline.sh"
   }
   ```

3. Restart Claude Code — the status line appears at the bottom of the terminal.

### Configuration

All sections are opt-out via environment variables (default: all enabled):

| Variable | Default | Controls |
|---|---|---|
| `STATUSLINE_SHOW_GIT` | `true` | repo@branch + diff counts |
| `STATUSLINE_SHOW_CONTEXT` | `true` | context window tokens + % |
| `STATUSLINE_SHOW_SESSION_COST` | `true` | session cost in USD |
| `STATUSLINE_SHOW_SESSION` | `true` | 5-hour plan limit |
| `STATUSLINE_SHOW_WEEKLY` | `true` | 7-day plan limit |
| `STATUSLINE_SHOW_EXTRA` | `true` | extra usage spend |
| `STATUSLINE_SPLIT_LINES` | `false` | render on two lines |
| `STATUSLINE_CACHE_TTL` | `60` | seconds between API fetches |
| `STATUSLINE_CURRENCY_SYMBOL` | `$` | set to `€` for Europe |

Set in your shell profile (`~/.zshrc` or `~/.bashrc`):
```bash
export STATUSLINE_SHOW_EXTRA=false
export STATUSLINE_CURRENCY_SYMBOL=€
```

### Color Thresholds

| Section | Green | Yellow | Red |
|---|---|---|---|
| Context window | < 50% | 50–75% | ≥ 75% |
| 5h / 7d limits | < 70% | 70–90% | ≥ 90% |
| Extra usage | < 50% | 50–80% | ≥ 80% |

⚡ appears on the 5h or 7d label when that limit is exceeded (routing to extra billing).

### Updating

The script is copied once and does not auto-update with lib-foundation releases.
To get a newer version, re-copy from the subtree after a `git subtree pull`.

---

*Original implementation: [claude-code-statusline](https://github.com/aleksander-dytko/claude-code-statusline) by Aleksander Dytko (MIT License)*
