#!/bin/bash
RUBRIC="/home/premsubramaniam/Downloads/Path AI Docs/intervention_grading_rubric.md"
CASELOG="/home/premsubramaniam/Downloads/Path AI Docs/mechanistic_synthesis_case_log.md"

CONTEXT="PATHAI evidence-grading rubric and case log, auto-loaded at session start:\n\n=== intervention_grading_rubric.md ===\n$(cat "$RUBRIC" 2>/dev/null)\n\n=== mechanistic_synthesis_case_log.md ===\n$(cat "$CASELOG" 2>/dev/null)"

jq -n --arg ctx "$CONTEXT" '{"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": $ctx}}'
