# Fictionalized Data Table — Derived Directly From PMID 37931033 Figure 1A/1D

This table is a renamed, 1:1 mapping of the real data in `PMIDS/PMID 37931033/figure1_data_table.md` (Tables 1 and 2). No effect/no-effect pattern was invented — every cell below reproduces the real result for its mapped real condition/cell line. Only the numeric percentage and death-marker values (needed for the benchmark's quantitative threshold question) are illustrative additions layered on top of the real categorical pattern, since the real figure only reports statistical significance (effect/no effect), not exact percentages.

## Mapping key

| Real (PMID 37931033) | Fictional (benchmark) |
|---|---|
| AKT1 | K1 |
| AKT2 | K2 |
| AKT3 | K3 |
| A375 | L1 |
| HT144 | L2 |
| SK-MEL28 | L3 |
| WM793 (Pten-/-) | L4 |
| MTG001 | L5 |
| MTG004 | L6 |

## Notation (must be stated explicitly in the prompt, not assumed)

K1, K2, K3 are three paralogous kinase proteins. siK1, siK2, siK3 are validated siRNAs; each silences expression of only its correspondingly numbered protein (confirmed on-target, no cross-silencing of the other two — see real Figure 1B/S3 verification). A treatment label like "siK1+siK2" names which siRNAs were applied — it does not itself state which protein remains unsilenced; the model must derive that from the set of three proteins minus the two named as silenced.

## Table 1 (fictionalized) — Proliferation, derived from real Table 1

| Treatment (siRNAs applied) | L1 | L2 | L3 | L4 | L5 | L6 |
|---|---|---|---|---|---|---|
| siK1 | No effect | No effect | No effect | No effect | No effect | No effect |
| siK2 | No effect | No effect | No effect | No effect | No effect | No effect |
| siK3 | No effect | No effect | No effect | No effect | No effect | No effect |
| siK1+siK2 | No effect | No effect | No effect | No effect | No effect | No effect |
| siK2+siK3 | No effect | No effect | No effect | No effect | No effect | No effect |
| siK1+siK3 | No effect | **Effect** | **Effect** | No effect | No effect | **Effect** |
| siK1+siK2+siK3 | **Effect** | **Effect** | **Effect** | **Effect** | **Effect** | **Effect** |

Directly reproduces real Table 1's pattern: AKT1→K1 and AKT3→K3 each sufficient alone in all 6 lines (siK2+siK3 leaves only K1 unsilenced; siK1+siK2 leaves only K3 unsilenced); AKT2→K2 alone sufficient only in L1/L4/L5 (=A375/WM793/MTG001), insufficient in L2/L3/L6 (=HT144/SK-MEL28/MTG004) — siK1+siK3 leaves only K2 unsilenced. No parenthetical naming the unsilenced protein is included in the treatment column — identifying it is part of the reasoning being tested, not given information.

## Table 2 (fictionalized) — Cell death, derived from real Table 2, L1 only (=A375)

| Treatment | Cell death observed? |
|---|---|
| Positive control (cytotoxic drug) | Yes — gradual increase |
| Negative control (non-targeting siRNA) | No |
| siK1+siK2+siK3 | Yes — dramatic increase |
| siK1+siK2+siK3 + reintroduced K1 protein (resistant to siK1) | No — rescued |

Directly reproduces real Table 2's pattern (staurosporine → generic positive control, siCtrl → negative control, siAKT1-3 → siK1+siK2+siK3, mouse Akt1 rescue → reintroduced K1 protein via a construct resistant to siK1).

## Illustrative numeric layer added for the benchmark (not present in the real paper — the real figure gives only significance, not exact %/death-marker values)

For the siK1+siK3 treatment, proliferation % and death-marker values consistent with the effect/no-effect pattern above:
L1 98%/0.12, L2 45%/0.22, L3 52%/0.18, L4 95%/0.10, L5 101%/0.15, L6 40%/0.25

For the siK1+siK2+siK3 treatment:
L1 8%/0.82, L2 5%/0.91, L3 6%/0.88, L4 9%/0.79, L5 7%/0.85, L6 4%/0.93

These numeric values were what actually went into `project_planck_kinase_prompt.md` — confirmed here to be consistent with, and layered on top of, the real effect/no-effect pattern rather than freely invented.
