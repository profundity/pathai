# Evidence Grading Rubric (reusable scoring sheet)

Applied in this order when reading a chunk.

## 1. Section-type awareness (read first)

Signals that a chunk is an abstract:
- General opening/background statement, not specific to the actual experiment
- Brief study-design line ("in this study...")
- Compressed results (some numbers, not full statistical backing)
- Interpretive closing claim ("these findings indicate...")
- No references to specific figures or tables

Rule: an abstract is **flagged, not rejected**. Its verification conditions (see §4) get marked "unconfirmed," which caps how high its confidence can go — but it is still scored on whatever concrete content "it actually contains. One abstract can outscore another.

## 2. General evidence-grading rules (read the text itself)

- Language carries no evidentiary weight on its own — grade by data, not wording. Hedge words and confident phrasing don't raise or lower a grade by themselves.
- Split compound claims and grade each part separately, against its own specific supporting evidence.
- Distinguish direct/functional evidence (a cell-line or in vivo result) from indirect/inferred evidence (e.g., an omics-based "revealed potential X activity" claim) — even when phrased identically.
- For rescue/add-back experiments, check the timing: was the rescue construct introduced *simultaneously* with the knockdown/knockout (co-transfection), or *after* the phenotype was already established? Simultaneous co-transfection tests whether the rescue **prevents** the phenotype from developing; a later add-back tests whether it **reverses** an already-established phenotype. Reversal is the stronger claim — it rules out the off-target explanation on a phenotype that's already fully present, while prevention leaves slightly more room for a confound in how the phenotype develops in the first place. Don't grade all "rescue" claims the same; check which design was actually used.
- Check the verb, not just the named target, when deciding whether a method was actually designed to hit a specific molecule. Direct-action verbs (inhibit, degrade, knock down, silence, activate) paired with a named molecule attribute the method's designed intent to that molecule — "pharmacologically inhibit AKT" means an AKT-targeted drug was used. Outcome verbs (affect, modulate, alter, impact, change) do not carry that same guarantee — "modulated AKT signaling" could just as easily describe a downstream consequence of hitting something else entirely. Don't assume every named target was the intended target; check which kind of verb is doing the work.
- When a claim underperforms relative to strong-sounding biological reasoning, consider (as one candidate hypothesis among several — incomplete target engagement, dosing/toxicity limits, feedback reactivation — not a default explanation) whether the tool's founding rationale predates a later complicating discovery about the system it targets. Example: AKT1 was discovered and studied first, for years, before AKT2/AKT3 were identified; paralog redundancy (all three needed together) was only established later by genetic studies. Pharmacological AKT inhibitors may have been developed against the earlier, simpler picture of the biology, which could explain underperformance without the drug's chemistry being at fault. Only pursue this when there's an actual, checkable historical timeline — don't manufacture one when a simpler mechanistic explanation already fits.
- When a claim names an entity (a protein, an isoform) but the precise scope is unclear (e.g., does "AKT" mean AKT1, AKT2, AKT3, or all three?), identify that precise sub-question first, then attempt to verify it against the primary source (methods, citations) — not just plausible field-level reasoning. If verification is inconclusive (source unavailable, no citation found, etc.), present the ambiguity itself as the answer — don't silently pick the more plausible-sounding reading and state it as settled. Worked case: "efforts to pharmacologically inhibit AKT have proven to be largely ineffective" (PMID 37931033) — reasoning suggested pan-AKT; checking the actual compound (INY-03-041) confirmed uneven isoform coverage (AKT2/3 reduced substantially, AKT1 only 50%), but whether the *background claim itself* meant pan-AKT specifically remained unconfirmed after full-text access was blocked — correctly left as an open question, not resolved by assumption.

## 3. Technique ranking (look up the intervention)

| Rank | Technique | One-line reason |
|------|-----------|------------------|
| 1 | CRISPR knockout | Shuts off production at the source (DNA level), permanently — no new functional protein can ever be made again; nothing to compensate or rebound from. |
| 2 | Chemical degrader | Acts directly on existing protein, but doesn't stop production — needs sustained presence, and the cell can resist by upregulating production. |
| 3 | siRNA / RNAi knockdown | Only reduces new protein synthesis (via mRNA degradation); doesn't touch existing protein at all, and effect is transient. |

