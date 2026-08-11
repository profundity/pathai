# Evidence Training-Example Schema

Each row = one graded causal claim, in the format future training examples (and the eventual gold-standard dataset) should follow. Derived directly from `intervention_grading_rubric.md` and `mechanistic_synthesis_case_log.md` — no column here is new science, each just gives an existing rubric judgment its own labeled slot instead of leaving it in prose.

| Column | What goes in it |
|---|---|
| **Gene/entity** | The gene or protein the claim is about |
| **Claim** | The one-sentence causal statement, in your own words |
| **Gene function(s), canonical** | What the gene is popularly known for — may be citation-biased, not necessarily most relevant here |
| **Gene function, in this study's context** | Which specific activity is actually operative in this claim/phenotype |
| **Activity type tested** | The specific molecular action assayed — e.g. phosphorylation vs. DNA-binding vs. scaffolding — so a multifunctional gene (e.g. kinase + TF) isn't collapsed into one label; same gene can get separate rows for separate activities |
| **Technique used** | What was actually done to test it (e.g. CRISPR knockout) |
| **Verb type** | Direct-action or outcome verb (rubric §2) |
| **Direction/sign** | Activates or inhibits the downstream thing |
| **Evidence grade** | Where it lands on the rubric's ranking (necessity only, necessity+sufficiency, etc.) |
| **Confidence** | High/medium/low, with reasoning |
| **Source (PMID/DOI)** | Traceable back to the actual paper |
| **Section type** | Abstract vs. body text — caps confidence per rubric §1 |
| **Claim type** | Necessity / sufficiency / necessity+sufficiency (rescue) — distinct from evidence grade, which ranks the technique itself |
| **Rescue/add-back present** | Yes/no; if yes, prevention (co-transfected) vs. reversal (added after phenotype established) |
| **Verification status** | Confirmed against primary source vs. still unconfirmed/ambiguous |
| **Phenotype/outcome measured** | The actual downstream readout (e.g. IL-6 levels, apoptosis, tumor size) — separate from the causal claim itself |
| **Species** | Mouse vs. human vs. other |
| **Model system** | Cell line, primary cells, in vivo/mouse, patient tissue |
| **Timepoint** | Acute vs. chronic, early vs. late — context can flip a claim's meaning over time |
| **Contradicting evidence** | Flag if another logged claim conflicts with this one — preserves contradictions instead of flattening them |
| **Curator notes** | Free-text escape hatch for anything that doesn't fit a column cleanly |

## Status
Applied to both existing worked cases as a proof of concept — see `evidence_training_examples.md`. Six rows produced (four from the AKT case, two from ARID5A), plus one manipulation correctly excluded (CRISPRa/EndoOE, no testable claim).

## Resolved
The "context/cell type" open question is now covered by **Species**, **Model system**, and **Timepoint** as separate columns, rather than folded into "gene function, in this study's context."

## Findings from the proof of concept (see evidence_training_examples.md for detail)
- Compound prose cases correctly split into multiple rows — matches rubric §2's "split compound claims" rule.
- The schema correctly refuses a row for manipulations with no testable claim (CRISPRa/EndoOE arm).
- **Open gaps identified, not yet fixed:** no column for cross-row relationships (e.g. one row mechanistically explaining another); no rule for multi-outcome single-experiment rows (split vs. combine); no column distinguishing *how* a row's data was obtained (primary text vs. secondary summary) — this turned out to correlate with confidence and should probably be explicit rather than implicit.
