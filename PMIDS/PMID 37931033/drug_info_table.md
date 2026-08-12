# Drug/Compound Reference Table — PMID 37931033

Compounds used in this paper, with mechanism and isoform selectivity verified against primary pharmacology sources (not just the paper's own labels), per rubric §2.

| Compound | Target | Mechanism | Isoform selectivity (IC50) | Notes |
|---|---|---|---|---|
| **MK2206** | AKT1/2/3 | Allosteric inhibitor (binds pleckstrin-homology domain, not the ATP pocket) | AKT1 = 8 nM, AKT2 = 12 nM, AKT3 = 65 nM | AKT1 ≈ AKT2 potency; AKT3 ~5–8x weaker. Labeled "pan-AKT" in the paper's text, but not uniformly potent across paralogs. |
| **GDC-0068** (ipatasertib) | AKT1/2/3 | ATP-competitive inhibitor | AKT1 = 5 nM, AKT2 = 18 nM, AKT3 = 8 nM | Most balanced of the three AKT-targeting compounds — AKT1 and AKT3 close, AKT2 ~3.6x weaker. Closest to genuinely "pan," though still not perfectly even. |
| **GDC-0941** (pictilisib) | PI3K (class I, upstream of AKT — not AKT itself) | Pan-Class I PI3K inhibitor | p110α = 3 nM, p110β = 33 nM (11x weaker), p110δ = 3 nM, p110γ = 75 nM (25x weaker) | α and δ hit hard; β and γ much less so. Meaningfully uneven despite "pan-Class I" label. Different target class entirely from the AKT inhibitors — included in the figure as a positive-control comparator, not an AKT-targeted compound. |
| **INY-03-041** | AKT1/2/3 | PROTAC (proteolysis-targeting chimera) — GDC-0068 conjugated to lenalidomide (CRBN E3 ligase recruiter). Dual mechanism: kinase inhibition (via the GDC-0068 moiety) + targeted proteasomal degradation (via CRBN-mediated ubiquitination). | ~77% reduction in total AKT protein at 1μM, vs. ~89% reduction by siAKT1–3. Time-course blotting showed *incomplete* per-paralog knockdown, unlike siRNA's near-complete loss. | Not from Supplementary Fig. S1 — this is from a separate, later experiment in the same paper (main text, main text section following Fig. 1/2). Tested at two different doses across the paper: 1μM (main text finding — significantly reduced proliferation, less potently than siAKT1-3) and 500nM (Figure 4, combined with GSK0394 — alone did not visibly separate from DMSO at this lower dose). |

## Source
Isoform/potency data pulled from primary pharmacology literature (MedChemExpress, Selleck Chemicals product/mechanism pages citing original characterization papers; ipatasertib Phase I paper, *Cancer Discovery* 2017; pictilisib Phase I paper, *Clin Cancer Res* 2015) — not from PMID 37931033 itself, which only labels these compounds descriptively ("pan-AKT allosteric inhibitor," "pan-AKT ATP competitive inhibitor," "inhibition of all four class 1 PI3Ks") without giving isoform-specific potency values.

## Relevance to Supplementary Figure S1
Fig. S1 tests MK2206 and GDC-0068 (both AKT-targeted) against GDC-0941 (PI3K-targeted, different node) across 6 melanoma cell lines. The paper's claim — "no significant effect of AKT inhibition on melanoma cell proliferation" — holds cleanly in 4/6 lines (A375, WM793, MTG001, MTG004), where AKT inhibitors track with DMSO control. In HT144 and SK-MEL28, MK2206 shows a visible reduction relative to control that the prose summary does not distinguish from the other 4 lines.
