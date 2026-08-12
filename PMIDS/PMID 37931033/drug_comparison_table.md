# Drug Comparison Table — PMID 37931033

Compact table version. Full mechanism detail and sourcing: see `drug_info_table.md` in this same folder.

| Compound | Target | Mechanism | IC50 (AKT1) | IC50 (AKT2) | IC50 (AKT3) |
|---|---|---|---|---|---|
| MK2206 | AKT1/2/3 | Allosteric | 8 nM | 12 nM | 65 nM |
| GDC-0068 (ipatasertib) | AKT1/2/3 | ATP-competitive | 5 nM | 18 nM | 8 nM |
| INY-03-041 | AKT1/2/3 | PROTAC (degrader) | — | — | — |

| Compound | Target | Mechanism | IC50 (p110α) | IC50 (p110β) | IC50 (p110γ) | IC50 (p110δ) |
|---|---|---|---|---|---|---|
| GDC-0941 (pictilisib) | PI3K class I | Pan-Class I inhibitor | 3 nM | 33 nM | 75 nM | 3 nM |

**Notes:**
- INY-03-041 has no per-isoform IC50 reported in the source paper — its evidence is expressed as % total AKT protein reduction instead (~77% at 1μM, vs. ~89% for siAKT1–3), since it's a degrader, not a catalytic inhibitor.
- GDC-0941 targets PI3K (upstream of AKT), not AKT itself — included in Figure S1 as a comparator, not an AKT-targeted compound.
