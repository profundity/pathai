---
name: pathai-pdf-pipeline-architecture
description: "Recommended modular architecture for a future PATHAI paper-ingestion pipeline, once scaling past hand-by-hand PDF reading"
metadata:
  node_type: memory
  type: project
  originSessionId: ad1a57c3-d71f-40c2-b5d6-d4e65d1daa0c
  modified: 2026-08-12T00:16:52.439Z
---

**The architecture, as separate, independently-retryable stages (not one monolithic script):**
1. **Scraper/discovery node** — Playwright or Crawlee, finds PDF links on a page (href ending `.pdf`, plus embedded PDFs inside iframes).
2. **PDF detector node** — confirms a found link is actually a real, parseable PDF before committing to download.
3. **Download node** — fetches the bytes.
4. **Text extraction node** — PyMuPDF (or pdf.js-extract / unpdf) turns the PDF into structured text with positions/tables/metadata, suitable for feeding into the evidence-training-schema work. OCR as an optional fallback for scanned (non-text) PDFs.

**Why separate nodes, not one pipeline function:** different PDFs fail in different, unrelated ways — weird encodings, password protection, embedded-viewer quirks. Splitting into stages means a failure at extraction doesn't force re-scraping, and a failure at download doesn't force re-discovery. Retry just the broken stage.

**Known limitation this does NOT solve:** CAPTCHA-gated downloads (see [[feedback-captcha-is-not-a-tooling-problem]]). This architecture is for the common case — papers that download cleanly — not for sites that put up an active anti-bot challenge on the binary itself.

**How to apply:** reach for this shape once PATHAI moves from hand-verifying individual papers (the current rubric/case-log/schema work) to batch-ingesting many papers at once. Not needed yet for the current one-case-at-a-time pace.
