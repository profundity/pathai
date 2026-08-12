---
name: reread-rubric-in-long-sessions
description: "In a long session, re-read intervention_grading_rubric.md fresh at the start of each new verification task — don't rely on it having been loaded once at session start"
metadata:
  node_type: memory
  type: feedback
  originSessionId: ad1a57c3-d71f-40c2-b5d6-d4e65d1daa0c
  modified: 2026-08-12T01:32:25.142Z
---

**The failure, concretely:** in a single long PATHAI session (covering many unrelated sub-topics — enrichment analysis, Cell2Sentence, job-interview prep, FSearch troubleshooting, and PDF access work, all before returning to paper verification), I checked three new inhibitor compounds (MK2206, GDC-0068, GDC-0941) for a Supplementary Figure S1 claim without applying the rubric's own §2 rule — verify isoform/entity scope against a primary source rather than trusting a "pan-AKT"/"pan-PI3K" label. That rule was already written down, in the rubric, with this exact paper as the worked example (the INY-03-041 case). It had also been loaded once via the SessionStart hook at the beginning of the session. Neither fact stopped me from missing it — the user had to point it out twice before I checked.

**Why loading it once isn't enough:** the SessionStart hook injects the rubric into context at the very start of a session. In a long session, that content becomes buried under everything discussed since, and having text "somewhere in context" is not the same as actively applying it to a new task. The user's own words: "How can I make a program with you if you don't read instructions we discussed ad nauseum?" — a fair question, since a rule that only works right after it's loaded isn't a reliable rule.

**The fix:** at the start of any new verification/grading sub-task within a session — not only at session start — re-read `intervention_grading_rubric.md` (and `mechanistic_synthesis_case_log.md` if relevant) fresh via the Read tool, rather than relying on recall of what's already in context. Treat it as an active lookup performed per task, not a one-time load. This strengthens (doesn't replace) [[feedback-always-load-rubric-before-grading]] — that memory says load it before grading; this one adds that in a long session, "before grading" means before *each* grading task, not just once near the start.
