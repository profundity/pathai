---
name: pathai-drug-reference-pattern
description: "Per-paper drug/compound reference tables in PMIDS/ are meant to be a durable, reusable cross-paper resource — check existing ones before re-deriving a compound's mechanism"
metadata:
  node_type: memory
  type: project
  originSessionId: ad1a57c3-d71f-40c2-b5d6-d4e65d1daa0c
  modified: 2026-08-12T01:41:41.844Z
---

**The pattern:** each per-paper folder in `PMIDS/` (e.g. `PMIDS/PMID 37931033/`) can contain a `drug_info_table.md` (and PDF version) — a verified compound/mechanism/isoform-selectivity reference for every drug used in that paper, checked against primary pharmacology sources rather than the paper's own descriptive labels. The user was explicit this isn't a one-off exercise: "I did not make you do this exercise for fun. This table is a point of reference for future."

**Why this matters going forward:** compounds recur across papers (e.g. MK2206 and GDC-0068 could plausibly appear again in a different PATHAI paper). Re-deriving a compound's mechanism and isoform selectivity from scratch every time it's encountered wastes work and risks inconsistency. The first `PMID 37931033/drug_info_table.md` is the seed of what should become a shared, cross-paper compound reference.

**How to apply:** before verifying a compound's mechanism/isoform-selectivity for a new paper, check whether it's already documented in an existing `PMIDS/*/drug_info_table.md` first. If found, reuse the verified data (with its sourcing) rather than re-searching from scratch — only re-verify if there's a specific reason to doubt the existing entry (e.g. a newer characterization paper, or a discrepancy with the new paper's own data). If PATHAI accumulates enough of these, consider consolidating into a single top-level compound reference file rather than leaving them scattered per-paper.
