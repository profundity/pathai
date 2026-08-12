---
name: reread-rubric-in-long-sessions
description: "In a long session, re-read intervention_grading_rubric.md fresh at the start of each new verification task — don't rely on it having been loaded once at session start"
metadata:
  node_type: memory
  type: feedback
  originSessionId: ad1a57c3-d71f-40c2-b5d6-d4e65d1daa0c
  modified: 2026-08-12T01:34:23.524Z
---

**The failure, concretely:** in a single long PATHAI session (covering many unrelated sub-topics — enrichment analysis, Cell2Sentence, job-interview prep, FSearch troubleshooting, and PDF access work, all before returning to paper verification), I checked three new inhibitor compounds (MK2206, GDC-0068, GDC-0941) for a Supplementary Figure S1 claim without applying the rubric's own §2 rule — verify isoform/entity scope against a primary source rather than trusting a "pan-AKT"/"pan-PI3K" label. That rule was already written down, in the rubric, with this exact paper as the worked example (the INY-03-041 case). It had also been loaded once via the SessionStart hook at the beginning of the session. Neither fact stopped me from missing it — the user had to point it out twice before I checked.

**Why loading it once isn't enough:** the SessionStart hook injects the rubric into context at the very start of a session. In a long session, that content becomes buried under everything discussed since, and having text "somewhere in context" is not the same as actively applying it to a new task. The user's own words: "How can I make a program with you if you don't read instructions we discussed ad nauseum?" — a fair question, since a rule that only works right after it's loaded isn't a reliable rule.

**The fix, sharpened after a second correction:** the user's own words: "Reread rubric every time you are going to do a paper analysis or this work. Every step of the analysis. Just having it open does nothing. You must actively read it." So the granularity is not "once per task" — it's **every step** of a paper-analysis/grading task: checking each compound, each claim, each figure panel, each new sub-question. Re-read `intervention_grading_rubric.md` (and `mechanistic_synthesis_case_log.md` if relevant) fresh via the Read tool at each such step, not just once at the task's start. "It's in context somewhere" does not count as having read it — an active Read tool call is required. This strengthens (doesn't replace) [[feedback-always-load-rubric-before-grading]] — that memory says load it before grading; this one specifies that "before grading" means before *every individual step* of a grading/analysis task in a long session, not once near the start of the task.
