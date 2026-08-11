# Evidence Training Examples (Proof of Concept)

Converting the two existing worked cases into the `evidence_training_schema.md` format. Goal: test whether the schema actually captures what the case log captured in prose. Format is transposed (column: value) per row, since 21 columns don't read well as a wide table.

---

## Source case: AKT pharmacological inhibition vs. genetic silencing (PMID 37931033)

The prose case log turned out to bundle **four separate causal claims** into one narrative. The schema forces them apart — which matches the rubric's own rule (§2: "split compound claims and grade each part separately"). That's the schema working as intended, not a failure of fit.

### Row 1 — Pharmacological AKT inhibition (negative result)
- **Gene/entity:** AKT (pan, via compound INY-03-041)
- **Claim:** Pharmacological AKT inhibition did not induce melanoma cell death
- **Gene function(s), canonical:** Serine/threonine kinase, central PI3K pathway node
- **Gene function, in this study's context:** Kinase activity (catalytic), same as canonical
- **Activity type tested:** Kinase inhibition (small molecule)
- **Technique used:** Chemical inhibitor (INY-03-041)
- **Verb type:** Direct-action ("inhibit")
- **Direction/sign:** N/A — negative result, no downstream effect observed
- **Evidence grade:** Rank 4 (chemical inhibitor) — lowest on technique ranking
- **Confidence:** Low-to-moderate, per §5's asymmetry rule — negative pharmacological result is weak evidence *against* the target's importance, not proof AKT doesn't matter
- **Source (PMID/DOI):** 37931033
- **Section type:** Body text (methods/results), not abstract
- **Claim type:** Necessity — attempted, result was null
- **Rescue/add-back present:** No
- **Verification status:** Confirmed — compound identity and isoform coverage verified via search (uneven: strong on AKT2/3, only 50% reduction of AKT1 at 72h)
- **Phenotype/outcome measured:** Melanoma cell death (not observed)
- **Species:** Human (melanoma cell line)
- **Model system:** Cell line, in vitro
- **Timepoint:** 72h (compound exposure)
- **Contradicting evidence:** Yes — see Row 2 (genetic knockdown, same target, opposite result)
- **Curator notes:** The compound's uneven isoform coverage (weak on AKT1) is itself a candidate explanation for the null result — doesn't need "network compensation" as the only explanation.

### Row 2 — Genetic triple knockdown of AKT1/2/3 (positive result)
- **Gene/entity:** AKT1, AKT2, AKT3 (all three paralogs)
- **Claim:** Genetic silencing of all three AKT paralogs significantly induced melanoma cell death
- **Gene function(s), canonical:** Serine/threonine kinase, central PI3K pathway node
- **Gene function, in this study's context:** Same — kinase/survival signaling
- **Activity type tested:** Full protein elimination (not just catalytic block)
- **Technique used:** Genetic silencing (triple knockdown — siRNA or shRNA, exact method not specified in the case log; flagged)
- **Verb type:** Direct-action ("silencing")
- **Direction/sign:** Loss of AKT → cell death (i.e., AKT is normally pro-survival)
- **Evidence grade:** Necessity, genetic — higher trust than Row 1 per the rubric's tie-breaker rule
- **Confidence:** High — genetic result, no structural-compensation escape route
- **Source (PMID/DOI):** 37931033
- **Section type:** Body text
- **Claim type:** Necessity
- **Rescue/add-back present:** No
- **Verification status:** Confirmed within the paper as reported; not independently re-verified against a primary source beyond the seed text
- **Phenotype/outcome measured:** Melanoma cell death (significant induction)
- **Species:** Human (melanoma cell line)
- **Model system:** Cell line, in vitro
- **Timepoint:** Not specified in case log — **gap**
- **Contradicting evidence:** Yes — Row 1 (same target, drug vs. genetic, opposite outcome); resolved by the tie-breaker rule (trust genetic)
- **Curator notes:** This is the row the tie-breaker rule (§5) says to trust when Row 1 and Row 2 conflict.