**Not yet ranked:** genetic knockout (non-CRISPR), CRISPRi, CRISPRa, splicing modulation, overexpression, dominant negative, mutant variant, chemical inhibitor, chemical activator, stimulus treatment, neutralizing antibody.

### Pairings that upgrade the claim type (not standalone rows)

**Rescue/add-back** isn't a silencing method, so it doesn't get its own rank on the table above — it always pairs with a base technique (siRNA + rescue, CRISPR + rescue). What it contributes isn't a confidence bonus on the base technique's existing claim — it changes what's actually being claimed.

A silencing method alone (CRISPR, siRNA, degrader) only tests **necessity**: remove the gene, phenotype appears, therefore the gene is required. Rescue adds the other half: restore *just that one gene* against the same perturbed background, and the phenotype resolves — a direct demonstration of **sufficiency**, that this one gene alone, not the broader disruption caused by the knockdown method, is what's actually responsible. Necessity plus sufficiency together is the strongest causal pairing in this whole framework — stronger than either half alone, and a different kind of claim than "specificity confirmed," not just a stronger version of it.

Any base technique paired with a rescue should be treated as making the upgraded necessity+sufficiency claim, not the base technique's necessity-only claim — see §2 for grading which type of rescue (prevention vs. reversal) was actually used.

## 4. Conditions that validate the ranking (check after applying it)

- Efficacy is actually verified (sequencing, PCR, Western blot, etc.) — if unconfirmed, the rank is not meaningless, but should be flagged and downweighted. A stated technique, even unconfirmed, still carries more information than no stated intervention at all, and can be used cautiously as a tie-breaker — just not treated as solid ground on its own.
- Specificity/off-target risk is separately confirmed, not assumed from the technique's category alone.
- The comparison assumes the same target and system (same gene, same cell type) — not comparisons across unrelated experiments.
- The ranking values sustained/permanent loss-of-function — it matters less if a study specifically needs a transient or reversible effect instead.

## 5. Pharmacological inhibition as an evidence-bearing tool (result-direction asymmetry)

**The structural distinction:** genetic tools (CRISPR, knockdown, complete degradation) remove the protein/node from the network entirely. Pharmacological inhibitors leave the protein structurally present and only block its catalytic output. That structural persistence is what lets a network sense and compensate around the block — e.g., mTORC1 inhibition (RAPTOR knockdown) increasing AKT phosphorylation via loss of negative feedback (PMID 39682777). This is a distinction between removing structure and silencing function, not just "weaker vs. stronger" tool potency.

**The resulting asymmetry — apply this whenever grading a pharmacological (function-blocking) result:**
- A **negative** pharmacological result (drug tested, no effect seen) is **weak evidence against** a causal claim. The target could still be genuinely important; the network may simply have compensated around the still-present protein. Don't downweight a target's causal importance just because a drug against it failed.
- A **positive** pharmacological result (drug tested, effect seen) is **comparatively strong evidence for** the causal claim — the effect occurred despite the tool's built-in handicap (the protein was still there and available for compensation), which is more informative than a positive result from a tool with no such handicap.
- Genetic silencing results do not carry this asymmetry — there's no structural scaffold left for the network to compensate around, so both positive and negative genetic results are read at closer to face value.

**Tie-breaker rule, when a drug result and a genetic silencing result conflict on the same target/system:** trust the genetic silencing result. Its failure mode doesn't include silent network compensation the way pharmacological inhibition's does. (Worked case: AKT — pharmacological inhibition showed no effect; genetic triple-knockdown showed significant cell death. The genetic result is the one to trust, and was independently confirmed correct once the drug's own uneven isoform coverage was found — see the case log.)

If the two agree (both positive, or both negative under matched conditions), weight them closer to equally — a drug's positive result earns a bit more credit specifically because it overcame its own handicap, not because pharmacological evidence is generally stronger.
