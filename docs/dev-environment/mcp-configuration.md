# MCP Configuration — Roblox Studio MCP across CLI + VS Code

**Audience:** anyone setting up the Roblox Studio MCP (or any other MCP) for use
with Claude Code on this project.

## TL;DR

The Roblox Studio MCP server (`C:/Tools/rbx-studio-mcp.exe --stdio`) is registered
at **user scope** in `~/.claude.json`, so it is available to **every** Claude Code
surface (CLI, VS Code extension, JetBrains plugin) for this Windows user, on any
project.

```bash
claude mcp list
# Roblox_Studio: C:/Tools/rbx-studio-mcp.exe --stdio - ✓ Connected
```

## Background — why this doc exists

Originally the MCP was registered without a scope flag, which defaults to **local**
scope. Local-scope MCP servers are stored under the *project key* inside
`~/.claude.json`:

```
projects → "<absolute-path-to-this-repo>" → mcpServers
```

The Claude Code CLI resolves that project key from its working directory, so the
MCP appeared in `/mcp` from the terminal. The VS Code extension didn't see it,
because it runs as a separate Claude Code instance and its project-key resolution
didn't line up with that path — leaving the MCP invisible inside VS Code.

## The three MCP scopes

| Scope | Where it lives | Visible to |
|-------|---------------|------------|
| **local** | `~/.claude.json` under the current project's key | CLI launched from that project dir |
| **project** | `.mcp.json` at repo root (commit to git) | Anyone working on the repo (CLI + IDE) |
| **user** | `~/.claude.json` at the user level | All your projects, all surfaces — only you |

MCP servers are **not** configured in `settings.json` / `settings.local.json` —
those files hold permissions, hooks, env vars, etc.

## How this project is configured

User scope, set with:

```bash
claude mcp add Roblox_Studio -s user -- "C:/Tools/rbx-studio-mcp.exe" --stdio
```

Rationale: the MCP binary lives at a machine-specific path (`C:/Tools/...`) and
isn't something teammates on other OSes would share. User scope keeps it out of
the repo while still working everywhere on this machine.

If a teammate joins on Windows and wants the same setup, they run the same
`claude mcp add ... -s user` command after dropping `rbx-studio-mcp.exe` in
`C:/Tools/`.

## Useful commands

```bash
# List configured MCP servers and connection status
claude mcp list

# Inspect a specific server
claude mcp get Roblox_Studio

# Remove from a given scope
claude mcp remove Roblox_Studio -s user      # or -s local / -s project

# Switch to project scope (creates .mcp.json in repo root)
claude mcp add Roblox_Studio -s project -- "C:/Tools/rbx-studio-mcp.exe" --stdio
```

## Troubleshooting — "MCP works in CLI but not in VS Code" (or vice versa)

1. Run `claude mcp list` from the CLI in the project dir — confirm it's listed.
2. Run `claude mcp get <Name>` and look at the printed **scope**.
   - If it says `local`, the MCP is bound to this project's key and other
     surfaces may not pick it up. Re-add it at `user` or `project` scope.
3. Restart the VS Code extension after changing scopes.
4. If the binary is missing or the path is wrong, `claude mcp list` will show
   the server as failed instead of `✓ Connected`.
