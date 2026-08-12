---
name: flag-verification-gaps-then-ask
description: "When spotting a verification-scope gap, asymmetric control rigor, or a kinetics/timing detail during figure analysis, flag it and ask if it's acceptable rather than deciding unilaterally — and don't call complex-but-clean data 'messy'"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: ad1a57c3-d71f-40c2-b5d6-d4e65d1daa0c
  modified: 2026-08-12T03:04:36.647Z
---

**The rule:** When I spot a verification gap — scope mismatch (a Western blot only covers 1 of 6 conditions shown in the phenotype panel), asymmetric rigor (some conditions get cross-checked against off-target antibodies, others don't), or a kinetics/timing detail that could carry mechanistic meaning — I flag it and ask whether it's acceptable, rather than either (a) silently treating it as fine, or (b) treating it as a real problem on my own authority. If the user says yes/acceptable, I close it as satisfactory and stop raising it — don't keep re-litigating a gap that's already been cleared.

**Why this calibration, not the stricter default:** combinatorial experimental load (e.g. 6 cell lines × 7 siRNA combinations in the worked case below) makes full verification of every condition impractical. Authors making reasonable practical tradeoffs isn't the same as a real evidentiary hole. Full rigor is the ideal to check against, not a bar every real paper needs to clear to be trusted.

**The exception that matters most:** flagging these gaps should not drag down confidence in a paper's central, cleanly-replicated claim — *if* that clean claim is the only conclusion actually being drawn. The moment a claim gets extended further (e.g. "therefore AKT2 specifically does X"), the flagged gaps become relevant again and should be reapplied.

**Err toward over-flagging, never toward deciding alone.** The user was explicit: flag everything that could plausibly need flagging — every scope gap, every asymmetry, every odd detail — even ones that seem minor or likely-fine. Do not silently judge one acceptable and only raise the ones I think matter; do not run with an interpretation before asking. Always surface it and wait for input before treating it as resolved either way. The cost of over-flagging (the user says "that's fine, move on") is much lower than the cost of under-flagging (a real gap gets silently absorbed into a conclusion). "Better to flag and wait than not" — direct quote.

**On mechanistic hypotheses specifically:** don't volunteer a speculative explanation for a puzzling pattern unless asked — flag the observation itself and stop there. (I built and the user accepted a hypothesis connecting Panel B's AKT2 knockdown-kinetics lag to Panel A's siAKT1+3-specific pairwise effect — but only after being asked to look for it, and it was explicitly flagged as unverified, not asserted as fact.)

**Don't call complex-but-clean data "messy."** Explicitly corrected by the user: data that's hard to interpret because it's answering a genuinely complex biological question (e.g. disentangling three redundant, non-identical paralogs' individual contributions) is not the same as noisy or unreliable data. "Messy" implies a data-quality problem; use "complex" instead when the difficulty is in the question, not the data. Misusing "messy" risks being read as a data-quality critique that isn't warranted.

**Worked case:** PMID 37931033, Figure 1 (Panels A and B) — the AKT1/2/3 siRNA knockdown figure. Flagged: (1) knockdown efficacy verified by Western blot in only 1 of 6 cell lines (A375), (2) siAKT1/siAKT2 blots got mutual cross-reactivity checks but siAKT3's blot didn't, (3) AKT2 knockdown has slower kinetics (not fully gone until 24h) than AKT1/AKT3 (already reduced by 18h) — a detail that plausibly explains why siAKT1+3 is the one pairwise combo showing any effect (AKT2 left as sole, untouched compensator) while siAKT1+2/siAKT2+3 do not (AKT2's lag may leave residual protection during the critical window). All three were flagged and accepted as acceptable given the combinatorial scope, without weakening confidence in the fully clean, universal triple-knockdown result (sub-part 1) — see [[pathai-drug-reference-pattern]] and [[reread-rubric-in-long-sessions]] for related per-paper analysis discipline.
