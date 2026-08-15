# PMID 37931033 — Figure 1 Data Tables (as analyzed)

Source: Parkman et al., Mol Cancer Ther 2024, Figure 1 (Panels A–D) and Supplementary Figures S3–S4. Read directly from the primary figures, not from the paper's summary text — see `evidence_training_examples.md` Rows 2-4 for the full graded/curated version of this data.

## Table 1 — Figure 1A: Proliferation (confluence assay), all 6 cell lines × 8 conditions

Effect = statistically significant reduction in confluence vs. siCtrl (p<0.0001 where marked). Read from trace separation in each line's panel.

| Condition | A375 | HT144 | SK-MEL28 | WM793 (Pten-/-) | MTG001 | MTG004 |
|---|---|---|---|---|---|---|
| siAKT1 alone | No effect | No effect | No effect | No effect | No effect | No effect |
| siAKT2 alone | No effect | No effect | No effect | No effect | No effect | No effect |
| siAKT3 alone | No effect | No effect | No effect | No effect | No effect | No effect |
| siAKT1+2 (AKT3 intact) | No effect | No effect | No effect | No effect | No effect | No effect |
| siAKT2+3 (AKT1 intact) | No effect | No effect | No effect | No effect | No effect | No effect |
| siAKT1+3 (AKT2 intact) | No effect | **Effect** | **Effect** | No effect | No effect | **Effect** |
| siAKT1+2+3 (all silenced) | **Effect** | **Effect** | **Effect** | **Effect** | **Effect** | **Effect** |

**Pattern:** AKT1 alone and AKT3 alone are each sufficient in all 6 lines (via siAKT2+3 and siAKT1+2 respectively). AKT2 alone is sufficient in only 3 of 6 lines (A375, WM793, MTG001) and insufficient in the other 3 (HT144, SK-MEL28, MTG004). Triple knockdown is the only condition with zero exceptions.

## Table 2 — Figure 1D: Cell death (Cytotox Red assay), A375 only

| Condition | Cell death observed? | Notes |
|---|---|---|
| Staurosporine (positive control) | Yes — gradual increase | Pan-kinase inhibitor, established cytotoxic control |
| siCtrl (negative control) | No | Baseline |
| siAKT1+2+3 (triple knockdown) | Yes — dramatic increase at ~22h | Comparable magnitude to staurosporine |
| siAKT1+2+3 + WT mouse Akt1 (rescue) | No — rescued | Death abrogated by AKT1 reintroduction |

**Note:** no pairwise (e.g. siAKT1+3) condition was tested in the death assay — only proliferation (Table 1) was measured for pairwise combinations. Whether the siAKT1+3 proliferation reduction in HT144/SK-MEL28/MTG004 reflects any degree of cell death, vs. pure growth-rate slowing, is untested in this figure.

## Table 3 — Verification coverage (Figure 1B/C + Supplementary Figure S3)

| Cell line | Knockdown confirmed | Method | Cross-reactivity checked (all 3 paralogs) | Activity readout |
|---|---|---|---|---|
| A375 | Yes | Western blot | Partial (siAKT1, siAKT2 only) | P-AKT(S473), Fig 1C |
| WM793 | Yes | Western blot | No (siAKT3 blot shows AKT3 band only) | P-PRAS40 |
| HT144 | Yes | Western blot | Yes (all 3 conditions × all 3 antibodies) | P-PRAS40 |
| MTG001 | Yes | qPCR | N/A (qPCR, not blot) | Not tested |
| MTG004 | Yes | qPCR | N/A (qPCR, not blot) | Not tested |
| SK-MEL28 | Not found | — | — | — |

## Table 4 — Supplementary Figure S4: mouse-specificity control (YUMM1.1, mouse cell line)

| Condition | Effect on mouse AKT expression/activity? |
|---|---|
| Human-specific siAKT1, siAKT2, siAKT3, and all combinations (including triple) | No effect — confirms siRNAs are human-specific, don't cross-react with mouse AKT (P-AKT/P-PRAS40 blot unchanged vs. siCtrl) |

This validates that the mouse AKT1 construct used in the Figure 1C-D rescue is genuinely resistant to the human-specific siRNAs, not itself being silenced.

## Key gaps/flags established during analysis (see `evidence_training_examples.md` for full curator notes)
- Rescue-construct data exists only for AKT1 (not AKT2 or AKT3), despite the paper's text stating all three were tested and concluding "any one paralog...can compensate for the other two."
- Endogenous pairwise-knockdown data (Table 1) independently supports AKT1 and AKT3 standalone sufficiency (6/6 lines each) and shows AKT2 standalone sufficiency is cell-line-dependent (3/6) — this is real evidence the paper's flat summary sentence doesn't fully convey.
- Cell death (Table 2) was only tested for the triple-knockdown condition — reduced proliferation under partial (pairwise) knockdown was never shown to translate to actual cell death in any line.