### Row 3 — Dual PI3K/mTOR inhibitor (positive pharmacological result)
- **Gene/entity:** PI3K, mTOR (dual node, not AKT itself)
- **Claim:** A dual PI3K/mTOR inhibitor suppressed melanoma proliferation in vitro and tumor growth in vivo
- **Gene function(s), canonical:** PI3K — lipid kinase; mTOR — serine/threonine kinase, growth control
- **Gene function, in this study's context:** Same as canonical
- **Activity type tested:** Kinase inhibition (small molecule, dual-target)
- **Technique used:** Chemical inhibitor (dual PI3K/mTOR)
- **Verb type:** Direct-action ("inhibit")
- **Direction/sign:** Inhibits proliferation and tumor growth
- **Evidence grade:** Rank 4 (chemical inhibitor) technique-wise, but positive result — per §5, a positive pharmacological result is comparatively strong evidence, since it succeeded despite the tool's structural-persistence handicap
- **Confidence:** Moderate-high — positive result, but proliferation vs. cell death distinction not confirmed as the same endpoint as Rows 1–2 (flagged explicitly in the case log)
- **Source (PMID/DOI):** 37931033
- **Section type:** Body text
- **Claim type:** Sufficiency-flavored (blocking the node was sufficient to suppress the phenotype) — not necessity
- **Rescue/add-back present:** No
- **Verification status:** Unconfirmed whether "suppressed proliferation" is the same claim as "induced cell death" (Rows 1–2) — explicitly left open in the case log, not resolved by assumption
- **Phenotype/outcome measured:** Proliferation (in vitro), tumor growth (in vivo)
- **Species:** Human cells in vitro; in vivo model species not specified in case log — **gap**
- **Model system:** Cell line + in vivo tumor model (dual)
- **Timepoint:** Not specified — **gap**
- **Contradicting evidence:** No direct contradiction; complements Rows 1–2 by targeting a different node
- **Curator notes:** Why dual-node inhibition succeeds where single-node (Row 1) fails is explained by Row 4.

### Row 4 — RAPTOR/mTORC1 knockdown increases AKT phosphorylation (feedback loop, different paper)
- **Gene/entity:** RAPTOR (mTORC1 component); downstream effect on AKT
- **Claim:** RAPTOR (mTORC1) knockdown increases AKT phosphorylation via loss of negative feedback
- **Gene function(s), canonical:** RAPTOR — mTORC1 scaffold/regulatory subunit
- **Gene function, in this study's context:** Same — negative-feedback regulation of AKT
- **Activity type tested:** Loss-of-function (knockdown), downstream phospho-readout
- **Technique used:** Genetic knockdown (RAPTOR)
- **Verb type:** Direct-action ("knockdown") producing an outcome-verb effect ("increasing")
- **Direction/sign:** Inhibiting mTORC1 → activates AKT (double-negative / disinhibition)
- **Evidence grade:** Necessity-type, genetic
- **Confidence:** High — genetic result, directly measured phospho-AKT readout
- **Source (PMID/DOI):** 39682777 (a *different* seed paper than Rows 1–3)
- **Section type:** Body text
- **Claim type:** Mechanistic/regulatory (not a phenotype-necessity claim — explains *why* Row 3 needed dual-node targeting)
- **Rescue/add-back present:** No
- **Verification status:** Confirmed within the seed text
- **Phenotype/outcome measured:** AKT phosphorylation level
- **Species:** Not specified in this excerpt — **gap**
- **Model system:** Not specified — **gap**
- **Timepoint:** Not specified — **gap**
- **Contradicting evidence:** None — this row *explains* Rows 1 and 3 rather than conflicting with them
- **Curator notes:** This is cross-paper integration — the schema has no native column for "which other row(s) this one explains/connects to." **Schema gap, flagged below.**

---

## Source case: ARID5A knockout and CRISPRa (PMID 39682777... — actually Prostate 82:97–106, DOI 10.1002/pros.24251, Ikeuchi et al. 2022)

Three manipulations were documented for this gene in this session. Only two produce rows — the third doesn't fit the schema, and that's correct, not a gap.

### Row 5 — ARID5A CRISPR knockout reduces IL-6 (in vitro)
- **Gene/entity:** ARID5A
- **Claim:** ARID5A knockout significantly reduces IL-6 expression (mRNA and protein), RNA Pol II occupancy, and H3K4me3 at the IL-6 TSS
- **Gene function(s), canonical:** AT-rich interaction domain (ARID) DNA-binding transcription factor
- **Gene function, in this study's context:** Same — DNA-binding, promotes IL-6 transcription
- **Activity type tested:** DNA-binding/transcriptional activation (via loss-of-function)
- **Technique used:** CRISPR knockout (double nickase, targeted to the ARID DNA-binding domain)
- **Verb type:** Direct-action ("knockout")
- **Direction/sign:** ARID5A activates IL-6 transcription (loss → decrease)
- **Evidence grade:** Rank 1 (CRISPR knockout) — necessity, strong
- **Confidence:** High — genetic, multiple concordant readouts (mRNA, protein, Pol II, H3K4me3), primary source read directly (not a secondary summary)
- **Source (PMID/DOI):** 10.1002/pros.24251 (Prostate 82:97–106, 2022)
- **Section type:** Body text (Results, verified via full-text PMC8665135)
- **Claim type:** Necessity only — no rescue/add-back performed
- **Rescue/add-back present:** No
- **Verification status:** Confirmed — read directly from primary full-text, not a search summary
- **Phenotype/outcome measured:** IL-6 mRNA, IL-6 protein (ELISA), Pol II occupancy, H3K4me3 occupancy at IL-6 TSS
- **Species:** Human
- **Model system:** Cell line (DU145 and PC-3, prostate cancer)
- **Timepoint:** Not specified per-assay in what was extracted — **gap**
- **Contradicting evidence:** None
- **Curator notes:** mRNA-stability sub-test (actinomycin D — no significant difference in most clones) supports "transcriptional," not "post-transcriptional," mechanism. Could be its own row or a note here; folded into notes for now rather than forced into a new row — **flagged as a schema judgment call.**

