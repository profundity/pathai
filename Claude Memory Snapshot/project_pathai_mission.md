---
name: pathai-mission
description: "PATHAI's core mission statement and the coverage-gap rationale behind it — the company blurb the user confirmed and refined"
metadata:
  node_type: memory
  type: project
  originSessionId: ad1a57c3-d71f-40c2-b5d6-d4e65d1daa0c
  modified: 2026-08-11T21:38:51.548Z
---

**Mission statement (user-confirmed, verbatim):** "PATHAI is built to fill that gap by reading papers to build mechanistic understanding, not just surfacing what's already been curated into structured databases."

**The coverage-gap rationale (user-confirmed, verbatim):** "That's a coverage gap, not a weighting bias. It means even a 'perfect' equal-weight, non-popularity-biased reasoning system still hits a wall the databases themselves impose — some genes simply have no mechanistic vocabulary to draw on yet, regardless of how the gene list is processed upstream."

**Why this framing, and how it was reached:** derived live from a real failure case, not asserted top-down. Working through gene-set enrichment (g:Profiler/Enrichr/STRING) on a real 25-gene mouse list, the user pointed out that even a gene ranked highest in a curated/selective experimental signature can have zero mechanistic entry in KEGG/Reactome/GO/STRING — because those databases only contain what's been curated, and curation coverage is incomplete across the genome. This is distinct from (and more fundamental than) the earlier "popularity bias" framing (well-studied genes get over-weighted, e.g. Jun dominating a STRING network) — a gene can escape popularity bias entirely and *still* be invisible to every pathway tool because the tool never had an entry for it at all.

**Terminology correction, explicit:** don't describe PATHAI's method as "mining" literature — the user corrected this specifically because "mining" is reminiscent of shallow text-mining/pattern extraction. The correct framing is "reading papers to build understanding" — an active, judgment-driven reconstruction of mechanism (verifying claims against primary sources, distinguishing verb types, checking what a technique actually demonstrated), not passive extraction.

**How to apply:** use this exact framing (coverage gap, not weighting bias; reading to build understanding, not mining) when describing PATHAI's purpose in any future session, pitch material, or README content. See also [[feedback-evidence-synthesis-method]] and the rubric/case-log files this framing is grounded in.
