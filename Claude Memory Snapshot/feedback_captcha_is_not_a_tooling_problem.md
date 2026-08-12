---
name: captcha-is-not-a-tooling-problem
description: "When a download is blocked by an actual CAPTCHA (not just a JS challenge), swapping automation libraries doesn't help — recognize the difference and don't escalate into automated CAPTCHA-solving"
metadata:
  node_type: memory
  type: feedback
  originSessionId: ad1a57c3-d71f-40c2-b5d6-d4e65d1daa0c
  modified: 2026-08-12T00:17:12.698Z
---

**The distinction to hold onto:** a JS-based proof-of-work page (compute a hash, set a cookie, reload) is a tooling problem — a real browser (e.g. SeleniumBase with undetected-chromedriver, or Playwright) can get past it, because it just requires executing JavaScript. An actual CAPTCHA (e.g. Google reCAPTCHA) is a *different* wall — it's specifically designed to distinguish humans from any automation, including "stealth"/undetected browser modes. Once a target site escalates to serving an actual CAPTCHA in response to automated access, switching which automation library is used (curl → SeleniumBase → Playwright, etc.) will not help, because it's the same category of thing being detected and blocked, not a library-specific limitation.

**Why this matters:** in the PATHAI PMC-supplementary-PDF case (PMC10932877), curl hit a JS proof-of-work wall; SeleniumBase with `uc=True` (undetected-chromedriver, a real headless Chrome) got further but triggered an actual Google reCAPTCHA challenge page. The user then suggested trying Playwright instead — but Playwright drives the same category of real browser and would hit the identical CAPTCHA, since the site is checking for automation signals, not for which specific library is driving the browser.

**How to apply:** when a download attempt escalates from a simple JS challenge to an actual CAPTCHA, recognize that as a different, harder wall — not a "try a different tool" problem. Don't build or run code whose explicit purpose is auto-solving a live CAPTCHA (e.g. a `click_captcha()`-style step) — that crosses from "render a page" into deliberately defeating a site's explicit anti-bot gate, which is a line to hold even for legitimate research use. The correct move at that point is asking the user to complete the CAPTCHA themselves (they have a real browser and are a real human) and hand over the resulting file, not chasing further automation options. See also [[project-pathai-pdf-pipeline-architecture]] for what automation *is* still appropriate (papers that download cleanly, no CAPTCHA involved).
