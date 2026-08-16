# Evidence Training Examples

Filled-in rows using the format defined in `evidence_training_schema.md`. Built one row at a time, with review between each — see `mechanistic_synthesis_case_log.md` for the full reasoning/verification trail behind each row.

---

## Source: PMID 37931033 — Genetic Silencing of AKT Induces Melanoma Cell Death via mTOR Suppression

### Row 1 — AKT inhibition, null result (4/6 cell lines: A375, WM793, MTG001, MTG004)
- **Gene/entity:** AKT1/2/3
- **Claim:** Pharmacological AKT inhibition (MK2206, GDC-0068) had no significant effect on proliferation in A375, WM793, MTG001, MTG004
- **Gene function(s), canonical:** Serine/threonine kinase, central PI3K pathway node
- **Gene function, in this study's context:** Same
- **Activity type tested:** Kinase inhibition (allosteric — MK2206; ATP-competitive — GDC-0068)
- **Target engagement / isoform coverage:** MK2206: AKT1=8nM, AKT2=12nM, AKT3=65nM. GDC-0068: AKT1=5nM, AKT2=18nM, AKT3=8nM. Neither perfectly uniform, but both engage all three paralogs.
- **Dose tested vs. IC50:** MK2206 2.5μM = 38-313x IC50 across AKT1-3; GDC-0068 1μM = 56-200x IC50 across AKT1-3. Both well above saturating.
- **Technique used:** Chemical inhibitor (two compounds, parallel)
- **Verb type:** Direct-action ("inhibit")
- **Direction/sign:** No effect
- **Outcome (this evidence alone):** Dose confirmed adequate (per rubric §5 dose-check rule) — result is usable. In these 4 lines, AKT inhibition alone does not constrain proliferation, despite full target engagement.
- **Evidence grade:** Rank 3 (chemical inhibitor)
- **Confidence:** Moderate-high — dose-verified, direct assay, consistent across 4 independent cell lines
- **Source (PMID/DOI):** 37931033, Supplementary Figure S1
- **Section type:** Body text / supplementary figure (verified directly, not secondary summary)
- **Claim type:** Necessity — attempted, null
- **Rescue/add-back present:** No
- **Verification status:** Confirmed — primary figure read directly
- **Phenotype/outcome measured:** Cell proliferation (% confluence)
- **Assay/Method:** Cell confluence assay (Incucyte-style live imaging)
- **Endpoint:** % confluence over time
- **Species:** Human
- **Model system:** Cell lines, in vitro
- **Timepoint:** 90-300h depending on line
- **Contradicting evidence:** Yes — see Row 1b (same experiment, 2 other cell lines)
- **Curator notes:** GDC-0941 (PI3K inhibitor, different target) is the visible outlier in most panels — likely driving the `****` significance markers, not the AKT inhibitors.
- **Curator notes (cross-row, drug-vs-genetic tie-breaker) *:** Conflicts with Row 2 (Figure 1, simultaneous siAKT1-3 knockdown — complete inhibition of proliferation, universal across all 6 lines) on the same target/system. Per rubric §5 tie-breaker rule, Row 2's genetic result is trusted by default — but flagged `*` per the §5 scaffold-function caveat, not resolved by assumption. See Row 2's matching note for the full reasoning.

