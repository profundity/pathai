---
name: show-figure-panels-inline
description: "When discussing a specific figure panel during paper analysis, display the cropped panel image inline via Read (not just a file path) before/alongside the discussion"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: ad1a57c3-d71f-40c2-b5d6-d4e65d1daa0c
  modified: 2026-08-12T02:15:19.844Z
---

When analyzing a paper's figure, don't just describe a panel in text or give the user a file path to go look at — crop the panel (via PIL/imagemagick) and use the Read tool to display it inline in the conversation automatically, before discussing it. The user wants the image visible "on the right panel" alongside the reasoning, not just referenced.

**Why:** user's own words: "You should pull up the figure automatically on the right panel and then crop to the specific panel you want to discuss." Confirmed after they had to explicitly ask twice (once for the full figure, once because they couldn't locate the saved PNGs in their file browser).

**How to apply:** during any figure-based row-building or verification step (like the PMID 37931033 evidence rows), whenever the discussion moves to a specific panel (A, B, C, D...), crop and Read that panel *before* writing the analysis text for it, not after. Also save cropped panels into the project folder (e.g. `PMIDS/<PMID>/figure1_panels/`), not just the session scratchpad — the scratchpad path isn't visible in the user's real file browser. See [[pathai-drug-reference-pattern]] for the related pattern of durable per-paper reference files.
