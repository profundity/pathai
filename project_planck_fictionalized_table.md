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

## Table 1 (fictionalized) — Proliferation, derived from real Table 1

| Condition | L1 | L2 | L3 | L4 | L5 | L6 |
|---|---|---|---|---|---|---|
| K1 alone | No effect | No effect | No effect | No effect | No effect | No effect |
| K2 alone | No effect | No effect | No effect | No effect | No effect | No effect |
| K3 alone | No effect | No effect | No effect | No effect | No effect | No effect |
| K1+K2 (K3 intact) | No effect | No effect | No effect | No effect | No effect | No effect |
| K2+K3 (K1 intact) | No effect | No effect | No effect | No effect | No effect | No effect |
| K1+K3 (K2 intact) | No effect | **Effect** | **Effect** | No effect | No effect | **Effect** |
| K1+K2+K3 (all silenced) | **Effect** | **Effect** | **Effect** | **Effect** | **Effect** | **Effect** |

Directly reproduces real Table 1's pattern: AKT1→K1 and AKT3→K3 each sufficient alone in all 6 lines (via K2+K3 and K1+K2 respectively); AKT2→K2 alone sufficient in only L1/L4/L5 (=A375/WM793/MTG001), insufficient in L2/L3/L6 (=HT144/SK-MEL28/MTG004).

## Table 2 (fictionalized) — Cell death, derived from real Table 2, L1 only (=A375)

| Condition | Cell death observed? |
|---|---|
| Positive control (cytotoxic drug) | Yes — gradual increase |
| Negative control | No |
| K1+K2+K3 (triple knockdown) | Yes — dramatic increase |
| K1+K2+K3 + reintroduced K1 (rescue) | No — rescued |

Directly reproduces real Table 2's pattern (staurosporine → generic positive control, siCtrl → negative control, siAKT1-3 → K1+K2+K3, mouse Akt1 rescue → reintroduced K1).

## Illustrative numeric layer added for the benchmark (not present in the real paper — the real figure gives only significance, not exact %/death-marker values)

For the K1+K3 (K2 intact) condition, proliferation % and death-marker values consistent with the effect/no-effect pattern above:
L1 98%/0.12, L2 45%/0.22, L3 52%/0.18, L4 95%/0.10, L5 101%/0.15, L6 40%/0.25

For the K1+K2+K3 (triple) condition:
L1 8%/0.82, L2 5%/0.91, L3 6%/0.88, L4 9%/0.79, L5 7%/0.85, L6 4%/0.93

These numeric values were what actually went into `project_planck_kinase_prompt.md` — confirmed here to be consistent with, and layered on top of, the real effect/no-effect pattern rather than freely invented.
