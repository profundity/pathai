# Mechanistic Synthesis Case Log

A running log of worked examples applying the evidence-synthesis method (claim → precise sub-question → hypothesis → verify → correct → integrate across sources → synthesize → flag unknowns). Each case is a concrete precedent to check new situations against — the method gets more reliable from accumulated real cases, not from the written rule alone.

---

## Case 1: AKT pharmacological inhibition vs. genetic silencing (melanoma, PMID 37931033)

**Source claim:** "Efforts to pharmacologically inhibit AKT have proven to be largely ineffective... genetic silencing of all three AKT paralogs significantly induced melanoma cell death... Pharmacological inhibition of PI3K and mTOR with a novel dual inhibitor effectively suppressed melanoma cell proliferation in vitro and inhibited tumor growth in vivo."

**Precise sub-questions identified:**
- Does "AKT" in the failure statement mean AKT1, AKT2, AKT3, or all three?
- Was the failed compound actually pan-AKT, or uneven across isoforms?
- Is "largely ineffective" describing this one compound, or the whole drug class?
- Are "suppressed proliferation" and "induced cell death" the same claim?

**Verification steps taken:**
- Checked isoform discovery history (AKT1 first, 1987; AKT2/3 later) — confirmed via search.
- Checked the specific compound (INY-03-041) — confirmed via search: substantially reduced AKT2/AKT3 but only 50% reduction of AKT1 at 72h. Uneven, not pan-balanced.
- Checked broader field data (MK-2206, capivasertib, ipatasertib) — confirmed genuine field-wide modest efficacy despite target engagement, a separate finding from the INY-03-041 result.
- Attempted to check whether the original background sentence cited this broader field pattern — blocked (403, no full-text access). Left explicitly unconfirmed, not resolved by assumption.
- Checked proliferation-vs-death distinction for the dual inhibitor — not confirmed for this specific paper's compound; supported only by analogy to a different compound (VS-5584) shown elsewhere to cause real apoptosis.

**Cross-source integration:** a different seed paper (PMID 39682777) showed RAPTOR (mTORC1) knockdown *increases* AKT phosphorylation — a feedback loop. This explained why a dual PI3K/mTOR inhibitor (blocking the feedback escape route) succeeds where single-node AKT or mTOR-alone inhibition struggles.

**Synthesized mechanistic picture:** the PI3K/AKT/mTOR pathway resists single-node disruption via (a) redundancy across AKT paralogs for the kill effect, (b) an asymmetric rescue (AKT1 alone is sufficient to restore survival even though all three must be removed to kill), and (c) a feedback loop reactivating AKT when mTORC1 is blocked alone. Only genetic elimination of all three paralogs, or a deliberately dual-node drug closing the feedback escape route, actually works.

**Errors made and corrected along the way (kept, not scrubbed):**
- Assumed pan-AKT inhibition was "automatic" from a conserved ATP pocket — wrong; potency across paralogs requires deliberate optimization, and the actual compound was uneven.
- Assumed the field's AKT1-centric history meant later pan-AKT drugs were built on an unrevised, outdated rationale — wrong; the field deliberately built pan-AKT inhibitors specifically to solve the redundancy problem.
- Presented the "field-wide" reading of "largely ineffective" as if confirmed — it wasn't; only inferred from outside search, not verified against this paper's own citations.

**Follow-on insight — pharmacological inhibition reframed as an evidence-bearing tool:**

Genetic tools remove the protein/node from the network entirely; pharmacological inhibitors leave the protein structurally present and only block its catalytic output. That structural persistence is exactly what let the network compensate — mTORC1 inhibition increasing AKT phosphorylation via loss of negative feedback. This is a distinction between removing structure and silencing function, not just weaker-vs-stronger potency.

That distinction produces a real asymmetry in how much to trust a pharmacological result: a **negative** result is weak evidence against a causal claim (the network may have simply compensated around the still-present protein), while a **positive** result is comparatively strong evidence for it (the effect occurred despite the tool's built-in handicap). Genetic silencing results don't carry this asymmetry — there's no structural scaffold left for the network to compensate around.

**Tie-breaker rule, when a drug result and a genetic silencing result conflict:** trust the genetic silencing result — its failure mode doesn't include silent compensation. In this case: pharmacological AKT inhibition showed no effect; genetic triple-knockdown showed significant cell death. The genetic result was the one to trust, and this was independently confirmed once the drug's own uneven isoform coverage (INY-03-041, weak on AKT1) was found.

This is now written into the rubric as §5, "Pharmacological inhibition as an evidence-bearing tool."
