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

## Status
Draft — not yet applied to any case. Next step: convert the two existing worked cases (AKT/INY-03-041, Ikeuchi/ARID5A) into this format as a proof of concept, per the small-steps plan.

## Open question
Whether a "context/cell type" column is needed as its own field, or is folded into "gene function, in this study's context" — flagged, not yet resolved.
