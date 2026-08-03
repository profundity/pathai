---
name: paper-lookup-order
description: "When verifying a citation/claim against a primary paper, check Semantic Scholar's API for an open-access PDF link before trying publisher pages or generic search"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: ad1a57c3-d71f-40c2-b5d6-d4e65d1daa0c
  modified: 2026-08-03T23:53:32.429Z
---

**The instruction:** once a paper's DOI or PMID is known (from a reference list, PubMed, or search), immediately query the Semantic Scholar API — `https://api.semanticscholar.org/graph/v1/paper/DOI:<doi>?fields=title,abstract,openAccessPdf,tldr` — before trying to fetch the publisher's page directly (Wiley/Springer/etc. frequently 403 WebFetch) or before doing another round of generic web search on the review/paper title. The `openAccessPdf` field, when present, gives a direct link to a free full-text copy (often PMC) in one call.

**Why:** In the PATHAI ARID5A/CRISPRa verification case, I spent ~5 turns guessing candidate review titles via WebSearch, fetching paywalled publisher pages that 403'd, and reasoning from incomplete secondary-source abstract summaries — before trying the Semantic Scholar API, which immediately surfaced a free PMC full-text link. The user called out the wasted turns directly: "You should have done this early." Two independent secondary summaries had both silently omitted a real experimental detail (a CRISPRa arm), so relying on search-snippet summaries instead of reading the primary text also produced a wrong intermediate conclusion, not just wasted time.

**How to apply:** treat "get the DOI/PMID → hit Semantic Scholar API → get openAccessPdf → fetch that URL" as the default verification path, ahead of generic search or guessing at publisher URLs. Only fall back to generic search if Semantic Scholar has no record or no open-access link. This complements [[feedback-verification-then-present-ambiguity]] and [[feedback-evidence-synthesis-method]] — verification should be efficient, not just eventually correct.
