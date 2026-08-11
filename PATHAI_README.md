# PATHAI — Project Index

**What this is:** PATHAI is built to fill a coverage gap in existing pathway databases (KEGG, Reactome, STRING, GO) by *reading* papers to build mechanistic understanding, not just surfacing what's already been curated into structured databases. That's a coverage gap, not a weighting bias: even a "perfect" equal-weight, non-popularity-biased reasoning system still hits a wall the databases themselves impose — some genes simply have no mechanistic vocabulary to draw on yet, regardless of how the gene list is processed upstream. The result is a mechanistic, evidence-graded biological knowledge graph — not a consensus pathway map, but a graph where every claim is graded by how strong the actual experiment behind it was (not just how confidently it was extracted), with contradictions preserved rather than flattened.

If you're picking this up cold — including a future AI session with no memory of how this was built — read in this order:

## 1. Start here for the current, live deliverable
- **`intervention_grading_rubric.md`** — the actual, living evidence-grading standard. This is the core output of the project so far: how to read a chunk (section-type awareness), general rules for reading text without being fooled by rhetoric, how to rank intervention techniques, the conditions that validate those rankings, and how to weigh pharmacological vs. genetic evidence against each other.
- **`mechanistic_synthesis_case_log.md`** — the worked case(s) that built and justify the rubric's rules. Read this to see *why* each rubric rule exists, with real reasoning, real errors made and corrected, and real verification steps against actual literature.
- **`evidence_training_schema.md`** — column format for turning rubric judgments into structured rows (gene, claim, function-in-context, activity type, evidence grade, etc.), the first step toward a gold-standard dataset at training scale.
- **`evidence_training_examples.md`** — the schema applied to both existing worked cases (AKT/INY-03-041, ARID5A) as a proof of concept: 6 rows, 1 correctly-excluded manipulation, and a list of schema gaps the exercise surfaced (cross-row relationships, multi-outcome rows, primary-vs-secondary-source provenance).

## 2. Test data
- **`pisk_mtor_seed_texts.txt`** — the seed corpus everything has been tested against: 10 text chunks across 3 real papers (PI3K/AKT/mTOR pathway). Deliberately narrow — see the case log and rubric for what this data can and can't yet prove.

## 3. Background and history
- **`AI Platform Requirements.md`**, **`PATHAI Part 2 Graph Building.md`** — the original, messy ChatGPT transcripts documenting how the project's pipeline (mentions → atoms → bridging → graph) was actually built, including 16+ script iterations, real bugs, and real pivots. Long and unfiltered — useful for provenance, not required reading.
- **`PATHAI_Project_Notebook(1).md`**, **`ROADMAP.md`**, **`PATHAI_ModelRouting.md`**, **`PATHAI_Biology.md`**, **`PATHAI_JSONSchemas.md`**, **`CHANGELOG.md`** — short, distilled summaries of that same history.

## 4. Full conversation record
- **`Chat History PATHAI/`** — verbatim transcripts of the sessions that built the rubric and case log, in order. Reference only; the rubric and case log already contain the distilled, usable output.

## 5. How the AI assistant's memory fits in
- **`Claude Memory Snapshot/`** — a point-in-time copy of the behavioral memory Claude Code has built up while working on this project (tone/collaboration preferences, and the general evidence-synthesis method). **This is a snapshot, not a live system** — it won't update automatically as new memories are saved, and it isn't automatically read by any AI tool; it's a human-readable archive so the reasoning approach isn't lost if this project moves machines, tools, or hands. Refresh it periodically by asking for an updated copy.

## What's NOT yet built
- Entity/gene ID normalization (e.g., mapping synonyms to one canonical ID) — flagged repeatedly as the biggest remaining technical gap.
- The actual graph-builder script — written once early in the project's history, never updated to match the current schema, never rerun.
- A validated gold-standard set comparing the rubric's judgments against independent expert review at scale.
- Coverage of the rubric beyond a handful of intervention techniques (3 of 15 ranked so far, plus the pharmacological-inhibition asymmetry rule).