### Row 6 — ARID5A knockout reduces plasma IL-6 in vivo (xenograft)
- **Gene/entity:** ARID5A
- **Claim:** ARID5A knockout reduces plasma IL-6 in a mouse xenograft model; tumor size unaffected
- **Gene function(s), canonical:** Same as Row 5
- **Gene function, in this study's context:** Same as Row 5
- **Activity type tested:** Same as Row 5 (knockout), different model system
- **Technique used:** CRISPR knockout (same clones as Row 5, implanted)
- **Verb type:** Direct-action
- **Direction/sign:** Loss of ARID5A → lower plasma IL-6 (2 of 4 clones significant, 2 trend-only)
- **Evidence grade:** Necessity, genetic — but weaker than Row 5 (partial significance across clones)
- **Confidence:** Moderate — mixed significance, and no phenotype effect (tumor size unchanged) despite the biomarker effect
- **Source (PMID/DOI):** 10.1002/pros.24251
- **Section type:** Body text
- **Claim type:** Necessity, partial/mixed
- **Rescue/add-back present:** No
- **Verification status:** Confirmed from primary text
- **Phenotype/outcome measured:** Plasma IL-6 (biomarker); tumor volume (phenotype) — **two outcomes, one negative, one positive, same row**
- **Species:** Human cells in mouse host (xenograft)
- **Model system:** In vivo, NSG mice, subcutaneous xenograft
- **Timepoint:** Not specified beyond "tumor development to humane endpoint" — **gap**
- **Contradicting evidence:** Internally tension-bearing — IL-6 dropped but tumor size didn't, meaning IL-6 suppression alone wasn't sufficient for a growth phenotype here
- **Curator notes:** This row shows the schema straining a little: two outcome measures (biomarker vs. phenotype) with different results, same technique, same paper. Splitting into two rows was considered and rejected — they're the same experiment, same animals, and separating them would lose that they're paired results. **Judgment call, not a clean fit.**

### Excluded — CRISPRa/EndoOE arm does not get a row
The dCas9-SAM overexpression ("EndoOE") system was built and confirmed by Western blot, but was **never used to test the IL-6 hypothesis** — its own stated purpose was to validate antibody specificity, not generate a causal claim. There is no claim to grade. Forcing this into a row would fabricate evidence-bearing content that isn't there. **This is the schema working correctly** — not every documented manipulation is a claim, and the schema should refuse rows with no testable claim rather than pad the dataset.

---

## What this proof of concept found

**Held up:**
- Splitting compound claims into separate rows (Rows 1–4 from one prose case) matches the rubric's own instruction and made the AKT case's internal tension (drug vs. genetic conflict) far more visible as structured data than as prose.
- The schema correctly *excludes* the CRISPRa/EndoOE arm — a genuine test of whether the schema would over-include, and it didn't.

**Gaps/judgment calls found (schema needs revision, not the cases):**
1. **No column for cross-row relationships.** Row 4 (RAPTOR/AKT feedback) *explains* Rows 1 and 3, but there's no field capturing that link — it only exists in curator notes. A "related/explains row(s)" column may be needed.
2. **Timepoint is frequently missing from source papers**, not just unfilled by the schema — several rows above have "not specified" rather than a real gap in extraction. Worth deciding whether "not reported" is a valid value or whether it signals the source needs re-checking.
3. **Multi-outcome single-experiment rows (Row 6) strain the one-claim-per-row principle** — when the same technique produces two different-direction results on two different outcome measures in the same experiment, splitting vs. combining both have costs. Needs an explicit rule, not just a case-by-case call.
4. **"Verification status" turned out to correlate strongly with how the source was accessed** (primary full-text vs. secondary search summary) — Rows 5–6 (primary text) came out higher-confidence than Rows 1–4 (partly reconstructed from the case log's own summary of verification steps, not re-verified live here). Worth a column distinguishing *how* the row's data was obtained, not just whether it's "confirmed."
