---
name: evidence-synthesis-method
description: "The portable, general-purpose method for building verified mechanistic understanding from raw evidence — the core discipline PATHAI is trying to teach and eventually automate"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: ad1a57c3-d71f-40c2-b5d6-d4e65d1daa0c
  modified: 2026-08-03T21:04:05.582Z
---

This is the consolidated version of a method demonstrated across a full worked case (AKT/PI3K/mTOR melanoma pathway, PMID 37931033) — written to be portable to any domain requiring evidence-grounded mechanistic reasoning, not just this one case or biology specifically. The user was explicit: the goal is for this to generalize to "any other scenario or place," not stay tied to AKT.

**The general process:**

1. **Start with a specific claim in the source material.** Not a vague topic — one concrete sentence or finding.
2. **Identify the precise, checkable sub-question hiding inside it.** Not "what does this mean broadly" but the specific ambiguity worth resolving (which entity, which mechanism, which version/scope of the claim).
3. **Form a hypothesis from background/domain reasoning — but hold it as a hypothesis, not a conclusion.** Reasoning from context is a legitimate first step, not a shortcut to skip.
4. **Verify the hypothesis against a primary or credible secondary source.** Go look, rather than trust the plausible reasoning alone — this is the step most often skipped, and most often where error hides.
5. **Let the verification correct the hypothesis, even when the original reasoning felt solid.** In the worked case, "pan-AKT inhibition should hit everything roughly equally" was a reasonable-sounding hypothesis that a real check overturned (the specific compound barely touched one isoform).
6. **Look for connections across independent pieces of evidence — cross-source integration, not single-source reading.** The mechanistic payoff came from connecting a feedback-loop finding in one paper to the drug-design logic in a different paper, not from either alone.
7. **Synthesize verified pieces into a coherent mechanistic narrative — not just a list of separately graded facts.** The goal is "how does this system actually behave and resist disruption," not a scorecard.
8. **Explicitly flag what remains unconfirmed rather than resolving it by assumption.** When verification is inconclusive, say so as the answer — don't quietly pick the more plausible-sounding reading (see [[verification-then-present-ambiguity]]).
9. **Expect and welcome correction as the actual error-catching mechanism, not friction.** Several steps in the worked case were wrong until challenged directly — the correction, not the first-pass reasoning, is what made the result trustworthy.
10. **Repeat across many real cases rather than relying on one written rule.** The same principle that governs how PATHAI's own AI should be trained (judge many concrete cases, don't just author abstract rules) applies to how this method gets internalized here too — see the case log this method feeds into.

**Honest limitation, stated plainly:** this method doesn't become "automatic instinct" the way practice reshapes a human skill — nothing about running this process updates the underlying model between sessions. What actually keeps this discipline alive across sessions is (a) this memory being read and applied deliberately each time, (b) a growing log of concrete worked cases to check new situations against, and (c) the user continuing to catch and correct drift in real time — the correction loop is the real mechanism, not the memory file alone.
