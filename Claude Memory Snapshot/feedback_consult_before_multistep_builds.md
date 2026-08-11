---
name: consult-before-multistep-builds
description: "Don't execute a multi-part build (e.g. converting several cases into a new schema) in one shot, even when a general next-step was agreed — check in after the first unit"
metadata:
  node_type: memory
  type: feedback
  originSessionId: ad1a57c3-d71f-40c2-b5d6-d4e65d1daa0c
  modified: 2026-08-11T23:09:01.624Z
---

**The instruction:** when a plan calls for applying a new format/schema/rule to multiple items (e.g. "convert the 2 worked cases into the schema"), do the *first one* and stop for review — don't produce all of them in one pass, even if the general direction was already agreed.

**Why:** In the PATHAI evidence-schema work, the user agreed to "step 2: convert the two worked cases into the schema format" as a plan, but I then wrote out all 6 resulting rows (splitting compound claims, making judgment calls about what fits/doesn't fit) in a single file-write without checking in. The user's objection: "I did not want you to do the next step without consulting." This repeats, in a new context, the exact failure mode the whole PATHAI rubric-building exercise was set up to prevent from session 1 — the user explicitly wanted to build the rubric by hand, correcting the assistant's reasoning live, rather than have the assistant author conclusions unilaterally. Agreeing to a *direction* is not the same as authorizing full, unsupervised execution of every step in that direction — especially when the work involves real judgment calls (e.g., how to split a compound claim, whether a manipulation gets a row at all).

**How to apply:** for any task that involves applying a new method/format to a list/batch of items, propose or produce the *first* item only, then stop and ask before continuing to the rest — even under general instructions like "do step 2" or "apply this to both cases." This is distinct from small, low-judgment mechanical edits (e.g. adding an agreed-upon column to a table) which don't need this pause. The dividing line is whether real interpretive judgment is being exercised per item — if yes, pause after item one. See also [[feedback-evidence-synthesis-method]] and [[feedback-always-load-rubric-before-grading]] — this is the same "human validates, AI doesn't author unilaterally" principle, now generalized beyond the rubric itself to any PATHAI artifact built the same way.
