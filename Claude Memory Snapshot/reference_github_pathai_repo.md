---
name: github-pathai-repo
description: "Where and how PATHAI's project folder is backed up on GitHub — account, repo, and access method (pointers only, no credentials)"
metadata: 
  node_type: memory
  type: reference
  originSessionId: ad1a57c3-d71f-40c2-b5d6-d4e65d1daa0c
  modified: 2026-08-03T21:40:56.128Z
---

**Account:** GitHub username `profundity`, email `premanu.32608@gmail.com` — a separate account from the machine's existing default GitHub identity (`c2b2pss`), set up specifically for this project.

**Repo:** `https://github.com/profundity/pathai` — private. Mirrors the local "Path AI Docs" project folder (rubric, case log, chat history, historical docs, memory snapshot).

**Access method:** a dedicated SSH key at `~/.ssh/id_ed25519_profundity` (public half registered on the `profundity` account's GitHub settings), used via an SSH config host alias `github-profundity` (see `~/.ssh/config`) so git operations for this project don't touch the machine's default GitHub identity. The remote is configured as `git@github-profundity:profundity/pathai.git`.

**Automatic sync:** `/home/premsubramaniam/Downloads/Path AI Docs/.scripts/refresh_memory_snapshot.sh` copies the memory folder into "Claude Memory Snapshot/", then commits and pushes any changes to this repo. It runs daily via cron (6am) and after every session via a project-scoped Stop hook (`.claude/settings.json` in the project folder).

**What is deliberately NOT stored here:** the SSH private key, any password, or any token. Only pointers to where credentials live (`~/.ssh/id_ed25519_profundity`) — never the credential material itself, since memory files are plain text and this one is designed to be portable/carried elsewhere.
