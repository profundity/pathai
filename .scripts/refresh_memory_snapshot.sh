#!/bin/bash
SRC="/home/premsubramaniam/.claude/projects/-home-premsubramaniam-Downloads-Path-AI-Docs/memory"
DEST="/home/premsubramaniam/Downloads/Path AI Docs/Claude Memory Snapshot"
PROJECT_DIR="/home/premsubramaniam/Downloads/Path AI Docs"

mkdir -p "$DEST"
cp "$SRC"/*.md "$DEST"/ 2>/dev/null

cd "$PROJECT_DIR" || exit 0
if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
  git add -A
  git commit -q -m "Auto-refresh memory snapshot ($(date -u +%Y-%m-%dT%H:%M:%SZ))"
  git push origin main -q 2>/dev/null
fi
