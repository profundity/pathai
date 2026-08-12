# Evidence Training-Example Schema

Each row = one graded causal claim, in the format future training examples (and the eventual gold-standard dataset) should follow. Derived directly from `intervention_grading_rubric.md` and `mechanistic_synthesis_case_log.md` — no column here is new science, each just gives an existing rubric judgment its own labeled slot instead of leaving it in prose.

| Column | What goes in it |
|---|---|
| **Gene/entity** | The gene or protein the claim is about |
| **Claim** | The one-sentence causal statement, in your own words |
| **Gene function(s), canonical** | What the gene is popularly known for — may be citation-biased, not necessarily most relevant here |
| **Gene function, in this study's context** | Which specific activity is actually operative in this claim/phenotype |
| **Activity type tested** | The specific molecular action assayed — e.g. phosphorylation vs. DNA-binding vs. scaffolding — so a multifunctional gene (e.g. kinase + TF) isn't collapsed into one label; same gene can get separate rows for separate activities |
| **Target engagement / isoform coverage** | For a paralog family or multi-target intervention, how evenly the technique actually hit each member — e.g. "uneven: AKT2/3 substantially reduced, AKT1 only ~50% at 72h." A negative result with poor coverage on one paralog is a different claim than a negative result with full coverage. |
| **Dose tested vs. IC50** | *Pharmacological interventions only (chemical inhibitors/degraders) — not applicable to genetic techniques.* The concentration(s) actually used, expressed as fold-multiple over the compound's known IC50 for its target(s)/isoform(s). Lets you check whether a negative result could simply reflect under-dosing before reaching for a network-compensation explanation (see rubric §5). |
| **Technique used** | What was actually done to test it (e.g. CRISPR knockout) |
| **Verb type** | Direct-action or outcome verb (rubric §2) |
| **Direction/sign** | Activates or inhibits the downstream thing |
| **Outcome (this evidence alone)** | What this specific piece of evidence establishes or rules out, taken by itself — distinct from Claim (the statement being tested) and Confidence (how much to trust it). General-purpose, applies to every row regardless of technique. Does NOT include synthesis across multiple rows/papers — that belongs in `mechanistic_synthesis_case_log.md`, not here. |
| **Evidence grade** | Where it lands on the rubric's ranking (necessity only, necessity+sufficiency, etc.) |
| **Confidence** | High/medium/low, with reasoning |
| **Source (PMID/DOI)** | Traceable back to the actual paper |
| **Section type** | Abstract vs. body text — caps confidence per rubric §1 |
| **Claim type** | Necessity / sufficiency / necessity+sufficiency (rescue) — distinct from evidence grade, which ranks the technique itself |
| **Rescue/add-back present** | Yes/no; if yes, prevention (co-transfected) vs. reversal (added after phenotype established) |
| **Verification status** | Confirmed against primary source vs. still unconfirmed/ambiguous |
| **Phenotype/outcome measured** | The actual downstream readout (e.g. IL-6 levels, apoptosis, tumor size) — separate from the causal claim itself |
| **Assay/Method** | The specific experimental technique that generated the readout (e.g. MTT viability, Annexin V/flow cytometry, clonogenic assay, Western blot, qPCR, kinase assay). Supplemental/supporting assays (e.g. a Western confirming target knockdown alongside the main phenotypic assay) belong here too, noted as supporting rather than primary. |
| **Endpoint** | The specific signal/number the assay produces (e.g. % viable cells, cleaved caspase-3 band intensity, Ct value) — distinct from the assay itself |
| **Species** | Mouse vs. human vs. other |
| **Model system** | Cell line, primary cells, in vivo/mouse, patient tissue |
| **Timepoint** | Acute vs. chronic, early vs. late — context can flip a claim's meaning over time |
| **Contradicting evidence** | Flag if another logged claim conflicts with this one — preserves contradictions instead of flattening them |
| **Curator notes** | Free-text escape hatch for anything that doesn't fit a column cleanly |

## Status
Draft — not yet applied to any case. Next step: convert the two existing worked cases (AKT/INY-03-041, Ikeuchi/ARID5A) into this format, one row at a time, with review between each.

## Resolved
The "context/cell type" open question is now covered by **Species**, **Model system**, and **Timepoint** as separate columns, rather than folded into "gene function, in this study's context."