### Row 1b — AKT inhibition, partial effect (2/6 cell lines: HT144, SK-MEL28)
*(Flagged by the user as overkill relative to its evidentiary weight — left in for now, candidate for trimming/merging later.)*
- **Gene/entity:** AKT1/2/3
- **Claim:** MK2206 showed a visible reduction in proliferation relative to DMSO control in HT144 and SK-MEL28; GDC-0068 tracked with control in HT144
- **Gene function(s), canonical/in-context:** Same as Row 1
- **Activity type tested:** Same as Row 1
- **Target engagement / isoform coverage:** Same as Row 1
- **Dose tested vs. IC50:** Same as Row 1 — dose adequacy confirmed, so this partial effect is not a dosing artifact either
- **Technique used:** Chemical inhibitor
- **Verb type:** Direct-action
- **Direction/sign:** Reduces proliferation (MK2206 only; GDC-0068 does not replicate this in HT144)
- **Outcome (this evidence alone):** In a minority of cell lines (2/6), AKT inhibition by MK2206 specifically does constrain proliferation — inconsistent with the paper's own summary ("no significant effect... regardless of PTEN status"), which does not distinguish these two lines from the other four.
- **Evidence grade:** Rank 3 (chemical inhibitor)
- **Confidence:** Moderate — real, dose-adequate signal, but not replicated by GDC-0068 in the same cell line, so single-compound-specific, not confirmed AKT-class-wide
- **Source (PMID/DOI):** 37931033, Supplementary Figure S1
- **Section type:** Supplementary figure (primary, verified directly)
- **Claim type:** Necessity — attempted, partial positive
- **Rescue/add-back present:** No
- **Verification status:** Confirmed — primary figure read directly
- **Phenotype/outcome measured:** Cell proliferation (% confluence)
- **Assay/Method:** Cell confluence assay
- **Endpoint:** % confluence over time
- **Species:** Human
- **Model system:** Cell lines, in vitro
- **Timepoint:** 90-115h (HT144, SK-MEL28 specifically)
- **Contradicting evidence:** Yes — Row 1 (same experiment, 4 other cell lines, null)
- **Curator notes:** Worth flagging as a genuine cell-line-dependent effect rather than noise, precisely because dose adequacy is confirmed and MK2206's effect is directionally consistent across both exception lines.

---

## Source: PMID 37931033 — Figure 1 (siRNA-mediated knockdown of AKT1-3)

*Rows 2-4 below are IN PROGRESS — only the columns marked complete below have been confirmed with the user. Remaining columns still to be filled in column-by-column. All three come from Figure 1, Panel A (proliferation/confluence assay across 6 cell lines: A375, HT144, SK-MEL28, WM793, MTG001, MTG004) and Panel B (knockdown-efficacy Western blot, A375 only).*

**Verification notes established for all three rows (Panel B + Supplementary Figure S3, flagged and accepted as acceptable — see rubric §4 and `feedback_flag_verification_gaps_then_ask.md`):**
- Knockdown efficacy verified by Western blot/qPCR in 5 of 6 cell lines: A375 (Fig 1B/C, Western), WM793 and HT144 (Suppl. Fig S3A, Western), MTG001 and MTG004 (Suppl. Fig S3B, qPCR). SK-MEL28 has no verification blot/qPCR found in the main figure or S3. User-confirmed: 5/6 is sufficient bulk-of-evidence, SK-MEL28 gap noted but accepted, not a blocking issue.
- siAKT1 and siAKT2 blots (Fig 1B, A375) each got mutual cross-reactivity checks (blotted against both AKT1 and AKT2 antibodies); siAKT3's Fig 1B blot only shows the AKT3 band. Suppl. Fig S3A's HT144 blot closes this gap — it blots all three conditions (siAKT1, siAKT2, siAKT3) against all three antibodies (AKT1, AKT2, AKT3), giving a full cross-reactivity check for at least one line. WM793's siAKT3 blot in S3A still only shows the AKT3 band alone (same asymmetry as Fig 1B) — accepted given HT144 covers the check.
- Suppl. Fig S3 also adds P-PRAS40 (a direct AKT substrate) as a functional/activity readout — confirms knockdown reduces actual AKT kinase output, not just protein presence, in WM793 and HT144. And PI3Kβ (upstream of AKT, not itself targeted) stays flat across all lanes — an orthogonal specificity check against generic knockdown toxicity, per `feedback_orthogonal_specificity_control.md`.
- AKT2 knockdown has slower kinetics (band still strong at 18h, gone by 24h) than AKT1/AKT3 (already visibly reduced at 18h) in the Fig 1B single-knockdown timecourse — a real, observed timing detail, plausibly (not confirmed) relevant to why siAKT1+3 is the one pairwise combo showing any effect (see Row 4 curator notes).

