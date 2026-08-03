---
name: always-load-rubric-before-grading
description: "Standing trigger — before grading any evidence for PATHAI (new papers, chunks, PDFs), always read the rubric and case log in full first"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: ad1a57c3-d71f-40c2-b5d6-d4e65d1daa0c
  modified: 2026-08-03T21:45:38.741Z
---

**The instruction, stated directly:** before grading, ranking, or reasoning about any new piece of biological evidence for PATHAI — including a fresh batch of PDFs handed over in a future session — always read `intervention_grading_rubric.md` and `mechanistic_synthesis_case_log.md` from the project folder in full, first, before starting the actual grading work. Don't rely on recalling the rules from memory summaries alone; the full files have the reasoning and worked examples that make the rules usable correctly.

**Why:** `MEMORY.md` is auto-loaded at the start of a session in this project, but it only contains one-line pointers — it doesn't guarantee the actual rubric and case log content gets read unless something prompts it. A future request like "here are 10 PDFs, apply the rubric" could otherwise proceed without the full rules actually being loaded into context.

**How to apply:** treat this as a hard prerequisite step, not an optional nicety — read both files before producing any grading output for new evidence, regardless of how the request is phrased. See also [[evidence-synthesis-method]] for the reasoning process these files support.
