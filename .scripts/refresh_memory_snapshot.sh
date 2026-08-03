#!/bin/bash
SRC="/home/premsubramaniam/.claude/projects/-home-premsubramaniam-Downloads-Path-AI-Docs/memory"
DEST="/home/premsubramaniam/Downloads/Path AI Docs/Claude Memory Snapshot"
mkdir -p "$DEST"
cp "$SRC"/*.md "$DEST"/ 2>/dev/null