### Row 2 (sub-part 1) — Simultaneous triple knockdown (siAKT1+2+3)
- **Gene/entity:** AKT1/2/3 — COMPLETE
- **Claim:** Simultaneous siAKT1-3 knockdown is associated with complete inhibition of proliferation in BRAF-mutant melanoma cells, across all 6 cell lines tested (p<0.0001). — COMPLETE
- **Contradicting evidence:** None within this dataset — this is the one result in Figure 1 with no cell-line exceptions. — COMPLETE
- **Curator notes (cross-row, drug-vs-genetic tie-breaker) *:** Conflicts with Row 1 (pharmacological AKT inhibition, MK2206/GDC-0068, null result in 4/6 lines) on the same target/system. Per rubric §5 tie-breaker rule, genetic silencing (this row) is trusted over the drug's null result by default — but flagged with `*` per the §5 scaffold-function caveat: this dataset alone doesn't establish whether the discrepancy is network compensation around the drug's still-present protein, or a non-catalytic (scaffold/protein-presence) requirement the drugs can't touch by design. Not resolved here — see rubric §5 for what would resolve it (e.g. a kinase-dead AKT rescue).
- **Curator notes (verification design):** Verification is assembled from a mix of methods and cell lines rather than one consistent battery repeated across lines — A375 gets Western + P-AKT activity readout, WM793/HT144 get Western + P-PRAS40, MTG001/MTG004 get qPCR only, SK-MEL28 gets nothing. The core finding (siRNAs knock down their intended target) is unequivocal across every line actually tested — but a cleaner design would have run the same 3+ lines through the same full battery (Western + qPCR + activity readout + cross-reactivity) rather than mixing and matching. Noted as a design-quality observation, not a reason to doubt the result.
- **Claim type:** Necessity
- **Rescue/add-back present:** Yes — but only in 1 of 6 lines (A375), via Panel D's mouse AKT1 reintroduction. Not tested for the other 5 lines. But can be taken as equivalent (under the established Panel A/Panel D proliferation-shutdown-equals-death assumption, the other 5 lines' proliferation shutdown is provisionally treated the same way, pending confirmation).
- **Curator notes (cross-row synthesis — why the triple knockdown must be universal):** The paper's rescue-construct claim ("any one paralog of mouse AKT can compensate for the other two," from the Figure 1C-D text) is only directly demonstrated for AKT1 via exogenous rescue — but it's independently supported by this row's own pairwise-knockdown data (Row 4/sub-part 3), without needing a rescue construct at all: AKT1 alone (via siAKT2+3) and AKT3 alone (via siAKT1+2) were each sufficient to sustain proliferation in 6/6 cell lines; AKT2 alone (via siAKT1+3) was only sufficient in 3/6 lines. So the paper's flat "any one paralog" phrasing is a slight overreach/imprecision — AKT1 and AKT3 are uniformly sufficient alone, AKT2 is only conditionally sufficient, cell-line-dependent. The more important pattern: *which* single paralog turns out to be sufficient varies by cell line, and nothing in this figure predicts it in advance (e.g. WM793's Pten-/- status doesn't track with the pattern — see Row 4's genotype caveat). That unpredictability is the mechanistic rationale for why the triple knockdown (this row) is the only condition with zero exceptions across all 6 lines: a strategy that only needs to hit one specific paralog can't be relied on across different melanomas if you can't know in advance which paralog that tumor depends on — simultaneous pan-AKT loss is the only approach that doesn't depend on knowing that answer ahead of time. This is a real strength argument for Row 2's universality, not just a report that it's universal.
- **Gene function(s), canonical:** AKT (PKB) — serine/threonine kinase, central PI3K pathway node
- **Gene function, in this study's context:** Same as canonical — AKT's serine/threonine kinase activity is the function under study; no alternate/non-canonical function (e.g. scaffolding) is being directly tested here.
- **Activity type tested:** Kinase activity (AKT's core functional role) — tested indirectly but necessarily, via suppression of endogenous AKT1/2/3 protein expression. Because kinase activity cannot exist without the protein, protein knockdown entails loss of kinase activity by necessity. This is the reverse of a pharmacological inhibitor, where activity can be blocked while the protein remains present — knockdown collapses "protein present" and "activity present" into one state, a drug does not.
- **Target engagement / isoform coverage:** All three paralogs (AKT1, AKT2, AKT3) targeted simultaneously with dedicated, paralog-specific siRNAs. On-target knockdown confirmed by Western blot/qPCR in 5 of 6 cell lines (A375, WM793, HT144, MTG001, MTG004); SK-MEL28 unverified but accepted given bulk-of-evidence. Cross-reactivity (does siAKT1 also hit AKT2/AKT3?) fully confirmed only for HT144, partial for A375, not shown for WM793/MTG001/MTG004 — accepted as adequate given the pattern holds everywhere it was checked. Unlike Row 1's pharmacological compounds, coverage here is binary by design (dedicated siRNA per paralog) rather than graded/uneven potency — "isoform coverage" isn't a dose/IC50 question the way it is for a drug.
- *(remaining columns not yet started: Dose tested vs. IC50 [n/a — siRNA], Technique used, Verb type, Direction/sign, Outcome (this evidence alone), Evidence grade, Confidence, Source, Section type, Claim type, Rescue/add-back present, Verification status, Phenotype/outcome measured, Assay/Method, Endpoint, Species, Model system, Timepoint)*

### Row 3 (sub-part 2) — Single knockdown (siAKT1, siAKT2, or siAKT3 alone)
- **Gene/entity:** AKT1/2/3 (tested individually) — COMPLETE
- **Claim:** In this study's 6 melanoma cell lines, siAKT1, siAKT2, or siAKT3 knockdown alone is associated with no change in proliferation relative to siCtrl. — COMPLETE
- **Contradicting evidence:** Not tested here, but other literature may show single- or double-paralog AKT knockdown affecting growth in different cell/tissue contexts — this negative result is specific to these 6 BRAF-mutant melanoma lines, not a general claim about AKT paralog redundancy. — COMPLETE
- *(all other columns not yet started)*

### Row 4 (sub-part 3) — Pairwise knockdown (siAKT1+3, and other pairwise combos)
- **Gene/entity:** AKT1/3 (pairwise); AKT1/2 and AKT2/3 also tested, no effect — COMPLETE
- **Claim:** In this study's 6 melanoma cell lines, siAKT1+3 knockdown is associated with decreased proliferation in 3 of 6 lines tested (HT144, SK-MEL28, MTG004; p<0.0001), with no effect in the other 3 lines or in the other pairwise combinations (siAKT1+2, siAKT2+3) tested. — COMPLETE
- **Contradicting evidence:** Cell-line-dependent within this same paper — the same siAKT1+3 knockdown gives opposite results (effect vs. no effect) depending on cell line, so this can't be generalized even within this study's own dataset, let alone to AKT paralog redundancy broadly. — COMPLETE
- **Curator notes (partial, hypothesis flagged not confirmed):** The one annotated genotype difference available (WM793's Pten-/- status) does not explain the effect/no-effect split — WM793 falls in the no-effect group. Beyond that, an unconfirmed hypothesis: siAKT1+3 excludes AKT2 (the slower-kinetics paralog per Panel B), so AKT1 and AKT3 — both fast-kinetics — are both fully gone early, leaving AKT2 as the sole, untouched compensator from the start; siAKT1+2 and siAKT2+3 each include AKT2 as a target, and if AKT2's kinetics lag holds in combination too, a delayed knockdown could leave more residual protection during the critical window, explaining why those two combos show no effect anywhere. Not verified — Panel B only shows AKT2 kinetics for the single knockdown, not the pairwise combinations.
- *(all other columns not yet started)*
