---
name: user-teaching-approach-code
description: "User has no AI/coding background — every code walkthrough for PATHAI needs three explicit layers, not just a diff"
metadata: 
  node_type: memory
  type: user
  originSessionId: ad1a57c3-d71f-40c2-b5d6-d4e65d1daa0c
  modified: 2026-07-20T01:40:02.621Z
---

The user explicitly stated: "I am not an AI guy" and asked to be taught the specific coding, understanding code, understanding code in the context of the project, and the descriptive understanding the code is trying to reach.

**Why this matters:** the user has demonstrated strong conceptual/philosophical rigor throughout PATHAI discussions (catching loose terminology like "counterfactual," pushing back on unvalidated scoring heuristics, correctly reasoning about entity normalization gaps) but does not have a programming or ML background to read code directly. Explanations need to build the vocabulary from scratch, the way basic terms (NLP, transformer, atom, chunk, node, edge) have been introduced in past sessions — see [[tone-avoid-condescension]] for how to phrase this without implying the user can't follow it.

**How to apply:** whenever introducing or changing code for PATHAI, cover three layers together, not just the diff:
1. What the code literally does, line by line, in plain language (no assumed familiarity with loops, dicts, regex, function calls, etc.).
2. Where it sits in the pipeline (chunk → mention → atom → edge → graph) — what stage, what it consumes/produces.
3. What real-world/biological goal the code is chasing — why it's shaped the way it is, tied to the evidence/causality reasoning the user already understands well conceptually.
