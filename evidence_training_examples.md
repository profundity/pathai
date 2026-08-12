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
- **Evidence grade:** Rank 4 (chemical inhibitor)
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
- **Evidence grade:** Rank 4 (chemical inhibitor)
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
