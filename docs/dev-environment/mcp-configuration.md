# MCP Configuration: the Roblox Studio MCP

**Audience:** anyone wiring the Roblox Studio MCP server into an MCP-capable
editor, so Studio can be inspected, screenshotted and probed from outside the app.

## TL;DR

The Roblox Studio MCP server runs as `C:/Tools/rbx-studio-mcp.exe --stdio`. It is
registered at **user scope**, so every editor surface on this Windows account
picks it up on any project, and nothing machine-specific lands in the repo.

Drop the server binary in `C:/Tools/` and install the companion Studio plugin it
ships with. Studio has to be open, with that plugin allowed to accept
connections, before the server will answer anything.

## Scopes, and why this project uses user scope

Most MCP clients offer three places to register a server:

| Scope | Where it lives | Visible to |
|-------|---------------|------------|
| **local** | the client's config, under the current project's key | that client only, launched from that project directory |
| **project** | `.mcp.json` at repo root (committed) | anyone working on the repo |
| **user** | the client's config at the user level | all your projects, all surfaces, only you |

This project uses **user** scope. The binary sits at a machine-specific path and
is Windows-only, so it is not something a teammate on another OS could reuse. User
scope keeps it out of the repo while still working everywhere on this machine.

Registering at **local** scope is the usual mistake. The server then binds to a
single project key, so it appears in a terminal launched from that directory and
is invisible from an editor extension whose project-key resolution differs.

MCP servers are not configured in an editor's `settings.json`. That file holds
permissions, hooks and environment variables.

## Troubleshooting

When the server works in one surface but not another:

1. List the configured MCP servers and confirm `Roblox_Studio` is among them.
2. Check its reported **scope**. If it reads `local`, re-register at `user` or
   `project` scope.
3. Restart the editor extension after changing scopes.
4. If the binary is missing or its path is wrong, the server is reported as
   failed rather than connected.
