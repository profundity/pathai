---
name: verification-then-present-ambiguity
description: "Worked case (AKT isoform ambiguity) establishing a 3-step discipline — precise question, attempted verification, honest ambiguity if unresolved"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: ad1a57c3-d71f-40c2-b5d6-d4e65d1daa0c
  modified: 2026-08-03T20:43:40.515Z
---

**The worked case:** the sentence "efforts to pharmacologically inhibit AKT have proven to be largely ineffective" (melanoma paper, PMID 37931033) looks simple but is ambiguous: does "AKT" mean AKT1, AKT2, AKT3, or all three together? Careful reasoning through the isoform history (AKT1 discovered first; AKT2/3 identified later; the field deliberately built pan-AKT inhibitors specifically because single-isoform inhibition was known to be insufficient due to redundancy) suggested the sentence likely meant a pan-AKT inhibitor. Checking the actual paper confirmed a specific compound (INY-03-041) was used, and revealed it had *uneven* isoform coverage — substantially reduced AKT2/AKT3 but only 50% reduction of AKT1 at 72h — which alone explained why it underperformed relative to genetic triple-knockdown. Checking further, broader clinical data on other pan-AKT inhibitors (MK-2206, capivasertib, ipatasertib) showed genuine, separate field-wide modest efficacy despite confirmed target engagement. But when asked to verify whether the *original background sentence itself* was citing that broader field-wide pattern (versus just foreshadowing the authors' own result), full-text access was blocked (403) — so that specific question remains genuinely unresolved, not just unconfirmed by laziness.

**The corrected 3-step discipline, as the user specified it:**
1. Reason carefully enough to identify the *precise, checkable* sub-question hiding inside a vague statement — not "what does this sentence mean" broadly, but "does 'AKT' here mean one isoform or all three."
2. Attempt verification against the primary source (methods, citations) — don't stop at plausible inference from field-level context.
3. If verification is inconclusive, the correct output is to **present the ambiguity itself to the reader**, explicitly, as an open distinction — not to silently pick the more plausible-sounding reading and state it as settled.

**How to apply to new cases:** when a new ambiguous claim comes up, check it against this case: is there a sharp, checkable sub-question hiding in the vague wording? Has verification actually been attempted against a primary source, not just background knowledge? If verification fails or is inconclusive, has the ambiguity been surfaced honestly, rather than resolved by picking the answer that sounds best?
