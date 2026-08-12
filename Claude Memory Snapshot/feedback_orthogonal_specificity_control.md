---
name: orthogonal-specificity-control
description: "When checking specificity/off-target risk on a knockdown or degrader blot, look for a readout outside the perturbed pathway entirely, not just a loading control or downstream-effector readout"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: ad1a57c3-d71f-40c2-b5d6-d4e65d1daa0c
  modified: 2026-08-12T18:58:13.157Z
---

A loading control (e.g. β-actin) only proves equal protein was loaded per lane, not that cells stayed healthy. A downstream-effector readout (e.g. a phospho-signal directly downstream of the target) only proves the pathway itself moved, not that nothing unrelated was also disrupted. The stronger check is a measured band for something **upstream or unrelated to the perturbed pathway** — if it stays flat across every condition, that's mild but real evidence against generic/non-specific knockdown toxicity, distinct from either of the other two checks.

**Why:** user's own observation on PMID 37931033 Supplementary Figure S3 — the blot includes PI3Kβ (upstream of AKT, not itself an siRNA target) alongside the AKT-paralog and P-PRAS40 (downstream effector) bands. PI3Kβ staying flat across all lanes is doing real specificity work, even though the paper doesn't label it as a control. Not treated as critical/must-have — just worth noting when present.

**How to apply:** when grading specificity/off-target risk under rubric §4, check for this third kind of readout (unrelated-pathway target) in addition to the loading control and downstream-effector signal. If present and stable, note it as supporting evidence against generic toxicity. If absent, don't treat it as a required gap — see [[flag-verification-gaps-then-ask]] for how to handle partial verification generally.
