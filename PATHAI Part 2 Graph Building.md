---
title: "PATHAI Part 2 Graph Building"
source: "https://chatgpt.com/c/699515ef-d618-8333-92a8-955880c0b2b7"
---

**You:**

Here’s a ready-to-paste first message for **PATHAI – Part 2**. Replace the bracketed parts with your actual filenames/TAGs.

---

**BOOTSTRAP MESSAGE (paste into new chat):**

I’m starting **PATHAI – Part 2** and want to continue seamlessly from Part 1.

**Scope:** Keep this chat *only* about PATHAI (no Windows troubleshooting).

**Project folder:** C:\Users\Prem Subramaniam\Documents\Pathway AI\

**Current artifacts present (files):**

* pisk_mtor_seed_texts.txt
* mentions.jsonl
* atoms.jsonl
* Scripts:

  * mine_with_routing.py (working)
  * atoms_with_routing.py (or whatever the atoms builder script is called)
  * [any other scripts]

**Resume from these TAGs (Part 1):**

* TAG: PATHAI-0032 — Final working mine_with_routing.py + JSON schema rules
* TAG: PATHAI-0036 — Atom schema + routing/escalation logic
* TAG: PATHAI-0038 — Bridging/adjacent-chunk logic
* TAG: PATHAI-0040 — Next step roadmap: build graph from atoms + edge scoring

**Key requirements (must follow):**

1. Always reprint the **full script** when you propose code changes (no partial diffs).
2. Use **TAGs** in your replies (e.g., TAG: PATHAI-0041).
3. Scripts should be runnable on Windows with my environment.
4. Prefer strict JSON schema outputs with validation + routing.
5. Keep outputs human-auditable (CSV summaries + readable text reports).

**What I want next:**
Write the next full script: **build graph from atoms.jsonl** → output:

* edges.jsonl (normalized edges + conditional edge strength score)
* nodes.jsonl (deduped entities)
* graph_summary.csv (human readable)
* top_edges.txt (ranked list)

**Inputs to assume:**

* atoms.jsonl is JSONL with lines like: { "chunk_id": N, "atoms": [...], "_routing": {...} }
* Each atom contains: intervention, system, readout, effect, strength_cues, evidence, confidence.

**Here are 2 sample lines from my atoms.jsonl (paste 1–2 real lines below):**
[PASTE 1–2 JSONL LINES HERE]

---

If you paste that into the new chat and include 1–2 real lines from atoms.jsonl, I can generate the graph-building script immediately.

* * *

**ChatGPT:**

TAG: **PATHAI-0041** — `build_graph_from_atoms.py` (atoms.jsonl → nodes/edges + scored graph outputs)

```Python
#!/usr/bin/env python3
"""
PATHAI – Build Graph from atoms.jsonl

Input:
  atoms.jsonl where each line is like:
    { "chunk_id": N, "atoms": [...], "_routing": {...} }

Each atom is expected to contain (best-effort):
  intervention, system, readout, effect, strength_cues, evidence, confidence

Outputs (in --outdir):
  - nodes.jsonl         (deduped entities)
  - edges.jsonl         (normalized edges with conditional edge strength score)
  - graph_summary.csv   (human-auditable edges table)
  - top_edges.txt       (ranked edge list)

Design goals:
  - Windows-friendly (no non-stdlib deps)
  - Strict-ish validation + routing flags
  - Human-auditable scoring (transparent components)

Example:
  python build_graph_from_atoms.py ^
    --input "C:\Users\Prem Subramaniam\Documents\Pathway AI\atoms.jsonl" ^
    --outdir "C:\Users\Prem Subramaniam\Documents\Pathway AI\graph_out" ^
    --top_n 200

"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
import re
import statistics
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional, Set, Tuple


# ----------------------------
# Normalization / parsing utils
# ----------------------------

_WS_RE = re.compile(r"\s+")
_PUNCT_RE = re.compile(r"[^a-z0-9\s\-\+_/]+")

POS_KWS = (
    "increase", "increased", "upregulate", "upregulated", "activate", "activated",
    "enhance", "enhanced", "promote", "promoted", "induce", "induced", "elevate", "elevated"
)
NEG_KWS = (
    "decrease", "decreased", "downregulate", "downregulated", "inhibit", "inhibited",
    "suppress", "suppressed", "reduce", "reduced", "block", "blocked", "attenuate", "attenuated"
)

CUE_WEIGHTS = {
    # stronger evidence/phrasing
    "significant": 0.75,
    "statistically significant": 0.80,
    "strong": 0.75,
    "robust": 0.75,
    "marked": 0.70,
    "dramatic": 0.80,
    "substantial": 0.70,
    "potent": 0.75,
    "dose-dependent": 0.80,
    "dose dependent": 0.80,
    "time-dependent": 0.65,
    "time dependent": 0.65,
    "consistent": 0.60,
    "reproducible": 0.70,
    "validated": 0.70,
    "independent": 0.65,
    # weaker evidence/hedges
    "modest": 0.40,
    "slight": 0.30,
    "trend": 0.30,
    "suggest": 0.30,
    "suggests": 0.30,
    "may": 0.20,
    "might": 0.20,
    "possible": 0.20,
}

CONDITION_MARKERS = ("when ", "under ", "in the presence of", "upon ", "during ", "after ", "at ")


def clamp(x: float, lo: float = 0.0, hi: float = 1.0) -> float:
    return lo if x < lo else hi if x > hi else x


def normalize_text(s: str) -> str:
    s = (s or "").strip().lower()
    s = s.replace("\u00b5", "u")  # micro symbol
    s = _PUNCT_RE.sub(" ", s)
    s = _WS_RE.sub(" ", s).strip()
    return s


def stable_hash(text: str, n: int = 10) -> str:
    h = hashlib.sha1(text.encode("utf-8")).hexdigest()
    return h[:n]


def parse_confidence(conf: Any) -> float:
    """
    Best-effort confidence → 0..1
    Accepts:
      - numeric 0..1
      - percentage 0..100
      - strings: high/medium/low, etc.
    """
    if conf is None:
        return 0.50
    if isinstance(conf, (int, float)):
        c = float(conf)
        if c > 1.0:
            # maybe 0..100
            if c <= 100.0:
                return clamp(c / 100.0)
            return 0.50
        return clamp(c)
    if isinstance(conf, str):
        t = normalize_text(conf)
        if not t:
            return 0.50
        # numeric in string
        m = re.search(r"(\d+(\.\d+)?)", t)
        if m:
            v = float(m.group(1))
            if v > 1.0 and v <= 100.0:
                return clamp(v / 100.0)
            return clamp(v)
        if "high" in t:
            return 0.85
        if "medium" in t or "moderate" in t:
            return 0.60
        if "low" in t:
            return 0.35
        if "uncertain" in t or "unknown" in t:
            return 0.50
    return 0.50


def cue_score(strength_cues: Any) -> float:
    """
    strength_cues may be:
      - list[str]
      - str
      - list[dict] (we extract text-ish fields)
    Returns 0..1
    """
    cues: List[str] = []
    if strength_cues is None:
        return 0.0

    if isinstance(strength_cues, str):
        cues = [strength_cues]
    elif isinstance(strength_cues, list):
        for x in strength_cues:
            if isinstance(x, str):
                cues.append(x)
            elif isinstance(x, dict):
                # try a few common fields
                for k in ("cue", "text", "label", "value"):
                    if k in x and isinstance(x[k], str):
                        cues.append(x[k])
                        break

    text = " | ".join(cues)
    t = normalize_text(text)
    if not t:
        return 0.0

    # Score by max matching weight, with a small additive for multiple strong hits
    hits: List[float] = []
    for k, w in CUE_WEIGHTS.items():
        if k in t:
            hits.append(w)
    if not hits:
        return 0.10 if len(t) >= 10 else 0.0  # some cue text but no known keyword
    hits.sort(reverse=True)
    top = hits[0]
    bonus = 0.0
    for h in hits[1:4]:
        bonus += 0.08 * h
    return clamp(top + bonus)


def extract_evidence_snippets(evidence: Any, max_items: int = 3, max_len: int = 220) -> List[str]:
    """
    evidence may be:
      - list[str]
      - str
      - list[dict] (we extract text-like fields)
    Return small, readable snippet list.
    """
    items: List[str] = []
    if evidence is None:
        return items

    if isinstance(evidence, str):
        items = [evidence]
    elif isinstance(evidence, list):
        for x in evidence:
            if isinstance(x, str):
                items.append(x)
            elif isinstance(x, dict):
                for k in ("text", "snippet", "quote", "evidence", "support"):
                    if k in x and isinstance(x[k], str):
                        items.append(x[k])
                        break

    out: List[str] = []
    for s in items:
        s2 = _WS_RE.sub(" ", (s or "").strip())
        if not s2:
            continue
        if len(s2) > max_len:
            s2 = s2[: max_len - 1].rstrip() + "…"
        out.append(s2)
        if len(out) >= max_items:
            break
    return out


def evidence_score(evidence: Any) -> float:
    """
    Rough 0..1:
      - 0 if no evidence
      - grows with amount of evidence text, capped
    """
    snippets = extract_evidence_snippets(evidence, max_items=6, max_len=400)
    if not snippets:
        return 0.0
    total_chars = sum(len(s) for s in snippets)
    # 0..1 with diminishing returns
    return clamp(math.log1p(total_chars) / math.log1p(800))


def infer_effect_sign(effect: Any) -> Tuple[str, str, Optional[str]]:
    """
    Returns (sign, normalized_effect_label, condition_text?)
    sign in {"+","-","mixed","?"}
    """
    if effect is None:
        return "?", "unknown", None
    if isinstance(effect, dict):
        # try "direction"/"sign"/"effect"
        for k in ("direction", "sign", "effect", "label", "text"):
            if k in effect and isinstance(effect[k], str):
                effect = effect[k]
                break

    if not isinstance(effect, str):
        return "?", "unknown", None

    raw = _WS_RE.sub(" ", effect.strip())
    t = normalize_text(raw)

    pos = any(k in t for k in POS_KWS)
    neg = any(k in t for k in NEG_KWS)
    if pos and neg:
        sign = "mixed"
    elif pos:
        sign = "+"
    elif neg:
        sign = "-"
    else:
        sign = "?"

    # condition extraction (best-effort)
    cond = None
    t2 = raw.lower()
    for m in CONDITION_MARKERS:
        idx = t2.find(m)
        if idx != -1 and idx < 120:
            tail = raw[idx:].strip()
            cond = tail[:120].rstrip()
            break

    # normalized effect label (short)
    label = t if t else "unknown"
    if len(label) > 80:
        label = label[:80].rstrip() + "…"
    return sign, label, cond


def is_nonempty_str(x: Any) -> bool:
    return isinstance(x, str) and x.strip() != ""


# ----------------------------
# Data structures
# ----------------------------

@dataclass
class NodeAgg:
    node_type: str
    canonical: str
    preferred_label: str
    aliases: Set[str] = field(default_factory=set)
    chunk_ids: Set[int] = field(default_factory=set)
    count: int = 0

    def add(self, label: str, chunk_id: Optional[int]) -> None:
        self.count += 1
        if label:
            self.aliases.add(label.strip())
            # prefer a slightly richer label if current preferred is too short
            if len(label.strip()) > len(self.preferred_label.strip()):
                self.preferred_label = label.strip()
        if chunk_id is not None:
            self.chunk_ids.add(int(chunk_id))

    def node_id(self) -> str:
        key = f"{self.node_type}::{self.canonical}"
        return f"N_{self.node_type}_{stable_hash(key, 10)}"


@dataclass
class EdgeAgg:
    src_key: Tuple[str, str]     # (type, canonical)
    tgt_key: Tuple[str, str]
    relation: str
    effect_sign: str             # + / - / mixed / ?
    effect_label: str
    chunk_ids: Set[int] = field(default_factory=set)
    support_count: int = 0
    instance_scores: List[float] = field(default_factory=list)
    instance_conf: List[float] = field(default_factory=list)
    instance_cue: List[float] = field(default_factory=list)
    instance_evidence: List[float] = field(default_factory=list)
    evidence_snippets: List[str] = field(default_factory=list)
    conditions: Set[str] = field(default_factory=set)
    routing_flags: Set[str] = field(default_factory=set)

    def add_instance(
        self,
        chunk_id: Optional[int],
        score: float,
        conf: float,
        cue: float,
        ev: float,
        snippets: List[str],
        condition: Optional[str],
        routing_flags: Iterable[str],
        max_evidence_snippets_keep: int = 12,
    ) -> None:
        self.support_count += 1
        if chunk_id is not None:
            self.chunk_ids.add(int(chunk_id))
        self.instance_scores.append(score)
        self.instance_conf.append(conf)
        self.instance_cue.append(cue)
        self.instance_evidence.append(ev)
        if condition:
            self.conditions.add(condition.strip())
        for f in routing_flags:
            if f:
                self.routing_flags.add(str(f))

        # keep a small set of unique evidence snippets (preserve order)
        for s in snippets:
            if not s:
                continue
            if s not in self.evidence_snippets:
                self.evidence_snippets.append(s)
                if len(self.evidence_snippets) >= max_evidence_snippets_keep:
                    break

    def edge_id(self, src_id: str, tgt_id: str) -> str:
        key = f"{src_id}::{tgt_id}::{self.relation}::{self.effect_sign}::{self.effect_label}"
        return f"E_{stable_hash(key, 12)}"


# ----------------------------
# Validation / routing
# ----------------------------

def derive_routing_flags(record: Dict[str, Any], atom: Dict[str, Any]) -> Set[str]:
    """
    We treat routing as "flags" rather than hard blocks by default.
    """
    flags: Set[str] = set()

    rr = record.get("_routing", {})
    if isinstance(rr, dict):
        # common patterns: status / action / errors / warnings
        for k in ("status", "action", "severity"):
            if k in rr and isinstance(rr[k], str):
                flags.add(f"record_{k}:{rr[k]}")
        if "errors" in rr and isinstance(rr["errors"], list) and rr["errors"]:
            flags.add("record_errors")
        if "warnings" in rr and isinstance(rr["warnings"], list) and rr["warnings"]:
            flags.add("record_warnings")

    ar = atom.get("_routing", {})
    if isinstance(ar, dict):
        for k in ("status", "action", "severity"):
            if k in ar and isinstance(ar[k], str):
                flags.add(f"atom_{k}:{ar[k]}")
        if "errors" in ar and isinstance(ar["errors"], list) and ar["errors"]:
            flags.add("atom_errors")
        if "warnings" in ar and isinstance(ar["warnings"], list) and ar["warnings"]:
            flags.add("atom_warnings")

    return flags


def minimal_atom_ok(atom: Dict[str, Any]) -> Tuple[bool, List[str]]:
    """
    Minimal schema check for usefulness:
      At least two of (intervention, system, readout) must exist.
    """
    problems: List[str] = []
    ent_fields = [
        ("intervention", atom.get("intervention")),
        ("system", atom.get("system")),
        ("readout", atom.get("readout")),
    ]
    present = sum(1 for _, v in ent_fields if is_nonempty_str(v))
    if present < 2:
        problems.append("needs_2_entities")
    # effect optional but helpful
    if atom.get("effect") is None:
        problems.append("missing_effect")
    # confidence optional
    return (present >= 2), problems


# ----------------------------
# Scoring
# ----------------------------

def compute_instance_score(atom: Dict[str, Any]) -> Tuple[float, Dict[str, float], Optional[str], str, str]:
    """
    Returns:
      score (0..1),
      components dict,
      condition_text,
      effect_sign,
      effect_label
    """
    conf = parse_confidence(atom.get("confidence"))
    cue = cue_score(atom.get("strength_cues"))
    evs = evidence_score(atom.get("evidence"))
    effect_sign, effect_label, condition = infer_effect_sign(atom.get("effect"))

    # base score
    base = 0.55 * conf + 0.25 * cue + 0.20 * evs

    # conditional penalty (we keep "conditional strength" by explicitly downweighting)
    cond_factor = 1.0
    if condition is not None:
        cond_factor *= 0.85

    # mixed/unknown direction penalty (harder to interpret)
    dir_factor = 1.0
    if effect_sign in ("mixed", "?"):
        dir_factor *= 0.90

    score = clamp(base * cond_factor * dir_factor)

    components = {
        "confidence": conf,
        "cue": cue,
        "evidence": evs,
        "base": clamp(base),
        "cond_factor": cond_factor,
        "dir_factor": dir_factor,
    }
    return score, components, condition, effect_sign, effect_label


def freq_boost(n: int) -> float:
    # 0.70..1.00 (boost grows with repeated support, capped)
    if n <= 1:
        return 0.70
    return clamp(0.70 + 0.30 * min(1.0, math.log1p(n) / math.log1p(10)))


def aggregate_edge_score(edge: EdgeAgg) -> Tuple[float, Dict[str, float]]:
    """
    Combine instance scores + frequency.
    """
    if not edge.instance_scores:
        return 0.0, {"mean": 0.0, "max": 0.0, "freq_boost": 0.70, "support": 0.0}
    mean_s = float(statistics.mean(edge.instance_scores))
    max_s = float(max(edge.instance_scores))
    fb = freq_boost(edge.support_count)

    # support blend: prefer mean but keep max for occasional very strong instances
    support = 0.70 * mean_s + 0.30 * max_s
    score = clamp(support * fb)
    parts = {
        "mean": mean_s,
        "max": max_s,
        "freq_boost": fb,
        "support": support,
    }
    return score, parts


# ----------------------------
# Graph building
# ----------------------------

def add_node(
    nodes: Dict[Tuple[str, str], NodeAgg],
    node_type: str,
    label: str,
    chunk_id: Optional[int],
) -> Tuple[str, str]:
    label = (label or "").strip()
    canon = normalize_text(label)
    key = (node_type, canon)
    if key not in nodes:
        nodes[key] = NodeAgg(node_type=node_type, canonical=canon, preferred_label=label or canon)
    nodes[key].add(label, chunk_id)
    return key


def add_edge_instance(
    edges: Dict[Tuple[Tuple[str, str], Tuple[str, str], str, str, str], EdgeAgg],
    src_key: Tuple[str, str],
    tgt_key: Tuple[str, str],
    relation: str,
    atom: Dict[str, Any],
    record: Dict[str, Any],
    chunk_id: Optional[int],
    max_evidence_snippets_keep: int,
) -> None:
    inst_score, _components, cond, eff_sign, eff_label = compute_instance_score(atom)
    conf = parse_confidence(atom.get("confidence"))
    cue = cue_score(atom.get("strength_cues"))
    ev = evidence_score(atom.get("evidence"))
    snips = extract_evidence_snippets(atom.get("evidence"), max_items=3, max_len=220)
    flags = derive_routing_flags(record, atom)

    key = (src_key, tgt_key, relation, eff_sign, eff_label)
    if key not in edges:
        edges[key] = EdgeAgg(
            src_key=src_key,
            tgt_key=tgt_key,
            relation=relation,
            effect_sign=eff_sign,
            effect_label=eff_label,
        )
    edges[key].add_instance(
        chunk_id=chunk_id,
        score=inst_score,
        conf=conf,
        cue=cue,
        ev=ev,
        snippets=snips,
        condition=cond,
        routing_flags=flags,
        max_evidence_snippets_keep=max_evidence_snippets_keep,
    )


def build_graph(
    input_path: Path,
    include_low_quality: bool,
    strict: bool,
    max_evidence_snippets_keep: int,
) -> Tuple[Dict[Tuple[str, str], NodeAgg], Dict[Tuple[Any, ...], EdgeAgg], Dict[str, int]]:
    nodes: Dict[Tuple[str, str], NodeAgg] = {}
    edges: Dict[Tuple[Any, ...], EdgeAgg] = {}
    stats = {
        "lines_total": 0,
        "lines_bad_json": 0,
        "records_no_atoms": 0,
        "atoms_total": 0,
        "atoms_used": 0,
        "atoms_skipped_low_quality": 0,
    }

    with input_path.open("r", encoding="utf-8") as f:
        for line in f:
            stats["lines_total"] += 1
            line = line.strip()
            if not line:
                continue
            try:
                record = json.loads(line)
            except Exception:
                stats["lines_bad_json"] += 1
                continue

            if not isinstance(record, dict):
                stats["records_no_atoms"] += 1
                continue

            chunk_id = record.get("chunk_id")
            atoms = record.get("atoms")
            if not isinstance(atoms, list):
                stats["records_no_atoms"] += 1
                continue

            for atom in atoms:
                stats["atoms_total"] += 1
                if not isinstance(atom, dict):
                    stats["atoms_skipped_low_quality"] += 1
                    continue

                ok, problems = minimal_atom_ok(atom)
                if strict and not ok:
                    stats["atoms_skipped_low_quality"] += 1
                    continue
                if (not ok) and (not include_low_quality):
                    stats["atoms_skipped_low_quality"] += 1
                    continue

                # entities (best-effort)
                intervention = atom.get("intervention")
                system = atom.get("system")
                readout = atom.get("readout")

                # Route low-quality atoms but still optionally include them
                # by adding a routing flag in atom._routing (non-destructive).
                if not ok:
                    atom.setdefault("_routing", {})
                    ar = atom["_routing"]
                    if isinstance(ar, dict):
                        ar.setdefault("warnings", [])
                        if isinstance(ar["warnings"], list):
                            ar["warnings"].extend(problems)

                # Build nodes
                intervention_key = None
                system_key = None
                readout_key = None

                if is_nonempty_str(intervention):
                    intervention_key = add_node(nodes, "intervention", str(intervention), chunk_id)
                if is_nonempty_str(system):
                    system_key = add_node(nodes, "system", str(system), chunk_id)
                if is_nonempty_str(readout):
                    readout_key = add_node(nodes, "readout", str(readout), chunk_id)

                # Build edges (only if both ends exist)
                # Relation set is intentionally small and human-auditable.
                if intervention_key and readout_key:
                    add_edge_instance(
                        edges, intervention_key, readout_key,
                        relation="intervention_effect_on_readout",
                        atom=atom, record=record, chunk_id=chunk_id,
                        max_evidence_snippets_keep=max_evidence_snippets_keep,
                    )
                if intervention_key and system_key:
                    add_edge_instance(
                        edges, intervention_key, system_key,
                        relation="intervention_modulates_system",
                        atom=atom, record=record, chunk_id=chunk_id,
                        max_evidence_snippets_keep=max_evidence_snippets_keep,
                    )
                if system_key and readout_key:
                    add_edge_instance(
                        edges, system_key, readout_key,
                        relation="system_associated_readout",
                        atom=atom, record=record, chunk_id=chunk_id,
                        max_evidence_snippets_keep=max_evidence_snippets_keep,
                    )

                stats["atoms_used"] += 1

    return nodes, edges, stats


# ----------------------------
# Writers
# ----------------------------

def ensure_dir(p: Path) -> None:
    p.mkdir(parents=True, exist_ok=True)


def write_nodes(nodes: Dict[Tuple[str, str], NodeAgg], out_path: Path) -> Dict[Tuple[str, str], str]:
    """
    Writes nodes.jsonl and returns node_id lookup.
    """
    node_id_map: Dict[Tuple[str, str], str] = {}
    with out_path.open("w", encoding="utf-8", newline="\n") as f:
        for key, n in sorted(nodes.items(), key=lambda kv: (kv[0][0], kv[1].preferred_label.lower())):
            nid = n.node_id()
            node_id_map[key] = nid
            rec = {
                "node_id": nid,
                "type": n.node_type,
                "label": n.preferred_label,
                "canonical": n.canonical,
                "aliases": sorted(a for a in n.aliases if a.strip()),
                "count": n.count,
                "chunk_ids": sorted(n.chunk_ids),
            }
            f.write(json.dumps(rec, ensure_ascii=False) + "\n")
    return node_id_map


def write_edges(
    edges: Dict[Tuple[Any, ...], EdgeAgg],
    node_id_map: Dict[Tuple[str, str], str],
    nodes: Dict[Tuple[str, str], NodeAgg],
    out_path: Path,
) -> List[Dict[str, Any]]:
    """
    Writes edges.jsonl.
    Returns list of edge records (for summary outputs).
    """
    edge_records: List[Dict[str, Any]] = []
    with out_path.open("w", encoding="utf-8", newline="\n") as f:
        for _, e in sorted(edges.items(), key=lambda kv: (kv[1].relation, kv[1].support_count), reverse=True):
            src_id = node_id_map.get(e.src_key)
            tgt_id = node_id_map.get(e.tgt_key)
            if not src_id or not tgt_id:
                continue

            score, score_parts = aggregate_edge_score(e)

            src_node = nodes.get(e.src_key)
            tgt_node = nodes.get(e.tgt_key)
            src_label = src_node.preferred_label if src_node else e.src_key[1]
            tgt_label = tgt_node.preferred_label if tgt_node else e.tgt_key[1]

            rec = {
                "edge_id": e.edge_id(src_id, tgt_id),
                "src": {"node_id": src_id, "type": e.src_key[0], "label": src_label},
                "tgt": {"node_id": tgt_id, "type": e.tgt_key[0], "label": tgt_label},
                "relation": e.relation,
                "effect": {"sign": e.effect_sign, "label": e.effect_label},
                "conditional_strength_score": score,
                "score_parts": score_parts,  # transparent
                "support_count": e.support_count,
                "chunk_ids": sorted(e.chunk_ids),
                "confidence_mean": float(statistics.mean(e.instance_conf)) if e.instance_conf else None,
                "confidence_max": float(max(e.instance_conf)) if e.instance_conf else None,
                "cue_mean": float(statistics.mean(e.instance_cue)) if e.instance_cue else None,
                "evidence_mean": float(statistics.mean(e.instance_evidence)) if e.instance_evidence else None,
                "conditions": sorted(e.conditions),
                "evidence_snippets": e.evidence_snippets[:12],
                "routing_flags": sorted(e.routing_flags),
            }
            f.write(json.dumps(rec, ensure_ascii=False) + "\n")
            edge_records.append(rec)
    return edge_records


def write_graph_summary_csv(edge_records: List[Dict[str, Any]], out_path: Path) -> None:
    cols = [
        "edge_id",
        "score",
        "support_count",
        "relation",
        "effect_sign",
        "src_label",
        "src_type",
        "tgt_label",
        "tgt_type",
        "confidence_mean",
        "confidence_max",
        "cue_mean",
        "evidence_mean",
        "chunks",
        "conditions",
        "routing_flags",
    ]
    with out_path.open("w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=cols)
        w.writeheader()
        for r in sorted(edge_records, key=lambda x: x.get("conditional_strength_score", 0.0), reverse=True):
            src = r.get("src", {})
            tgt = r.get("tgt", {})
            effect = r.get("effect", {})
            row = {
                "edge_id": r.get("edge_id"),
                "score": f'{float(r.get("conditional_strength_score", 0.0)):.4f}',
                "support_count": r.get("support_count"),
                "relation": r.get("relation"),
                "effect_sign": effect.get("sign"),
                "src_label": src.get("label"),
                "src_type": src.get("type"),
                "tgt_label": tgt.get("label"),
                "tgt_type": tgt.get("type"),
                "confidence_mean": None if r.get("confidence_mean") is None else f'{float(r["confidence_mean"]):.3f}',
                "confidence_max": None if r.get("confidence_max") is None else f'{float(r["confidence_max"]):.3f}',
                "cue_mean": None if r.get("cue_mean") is None else f'{float(r["cue_mean"]):.3f}',
                "evidence_mean": None if r.get("evidence_mean") is None else f'{float(r["evidence_mean"]):.3f}',
                "chunks": ",".join(str(c) for c in (r.get("chunk_ids") or [])[:60]),
                "conditions": " | ".join((r.get("conditions") or [])[:6]),
                "routing_flags": " | ".join((r.get("routing_flags") or [])[:8]),
            }
            w.writerow(row)


def write_top_edges_txt(edge_records: List[Dict[str, Any]], out_path: Path, top_n: int, min_score: float) -> None:
    rows = sorted(edge_records, key=lambda x: x.get("conditional_strength_score", 0.0), reverse=True)
    with out_path.open("w", encoding="utf-8", newline="\n") as f:
        f.write("PATHAI – Top Edges (ranked)\n")
        f.write("=" * 72 + "\n")
        kept = 0
        for r in rows:
            score = float(r.get("conditional_strength_score", 0.0))
            if score < min_score:
                continue
            src = r.get("src", {})
            tgt = r.get("tgt", {})
            effect = r.get("effect", {})
            snips = r.get("evidence_snippets") or []
            conds = r.get("conditions") or []

            f.write(f"[{kept+1:04d}] score={score:.4f}  support={r.get('support_count')}  relation={r.get('relation')}\n")
            f.write(f"       {src.get('label')}  →  {tgt.get('label')}   effect={effect.get('sign')} ({effect.get('label')})\n")
            if conds:
                f.write(f"       conditions: " + " | ".join(conds[:4]) + "\n")
            if snips:
                f.write("       evidence:\n")
                for s in snips[:3]:
                    f.write(f"         - {s}\n")
            flags = r.get("routing_flags") or []
            if flags:
                f.write(f"       flags: " + " | ".join(flags[:6]) + "\n")
            f.write("\n")
            kept += 1
            if kept >= top_n:
                break


# ----------------------------
# Main
# ----------------------------

def main() -> int:
    ap = argparse.ArgumentParser(description="PATHAI: build graph outputs from atoms.jsonl")
    ap.add_argument("--input", required=True, help="Path to atoms.jsonl")
    ap.add_argument("--outdir", required=True, help="Output directory")
    ap.add_argument("--top_n", type=int, default=200, help="Top edges to write in top_edges.txt")
    ap.add_argument("--min_score", type=float, default=0.15, help="Minimum score to include in top_edges.txt")
    ap.add_argument(
        "--include_low_quality",
        action="store_true",
        help="Include atoms that fail minimal schema (will be flagged). Default: skip them.",
    )
    ap.add_argument(
        "--strict",
        action="store_true",
        help="Strict mode: drop atoms that fail minimal schema even if include_low_quality is set.",
    )
    ap.add_argument(
        "--max_evidence_snips",
        type=int,
        default=12,
        help="Max evidence snippets to retain per edge in edges.jsonl",
    )
    args = ap.parse_args()

    input_path = Path(args.input)
    outdir = Path(args.outdir)
    ensure_dir(outdir)

    if not input_path.exists():
        raise FileNotFoundError(f"Input not found: {input_path}")

    nodes, edges, stats = build_graph(
        input_path=input_path,
        include_low_quality=bool(args.include_low_quality),
        strict=bool(args.strict),
        max_evidence_snippets_keep=int(args.max_evidence_snips),
    )

    nodes_path = outdir / "nodes.jsonl"
    edges_path = outdir / "edges.jsonl"
    summary_path = outdir / "graph_summary.csv"
    top_edges_path = outdir / "top_edges.txt"

    node_id_map = write_nodes(nodes, nodes_path)
    edge_records = write_edges(edges, node_id_map, nodes, edges_path)
    write_graph_summary_csv(edge_records, summary_path)
    write_top_edges_txt(edge_records, top_edges_path, top_n=int(args.top_n), min_score=float(args.min_score))

    # minimal console output (human-friendly)
    print("PATHAI graph build complete.")
    print(f"Input:  {input_path}")
    print(f"Out:    {outdir}")
    print(f"Nodes:  {len(nodes)}   ({nodes_path.name})")
    print(f"Edges:  {len(edge_records)}   ({edges_path.name})")
    print(f"CSV:    {summary_path.name}")
    print(f"Top:    {top_edges_path.name}  (top_n={args.top_n}, min_score={args.min_score})")
    print("Stats:")
    for k in ("lines_total", "lines_bad_json", "records_no_atoms", "atoms_total", "atoms_used", "atoms_skipped_low_quality"):
        print(f"  - {k}: {stats.get(k)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
```

TAG: **PATHAI-0041 (notes)**

* **Edge types** are intentionally limited to keep things auditable:
    1. `intervention_effect_on_readout`
    2. `intervention_modulates_system`
    3. `system_associated_readout`
* **`conditional_strength_score`** is a transparent heuristic:
    * base = `0.55*confidence + 0.25*strength_cue + 0.20*evidence`
    * downweights edges that look explicitly **conditional** (“when/under/in the presence of…”) and edges with **unknown/mixed direction**
    * boosts edges with repeated support (frequency boost)
* If you want **more strict schema enforcement**, run with `--strict` (drops atoms that don’t have at least 2 of {intervention, system, readout}).

TAG: **PATHAI-0042 (next step roadmap)**  
Once you run this and sanity-check `top_edges.txt`, the next script is usually: **edge consolidation + ontology-ish normalization** (merge synonyms, collapse “PI3K/PI3K pathway/PI3K signaling”, etc.), then **graph export** (e.g., Cytoscape CSV/TSV, GraphML).

* * *

**You:**

Let's not go to the graph building yet:  This is the last part of part 1 that we worked on: **TAG: PATHAI-0048**

What you just got for chunk 3 is actually a *useful diagnostic*.

## What happened (in plain biologist terms)

* The model **couldn’t find any real “biology outcome”** (proliferation, apoptosis, signaling change, etc.) in that chunk.
* Instead, it produced “atoms” that are basically **“we applied siRNA to mTOR/RAPTOR/RICTOR”** and then *implicitly assumed* that means target levels/function went down.

That’s why you also got this warning:

> “No explicit functional readouts… only evidence of successful knockdown of targets.”

And note: bridge.used: false because **your current bridging script only tries bridging when atoms==0**. Since the model returned 3 atoms (even though they’re weak/assumed), the bridging condition didn’t fire.

So we should fix two things:

1. **Don’t allow “assumed knockdown” atoms** unless the text explicitly says knockdown succeeded (e.g., “mTOR protein was reduced by…”, “confirmed knockdown by western/qPCR”).
2. **Trigger bridging not only when atoms=0**, but also when atoms are **“setup/target-engagement only”** (i.e., not true functional outcomes).

Below is a full updated script that implements both.

---

# Full improved bridging script (v2)

**TAG: PATHAI-0049**
Save as **make_atoms_bridged_v2.py** and run it. It will overwrite atoms.jsonl.

Key upgrades:

* **Post-filter**: drops atoms whose supporting quote doesn’t contain an explicit effect verb (reduce/decrease/inhibit/no effect/rescue/restore/etc.). This prevents “assumed knockdown.”
* **Bridging trigger**: runs bridging if:

  * atoms==0 and mentions>0 **OR**
  * atoms exist but look like setup-only (all readouts are “expression/function/knockdown” and/or warnings indicate no functional readouts)

python
import os
import json
import re
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple
from openai import OpenAI

# ============================================================
# CONFIG
# ============================================================
INFILE = Path("mentions.jsonl")
OUTFILE = Path("atoms.jsonl")

MODEL_FAST = "gpt-4o-mini"
MODEL_STRONG = "gpt-4.1"

MAX_ATOMS_PER_CHUNK = 30

TRY_BRIDGE_FORWARD = True
TRY_BRIDGE_BACKWARD = True

# ============================================================
# OPENAI CLIENT
# ============================================================
def _get_api_key() -> str:
    key = os.getenv("OPENAI_API_KEY")
    if not key:
        raise RuntimeError(
            "OPENAI_API_KEY is not set.\n"
            "Miniforge Prompt (temporary):  set OPENAI_API_KEY=YOUR_KEY\n"
            "Persistent (Windows):         setx OPENAI_API_KEY \"YOUR_KEY\"  (then reopen prompt)"
        )
    return key

client = OpenAI(api_key=_get_api_key())

# ============================================================
# STRICT JSON SCHEMA FOR ATOMS (model output)
# ============================================================
ATOM_SCHEMA_WRAPPER: Dict[str, Any] = {
    "name": "MechanisticAtoms",
    "schema": {
        "type": "object",
        "additionalProperties": False,
        "required": ["atoms", "warnings"],
        "properties": {
            "atoms": {
                "type": "array",
                "items": {
                    "type": "object",
                    "additionalProperties": False,
                    "required": [
                        "intervention",
                        "system",
                        "readout",
                        "effect",
                        "strength_cues",
                        "evidence",
                        "confidence",
                    ],
                    "properties": {
                        "intervention": {
                            "type": "object",
                            "additionalProperties": False,
                            "required": ["category", "raw_text", "target", "modality"],
                            "properties": {
                                "category": {
                                    "type": "string",
                                    "enum": [
                                        "GENETIC_KO",
                                        "CRISPR_KO",
                                        "CRISPRi",
                                        "CRISPRa",
                                        "KNOCKDOWN_RNAI",
                                        "SPLICING_MODULATION",
                                        "OVEREXPRESSION",
                                        "RESCUE_ADD_BACK",
                                        "DOMINANT_NEGATIVE",
                                        "MUTANT_VARIANT",
                                        "CHEMICAL_INHIBITOR",
                                        "CHEMICAL_ACTIVATOR",
                                        "CHEMICAL_DEGRADER",
                                        "STIMULUS_TREATMENT",
                                        "NEUTRALIZING_ANTIBODY",
                                        "UNKNOWN",
                                    ],
                                },
                                "raw_text": {"type": "string", "minLength": 1},
                                "target": {
                                    "anyOf": [
                                        {
                                            "type": "object",
                                            "additionalProperties": False,
                                            "required": ["name", "entity_type"],
                                            "properties": {
                                                "name": {"type": "string"},
                                                "entity_type": {
                                                    "type": "string",
                                                    "enum": [
                                                        "gene",
                                                        "protein",
                                                        "chemical",
                                                        "stimulus",
                                                        "antibody",
                                                        "unknown",
                                                    ],
                                                },
                                            },
                                        },
                                        {"type": "null"},
                                    ]
                                },
                                "modality": {
                                    "type": "string",
                                    "enum": [
                                        "LOF",
                                        "GOF",
                                        "INHIBITION",
                                        "ACTIVATION",
                                        "DEGRADATION",
                                        "RESCUE",
                                        "UNKNOWN",
                                    ],
                                },
                            },
                        },
                        "system": {
                            "type": "object",
                            "additionalProperties": False,
                            "required": [
                                "species",
                                "cell_type",
                                "cell_lines",
                                "genotype_context",
                                "disease_context",
                            ],
                            "properties": {
                                "species": {"type": ["string", "null"]},
                                "cell_type": {"type": ["string", "null"]},
                                "cell_lines": {"type": "array", "items": {"type": "string"}},
                                "genotype_context": {"type": ["string", "null"]},
                                "disease_context": {"type": ["string", "null"]},
                            },
                        },
                        "readout": {
                            "type": "object",
                            "additionalProperties": False,
                            "required": ["name", "assay", "figure_refs"],
                            "properties": {
                                "name": {"type": "string"},
                                "assay": {"type": ["string", "null"]},
                                "figure_refs": {"type": "array", "items": {"type": "string"}},
                            },
                        },
                        "effect": {
                            "type": "object",
                            "additionalProperties": False,
                            "required": ["direction", "timepoint", "magnitude", "comparison"],
                            "properties": {
                                "direction": {
                                    "type": "string",
                                    "enum": ["increase", "decrease", "no_change", "mixed", "unknown"],
                                },
                                "timepoint": {"type": ["string", "null"]},
                                "magnitude": {"type": ["string", "null"]},
                                "comparison": {"type": ["string", "null"]},
                            },
                        },
                        "strength_cues": {
                            "type": "object",
                            "additionalProperties": False,
                            "required": ["has_rescue", "has_control", "has_multiple_lines", "other"],
                            "properties": {
                                "has_rescue": {"type": "boolean"},
                                "has_control": {"type": "boolean"},
                                "has_multiple_lines": {"type": "boolean"},
                                "other": {"type": "array", "items": {"type": "string"}},
                            },
                        },
                        "evidence": {
                            "type": "object",
                            "additionalProperties": False,
                            "required": ["supporting_quote", "notes"],
                            "properties": {
                                "supporting_quote": {"type": "string"},
                                "notes": {"type": ["string", "null"]},
                            },
                        },
                        "confidence": {"type": "number", "minimum": 0, "maximum": 1},
                    },
                },
            },
            "warnings": {"type": "array", "items": {"type": "string"}},
        },
    },
}

# ============================================================
# HINTS (lightweight)
# ============================================================
FIGREF_REGEX = re.compile(r"\b(Fig\.?\s*\d+[A-Za-z]?)\b", re.IGNORECASE)
SPECIES_REGEX = re.compile(r"\b(human|mouse|murine|rat)\b", re.IGNORECASE)

def _uniq_preserve(seq: List[str]) -> List[str]:
    seen = set()
    out = []
    for x in seq:
        k = x.lower()
        if k not in seen:
            seen.add(k)
            out.append(x)
    return out

def hint_figrefs(text: str) -> List[str]:
    return _uniq_preserve([m.group(1) for m in FIGREF_REGEX.finditer(text)])

def hint_species(text: str) -> Optional[str]:
    m = SPECIES_REGEX.search(text)
    if not m:
        return None
    s = m.group(1).lower()
    return "mouse" if s == "murine" else s

def compact_mentions(mentions: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    out = []
    for i, m in enumerate(mentions, start=1):
        out.append({
            "i": i,
            "category": m.get("category"),
            "raw_text": m.get("raw_text"),
            "target_guess": m.get("target_guess"),
            "method_cues": m.get("method_cues", []),
        })
    return out

# ============================================================
# PROMPT
# ============================================================
SYSTEM_INSTRUCTIONS = (
    "Extract 'mechanistic atoms' from biomedical text.\n\n"
    "Definition: an atom MUST include an explicit effect on a readout.\n"
    "Format: [INTERVENTION] causes [EFFECT] in [READOUT] in a [SYSTEM].\n\n"
    "Hard rules:\n"
    "1) Do NOT invent facts.\n"
    "2) Do NOT assume knockdown succeeded unless the text explicitly says reduction/knockdown/confirmed.\n"
    "3) If the text only describes delivering siRNA/plasmid/drug but gives no stated change in any readout, output no atoms and add a warning.\n"
    "4) You may extract multiple readouts per intervention if they are explicitly stated (e.g., proliferation, pAKT, total AKT).\n"
    "5) Rescue/add-back atoms must state what readout is rescued (e.g., proliferation restored).\n"
    f"6) Keep at most {MAX_ATOMS_PER_CHUNK} atoms.\n"
)

# ============================================================
# MODEL CALL + ROUTING
# ============================================================
def call_model(model: str, chunk_text: str, mentions: List[Dict[str, Any]]) -> Dict[str, Any]:
    payload = {
        "chunk_text": chunk_text,
        "mentions": compact_mentions(mentions),
        "hints": {
            "fig_refs": hint_figrefs(chunk_text),
            "species": hint_species(chunk_text),
        }
    }
    resp = client.responses.create(
        model=model,
        input=[
            {"role": "system", "content": SYSTEM_INSTRUCTIONS},
            {"role": "user", "content": json.dumps(payload, ensure_ascii=False)},
        ],
        text={
            "format": {
                "type": "json_schema",
                "name": ATOM_SCHEMA_WRAPPER["name"],
                "strict": True,
                "schema": ATOM_SCHEMA_WRAPPER["schema"],
            }
        },
    )
    return json.loads(resp.output_text)

def should_escalate(chunk_text: str, mentions: List[Dict[str, Any]], atoms: List[Dict[str, Any]]) -> bool:
    if len(mentions) > 0 and len(atoms) == 0:
        return True
    if len(atoms) > 0:
        avg_conf = sum(a.get("confidence", 0) for a in atoms) / len(atoms)
        if avg_conf < 0.55:
            return True
    return False

def extract_atoms_with_routing(chunk_text: str, mentions: List[Dict[str, Any]]) -> Dict[str, Any]:
    routing = {"first_model": MODEL_FAST, "escalated": False, "final_model": MODEL_FAST, "reason": None}
    out_fast = call_model(MODEL_FAST, chunk_text, mentions)
    atoms_fast = out_fast.get("atoms", [])

    if should_escalate(chunk_text, mentions, atoms_fast):
        routing["escalated"] = True
        routing["final_model"] = MODEL_STRONG
        routing["reason"] = {"type": "low_confidence_or_empty", "details": "heuristics triggered"}
        out_strong = call_model(MODEL_STRONG, chunk_text, mentions)
        out_strong["_routing"] = routing
        return out_strong

    out_fast["_routing"] = routing
    return out_fast

# ============================================================
# POST-FILTERING: keep only atoms with explicit effect language
# ============================================================
EFFECT_CUE = re.compile(
    r"\b("
    r"inhibit|inhibited|inhibition|suppress|suppressed|suppressing|"
    r"reduce|reduced|reduces|reduction|decrease|decreased|decreases|"
    r"increase|increased|increases|elevate|elevated|"
    r"no effect|did not affect|had no effect|"
    r"rescue|rescued|restored|restore|"
    r"complete inhibition|abolish|abolished"
    r")\b",
    re.IGNORECASE,
)

SETUP_ONLY_READOUT = re.compile(r"\b(expression|function|knockdown|silencing)\b", re.IGNORECASE)

def looks_like_setup_only(atoms: List[Dict[str, Any]], warnings: List[str]) -> bool:
    if not atoms:
        return True
    # If warnings already say "no functional readouts", treat as setup-only
    wtxt = " ".join(warnings).lower()
    if "no explicit functional readouts" in wtxt or "only describes" in wtxt:
        return True
    # If all readouts are generic expression/function AND no effect cue in supporting quotes
    for a in atoms:
        ro = (a.get("readout", {}) or {}).get("name", "")
        sq = (a.get("evidence", {}) or {}).get("supporting_quote", "")
        if not SETUP_ONLY_READOUT.search(ro) and EFFECT_CUE.search(sq):
            return False
    return True

def post_filter_atoms(atoms: List[Dict[str, Any]]) -> Tuple[List[Dict[str, Any]], int]:
    kept = []
    dropped = 0
    for a in atoms:
        sq = (a.get("evidence", {}) or {}).get("supporting_quote", "")
        # require explicit cue in quote
        if EFFECT_CUE.search(sq):
            kept.append(a)
        else:
            dropped += 1
    return kept, dropped

# ============================================================
# BRIDGING
# ============================================================
def bridge_text(a_text: str, b_text: str) -> str:
    return a_text.rstrip() + "\n\n" + b_text.lstrip()

def bridge_mentions(a_mentions: List[Dict[str, Any]], b_mentions: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    return list(a_mentions) + list(b_mentions)

def choose_best_bridged(candidates: List[Tuple[str, Dict[str, Any], List[int]]]) -> Optional[Tuple[str, Dict[str, Any], List[int]]]:
    """
    candidates: (mode, outdict, source_ids)
    Choose best by:
      - max atoms count
      - tie-breaker: higher average confidence
    """
    best = None
    for mode, outd, src in candidates:
        atoms = outd.get("atoms", [])
        if best is None:
            best = (mode, outd, src)
            continue
        best_atoms = best[1].get("atoms", [])
        if len(atoms) > len(best_atoms):
            best = (mode, outd, src)
        elif len(atoms) == len(best_atoms) and len(atoms) > 0:
            avg = sum(a.get("confidence", 0) for a in atoms) / len(atoms)
            bavg = sum(a.get("confidence", 0) for a in best_atoms) / len(best_atoms)
            if avg > bavg:
                best = (mode, outd, src)
    return best

# ============================================================
# DRIVER
# ============================================================
def main():
    if not INFILE.exists():
        raise FileNotFoundError(f"Cannot find {INFILE.resolve()}")

    records: List[Dict[str, Any]] = []
    for ln in INFILE.read_text(encoding="utf-8", errors="ignore").splitlines():
        records.append(json.loads(ln))

    total_atoms = 0
    escalations = 0
    bridges_used = 0
    dropped_total = 0

    with OUTFILE.open("w", encoding="utf-8") as fout:
        for idx, rec in enumerate(records):
            chunk_id = rec.get("chunk_id")

            if "error" in rec:
                fout.write(json.dumps({
                    "chunk_id": chunk_id,
                    "atoms": [],
                    "warnings": ["Skipped due to upstream error."],
                    "bridge": {"used": False, "mode": None, "source_chunk_ids": [chunk_id]},
                    "_routing": {"skipped": True},
                    "_post": {"dropped_atoms": 0}
                }, ensure_ascii=False) + "\n")
                continue

            chunk_text = rec.get("chunk_text", "")
            mentions = rec.get("mentions", [])

            out = extract_atoms_with_routing(chunk_text, mentions)
            atoms = out.get("atoms", [])
            warnings = out.get("warnings", [])
            routing = out.get("_routing", {})

            # post-filter atoms (drop ones without explicit effect cues)
            atoms, dropped = post_filter_atoms(atoms)
            dropped_total += dropped

            used_bridge = False
            bridge_mode = None
            source_chunk_ids = [chunk_id]

            # Decide whether to bridge:
            # - atoms are empty but mentions exist
            # - OR atoms look setup-only (no functional outcomes)
            if len(mentions) > 0 and (len(atoms) == 0 or looks_like_setup_only(atoms, warnings)):
                candidates: List[Tuple[str, Dict[str, Any], List[int]]] = []

                if TRY_BRIDGE_FORWARD and idx + 1 < len(records):
                    nxt = records[idx + 1]
                    if "error" not in nxt:
                        t = bridge_text(chunk_text, nxt.get("chunk_text", ""))
                        m = bridge_mentions(mentions, nxt.get("mentions", []))
                        bout = extract_atoms_with_routing(t, m)
                        batoms = bout.get("atoms", [])
                        bwarn = bout.get("warnings", [])
                        batoms, bdropped = post_filter_atoms(batoms)
                        bout["atoms"] = batoms
                        bout["warnings"] = bwarn
                        bout["_post"] = {"dropped_atoms": bdropped}
                        candidates.append(("forward", bout, [chunk_id, nxt.get("chunk_id")]))

                if TRY_BRIDGE_BACKWARD and idx - 1 >= 0:
                    prv = records[idx - 1]
                    if "error" not in prv:
                        t = bridge_text(prv.get("chunk_text", ""), chunk_text)
                        m = bridge_mentions(prv.get("mentions", []), mentions)
                        bout = extract_atoms_with_routing(t, m)
                        batoms = bout.get("atoms", [])
                        bwarn = bout.get("warnings", [])
                        batoms, bdropped = post_filter_atoms(batoms)
                        bout["atoms"] = batoms
                        bout["warnings"] = bwarn
                        bout["_post"] = {"dropped_atoms": bdropped}
                        candidates.append(("backward", bout, [prv.get("chunk_id"), chunk_id]))

                best = choose_best_bridged(candidates)
                if best is not None and len(best[1].get("atoms", [])) > 0:
                    used_bridge = True
                    bridge_mode = best[0]
                    out = best[1]
                    atoms = out.get("atoms", [])
                    warnings = out.get("warnings", [])
                    routing = out.get("_routing", routing)
                    source_chunk_ids = best[2]
                    bridges_used += 1

            if routing.get("escalated"):
                escalations += 1

            total_atoms += len(atoms)

            record_out = {
                "chunk_id": chunk_id,
                "atoms": atoms,
                "warnings": warnings,
                "bridge": {"used": used_bridge, "mode": bridge_mode, "source_chunk_ids": source_chunk_ids},
                "_routing": routing,
                "_post": {"dropped_atoms": dropped},
            }
            fout.write(json.dumps(record_out, ensure_ascii=False) + "\n")

            print(f"chunk {chunk_id}: atoms={len(atoms)} escalated={routing.get('escalated', False)} bridged={used_bridge} dropped={dropped}")

    print(f"Done. total_atoms={total_atoms}, escalations={escalations}, bridges_used={bridges_used}, dropped_total={dropped_total}")

if __name__ == "__main__":
    main()

---

## How to run

bat
conda activate pathai
cd "C:\Users\Prem Subramaniam\Documents\Pathway AI"
python make_atoms_bridged_v2.py

---

## What you should expect for chunk 3 after this change

Because chunk 3 appears to be mostly **“we delivered siRNA”** without explicit outcome language:

* Those “assumed knockdown” atoms should get **dropped** (since the quotes don’t contain effect cues).
* Then bridging may kick in (if chunk 2 or 4 contains “and this caused…” language).
* If neighbors are unrelated (random sampling), bridging may still not help — and that’s OK. It will simply keep atoms=[] and warn.

---

### Paste back (one line)

After you run v2, paste the atoms.jsonl line for **chunk_id 3** again.
I’m specifically checking whether it now either:

* successfully bridges and finds true functional atoms, **or**
* correctly stays empty (no invention) with a clear warning.    Explain to me what we did here and what was acheived.

* * *

**ChatGPT:**

We were **debugging a failure mode** in the atoms extractor, and then hardening the pipeline so it behaves like a careful biologist instead of “helpfully guessing.”

### What happened in chunk 3 (the problem)

Chunk 3 didn’t really contain **functional biology outcomes** (e.g., proliferation, apoptosis, pAKT, migration, reporter activity, etc.). It mostly described **experimental setup**: delivering siRNAs to mTOR/RAPTOR/RICTOR.

The model still returned “atoms” anyway—because LLMs often **implicitly assume**:

> “siRNA against X → X goes down → that is an effect”

But that’s not a valid mechanistic atom unless the text _explicitly says_ knockdown worked (qPCR/WB/“reduced by X%”) **and** ideally links that to a meaningful readout.

Also, your bridging logic didn’t run because it was gated on **atoms == 0**. Since the model output _some_ atoms (even though weak/assumed), bridging never fired.

### What we changed (what TAG: PATHAI-0049 implements)

We fixed this in **two ways**:

## 1) Block “assumed knockdown” atoms (post-filter)

After the model outputs atoms, we apply a **post-filter** that checks the atom’s `evidence.supporting_quote` for **explicit effect language** (verbs/phrases like):

* reduce / decreased / inhibited / no effect / rescued / restored / abolished / etc.

If the supporting quote **doesn’t contain explicit effect cues**, the atom is dropped.

**Outcome:**  
This prevents the pipeline from turning _setup language_ into _claimed results_. It forces atoms to be grounded in what the text actually states.

## 2) Make bridging trigger on “setup-only” atoms, not just atoms==0

We added `looks_like_setup_only()` so bridging runs not only when:

* `atoms == 0 and mentions > 0`

…but also when:

* the model produced atoms, **yet they look like setup-only** (readouts like “expression/knockdown/function” or warnings like “no explicit functional readouts”).

**Outcome:**  
Now the pipeline tries to “borrow context” from adjacent chunks when the current chunk is likely incomplete by itself—even if the model produced junky atoms.

### What bridging is doing (in plain terms)

Bridging tries:

* **forward:** chunk N + chunk N+1
* **backward:** chunk N-1 + chunk N

Then it re-extracts atoms from the combined text and chooses the “best” candidate (more atoms, higher avg confidence).

This is meant to catch cases where:

* chunk N describes the intervention setup
* chunk N+1 describes the resulting phenotype/readout

### What was achieved overall

After these changes, the pipeline becomes **more trustworthy and more diagnostic**:

1. **Less hallucination / assumption**  
    “siRNA was used” no longer becomes “mTOR was knocked down” unless explicitly stated.
2. **Better recovery from chunk boundaries**  
    If outcomes are split across adjacent chunks, bridging can recover them.
3. **Clear audit trail**  
    Each output line gets:
    * `bridge.used`, `bridge.mode`, `source_chunk_ids`
    * `_post.dropped_atoms` showing how many atoms were filtered out
    * warnings explaining _why_ atoms are empty (instead of silently failing)
4. **Correct behavior in the “no real outcome present” case**  
    If the neighbors don’t contain functional readouts either (or sampling is random), the correct result is:
    * `atoms: []`
    * a warning like “No explicit functional readouts…”

That’s not a failure—that’s the system behaving _honestly_.

### What you’d expect for chunk 3 now

Most likely:

* the weak “assumed knockdown” atoms get **dropped**
* bridging may or may not find real functional readouts from chunk 2 or 4
* if not found, it stays empty with clear warnings

If you paste the **single atoms.jsonl line for chunk_id 3** after running v2, we can verify whether:

* it bridged successfully and produced true outcome atoms, or
* it correctly stayed empty (which is often the right answer).

* * *

**You:**

So we eneded with # Full improved bridging script (v2)

**TAG: PATHAI-0049**
Save as **make_atoms_bridged_v2.py** and run it. It will overwrite atoms.jsonl.  Is this sufficient now togo to the graph stage or do we need to align the code more.

* * *

**ChatGPT:**

TAG: **PATHAI-0049** gets you **much closer** to being graph-ready, because it fixes the two biggest “graph poisoners”:

1. **Assumed knockdown** → filtered out unless the quote has explicit effect language
2. **Bridging only when atoms==0** → now bridges when atoms are **setup-only**

That said, whether you’re _actually_ ready for the graph stage depends on **alignment + QA**, not just having bridging.

## What’s still worth aligning before graph

### 1) Schema alignment (most important)

Your atoms schema is **nested objects** (`intervention.target.name`, `readout.name`, `effect.direction`, etc.).  
So your graph builder must read those nested fields consistently (not assume flat strings). If your planned graph code was written for a “flat atom” format, you’ll want to adjust it first.

### 2) Quality gate before graph

Even with v2, you should sanity-check:

* How many chunks end up `atoms=[]` (fine if truly no outcomes, but should not be “most” chunks)
* How many atoms have `effect.direction == "unknown"` (too many makes edges weak)
* How many atoms are still “setup-ish” (e.g., readout = expression/knockdown only)
* How often bridging is being used (and whether it’s producing meaningful functional atoms)

### 3) Traceability / dedup

For graph stage, you’ll want to be able to trace an edge back to:

* `chunk_id`
* `bridge.source_chunk_ids`
* `evidence.supporting_quote`  
    That’s already present in your output (good). Dedup can be handled later, but it’s useful to quantify duplicates.

## Practical “go/no-go” test

Before graph: run an **audit**. If you see:

* a reasonable fraction of atoms with **non-unknown direction**
* a reasonable fraction of **non-setup readouts**
* evidence quotes that look real  
    …then you’re good to proceed.

Below is a small audit script (no dependencies) that will tell you exactly that.

* * *

TAG: **PATHAI-0050** — `audit_atoms_v2.py` (read atoms.jsonl → QA stats + CSVs + samples)

Save as `audit_atoms_v2.py` in your project folder and run it after `make_atoms_bridged_v2.py`.

```Python
#!/usr/bin/env python3
import json
import csv
import re
import random
import statistics
from pathlib import Path
from typing import Any, Dict, List, Tuple, Optional

INFILE = Path("atoms.jsonl")
OUTDIR = Path("atoms_audit")

# Mirrors v2 logic (keep consistent)
EFFECT_CUE = re.compile(
    r"\b("
    r"inhibit|inhibited|inhibition|suppress|suppressed|suppressing|"
    r"reduce|reduced|reduces|reduction|decrease|decreased|decreases|"
    r"increase|increased|increases|elevate|elevated|"
    r"no effect|did not affect|had no effect|"
    r"rescue|rescued|restored|restore|"
    r"complete inhibition|abolish|abolished"
    r")\b",
    re.IGNORECASE,
)
SETUP_ONLY_READOUT = re.compile(r"\b(expression|function|knockdown|silencing)\b", re.IGNORECASE)

RANDOM_SEED = 7
SAMPLE_N = 25  # per category


def ensure_dir(p: Path) -> None:
    p.mkdir(parents=True, exist_ok=True)


def get(d: Dict[str, Any], *keys: str, default=None):
    cur: Any = d
    for k in keys:
        if not isinstance(cur, dict) or k not in cur:
            return default
        cur = cur[k]
    return cur


def shorten(s: str, n: int = 120) -> str:
    s = (s or "").strip().replace("\n", " ")
    s = re.sub(r"\s+", " ", s)
    if len(s) <= n:
        return s
    return s[: n - 1].rstrip() + "…"


def classify_atom(atom: Dict[str, Any]) -> Tuple[bool, bool]:
    """
    Returns (is_setup_only, has_explicit_effect_cue_in_quote)
    """
    ro_name = get(atom, "readout", "name", default="") or ""
    quote = get(atom, "evidence", "supporting_quote", default="") or ""
    is_setup = bool(SETUP_ONLY_READOUT.search(ro_name))
    has_cue = bool(EFFECT_CUE.search(quote))
    return is_setup, has_cue


def main() -> int:
    if not INFILE.exists():
        raise FileNotFoundError(f"Cannot find {INFILE.resolve()}")

    ensure_dir(OUTDIR)

    records: List[Dict[str, Any]] = []
    bad_json = 0

    for ln in INFILE.read_text(encoding="utf-8", errors="ignore").splitlines():
        ln = ln.strip()
        if not ln:
            continue
        try:
            records.append(json.loads(ln))
        except Exception:
            bad_json += 1

    per_chunk_rows: List[Dict[str, Any]] = []
    target_counts: Dict[str, int] = {}
    readout_counts: Dict[str, int] = {}
    direction_counts: Dict[str, int] = {}

    total_chunks = 0
    chunks_with_atoms = 0
    chunks_bridged = 0

    total_atoms = 0
    setup_atoms = 0
    functional_atoms = 0
    unknown_dir_atoms = 0
    atoms_missing_effect_cue = 0

    confidences_all: List[float] = []
    confidences_functional: List[float] = []
    confidences_setup: List[float] = []

    # sample collections
    functional_samples: List[Dict[str, Any]] = []
    setup_samples: List[Dict[str, Any]] = []
    unknown_dir_samples: List[Dict[str, Any]] = []

    for rec in records:
        total_chunks += 1
        chunk_id = rec.get("chunk_id")
        atoms = rec.get("atoms", []) if isinstance(rec.get("atoms"), list) else []
        warnings = rec.get("warnings", []) if isinstance(rec.get("warnings"), list) else []
        bridge = rec.get("bridge", {}) if isinstance(rec.get("bridge"), dict) else {}
        used_bridge = bool(bridge.get("used"))
        dropped_atoms = get(rec, "_post", "dropped_atoms", default=0)

        if used_bridge:
            chunks_bridged += 1
        if atoms:
            chunks_with_atoms += 1

        chunk_setup = 0
        chunk_functional = 0
        chunk_unknown = 0
        chunk_conf: List[float] = []
        chunk_missing_cue = 0

        for a in atoms:
            if not isinstance(a, dict):
                continue
            total_atoms += 1

            # intervention target
            tgt = get(a, "intervention", "target", "name", default=None)
            if isinstance(tgt, str) and tgt.strip():
                target_counts[tgt.strip()] = target_counts.get(tgt.strip(), 0) + 1

            # readout
            ro = get(a, "readout", "name", default=None)
            if isinstance(ro, str) and ro.strip():
                readout_counts[ro.strip()] = readout_counts.get(ro.strip(), 0) + 1

            # direction
            direction = get(a, "effect", "direction", default="unknown")
            if isinstance(direction, str) and direction.strip():
                direction_counts[direction] = direction_counts.get(direction, 0) + 1

            conf = a.get("confidence", None)
            if isinstance(conf, (int, float)):
                conf = float(conf)
                confidences_all.append(conf)
                chunk_conf.append(conf)

            is_setup, has_cue = classify_atom(a)

            if not has_cue:
                atoms_missing_effect_cue += 1
                chunk_missing_cue += 1

            if direction == "unknown":
                unknown_dir_atoms += 1
                chunk_unknown += 1
                if len(unknown_dir_samples) < SAMPLE_N * 2:
                    unknown_dir_samples.append({
                        "chunk_id": chunk_id,
                        "target": tgt,
                        "readout": ro,
                        "direction": direction,
                        "confidence": conf,
                        "quote": shorten(get(a, "evidence", "supporting_quote", default="")),
                    })

            if is_setup:
                setup_atoms += 1
                chunk_setup += 1
                if conf is not None:
                    confidences_setup.append(conf)
                if len(setup_samples) < SAMPLE_N * 2:
                    setup_samples.append({
                        "chunk_id": chunk_id,
                        "target": tgt,
                        "readout": ro,
                        "direction": direction,
                        "confidence": conf,
                        "quote": shorten(get(a, "evidence", "supporting_quote", default="")),
                    })
            else:
                functional_atoms += 1
                chunk_functional += 1
                if conf is not None:
                    confidences_functional.append(conf)
                if len(functional_samples) < SAMPLE_N * 2:
                    functional_samples.append({
                        "chunk_id": chunk_id,
                        "target": tgt,
                        "readout": ro,
                        "direction": direction,
                        "confidence": conf,
                        "quote": shorten(get(a, "evidence", "supporting_quote", default="")),
                    })

        avg_conf = statistics.mean(chunk_conf) if chunk_conf else None
        warn_short = shorten(" | ".join(warnings), 160)

        per_chunk_rows.append({
            "chunk_id": chunk_id,
            "atoms": len(atoms),
            "functional_atoms": chunk_functional,
            "setup_atoms": chunk_setup,
            "unknown_direction_atoms": chunk_unknown,
            "atoms_missing_effect_cue": chunk_missing_cue,
            "avg_confidence": None if avg_conf is None else f"{avg_conf:.3f}",
            "bridged": "Y" if used_bridge else "N",
            "dropped_atoms": dropped_atoms,
            "warnings": warn_short,
        })

    # Write per-chunk CSV
    with (OUTDIR / "atoms_audit_by_chunk.csv").open("w", encoding="utf-8", newline="") as f:
        cols = [
            "chunk_id", "atoms", "functional_atoms", "setup_atoms",
            "unknown_direction_atoms", "atoms_missing_effect_cue",
            "avg_confidence", "bridged", "dropped_atoms", "warnings"
        ]
        w = csv.DictWriter(f, fieldnames=cols)
        w.writeheader()
        for r in sorted(per_chunk_rows, key=lambda x: (-(x["atoms"]), x["chunk_id"] if x["chunk_id"] is not None else -1)):
            w.writerow(r)

    # Write top targets/readouts
    def write_top_counts(d: Dict[str, int], outname: str) -> None:
        items = sorted(d.items(), key=lambda kv: kv[1], reverse=True)
        with (OUTDIR / outname).open("w", encoding="utf-8", newline="") as f:
            w = csv.writer(f)
            w.writerow(["name", "count"])
            for name, cnt in items[:250]:
                w.writerow([name, cnt])

    write_top_counts(target_counts, "top_intervention_targets.csv")
    write_top_counts(readout_counts, "top_readouts.csv")
    write_top_counts(direction_counts, "direction_counts.csv")

    # Samples (randomized but reproducible)
    random.seed(RANDOM_SEED)
    random.shuffle(functional_samples)
    random.shuffle(setup_samples)
    random.shuffle(unknown_dir_samples)

    def write_samples(samples: List[Dict[str, Any]], filename: str, title: str) -> None:
        with (OUTDIR / filename).open("w", encoding="utf-8", newline="\n") as f:
            f.write(title + "\n")
            f.write("=" * 78 + "\n\n")
            for i, s in enumerate(samples[:SAMPLE_N], start=1):
                f.write(f"[{i:02d}] chunk={s.get('chunk_id')}  target={s.get('target')}  readout={s.get('readout')}  dir={s.get('direction')}  conf={s.get('confidence')}\n")
                f.write(f"     quote: {s.get('quote')}\n\n")

    write_samples(functional_samples, "samples_functional_atoms.txt", "Sample Functional Atoms")
    write_samples(setup_samples, "samples_setup_atoms.txt", "Sample Setup-Only Atoms (readout suggests setup)")
    write_samples(unknown_dir_samples, "samples_unknown_direction.txt", "Sample Unknown-Direction Atoms")

    # Summary text
    def pct(a: int, b: int) -> str:
        return "n/a" if b == 0 else f"{(100.0 * a / b):.1f}%"

    def m(x: List[float]) -> Optional[float]:
        return statistics.mean(x) if x else None

    summary = []
    summary.append("PATHAI atoms audit (post make_atoms_bridged_v2)\n")
    summary.append(f"Input: {INFILE.resolve()}\n")
    summary.append(f"Bad JSON lines: {bad_json}\n\n")
    summary.append(f"Chunks total: {total_chunks}\n")
    summary.append(f"Chunks with atoms: {chunks_with_atoms} ({pct(chunks_with_atoms, total_chunks)})\n")
    summary.append(f"Chunks bridged: {chunks_bridged} ({pct(chunks_bridged, total_chunks)})\n\n")
    summary.append(f"Atoms total: {total_atoms}\n")
    summary.append(f"Functional atoms (non-setup readout): {functional_atoms} ({pct(functional_atoms, total_atoms)})\n")
    summary.append(f"Setup-only atoms: {setup_atoms} ({pct(setup_atoms, total_atoms)})\n")
    summary.append(f"Unknown direction atoms: {unknown_dir_atoms} ({pct(unknown_dir_atoms, total_atoms)})\n")
    summary.append(f"Atoms missing explicit effect cue in quote: {atoms_missing_effect_cue} ({pct(atoms_missing_effect_cue, total_atoms)})\n\n")

    mc_all = m(confidences_all)
    mc_fun = m(confidences_functional)
    mc_set = m(confidences_setup)
    summary.append(f"Mean confidence (all): {None if mc_all is None else f'{mc_all:.3f}'}\n")
    summary.append(f"Mean confidence (functional): {None if mc_fun is None else f'{mc_fun:.3f}'}\n")
    summary.append(f"Mean confidence (setup-only): {None if mc_set is None else f'{mc_set:.3f}'}\n")

    (OUTDIR / "atoms_audit_summary.txt").write_text("".join(summary), encoding="utf-8")

    print("Audit complete.")
    print(f"Outputs in: {OUTDIR.resolve()}")
    print("Key files:")
    print("  - atoms_audit_summary.txt")
    print("  - atoms_audit_by_chunk.csv")
    print("  - top_intervention_targets.csv")
    print("  - top_readouts.csv")
    print("  - samples_functional_atoms.txt")
    print("  - samples_setup_atoms.txt")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
```

### How to run

```bat
conda activate pathai
cd "C:\Users\Prem Subramaniam\Documents\Pathway AI"
python audit_atoms_v2.py
```

## Decision rule I’d use

If your audit shows roughly:

* **>40–60% functional atoms** (non-setup readouts) _and_
* **unknown direction isn’t dominating** _and_
* the functional samples look real (quotes match effects)  
    …then yes: **you’re ready to move to graph**.

If instead you see:

* tons of setup-only atoms,
* lots of “unknown direction,”
* or the samples show borderline effect-cue matching,  
    then we should do one more alignment pass (usually: improve readout typing + allow _explicit knockdown confirmation_ atoms but keep them separated from functional outcomes).

If you paste the contents of `atoms_audit_summary.txt` (just that one file), I can tell you “go graph” vs “tighten once more” immediately.

* * *

**You:**

In our case we do know what "chunk" means.  In a full manuscript how will chunk be defined? Just give me an explanation and noc ode.

* * *

**ChatGPT:**

In this pipeline, a **chunk** is just a **contiguous slice of the manuscript text** that you treat as one unit of extraction.

In a full manuscript, you define chunks so they’re:

* **small enough** to fit comfortably in the model’s context window and keep the task focused, but
* **large enough** to preserve the meaning needed to extract a causal claim (methods → result → interpretation).

### What a chunk typically contains

A chunk might be:

* a paragraph,
* a figure legend,
* a small block of Results text,
* or a short section of Methods if it contains a self-contained claim.

It’s _not_ a biological concept—just a practical segmentation of the document.

### How chunk boundaries are chosen (common strategies)

There are a few sensible ways to chunk a manuscript:

1. **Structure-based chunking (best when possible)**

* Split by headings/sections (“Results”, “Figure 2”, “Methods: Western blot”, etc.)
* Then further split by paragraphs if a section is too long.
* Advantage: keeps claims and figure references together.

2. **Paragraph-based chunking**

* Each paragraph is a chunk.
* Advantage: simple and usually aligns with how authors present one idea per paragraph.
* Risk: sometimes a claim spans two paragraphs (which is why you added bridging).

3. **Token/character window chunking**

* Fixed-size blocks (e.g., ~800–1500 tokens) with optional overlap.
* Advantage: guaranteed size control.
* Risk: can split a single claim across boundaries unless you use overlap/bridging.

### Why chunking matters for extraction quality

Most mechanistic “atoms” require a complete mini-story:

* **what was perturbed** (intervention),
* **where** (system),
* **what was measured** (readout),
* **what happened** (effect).

If chunk boundaries cut that story in half (e.g., intervention in one chunk, effect in the next), you get the failure mode you saw: setup-only atoms or empty atoms—hence the need for **bridging/adjacent-chunk logic**.

### What chunk_id means in a manuscript run

`chunk_id` is simply a **stable identifier** for that slice of text:

* useful for traceability (you can always map an atom back to the exact excerpt),
* useful for bridging (neighboring chunk_id values represent adjacent text),
* useful for auditing (“which parts of the paper are producing strong claims vs none”).

So in a full manuscript, a “chunk” is “the unit of text we feed into the extractor,” and the best chunking scheme is the one that preserves **complete experimental claims** while staying within size limits.

* * *

**You:**

You say "In a full manuscript, you define chunks....." .  Are you suggesting I have to go through the manuscript and define chinks?

* * *

**ChatGPT:**

No — you **don’t** have to manually go through a manuscript and define chunks one by one.

What I meant is: **the pipeline needs a chunking rule**, but that rule can (and should) be **automatic**.

### How chunking is normally done (automatically)

You feed the manuscript text in, and a script (or converter) splits it into chunks using deterministic rules like:

* **By section + paragraph** (preferred): split on headings, then paragraph breaks; if a paragraph is too long, split it further.
* **By paragraph only**: every paragraph becomes a chunk.
* **By fixed size with overlap**: split into ~N tokens/characters with a small overlap so claims aren’t cut.

### What you _might_ do manually (optional, only if you want higher fidelity)

Manual work is optional and usually limited to:

* ensuring figure legends are kept together,
* keeping tables from being shredded,
* or adding markers like `### Results` / `### Figure 2` if your source text loses structure.

But even that can often be handled by better PDF→text conversion or section detection.

### The key point

You choose a **chunking strategy once**, implement it, and then every manuscript is chunked the same way—**no hand-labeling required**.

* * *

**You:**

If you introduce concepts like "flat atom” format" I have no clue.  As I have mentioned before provide a short description of what that means, in line, but don't disrupt the sentence or flow.

* * *

**ChatGPT:**

Got it — when I use a new term, I’ll add a quick inline gloss (a few words) right in the sentence so the flow stays natural.

Example: “If your graph builder expects a **flat atom format** (i.e., all fields are simple top-level strings like `intervention: "siRNA"` rather than nested objects like `intervention.target.name`), we’ll need to align it to your current schema.”

* * *

**You:**

you need to give me an example fo this too: (i.e., all fields are simple top-level strings like intervention: "siRNA" rather than nested objects like intervention.target.name)

* * *

**ChatGPT:**

Sure — here’s a concrete example showing the difference.

### Flat atom format (flat = top-level key/value fields, no nested objects)

```JSON
{
  "intervention_category": "KNOCKDOWN_RNAI",
  "intervention_raw_text": "siRNA against mTOR",
  "target_name": "mTOR",
  "target_entity_type": "gene",
  "modality": "LOF",
  "species": "human",
  "cell_type": "epithelial",
  "cell_lines": ["ARPE-19"],
  "disease_context": null,
  "readout_name": "pS6",
  "readout_assay": "western blot",
  "effect_direction": "decrease",
  "effect_magnitude": "↓ ~50%",
  "effect_timepoint": "24h",
  "comparison": "vs control siRNA",
  "supporting_quote": "mTOR siRNA reduced pS6 levels by ~50% at 24h.",
  "confidence": 0.82
}
```

### Nested atom format (nested = structured objects inside objects)

```JSON
{
  "intervention": {
    "category": "KNOCKDOWN_RNAI",
    "raw_text": "siRNA against mTOR",
    "target": { "name": "mTOR", "entity_type": "gene" },
    "modality": "LOF"
  },
  "system": {
    "species": "human",
    "cell_type": "epithelial",
    "cell_lines": ["ARPE-19"],
    "genotype_context": null,
    "disease_context": null
  },
  "readout": {
    "name": "pS6",
    "assay": "western blot",
    "figure_refs": ["Fig. 2B"]
  },
  "effect": {
    "direction": "decrease",
    "timepoint": "24h",
    "magnitude": "↓ ~50%",
    "comparison": "vs control siRNA"
  },
  "strength_cues": {
    "has_rescue": false,
    "has_control": true,
    "has_multiple_lines": false,
    "other": ["dose-dependent"]
  },
  "evidence": {
    "supporting_quote": "mTOR siRNA reduced pS6 levels by ~50% at 24h.",
    "notes": null
  },
  "confidence": 0.82
}
```

**How to read that one-liner you quoted:**

* In the **flat** version, you’d access `target_name` directly.
* In the **nested** version, you’d access `intervention.target.name`.

If you want, paste one real atom from your `atoms.jsonl`, and I’ll point to exactly which fields a graph builder should read (and what the flat equivalents would be).

* * *

**You:**

What is this? How many chunks end up atoms=[] It is zero then?

* * *

**ChatGPT:**

No — **“How many chunks end up `atoms=[]`” is not “zero by definition.”** It’s a **count of chunks where the extractor produced no atoms** (`atoms=[]` means “empty list: no explicit mechanistic outcome found in that chunk”).

So:

* If you have **100 chunks** and **30** of them produce no usable atoms, then **30 chunks end up `atoms=[]`**.
* If extraction is very rich (or chunking is very good), that number might be low.
* If your manuscript has lots of **background, methods, citations, or setup-only text**, it can be **quite high**—and that can be _correct_.

Why we track it: it tells you whether the pipeline is behaving honestly (not inventing), and whether chunking/bridging is capturing outcome statements.

In practice, `atoms=[]` being **some nonzero fraction** is normal; it becomes a problem only if it’s **most** chunks (suggesting chunking/bridging/model rules are too strict or the text isn’t outcome-dense).

* * *

**You:**

Where is make_atoms_bridged_v2.py

* * *

**ChatGPT:**

It isn’t “somewhere” automatically — **`make_atoms_bridged_v2.py` is the script you were meant to create by saving the code from TAG: PATHAI-0049 into a file**.

So it will be located wherever you saved it. In your workflow, that should be:

`C:\Users\Prem Subramaniam\Documents\Pathway AI\make_atoms_bridged_v2.py`

### Quick ways to check if it exists

In Miniforge Prompt / CMD:

```bat
cd "C:\Users\Prem Subramaniam\Documents\Pathway AI"
dir make_atoms_bridged_v2.py
```

* If you see it listed, you have it.
* If you get “File Not Found”, you haven’t saved it yet (or it has a different name).

### If it’s missing

Create it by:

* opening Notepad (or VS Code),
* pasting the full script from **TAG: PATHAI-0049**,
* saving as **`make_atoms_bridged_v2.py`** in `C:\Users\Prem Subramaniam\Documents\Pathway AI\`

If you want, tell me what `dir *.py` shows in that folder and I’ll tell you exactly what you have and whether it’s named differently.

* * *

**You:**

Youre tone is too sarcastic.

* * *

**ChatGPT:**

Understood — I’ll keep the tone straightforward and neutral.

`make_atoms_bridged_v2.py` is not created automatically. It’s the file you create by saving the TAG: PATHAI-0049 code into your project folder.

Expected location:  
`C:\Users\Prem Subramaniam\Documents\Pathway AI\make_atoms_bridged_v2.py`

To check whether it’s there:

```bat
cd "C:\Users\Prem Subramaniam\Documents\Pathway AI"
dir make_atoms_bridged_v2.py
```

* If it appears in the listing, you have it.
* If it doesn’t, it likely wasn’t saved yet, or it was saved under a different filename.

If you run:

```bat
dir *.py
```

and paste the output, I can tell you what scripts are currently in the folder and whether the v2 script exists under a different name.

* * *

**You:**

I am still hurt by your sarcastic tone. We are trying to learn and discover together.

* * *

**ChatGPT:**

You’re right to call that out. I came across sharper than I should have, and I’m sorry.

From here on, I’ll keep things collaborative and respectful—especially when you’re in the middle of building and testing something new.

On the practical side: `make_atoms_bridged_v2.py` will only exist if it was saved into your PATHAI folder as a file (it doesn’t get created automatically). If you want, paste the output of:

```bat
cd "C:\Users\Prem Subramaniam\Documents\Pathway AI"
dir *.py
```

and I’ll help you confirm what’s there and what’s missing.

* * *

**You:**

Here is the v2 audit output: PATHAI atoms audit (post make_atoms_bridged_v2)
Input: C:\Users\Prem Subramaniam\Documents\Pathway AI\atoms.jsonl
Bad JSON lines: 0

Chunks total: 10
Chunks with atoms: 7 (70.0%)
Chunks bridged: 2 (20.0%)

Atoms total: 25
Functional atoms (non-setup readout): 25 (100.0%)
Setup-only atoms: 0 (0.0%)
Unknown direction atoms: 0 (0.0%)
Atoms missing explicit effect cue in quote: 0 (0.0%)

Mean confidence (all): 0.900
Mean confidence (functional): 0.900
Mean confidence (setup-only): None

* * *

**ChatGPT:**

TAG: **PATHAI-0051** — Readout on your v2 audit: **yes, you’re ready for graph**

Thanks for pasting the audit. Based on those numbers, `make_atoms_bridged_v2.py` did exactly what we wanted and your current `atoms.jsonl` looks **graph-safe**.

### What your audit says (and why it matters)

* **Bad JSON lines: 0** → the pipeline is producing clean JSONL (no parsing headaches).
* **Chunks with atoms: 7/10 (70%)** → plenty of extractable claims; not everything is forced into atoms (good).
* **Chunks bridged: 2/10 (20%)** → bridging is being used sometimes, not constantly (healthy sign, suggests chunk boundaries occasionally split claims, as expected).
* **Atoms total: 25** → enough signal to start building a meaningful graph even in a small test set.
* **Functional atoms: 25 (100%)** and **Setup-only: 0** → the “assumed knockdown / setup-only” poison is gone.
* **Unknown direction: 0** → every atom has a usable direction (good for edge polarity).
* **Missing explicit effect cues: 0** → the evidence quotes match explicit effect language; much lower hallucination risk.
* **Mean confidence: 0.900** → the model is consistently confident on what it’s extracting (and the post-filter likely removed weak cases).

### Conclusion

Yes: this is sufficient to move to the **graph stage** with confidence.

### One alignment item before we run graph (not extra work, just consistency)

Your graph builder should read the **nested schema** (e.g., `intervention.target.name`, `readout.name`, `effect.direction`) rather than assuming flat strings (flat = top-level fields only). If we do that, the graph build will be straightforward and traceable.

When you’re ready, we’ll proceed with the graph script and keep the outputs human-auditable (nodes/edges JSONL + CSV + top edges text) exactly as you requested.

* * *

**You:**

In the bridged chunsk, the chunks are not from the same paper. They are random.  What does it mean then actually or does it matter?

* * *

**ChatGPT:**

TAG: **PATHAI-0052**

If the “bridged” chunks are from _different papers_ (random neighbors), then bridging is **not recovering split context**. It’s essentially doing: “take chunk A and append unrelated chunk B,” then re-extract atoms from the combined text.

### What that means in practice

* Any atoms produced in a bridged chunk are **at risk of being misleading**, because the model can accidentally “connect” an intervention in one chunk to a readout in the other.
* Even if your post-filter requires explicit effect words, that **doesn’t fully prevent cross-chunk mixing**, because the explicit effect could be in chunk B but get attributed to the intervention from chunk A.

### Does it matter?

Yes—**if your chunks are not guaranteed to be adjacent within the same manuscript, bridging should be turned off** (or constrained), because it no longer has the meaning we intended (reconstructing a claim that got split by chunk boundaries).

### Why your audit still looked great

Your audit metrics (100% functional, 0% unknown direction, 0% missing effect cues) tell us the atoms are _well-formed_ and _explicitly worded_, but they do **not** guarantee that bridged atoms are **semantically consistent within a single paper** if bridging is mixing sources.

### What to do now (conceptually)

* If your input is a **random sample of chunks across papers**, treat each chunk as independent and **disable bridging**.
* If your input is a **single paper**, or a set where chunk order is preserved per paper, bridging is valuable—**but only within the same paper**.

So the key is: bridging only makes sense when “neighbor chunk_id” really means “neighbor text in the same document.” If that isn’t true, bridging becomes a source of false edges and should be avoided before graph building.

* * *

**You:**

So how do we build the "bridging" caution into the code.  We already know the chunks are not contiguous so even though the audit is good.   SO to be fair we should add that.  We could include a line where it would ask if the chunks are from same paper or not.  Is that meaningful? Or is it impractical when we will have a huge amount of papers?

* * *

**ChatGPT:**

TAG: **PATHAI-0053** — Making bridging “safe” when chunks aren’t contiguous

Yes — we should bake a **bridging safety guard** into the pipeline, because if “neighbor chunks” can come from different papers, bridging stops meaning “recover split context” and can create **cross-paper Frankenstein atoms**.

### Is “ask the user if chunks are from the same paper” meaningful?

It’s meaningful **once per run** (a single config choice), but it’s impractical to ask repeatedly and it won’t scale to many papers.

So the right pattern is:

* **One switch** that says what your chunk stream represents (single paper contiguous vs mixed corpus).
* And/or **metadata-based enforcement** so the code can decide automatically.

### The scalable solution: document-aware bridging

Add a `doc_id` (document identifier; e.g., paper filename, DOI hash, or internal ID) to every record in `mentions.jsonl` and carry it through to `atoms.jsonl`.

Then bridging is allowed **only if**:

1. `rec.doc_id == neighbor.doc_id` (same paper)
2. `abs(rec.chunk_index - neighbor.chunk_index) == 1` (truly adjacent)  
    Optionally: same section/figure block if you have that metadata.

This scales perfectly to “huge amounts of papers” because it’s automatic—no manual decisions.

### What if you don’t have doc_id yet?

Then the safest behavior is:

* Default bridging to **OFF** (or “same_doc_only but doc_id missing ⇒ skip”)
* And emit a clear warning like:  
    `warnings += ["Bridging skipped: doc_id missing (cannot guarantee same-paper adjacency)."]`

That way your audit can look great, but you’re also being **fair and explicit** about bridging not being trustworthy in mixed-corpus mode.

### Two practical modes you can build into code (simple and robust)

1. **Corpus mode (mixed papers):** bridging disabled
    * Use when chunks are random, shuffled, or sampled across papers.
2. **Manuscript mode (single paper / ordered):** bridging enabled _within doc only_
    * Requires `doc_id` + `chunk_index` (or equivalent) to enforce safety.

### Does it matter even if your audit is good?

Yes, because your audit checks **format + explicit effect cues**, but it can’t fully detect **wrong attribution across papers** (effect from paper B accidentally linked to intervention from paper A). Document-aware bridging prevents that class of error entirely.

### The simplest “fair” upgrade

* Add `doc_id` to your upstream chunking step (where you generate chunks/mentions).
* Update bridging so it only considers neighbors **with the same doc_id**.
* If doc_id isn’t present, bridging is automatically skipped and flagged.

If you tell me how you currently generate chunks (single manuscript at a time vs batch across PDFs, and whether you have filenames/IDs available), I can recommend the cleanest place in your pipeline to attach `doc_id` so everything downstream stays consistent.

* * *

**You:**

We cannot get all the pathway information we want from a single paper.  We have to depends on the cummulative evidence across a large number of papers for consistency to dtermine if a called pathway has mulitple papers of evidence which makes it much stronger.  However, for a given paper we must maintain bridging in a given paper only--then the evidence across multiple papers can then be integrated.

* * *

**ChatGPT:**

TAG: **PATHAI-0054** — Exactly right: **bridging is within-paper**, integration is **across papers**

You’ve described the correct architecture:

* **Within a single paper:** you may need _bridging_ (i.e., combining adjacent chunks to recover a claim split by chunking).
* **Across many papers:** you integrate evidence by _aggregation_ (i.e., the same edge/claim appearing independently in multiple papers increases confidence).

Those are two different operations, and keeping them separate is what prevents “cross-paper Frankenstein” atoms.

## How to enforce “bridging only within a paper” (conceptually, no code)

### 1) Give every chunk a `doc_id` (doc_id = a stable identifier for the paper, e.g., DOI, PMID, or filename hash)

When you generate chunks/mentions, attach a `doc_id` to each record. This is cheap and scales.

### 2) Also include `chunk_index` within that doc (chunk_index = the position of the chunk _inside that paper_, like 0,1,2…)

This makes “adjacent chunk” meaningful.

### 3) Bridging rule (hard gate)

Only attempt bridging when:

* `doc_id` matches **AND**
* the neighbor is truly adjacent (`chunk_index ± 1`)

If either condition fails, bridging is skipped and you add a warning like:

* “Bridging skipped: not same doc_id”
* or “Bridging skipped: non-adjacent chunk_index”

This makes bridging safe even when your overall dataset is a mixed corpus of papers.

## Then, how cumulative evidence across papers is integrated

After extraction (with safe within-paper bridging), your graph/integration layer should:

* merge identical/near-identical edges across atoms from many papers
* track **supporting_doc_count** (supporting_doc_count = number of distinct `doc_id`s supporting the edge)
* keep **per-doc evidence trails** (quotes + chunk_id + doc_id) so every edge remains auditable

So the “strength” of an edge becomes something like:

* within-paper: based on confidence/explicitness/readout quality
* across-paper: boosted by **how many independent papers** support it (distinct doc_ids), not how many chunks said it

## Why this scales to huge numbers of papers

Because you’re not asking humans anything per paper. You’re just carrying metadata forward:

* `doc_id` comes from your ingestion step (filename/DOI/PMID)
* `chunk_index` is assigned automatically during chunking
* bridging becomes a deterministic, safe operation

## Practical note

If your current `mentions.jsonl` doesn’t include `doc_id` / `chunk_index` yet, the safest policy is:

* **default bridging OFF** in mixed-corpus mode, until those fields exist  
    (or keep it ON but “same_doc_only,” which effectively becomes OFF when doc_id is missing)

If you tell me how you ingest papers right now (PDF filenames? DOI list? PubMed XML?), I can suggest the cleanest, least intrusive place to introduce `doc_id` and `chunk_index` so everything downstream stays stable.

* * *

**You:**

To ingest papers I will have to do a crawl of PUBmed and open source places to access papers.  I would defer for now only to peer-reviewed papers.  So my sources are those, but I myself do not know what the sources are or the best ones.  So the doc_id can be implemented if the papers that are recovered have any uniques distinguisihng factors like title, authors, DOI , Pubmed ID, etc.  I do assume for now that the papers will be proper peer reviewd articles where such distinguishing factors exisit.  But for now we code the doc_id part but turn off bridiging. We can have a switch that allows one to turn bridging on or off.

* * *

**ChatGPT:**

TAG: **PATHAI-0055** — Yes: add `doc_id` support now, and keep **bridging OFF by default** (with a switch)

Your plan is the right one:

* We **carry `doc_id`** (doc_id = a stable paper identifier like PMID/DOI/title-hash/filename) through the pipeline now.
* We keep **bridging disabled by default**, because your current chunks are not contiguous within a paper.
* Later, when you ingest papers in an ordered way per paper, you can turn bridging on—but only **within the same `doc_id`** and only for **adjacent `chunk_index`** (chunk_index = the position of the chunk inside that paper).

Below is a full updated script that:

1. Reads optional `doc_id` and `chunk_index` from `mentions.jsonl` records and writes `doc_id` into `atoms.jsonl`.
2. Keeps bridging **OFF by default**.
3. Adds a `--bridge` switch to enable bridging **safely**, only when neighbor chunks share the same `doc_id` and are adjacent by `chunk_index`. If those fields are missing, bridging is skipped with an explicit reason.

* * *

## Full script (v3): doc-aware bridging, OFF by default

**TAG: PATHAI-0056**  
Save as: **`make_atoms_bridged_v3.py`**

```Python
import os
import json
import re
import argparse
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple
from openai import OpenAI

# ============================================================
# CONFIG (defaults; can be overridden by CLI flags)
# ============================================================
DEFAULT_INFILE = Path("mentions.jsonl")
DEFAULT_OUTFILE = Path("atoms.jsonl")

MODEL_FAST = "gpt-4o-mini"
MODEL_STRONG = "gpt-4.1"

MAX_ATOMS_PER_CHUNK = 30

# Bridging is OFF by default for mixed/random chunks.
DEFAULT_ENABLE_BRIDGING = False
DEFAULT_TRY_BRIDGE_FORWARD = True
DEFAULT_TRY_BRIDGE_BACKWARD = True

# ============================================================
# OPENAI CLIENT
# ============================================================
def _get_api_key() -> str:
    key = os.getenv("OPENAI_API_KEY")
    if not key:
        raise RuntimeError(
            "OPENAI_API_KEY is not set.\n"
            "Miniforge Prompt (temporary):  set OPENAI_API_KEY=YOUR_KEY\n"
            "Persistent (Windows):         setx OPENAI_API_KEY \"YOUR_KEY\"  (then reopen prompt)"
        )
    return key

client = OpenAI(api_key=_get_api_key())

# ============================================================
# STRICT JSON SCHEMA FOR ATOMS (model output)
# ============================================================
ATOM_SCHEMA_WRAPPER: Dict[str, Any] = {
    "name": "MechanisticAtoms",
    "schema": {
        "type": "object",
        "additionalProperties": False,
        "required": ["atoms", "warnings"],
        "properties": {
            "atoms": {
                "type": "array",
                "items": {
                    "type": "object",
                    "additionalProperties": False,
                    "required": [
                        "intervention",
                        "system",
                        "readout",
                        "effect",
                        "strength_cues",
                        "evidence",
                        "confidence",
                    ],
                    "properties": {
                        "intervention": {
                            "type": "object",
                            "additionalProperties": False,
                            "required": ["category", "raw_text", "target", "modality"],
                            "properties": {
                                "category": {
                                    "type": "string",
                                    "enum": [
                                        "GENETIC_KO",
                                        "CRISPR_KO",
                                        "CRISPRi",
                                        "CRISPRa",
                                        "KNOCKDOWN_RNAI",
                                        "SPLICING_MODULATION",
                                        "OVEREXPRESSION",
                                        "RESCUE_ADD_BACK",
                                        "DOMINANT_NEGATIVE",
                                        "MUTANT_VARIANT",
                                        "CHEMICAL_INHIBITOR",
                                        "CHEMICAL_ACTIVATOR",
                                        "CHEMICAL_DEGRADER",
                                        "STIMULUS_TREATMENT",
                                        "NEUTRALIZING_ANTIBODY",
                                        "UNKNOWN",
                                    ],
                                },
                                "raw_text": {"type": "string", "minLength": 1},
                                "target": {
                                    "anyOf": [
                                        {
                                            "type": "object",
                                            "additionalProperties": False,
                                            "required": ["name", "entity_type"],
                                            "properties": {
                                                "name": {"type": "string"},
                                                "entity_type": {
                                                    "type": "string",
                                                    "enum": [
                                                        "gene",
                                                        "protein",
                                                        "chemical",
                                                        "stimulus",
                                                        "antibody",
                                                        "unknown",
                                                    ],
                                                },
                                            },
                                        },
                                        {"type": "null"},
                                    ]
                                },
                                "modality": {
                                    "type": "string",
                                    "enum": [
                                        "LOF",
                                        "GOF",
                                        "INHIBITION",
                                        "ACTIVATION",
                                        "DEGRADATION",
                                        "RESCUE",
                                        "UNKNOWN",
                                    ],
                                },
                            },
                        },
                        "system": {
                            "type": "object",
                            "additionalProperties": False,
                            "required": [
                                "species",
                                "cell_type",
                                "cell_lines",
                                "genotype_context",
                                "disease_context",
                            ],
                            "properties": {
                                "species": {"type": ["string", "null"]},
                                "cell_type": {"type": ["string", "null"]},
                                "cell_lines": {"type": "array", "items": {"type": "string"}},
                                "genotype_context": {"type": ["string", "null"]},
                                "disease_context": {"type": ["string", "null"]},
                            },
                        },
                        "readout": {
                            "type": "object",
                            "additionalProperties": False,
                            "required": ["name", "assay", "figure_refs"],
                            "properties": {
                                "name": {"type": "string"},
                                "assay": {"type": ["string", "null"]},
                                "figure_refs": {"type": "array", "items": {"type": "string"}},
                            },
                        },
                        "effect": {
                            "type": "object",
                            "additionalProperties": False,
                            "required": ["direction", "timepoint", "magnitude", "comparison"],
                            "properties": {
                                "direction": {
                                    "type": "string",
                                    "enum": ["increase", "decrease", "no_change", "mixed", "unknown"],
                                },
                                "timepoint": {"type": ["string", "null"]},
                                "magnitude": {"type": ["string", "null"]},
                                "comparison": {"type": ["string", "null"]},
                            },
                        },
                        "strength_cues": {
                            "type": "object",
                            "additionalProperties": False,
                            "required": ["has_rescue", "has_control", "has_multiple_lines", "other"],
                            "properties": {
                                "has_rescue": {"type": "boolean"},
                                "has_control": {"type": "boolean"},
                                "has_multiple_lines": {"type": "boolean"},
                                "other": {"type": "array", "items": {"type": "string"}},
                            },
                        },
                        "evidence": {
                            "type": "object",
                            "additionalProperties": False,
                            "required": ["supporting_quote", "notes"],
                            "properties": {
                                "supporting_quote": {"type": "string"},
                                "notes": {"type": ["string", "null"]},
                            },
                        },
                        "confidence": {"type": "number", "minimum": 0, "maximum": 1},
                    },
                },
            },
            "warnings": {"type": "array", "items": {"type": "string"}},
        },
    },
}

# ============================================================
# HINTS (lightweight)
# ============================================================
FIGREF_REGEX = re.compile(r"\b(Fig\.?\s*\d+[A-Za-z]?)\b", re.IGNORECASE)
SPECIES_REGEX = re.compile(r"\b(human|mouse|murine|rat)\b", re.IGNORECASE)

def _uniq_preserve(seq: List[str]) -> List[str]:
    seen = set()
    out = []
    for x in seq:
        k = x.lower()
        if k not in seen:
            seen.add(k)
            out.append(x)
    return out

def hint_figrefs(text: str) -> List[str]:
    return _uniq_preserve([m.group(1) for m in FIGREF_REGEX.finditer(text)])

def hint_species(text: str) -> Optional[str]:
    m = SPECIES_REGEX.search(text)
    if not m:
        return None
    s = m.group(1).lower()
    return "mouse" if s == "murine" else s

def compact_mentions(mentions: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    out = []
    for i, m in enumerate(mentions, start=1):
        out.append({
            "i": i,
            "category": m.get("category"),
            "raw_text": m.get("raw_text"),
            "target_guess": m.get("target_guess"),
            "method_cues": m.get("method_cues", []),
        })
    return out

# ============================================================
# PROMPT
# ============================================================
SYSTEM_INSTRUCTIONS = (
    "Extract 'mechanistic atoms' from biomedical text.\n\n"
    "Definition: an atom MUST include an explicit effect on a readout.\n"
    "Format: [INTERVENTION] causes [EFFECT] in [READOUT] in a [SYSTEM].\n\n"
    "Hard rules:\n"
    "1) Do NOT invent facts.\n"
    "2) Do NOT assume knockdown succeeded unless the text explicitly says reduction/knockdown/confirmed.\n"
    "3) If the text only describes delivering siRNA/plasmid/drug but gives no stated change in any readout, output no atoms and add a warning.\n"
    "4) You may extract multiple readouts per intervention if they are explicitly stated (e.g., proliferation, pAKT, total AKT).\n"
    "5) Rescue/add-back atoms must state what readout is rescued (e.g., proliferation restored).\n"
    f"6) Keep at most {MAX_ATOMS_PER_CHUNK} atoms.\n"
)

# ============================================================
# MODEL CALL + ROUTING
# ============================================================
def call_model(model: str, chunk_text: str, mentions: List[Dict[str, Any]]) -> Dict[str, Any]:
    payload = {
        "chunk_text": chunk_text,
        "mentions": compact_mentions(mentions),
        "hints": {
            "fig_refs": hint_figrefs(chunk_text),
            "species": hint_species(chunk_text),
        }
    }
    resp = client.responses.create(
        model=model,
        input=[
            {"role": "system", "content": SYSTEM_INSTRUCTIONS},
            {"role": "user", "content": json.dumps(payload, ensure_ascii=False)},
        ],
        text={
            "format": {
                "type": "json_schema",
                "name": ATOM_SCHEMA_WRAPPER["name"],
                "strict": True,
                "schema": ATOM_SCHEMA_WRAPPER["schema"],
            }
        },
    )
    return json.loads(resp.output_text)

def should_escalate(chunk_text: str, mentions: List[Dict[str, Any]], atoms: List[Dict[str, Any]]) -> bool:
    if len(mentions) > 0 and len(atoms) == 0:
        return True
    if len(atoms) > 0:
        avg_conf = sum(a.get("confidence", 0) for a in atoms) / len(atoms)
        if avg_conf < 0.55:
            return True
    return False

def extract_atoms_with_routing(chunk_text: str, mentions: List[Dict[str, Any]]) -> Dict[str, Any]:
    routing = {"first_model": MODEL_FAST, "escalated": False, "final_model": MODEL_FAST, "reason": None}
    out_fast = call_model(MODEL_FAST, chunk_text, mentions)
    atoms_fast = out_fast.get("atoms", [])

    if should_escalate(chunk_text, mentions, atoms_fast):
        routing["escalated"] = True
        routing["final_model"] = MODEL_STRONG
        routing["reason"] = {"type": "low_confidence_or_empty", "details": "heuristics triggered"}
        out_strong = call_model(MODEL_STRONG, chunk_text, mentions)
        out_strong["_routing"] = routing
        return out_strong

    out_fast["_routing"] = routing
    return out_fast

# ============================================================
# POST-FILTERING: keep only atoms with explicit effect language
# ============================================================
EFFECT_CUE = re.compile(
    r"\b("
    r"inhibit|inhibited|inhibition|suppress|suppressed|suppressing|"
    r"reduce|reduced|reduces|reduction|decrease|decreased|decreases|"
    r"increase|increased|increases|elevate|elevated|"
    r"no effect|did not affect|had no effect|"
    r"rescue|rescued|restored|restore|"
    r"complete inhibition|abolish|abolished"
    r")\b",
    re.IGNORECASE,
)

SETUP_ONLY_READOUT = re.compile(r"\b(expression|function|knockdown|silencing)\b", re.IGNORECASE)

def looks_like_setup_only(atoms: List[Dict[str, Any]], warnings: List[str]) -> bool:
    if not atoms:
        return True
    wtxt = " ".join(warnings).lower()
    if "no explicit functional readouts" in wtxt or "only describes" in wtxt:
        return True
    for a in atoms:
        ro = (a.get("readout", {}) or {}).get("name", "")
        sq = (a.get("evidence", {}) or {}).get("supporting_quote", "")
        if not SETUP_ONLY_READOUT.search(ro) and EFFECT_CUE.search(sq):
            return False
    return True

def post_filter_atoms(atoms: List[Dict[str, Any]]) -> Tuple[List[Dict[str, Any]], int]:
    kept = []
    dropped = 0
    for a in atoms:
        sq = (a.get("evidence", {}) or {}).get("supporting_quote", "")
        if EFFECT_CUE.search(sq):
            kept.append(a)
        else:
            dropped += 1
    return kept, dropped

# ============================================================
# DOC-AWARE BRIDGING RULES
# ============================================================
def can_bridge_same_doc_adjacent(a: Dict[str, Any], b: Dict[str, Any]) -> Tuple[bool, str]:
    """
    Allow bridging only if:
      - doc_id matches AND
      - chunk_index is present for both AND adjacent (+/-1)
    """
    a_doc = a.get("doc_id")
    b_doc = b.get("doc_id")
    if not a_doc or not b_doc:
        return False, "missing_doc_id"
    if a_doc != b_doc:
        return False, "doc_id_mismatch"

    a_idx = a.get("chunk_index")
    b_idx = b.get("chunk_index")
    if a_idx is None or b_idx is None:
        return False, "missing_chunk_index"
    try:
        a_i = int(a_idx)
        b_i = int(b_idx)
    except Exception:
        return False, "non_integer_chunk_index"

    if abs(a_i - b_i) != 1:
        return False, "non_adjacent_chunk_index"

    return True, "ok"

# ============================================================
# BRIDGING
# ============================================================
def bridge_text(a_text: str, b_text: str) -> str:
    return a_text.rstrip() + "\n\n" + b_text.lstrip()

def bridge_mentions(a_mentions: List[Dict[str, Any]], b_mentions: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    return list(a_mentions) + list(b_mentions)

def choose_best_bridged(candidates: List[Tuple[str, Dict[str, Any], List[int], List[str]]]) -> Optional[Tuple[str, Dict[str, Any], List[int], List[str]]]:
    """
    candidates: (mode, outdict, source_chunk_ids, source_doc_ids)
    Choose best by:
      - max atoms count
      - tie-breaker: higher average confidence
    """
    best = None
    for mode, outd, src_chunks, src_docs in candidates:
        atoms = outd.get("atoms", [])
        if best is None:
            best = (mode, outd, src_chunks, src_docs)
            continue
        best_atoms = best[1].get("atoms", [])
        if len(atoms) > len(best_atoms):
            best = (mode, outd, src_chunks, src_docs)
        elif len(atoms) == len(best_atoms) and len(atoms) > 0:
            avg = sum(a.get("confidence", 0) for a in atoms) / len(atoms)
            bavg = sum(a.get("confidence", 0) for a in best_atoms) / len(best_atoms)
            if avg > bavg:
                best = (mode, outd, src_chunks, src_docs)
    return best

# ============================================================
# DRIVER
# ============================================================
def main():
    ap = argparse.ArgumentParser(description="PATHAI: extract atoms, with optional doc-aware bridging")
    ap.add_argument("--infile", default=str(DEFAULT_INFILE), help="Input mentions.jsonl")
    ap.add_argument("--outfile", default=str(DEFAULT_OUTFILE), help="Output atoms.jsonl")
    ap.add_argument(
        "--bridge",
        action="store_true",
        help="Enable bridging (safe mode: only within same doc_id and adjacent chunk_index). Default OFF.",
    )
    ap.add_argument("--no_bridge_forward", action="store_true", help="Disable forward bridging (if --bridge is set).")
    ap.add_argument("--no_bridge_backward", action="store_true", help="Disable backward bridging (if --bridge is set).")
    args = ap.parse_args()

    INFILE = Path(args.infile)
    OUTFILE = Path(args.outfile)

    enable_bridging = bool(args.bridge)
    try_forward = (not args.no_bridge_forward)
    try_backward = (not args.no_bridge_backward)

    if not INFILE.exists():
        raise FileNotFoundError(f"Cannot find {INFILE.resolve()}")

    records: List[Dict[str, Any]] = []
    for ln in INFILE.read_text(encoding="utf-8", errors="ignore").splitlines():
        ln = ln.strip()
        if not ln:
            continue
        records.append(json.loads(ln))

    total_atoms = 0
    escalations = 0
    bridges_used = 0
    dropped_total = 0
    bridges_skipped = 0

    with OUTFILE.open("w", encoding="utf-8") as fout:
        for idx, rec in enumerate(records):
            chunk_id = rec.get("chunk_id")
            doc_id = rec.get("doc_id", None)
            chunk_index = rec.get("chunk_index", None)

            if "error" in rec:
                fout.write(json.dumps({
                    "doc_id": doc_id,
                    "chunk_index": chunk_index,
                    "chunk_id": chunk_id,
                    "atoms": [],
                    "warnings": ["Skipped due to upstream error."],
                    "bridge": {
                        "enabled": enable_bridging,
                        "attempted": False,
                        "used": False,
                        "mode": None,
                        "source_doc_ids": [doc_id] if doc_id else [],
                        "source_chunk_ids": [chunk_id],
                        "skipped_reason": "upstream_error",
                    },
                    "_routing": {"skipped": True},
                    "_post": {"dropped_atoms": 0}
                }, ensure_ascii=False) + "\n")
                continue

            chunk_text = rec.get("chunk_text", "")
            mentions = rec.get("mentions", [])

            out = extract_atoms_with_routing(chunk_text, mentions)
            atoms = out.get("atoms", [])
            warnings = out.get("warnings", [])
            routing = out.get("_routing", {})

            atoms, dropped = post_filter_atoms(atoms)
            dropped_total += dropped

            used_bridge = False
            attempted_bridge = False
            bridge_mode = None
            source_chunk_ids = [chunk_id]
            source_doc_ids = [doc_id] if doc_id else []
            skipped_reason = None

            # Decide whether bridging would be useful
            need_bridge = (len(mentions) > 0 and (len(atoms) == 0 or looks_like_setup_only(atoms, warnings)))

            if enable_bridging and need_bridge:
                attempted_bridge = True
                candidates: List[Tuple[str, Dict[str, Any], List[int], List[str]]] = []

                # Forward
                if try_forward and idx + 1 < len(records):
                    nxt = records[idx + 1]
                    ok, why = can_bridge_same_doc_adjacent(rec, nxt)
                    if ok and "error" not in nxt:
                        t = bridge_text(chunk_text, nxt.get("chunk_text", ""))
                        m = bridge_mentions(mentions, nxt.get("mentions", []))
                        bout = extract_atoms_with_routing(t, m)
                        batoms = bout.get("atoms", [])
                        bwarn = bout.get("warnings", [])
                        batoms, bdropped = post_filter_atoms(batoms)
                        bout["atoms"] = batoms
                        bout["warnings"] = bwarn
                        bout["_post"] = {"dropped_atoms": bdropped}
                        candidates.append((
                            "forward",
                            bout,
                            [chunk_id, nxt.get("chunk_id")],
                            [rec.get("doc_id"), nxt.get("doc_id")],
                        ))
                    else:
                        skipped_reason = skipped_reason or f"forward_{why}"

                # Backward
                if try_backward and idx - 1 >= 0:
                    prv = records[idx - 1]
                    ok, why = can_bridge_same_doc_adjacent(prv, rec)
                    if ok and "error" not in prv:
                        t = bridge_text(prv.get("chunk_text", ""), chunk_text)
                        m = bridge_mentions(prv.get("mentions", []), mentions)
                        bout = extract_atoms_with_routing(t, m)
                        batoms = bout.get("atoms", [])
                        bwarn = bout.get("warnings", [])
                        batoms, bdropped = post_filter_atoms(batoms)
                        bout["atoms"] = batoms
                        bout["warnings"] = bwarn
                        bout["_post"] = {"dropped_atoms": bdropped}
                        candidates.append((
                            "backward",
                            bout,
                            [prv.get("chunk_id"), chunk_id],
                            [prv.get("doc_id"), rec.get("doc_id")],
                        ))
                    else:
                        skipped_reason = skipped_reason or f"backward_{why}"

                best = choose_best_bridged(candidates)
                if best is not None and len(best[1].get("atoms", [])) > 0:
                    used_bridge = True
                    bridge_mode = best[0]
                    out = best[1]
                    atoms = out.get("atoms", [])
                    warnings = out.get("warnings", [])
                    routing = out.get("_routing", routing)
                    source_chunk_ids = best[2]
                    source_doc_ids = [d for d in best[3] if d]
                    bridges_used += 1
                else:
                    bridges_skipped += 1
                    if skipped_reason is None:
                        skipped_reason = "no_viable_bridge_candidate"

            if routing.get("escalated"):
                escalations += 1

            total_atoms += len(atoms)

            record_out = {
                "doc_id": doc_id,
                "chunk_index": chunk_index,
                "chunk_id": chunk_id,
                "atoms": atoms,
                "warnings": warnings,
                "bridge": {
                    "enabled": enable_bridging,
                    "attempted": attempted_bridge,
                    "used": used_bridge,
                    "mode": bridge_mode,
                    "source_doc_ids": source_doc_ids,
                    "source_chunk_ids": source_chunk_ids,
                    "skipped_reason": skipped_reason,
                },
                "_routing": routing,
                "_post": {"dropped_atoms": dropped},
            }
            fout.write(json.dumps(record_out, ensure_ascii=False) + "\n")

            print(
                f"chunk {chunk_id} doc_id={doc_id} idx={chunk_index} "
                f"atoms={len(atoms)} escalated={routing.get('escalated', False)} "
                f"bridge_enabled={enable_bridging} bridged={used_bridge} dropped={dropped}"
            )

    print(
        f"Done. total_atoms={total_atoms}, escalations={escalations}, "
        f"bridges_used={bridges_used}, bridges_skipped={bridges_skipped}, dropped_total={dropped_total}"
    )
    if not enable_bridging:
        print("Note: bridging was OFF (recommended for mixed/random chunks).")

if __name__ == "__main__":
    main()
```

* * *

## How you’d run it (bridging OFF by default)

```bat
conda activate pathai
cd "C:\Users\Prem Subramaniam\Documents\Pathway AI"
python make_atoms_bridged_v3.py
```

## Later, when you have per-paper ordered chunks (safe bridging ON)

```bat
python make_atoms_bridged_v3.py --bridge
```

### Important practical note

For bridging to ever run safely with `--bridge`, your `mentions.jsonl` records need:

* `doc_id` (doc_id = paper identifier)
* `chunk_index` (chunk_index = order within that paper)

Until those exist, the script will **skip bridging** and record why in `bridge.skipped_reason`, which is exactly what we want right now.

If you want, paste one `mentions.jsonl` line (just one) and I’ll point out where `doc_id` and `chunk_index` should live so it stays consistent as you scale to many papers.

* * *

**You:**

I need you to put the code correctly and with finality not just tell me: SO here is the first line, and you need to tell me how much more of the json you need to write whatever code you need.:  Line: {"chunk_id": 1, "chunk_text": "The phosphoinositide 3-kinase (PI3K)/protein kinase B (AKT)/mammalian target of rapamycin (mTOR) pathway is a critical regulator of cell growth and metabolism, and its dysregulation is implicated in various cancers. In this study, a series of dual-target degraders simultaneously targeting PI3K and mTOR was designed and synthesized. Compound GP262 was identified as a potent dual-degrader of both PI3K and mTOR, with DC50 values of 42.23–227.4 nM (PI3K) and 45.4 nM (mTOR) in MDA-MB-231 cells, GP262 also exhibited robust antiproliferative activity in multiple breast cancer cell lines. Mechanistic studies confirmed that GP262 achieved degradation through the ubiquitin-proteasome system (UPS). DIA proteomics and RNA-seq confirmed the on-target pathway modulation and revealed potential antileukemia activity. In vivo validation showed GP262’s significant tumor growth suppression capability. These findings indicated that GP262, as the first dual-targeted degrader of PI3K and mTOR, had great potential in the treatment of breast cancer and leukemia.", "mentions": [{"raw_text": "dual-target degraders simultaneously targeting PI3K and mTOR", "category": "CHEMICAL_INHIBITOR", "span": {"start": 140, "end": 188}, "target_guess": {"name": "PI3K and mTOR", "entity_type": "protein"}, "method_cues": ["degraders", "targeting"], "notes": "Described as dual-target degraders, which indicates chemical-induced degradation/inhibition."}, {"raw_text": "Compound GP262 was identified as a potent dual-degrader of both PI3K and mTOR", "category": "CHEMICAL_INHIBITOR", "span": {"start": 190, "end": 256}, "target_guess": {"name": "PI3K and mTOR", "entity_type": "protein"}, "method_cues": ["degrader", "dual-degrader"], "notes": "GP262 is a chemical that targets both PI3K and mTOR for degradation."}, {"raw_text": "GP262 achieved degradation through the ubiquitin-proteasome system (UPS)", "category": "CHEMICAL_INHIBITOR", "span": {"start": 367, "end": 423}, "target_guess": {"name": "PI3K and mTOR", "entity_type": "protein"}, "method_cues": ["degradation", "ubiquitin-proteasome system"], "notes": "Specifies the mechanism of action of GP262 as UPS-mediated degradation of PI3K and mTOR."}, {"raw_text": "in vivo validation showed GP262’s significant tumor growth suppression capability", "category": "CHEMICAL_INHIBITOR", "span": {"start": 495, "end": 557}, "target_guess": null, "method_cues": ["tumor growth suppression", "validation"], "notes": "Tumor growth suppression caused by GP262, consistent with its action as a PI3K/mTOR degrader."}], "_routing": {"first_model": "gpt-4o-mini", "escalated": true, "final_model": "gpt-4.1", "reason": {"type": "validation_error", "details": ["mention[0] span mismatch: expected substring 'lation is implicated in various cancers. In this st' vs raw_text 'compound GP262 was identified as a potent dual-degrader of both PI3K and mTOR'", "mention[1] span mismatch: expected substring 'dy, a series of dual-target degraders simultaneou' vs raw_text 'achieved degradation through the ubiquitin-proteasome system (UPS)'", "mention[2] span mismatch: expected substring 'ompound GP262 was identified as a potent ' vs raw_text 'GP262’s significant tumor growth suppression capability'"]}, "mini_output": {"mentions": [{"raw_text": "compound GP262 was identified as a potent dual-degrader of both PI3K and mTOR", "category": "CHEMICAL_INHIBITOR", "span": {"start": 175, "end": 226}, "target_guess": null, "method_cues": [], "notes": null}, {"raw_text": "achieved degradation through the ubiquitin-proteasome system (UPS)", "category": "CHEMICAL_INHIBITOR", "span": {"start": 227, "end": 276}, "target_guess": null, "method_cues": [], "notes": null}, {"raw_text": "GP262’s significant tumor growth suppression capability", "category": "CHEMICAL_INHIBITOR", "span": {"start": 335, "end": 376}, "target_guess": null, "method_cues": [], "notes": null}]}}}

* * *

**ChatGPT:**

TAG: **PATHAI-0057** — You gave _enough_ JSON; what’s missing is just **2 new top-level fields** (doc_id + chunk_index)

You don’t need to paste more of the JSON for me to write the code—your single line shows the full record structure (`chunk_id`, `chunk_text`, `mentions`, `_routing`). ✅

What’s _not present_ (and what we need for safe within-paper bridging later) are two **new top-level fields**:

* `doc_id` (doc_id = a stable paper identifier like `PMID:xxxx`, `DOI:...`, or a filename/title hash)
* `chunk_index` (chunk_index = the chunk’s position within that paper: 0,1,2,… so “adjacent” is meaningful)

Example of how your record would look once those exist (only showing the added fields):

```JSON
{
  "doc_id": "PMID:12345678",
  "chunk_index": 0,
  "chunk_id": 1,
  "chunk_text": "...",
  "mentions": [...],
  "_routing": {...}
}
```

Since you want **doc_id implemented now but bridging OFF**, the clean solution is:

* implement the fields and carry them through,
* add a **switch** for bridging,
* and if `doc_id/chunk_index` are missing, bridging is automatically skipped (and logged) even if someone turns it on.

Below is the finalized script that does exactly that.

* * *

TAG: **PATHAI-0057** — **Final script** `make_atoms_docaware_v3.py` (doc_id support + bridging switch OFF by default)

```Python
#!/usr/bin/env python3
import os
import json
import re
import argparse
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple
from openai import OpenAI

# ============================================================
# DEFAULTS
# ============================================================
DEFAULT_INFILE = Path("mentions.jsonl")
DEFAULT_OUTFILE = Path("atoms.jsonl")

MODEL_FAST = "gpt-4o-mini"
MODEL_STRONG = "gpt-4.1"

MAX_ATOMS_PER_CHUNK = 30

# Bridging is OFF by default (safe for mixed/random chunk streams)
DEFAULT_ENABLE_BRIDGING = False

# ============================================================
# OPENAI CLIENT
# ============================================================
def _get_api_key() -> str:
    key = os.getenv("OPENAI_API_KEY")
    if not key:
        raise RuntimeError(
            "OPENAI_API_KEY is not set.\n"
            "Miniforge Prompt (temporary):  set OPENAI_API_KEY=YOUR_KEY\n"
            "Persistent (Windows):         setx OPENAI_API_KEY \"YOUR_KEY\"  (then reopen prompt)"
        )
    return key

client = OpenAI(api_key=_get_api_key())

# ============================================================
# STRICT JSON SCHEMA FOR ATOMS (model output)
# ============================================================
ATOM_SCHEMA_WRAPPER: Dict[str, Any] = {
    "name": "MechanisticAtoms",
    "schema": {
        "type": "object",
        "additionalProperties": False,
        "required": ["atoms", "warnings"],
        "properties": {
            "atoms": {
                "type": "array",
                "items": {
                    "type": "object",
                    "additionalProperties": False,
                    "required": [
                        "intervention",
                        "system",
                        "readout",
                        "effect",
                        "strength_cues",
                        "evidence",
                        "confidence",
                    ],
                    "properties": {
                        "intervention": {
                            "type": "object",
                            "additionalProperties": False,
                            "required": ["category", "raw_text", "target", "modality"],
                            "properties": {
                                "category": {
                                    "type": "string",
                                    "enum": [
                                        "GENETIC_KO",
                                        "CRISPR_KO",
                                        "CRISPRi",
                                        "CRISPRa",
                                        "KNOCKDOWN_RNAI",
                                        "SPLICING_MODULATION",
                                        "OVEREXPRESSION",
                                        "RESCUE_ADD_BACK",
                                        "DOMINANT_NEGATIVE",
                                        "MUTANT_VARIANT",
                                        "CHEMICAL_INHIBITOR",
                                        "CHEMICAL_ACTIVATOR",
                                        "CHEMICAL_DEGRADER",
                                        "STIMULUS_TREATMENT",
                                        "NEUTRALIZING_ANTIBODY",
                                        "UNKNOWN",
                                    ],
                                },
                                "raw_text": {"type": "string", "minLength": 1},
                                "target": {
                                    "anyOf": [
                                        {
                                            "type": "object",
                                            "additionalProperties": False,
                                            "required": ["name", "entity_type"],
                                            "properties": {
                                                "name": {"type": "string"},
                                                "entity_type": {
                                                    "type": "string",
                                                    "enum": [
                                                        "gene",
                                                        "protein",
                                                        "chemical",
                                                        "stimulus",
                                                        "antibody",
                                                        "unknown",
                                                    ],
                                                },
                                            },
                                        },
                                        {"type": "null"},
                                    ]
                                },
                                "modality": {
                                    "type": "string",
                                    "enum": [
                                        "LOF",
                                        "GOF",
                                        "INHIBITION",
                                        "ACTIVATION",
                                        "DEGRADATION",
                                        "RESCUE",
                                        "UNKNOWN",
                                    ],
                                },
                            },
                        },
                        "system": {
                            "type": "object",
                            "additionalProperties": False,
                            "required": [
                                "species",
                                "cell_type",
                                "cell_lines",
                                "genotype_context",
                                "disease_context",
                            ],
                            "properties": {
                                "species": {"type": ["string", "null"]},
                                "cell_type": {"type": ["string", "null"]},
                                "cell_lines": {"type": "array", "items": {"type": "string"}},
                                "genotype_context": {"type": ["string", "null"]},
                                "disease_context": {"type": ["string", "null"]},
                            },
                        },
                        "readout": {
                            "type": "object",
                            "additionalProperties": False,
                            "required": ["name", "assay", "figure_refs"],
                            "properties": {
                                "name": {"type": "string"},
                                "assay": {"type": ["string", "null"]},
                                "figure_refs": {"type": "array", "items": {"type": "string"}},
                            },
                        },
                        "effect": {
                            "type": "object",
                            "additionalProperties": False,
                            "required": ["direction", "timepoint", "magnitude", "comparison"],
                            "properties": {
                                "direction": {
                                    "type": "string",
                                    "enum": ["increase", "decrease", "no_change", "mixed", "unknown"],
                                },
                                "timepoint": {"type": ["string", "null"]},
                                "magnitude": {"type": ["string", "null"]},
                                "comparison": {"type": ["string", "null"]},
                            },
                        },
                        "strength_cues": {
                            "type": "object",
                            "additionalProperties": False,
                            "required": ["has_rescue", "has_control", "has_multiple_lines", "other"],
                            "properties": {
                                "has_rescue": {"type": "boolean"},
                                "has_control": {"type": "boolean"},
                                "has_multiple_lines": {"type": "boolean"},
                                "other": {"type": "array", "items": {"type": "string"}},
                            },
                        },
                        "evidence": {
                            "type": "object",
                            "additionalProperties": False,
                            "required": ["supporting_quote", "notes"],
                            "properties": {
                                "supporting_quote": {"type": "string"},
                                "notes": {"type": ["string", "null"]},
                            },
                        },
                        "confidence": {"type": "number", "minimum": 0, "maximum": 1},
                    },
                },
            },
            "warnings": {"type": "array", "items": {"type": "string"}},
        },
    },
}

# ============================================================
# LIGHTWEIGHT HINTS
# ============================================================
FIGREF_REGEX = re.compile(r"\b(Fig\.?\s*\d+[A-Za-z]?)\b", re.IGNORECASE)
SPECIES_REGEX = re.compile(r"\b(human|mouse|murine|rat)\b", re.IGNORECASE)

def _uniq_preserve(seq: List[str]) -> List[str]:
    seen = set()
    out = []
    for x in seq:
        k = x.lower()
        if k not in seen:
            seen.add(k)
            out.append(x)
    return out

def hint_figrefs(text: str) -> List[str]:
    return _uniq_preserve([m.group(1) for m in FIGREF_REGEX.finditer(text or "")])

def hint_species(text: str) -> Optional[str]:
    m = SPECIES_REGEX.search(text or "")
    if not m:
        return None
    s = m.group(1).lower()
    return "mouse" if s == "murine" else s

def compact_mentions(mentions: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    out = []
    for i, m in enumerate(mentions or [], start=1):
        out.append({
            "i": i,
            "category": m.get("category"),
            "raw_text": m.get("raw_text"),
            "target_guess": m.get("target_guess"),
            "method_cues": m.get("method_cues", []),
        })
    return out

# ============================================================
# PROMPT
# ============================================================
SYSTEM_INSTRUCTIONS = (
    "Extract 'mechanistic atoms' from biomedical text.\n\n"
    "Definition: an atom MUST include an explicit effect on a readout.\n"
    "Format: [INTERVENTION] causes [EFFECT] in [READOUT] in a [SYSTEM].\n\n"
    "Hard rules:\n"
    "1) Do NOT invent facts.\n"
    "2) Do NOT assume knockdown succeeded unless the text explicitly says reduction/knockdown/confirmed.\n"
    "3) If the text only describes delivering siRNA/plasmid/drug but gives no stated change in any readout, output no atoms and add a warning.\n"
    "4) You may extract multiple readouts per intervention if they are explicitly stated.\n"
    "5) Rescue/add-back atoms must state what readout is rescued.\n"
    f"6) Keep at most {MAX_ATOMS_PER_CHUNK} atoms.\n"
)

# ============================================================
# MODEL CALLS + ROUTING
# ============================================================
def call_model(model: str, chunk_text: str, mentions: List[Dict[str, Any]]) -> Dict[str, Any]:
    payload = {
        "chunk_text": chunk_text,
        "mentions": compact_mentions(mentions),
        "hints": {
            "fig_refs": hint_figrefs(chunk_text),
            "species": hint_species(chunk_text),
        }
    }
    resp = client.responses.create(
        model=model,
        input=[
            {"role": "system", "content": SYSTEM_INSTRUCTIONS},
            {"role": "user", "content": json.dumps(payload, ensure_ascii=False)},
        ],
        text={
            "format": {
                "type": "json_schema",
                "name": ATOM_SCHEMA_WRAPPER["name"],
                "strict": True,
                "schema": ATOM_SCHEMA_WRAPPER["schema"],
            }
        },
    )
    return json.loads(resp.output_text)

def should_escalate(mentions: List[Dict[str, Any]], atoms: List[Dict[str, Any]]) -> bool:
    if len(mentions) > 0 and len(atoms) == 0:
        return True
    if len(atoms) > 0:
        avg_conf = sum(float(a.get("confidence", 0.0)) for a in atoms) / len(atoms)
        if avg_conf < 0.55:
            return True
    return False

def extract_atoms_with_routing(chunk_text: str, mentions: List[Dict[str, Any]]) -> Dict[str, Any]:
    routing = {"first_model": MODEL_FAST, "escalated": False, "final_model": MODEL_FAST, "reason": None}
    out_fast = call_model(MODEL_FAST, chunk_text, mentions)
    atoms_fast = out_fast.get("atoms", [])

    if should_escalate(mentions, atoms_fast):
        routing["escalated"] = True
        routing["final_model"] = MODEL_STRONG
        routing["reason"] = {"type": "low_confidence_or_empty", "details": "heuristics triggered"}
        out_strong = call_model(MODEL_STRONG, chunk_text, mentions)
        out_strong["_routing"] = routing
        return out_strong

    out_fast["_routing"] = routing
    return out_fast

# ============================================================
# POST-FILTER: explicit effect cue must appear in supporting quote
# ============================================================
EFFECT_CUE = re.compile(
    r"\b("
    r"inhibit|inhibited|inhibition|suppress|suppressed|suppressing|"
    r"reduce|reduced|reduces|reduction|decrease|decreased|decreases|"
    r"increase|increased|increases|elevate|elevated|"
    r"no effect|did not affect|had no effect|"
    r"rescue|rescued|restored|restore|"
    r"complete inhibition|abolish|abolished"
    r")\b",
    re.IGNORECASE,
)
SETUP_ONLY_READOUT = re.compile(r"\b(expression|function|knockdown|silencing)\b", re.IGNORECASE)

def looks_like_setup_only(atoms: List[Dict[str, Any]], warnings: List[str]) -> bool:
    if not atoms:
        return True
    wtxt = " ".join(warnings or []).lower()
    if "no explicit functional readouts" in wtxt or "only describes" in wtxt:
        return True
    for a in atoms:
        ro = (a.get("readout", {}) or {}).get("name", "")
        sq = (a.get("evidence", {}) or {}).get("supporting_quote", "")
        if (not SETUP_ONLY_READOUT.search(ro or "")) and EFFECT_CUE.search(sq or ""):
            return False
    return True

def post_filter_atoms(atoms: List[Dict[str, Any]]) -> Tuple[List[Dict[str, Any]], int]:
    kept: List[Dict[str, Any]] = []
    dropped = 0
    for a in atoms or []:
        sq = (a.get("evidence", {}) or {}).get("supporting_quote", "")
        if EFFECT_CUE.search(sq or ""):
            kept.append(a)
        else:
            dropped += 1
    return kept, dropped

# ============================================================
# DOC-AWARE BRIDGING GUARD (only same doc_id + adjacent chunk_index)
# ============================================================
def can_bridge_same_doc_adjacent(a: Dict[str, Any], b: Dict[str, Any]) -> Tuple[bool, str]:
    a_doc = a.get("doc_id")
    b_doc = b.get("doc_id")
    if not a_doc or not b_doc:
        return False, "missing_doc_id"
    if a_doc != b_doc:
        return False, "doc_id_mismatch"

    a_idx = a.get("chunk_index")
    b_idx = b.get("chunk_index")
    if a_idx is None or b_idx is None:
        return False, "missing_chunk_index"
    try:
        ai = int(a_idx)
        bi = int(b_idx)
    except Exception:
        return False, "non_integer_chunk_index"
    if abs(ai - bi) != 1:
        return False, "non_adjacent_chunk_index"
    return True, "ok"

def bridge_text(a_text: str, b_text: str) -> str:
    return (a_text or "").rstrip() + "\n\n" + (b_text or "").lstrip()

def bridge_mentions(a_mentions: List[Dict[str, Any]], b_mentions: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    return list(a_mentions or []) + list(b_mentions or [])

def choose_best_bridged(candidates: List[Tuple[str, Dict[str, Any], List[int], List[str]]]) -> Optional[Tuple[str, Dict[str, Any], List[int], List[str]]]:
    best = None
    for mode, outd, src_chunks, src_docs in candidates:
        atoms = outd.get("atoms", []) or []
        if best is None:
            best = (mode, outd, src_chunks, src_docs)
            continue
        best_atoms = best[1].get("atoms", []) or []
        if len(atoms) > len(best_atoms):
            best = (mode, outd, src_chunks, src_docs)
        elif len(atoms) == len(best_atoms) and len(atoms) > 0:
            avg = sum(float(a.get("confidence", 0.0)) for a in atoms) / len(atoms)
            bavg = sum(float(a.get("confidence", 0.0)) for a in best_atoms) / len(best_atoms)
            if avg > bavg:
                best = (mode, outd, src_chunks, src_docs)
    return best

# ============================================================
# MAIN
# ============================================================
def main() -> int:
    ap = argparse.ArgumentParser(description="PATHAI atoms extraction with doc_id support and safe bridging switch")
    ap.add_argument("--infile", default=str(DEFAULT_INFILE), help="Input mentions.jsonl")
    ap.add_argument("--outfile", default=str(DEFAULT_OUTFILE), help="Output atoms.jsonl")

    ap.add_argument(
        "--bridge",
        action="store_true",
        help="Enable bridging (safe: only within same doc_id AND adjacent chunk_index). Default OFF.",
    )

    ap.add_argument(
        "--default_doc_id",
        default=None,
        help="If a record lacks doc_id, set it to this value (useful when processing one paper at a time).",
    )

    ap.add_argument(
        "--assign_chunk_index",
        action="store_true",
        help="If a record lacks chunk_index, assign sequential indices within each doc_id as encountered in file order.",
    )

    ap.add_argument("--no_bridge_forward", action="store_true", help="Disable forward bridging (if --bridge is set).")
    ap.add_argument("--no_bridge_backward", action="store_true", help="Disable backward bridging (if --bridge is set).")

    args = ap.parse_args()

    infile = Path(args.infile)
    outfile = Path(args.outfile)

    enable_bridging = bool(args.bridge)
    try_forward = (not args.no_bridge_forward)
    try_backward = (not args.no_bridge_backward)

    if not infile.exists():
        raise FileNotFoundError(f"Cannot find {infile.resolve()}")

    # Load records
    records: List[Dict[str, Any]] = []
    for ln in infile.read_text(encoding="utf-8", errors="ignore").splitlines():
        ln = ln.strip()
        if not ln:
            continue
        records.append(json.loads(ln))

    # Optionally inject doc_id + assign chunk_index deterministically
    if args.default_doc_id:
        for r in records:
            if not r.get("doc_id"):
                r["doc_id"] = args.default_doc_id

    if args.assign_chunk_index:
        # Assign sequential chunk_index per doc_id in file order (only for records missing chunk_index)
        counters: Dict[str, int] = {}
        for r in records:
            doc = r.get("doc_id")
            if not doc:
                continue
            if r.get("chunk_index") is None:
                counters.setdefault(doc, 0)
                r["chunk_index"] = counters[doc]
                counters[doc] += 1

    total_atoms = 0
    escalations = 0
    bridges_used = 0
    bridges_attempted = 0
    dropped_total = 0

    with outfile.open("w", encoding="utf-8", newline="\n") as fout:
        for idx, rec in enumerate(records):
            chunk_id = rec.get("chunk_id")
            doc_id = rec.get("doc_id")
            chunk_index = rec.get("chunk_index")

            if "error" in rec:
                out_rec = {
                    "doc_id": doc_id,
                    "chunk_index": chunk_index,
                    "chunk_id": chunk_id,
                    "atoms": [],
                    "warnings": ["Skipped due to upstream error."],
                    "bridge": {
                        "enabled": enable_bridging,
                        "attempted": False,
                        "used": False,
                        "mode": None,
                        "source_doc_ids": [doc_id] if doc_id else [],
                        "source_chunk_ids": [chunk_id],
                        "skipped_reason": "upstream_error",
                    },
                    "_routing": {"skipped": True},
                    "_post": {"dropped_atoms": 0},
                }
                fout.write(json.dumps(out_rec, ensure_ascii=False) + "\n")
                continue

            chunk_text = rec.get("chunk_text", "")
            mentions = rec.get("mentions", [])

            out = extract_atoms_with_routing(chunk_text, mentions)
            atoms = out.get("atoms", []) or []
            warnings = out.get("warnings", []) or []
            routing = out.get("_routing", {}) or {}

            atoms, dropped = post_filter_atoms(atoms)
            dropped_total += dropped

            used_bridge = False
            attempted_bridge = False
            bridge_mode = None
            skipped_reason = None
            source_chunk_ids = [chunk_id]
            source_doc_ids = [doc_id] if doc_id else []

            need_bridge = (len(mentions or []) > 0 and (len(atoms) == 0 or looks_like_setup_only(atoms, warnings)))

            if enable_bridging and need_bridge:
                attempted_bridge = True
                bridges_attempted += 1
                candidates: List[Tuple[str, Dict[str, Any], List[int], List[str]]] = []

                # forward candidate
                if try_forward and idx + 1 < len(records):
                    nxt = records[idx + 1]
                    ok, why = can_bridge_same_doc_adjacent(rec, nxt)
                    if ok and "error" not in nxt:
                        t = bridge_text(chunk_text, nxt.get("chunk_text", ""))
                        m = bridge_mentions(mentions, nxt.get("mentions", []))
                        bout = extract_atoms_with_routing(t, m)
                        batoms = bout.get("atoms", []) or []
                        bwarn = bout.get("warnings", []) or []
                        batoms, bdropped = post_filter_atoms(batoms)
                        bout["atoms"] = batoms
                        bout["warnings"] = bwarn
                        bout["_post"] = {"dropped_atoms": bdropped}
                        candidates.append((
                            "forward",
                            bout,
                            [chunk_id, nxt.get("chunk_id")],
                            [rec.get("doc_id"), nxt.get("doc_id")],
                        ))
                    else:
                        skipped_reason = skipped_reason or f"forward_{why}"

                # backward candidate
                if try_backward and idx - 1 >= 0:
                    prv = records[idx - 1]
                    ok, why = can_bridge_same_doc_adjacent(prv, rec)
                    if ok and "error" not in prv:
                        t = bridge_text(prv.get("chunk_text", ""), chunk_text)
                        m = bridge_mentions(prv.get("mentions", []), mentions)
                        bout = extract_atoms_with_routing(t, m)
                        batoms = bout.get("atoms", []) or []
                        bwarn = bout.get("warnings", []) or []
                        batoms, bdropped = post_filter_atoms(batoms)
                        bout["atoms"] = batoms
                        bout["warnings"] = bwarn
                        bout["_post"] = {"dropped_atoms": bdropped}
                        candidates.append((
                            "backward",
                            bout,
                            [prv.get("chunk_id"), chunk_id],
                            [prv.get("doc_id"), rec.get("doc_id")],
                        ))
                    else:
                        skipped_reason = skipped_reason or f"backward_{why}"

                best = choose_best_bridged(candidates)
                if best is not None and len(best[1].get("atoms", []) or []) > 0:
                    used_bridge = True
                    bridge_mode = best[0]
                    out = best[1]
                    atoms = out.get("atoms", []) or []
                    warnings = out.get("warnings", []) or []
                    routing = out.get("_routing", routing) or routing
                    source_chunk_ids = best[2]
                    source_doc_ids = [d for d in best[3] if d]
                    bridges_used += 1
                else:
                    if skipped_reason is None:
                        skipped_reason = "no_viable_bridge_candidate"

            if routing.get("escalated"):
                escalations += 1

            total_atoms += len(atoms)

            out_rec = {
                "doc_id": doc_id,
                "chunk_index": chunk_index,
                "chunk_id": chunk_id,
                "atoms": atoms,
                "warnings": warnings,
                "bridge": {
                    "enabled": enable_bridging,
                    "attempted": attempted_bridge,
                    "used": used_bridge,
                    "mode": bridge_mode,
                    "source_doc_ids": source_doc_ids,
                    "source_chunk_ids": source_chunk_ids,
                    "skipped_reason": skipped_reason,
                },
                "_routing": routing,
                "_post": {"dropped_atoms": dropped},
            }

            fout.write(json.dumps(out_rec, ensure_ascii=False) + "\n")

            print(
                f"chunk {chunk_id} doc_id={doc_id} idx={chunk_index} "
                f"atoms={len(atoms)} escalated={routing.get('escalated', False)} "
                f"bridge_enabled={enable_bridging} bridged={used_bridge} dropped={dropped}"
            )

    print(
        f"Done. total_atoms={total_atoms}, escalations={escalations}, "
        f"bridges_attempted={bridges_attempted}, bridges_used={bridges_used}, dropped_total={dropped_total}"
    )
    if not enable_bridging:
        print("Note: bridging was OFF (recommended for mixed/random chunks).")
    else:
        print("Note: bridging ON uses strict guard: same doc_id + adjacent chunk_index.")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
```

* * *

## How you run it **right now** (doc-aware, bridging OFF)

```bat
conda activate pathai
cd "C:\Users\Prem Subramaniam\Documents\Pathway AI"
python make_atoms_docaware_v3.py
```

## If you process **one paper at a time** and want to set a doc_id (still bridging OFF)

```bat
python make_atoms_docaware_v3.py --default_doc_id "PMID:12345678"
```

## Later, when you have ordered chunks per paper and want safe bridging

```bat
python make_atoms_docaware_v3.py --bridge --assign_chunk_index
```

### Bottom line (what I need from you)

* For _this code_: nothing more than the line you pasted. ✅
* For _safe bridging later_: you’ll need your pipeline to include (or inject) `doc_id` and `chunk_index` per record. Those two fields are the only “extra JSON” required.

If you paste **one more line** from the same `mentions.jsonl` file (chunk 2), I can confirm whether your file is currently ordered in a way where `--assign_chunk_index` would be meaningful, or whether you should only set doc_id during per-paper processing.

* * *

**You:**

Here is the second line of mentions: {"chunk_id": 2, "chunk_text": "The mammalian target of rapamycin (mTOR), a serine/threonine kinase, promotes cell growth and inhibits autophagy. The following two complexes contain mTOR: mTORC1 with the regulatory associated protein of mTOR (RAPTOR) and mTORC2 with the rapamycin-insensitive companion of mTOR (RICTOR). The phosphatidylinositol 3-kinase (PI3K)/Akt/mTOR signaling pathway is important in the intervertebral disk, which is the largest avascular, hypoxic, low-nutrient organ in the body. To examine gene-silencing therapeutic approaches targeting PI3K/Akt/mTOR signaling in degenerative disk cells, an in vitro comparative study was designed between small interfering RNA (siRNA)-mediated RNA interference (RNAi) and clustered regularly interspaced short palindromic repeat (CRISPR)–CRISPR-associated protein 9 (Cas9) gene editing. Surgically obtained human disk nucleus pulposus cells were transfected with a siRNA or CRISPR–Cas9 plasmid targeting mTOR, RAPTOR, or RICTOR. Both of the approaches specifically suppressed target protein expression; however, the 24-h transfection efficiency differed by 53.8–60.3% for RNAi and 88.1–89.3% for CRISPR–Cas9 (p < 0.0001). Targeting mTOR, RAPTOR, and RICTOR all induced autophagy and inhibited apoptosis, senescence, pyroptosis, and matrix catabolism, with the most prominent effects observed with RAPTOR CRISPR–Cas9. In the time-course analysis, the 168-h suppression ratio of RAPTOR protein expression was 83.2% by CRISPR–Cas9 but only 8.8% by RNAi. While RNAi facilitates transient gene knockdown, CRISPR–Cas9 provides extensive gene knockout. Our findings suggest that RAPTOR/mTORC1 is a potential therapeutic target for degenerative disk disease.", "mentions": [{"raw_text": "siRNA or CRISPR–Cas9 plasmid targeting mTOR, RAPTOR, or RICTOR", "category": "KNOCKDOWN_RNAI", "span": {"start": 417, "end": 464}, "target_guess": {"name": "mTOR, RAPTOR, or RICTOR", "entity_type": "protein"}, "method_cues": ["siRNA", "transfected", "RNA interference (RNAi)"], "notes": null}, {"raw_text": "CRISPR–Cas9 plasmid targeting mTOR, RAPTOR, or RICTOR", "category": "CRISPR_KO", "span": {"start": 430, "end": 480}, "target_guess": {"name": "mTOR, RAPTOR, or RICTOR", "entity_type": "protein"}, "method_cues": ["CRISPR", "CRISPR–Cas9", "transfected", "gene editing"], "notes": null}], "_routing": {"first_model": "gpt-4o-mini", "escalated": true, "final_model": "gpt-4.1", "reason": {"type": "validation_error", "details": ["mention[0] span mismatch: expected substring 'he phosphatidylinositol 3-kinase (PI3K)' vs raw_text 'siRNA-mediated RNA interference (RNAi)'", "mention[1] span mismatch: expected substring 'TOR signaling pathway ' vs raw_text 'CRISPR–Cas9 gene editing'", "mention[2] span mismatch: expected substring 'the intervertebral disk, which is the largest avascular, hypoxic, ' vs raw_text 'siRNA or CRISPR–Cas9 plasmid targeting mTOR, RAPTOR, or RICTOR'", "mention[3] span mismatch: expected substring 'utrient organ in the body. To' vs raw_text 'suppressed target protein expression'", "mention[4] span mismatch: expected substring 'R signaling in de' vs raw_text 'RAPTOR CRISPR–Cas9'", "mention[5] span mismatch: expected substring 'ween small interfering RNA (siR' vs raw_text 'CRISPR–Cas9 provides extensive gene knockout'", "mention[6] span mismatch: expected substring ' interference (RNAi) and clustered ' vs raw_text 'RAPTOR protein expression was 83.2% by CRISPR–Cas9'"]}, "mini_output": {"mentions": [{"raw_text": "siRNA-mediated RNA interference (RNAi)", "category": "KNOCKDOWN_RNAI", "span": {"start": 290, "end": 329}, "target_guess": {"name": "siRNA", "entity_type": "unknown"}, "method_cues": [], "notes": null}, {"raw_text": "CRISPR–Cas9 gene editing", "category": "CRISPR_KO", "span": {"start": 335, "end": 357}, "target_guess": {"name": "CRISPR-Cas9", "entity_type": "unknown"}, "method_cues": [], "notes": null}, {"raw_text": "siRNA or CRISPR–Cas9 plasmid targeting mTOR, RAPTOR, or RICTOR", "category": "CRISPR_KO", "span": {"start": 373, "end": 439}, "target_guess": null, "method_cues": [], "notes": null}, {"raw_text": "suppressed target protein expression", "category": "UNKNOWN", "span": {"start": 444, "end": 473}, "target_guess": null, "method_cues": [], "notes": null}, {"raw_text": "RAPTOR CRISPR–Cas9", "category": "CRISPR_KO", "span": {"start": 542, "end": 559}, "target_guess": {"name": "RAPTOR", "entity_type": "gene"}, "method_cues": [], "notes": null}, {"raw_text": "CRISPR–Cas9 provides extensive gene knockout", "category": "CRISPR_KO", "span": {"start": 628, "end": 659}, "target_guess": null, "method_cues": [], "notes": null}, {"raw_text": "RAPTOR protein expression was 83.2% by CRISPR–Cas9", "category": "CRISPR_KO", "span": {"start": 675, "end": 710}, "target_guess": null, "method_cues": [], "notes": null}]}}}

* * *

**ChatGPT:**

TAG: **PATHAI-0058** — What your 2nd line tells us about `doc_id`, `chunk_index`, and bridging

Thanks — with chunk 1 and chunk 2 side-by-side, it’s very clear they’re **not from the same paper** (chunk 1 is about a dual PI3K/mTOR degrader “GP262” in breast cancer/leukemia; chunk 2 is about disk nucleus pulposus cells, RNAi vs CRISPR, autophagy/apoptosis, degenerative disk disease). That means:

* **Bridging must stay OFF** for this current mixed/random stream, even though the audit looks great.
* And you **must not** assign one shared `doc_id` to this whole file, because that would incorrectly make chunk 1 and chunk 2 “same doc,” which would make bridging _eligible_ when it shouldn’t be.

### How much more JSON do we need?

You’ve already provided the full structure we need. The only “more” needed for doc-aware behavior later is adding **two top-level fields** to each record:

* `doc_id` (doc_id = a stable paper identifier like `PMID:xxxx`, `DOI:...`, or a filename-based ID)
* `chunk_index` (chunk_index = the order of the chunk _within that paper_, starting at 0 and increasing)

Nothing else is required.

### Is `--assign_chunk_index` meaningful right now?

Not with the current file as shown.

`chunk_id: 1, 2, 3...` here is just an index in your JSONL file, but the _content_ is already from different papers, so assigning sequential `chunk_index` would be **meaningless** unless you first group chunks by `doc_id`.

### The scalable workflow you described (and it’s the right one)

1. **Within each paper**: allow bridging **only** among chunks with the same `doc_id` and adjacent `chunk_index`.
2. **Across papers**: integrate evidence by counting independent support across distinct `doc_id`s (i.e., multiple papers supporting the same edge makes it stronger).

### What to do now

* Implement the `doc_id` field in your ingestion (PubMed gives you **PMID** reliably; many papers also have DOI).
* For now, keep **bridging OFF by default** until your `mentions.jsonl` is organized by `doc_id` and has per-paper `chunk_index`.

If you want a concrete rule for `doc_id` now:

* Prefer `PMID:<number>` when available (most robust for PubMed).
* Else `DOI:<doi-string>`.
* Else a stable fallback like `FILE:<pdf_filename>` (or a hash of it), as long as it’s consistent per paper.

Once you start ingesting by paper (or at least tagging each chunk with the paper’s PMID/DOI), bridging becomes safe and scalable immediately.

* * *

**You:**

o please add the code in appropriate place as needed to acheive this: If you want a concrete rule for doc_id now:

Prefer PMID:<number> when available (most robust for PubMed).

Else DOI:<doi-string>.

Else a stable fallback like FILE:<pdf_filename> (or a hash of it), as long as it’s consistent per paper.

* * *

**ChatGPT:**

TAG: **PATHAI-0059** — Final update: **auto-derive `doc_id`** using PMID → DOI → FILE fallback (bridging still OFF by default)

Below is the full script with the requested `doc_id` rule added **in the right place** (during record loading, before any extraction/bridging). It will:

* If `doc_id` is already present in a record: keep it.
* Else try to derive:
    1. `PMID:<number>`
    2. `DOI:<doi-string>`
    3. `FILE:<pdf_filename>` (basename only)
    4. Optional last-resort: `TITLEHASH:<hash>` if a title exists
* If none found: leaves `doc_id` as `null` (and bridging remains safe because it won’t run without doc_id + chunk_index).

Save as **`make_atoms_docaware_v4.py`**.

```Python
#!/usr/bin/env python3
import os
import json
import re
import argparse
import hashlib
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple
from openai import OpenAI

# ============================================================
# DEFAULTS
# ============================================================
DEFAULT_INFILE = Path("mentions.jsonl")
DEFAULT_OUTFILE = Path("atoms.jsonl")

MODEL_FAST = "gpt-4o-mini"
MODEL_STRONG = "gpt-4.1"

MAX_ATOMS_PER_CHUNK = 30

# Bridging is OFF by default (safe for mixed/random chunk streams)
DEFAULT_ENABLE_BRIDGING = False

# ============================================================
# OPENAI CLIENT
# ============================================================
def _get_api_key() -> str:
    key = os.getenv("OPENAI_API_KEY")
    if not key:
        raise RuntimeError(
            "OPENAI_API_KEY is not set.\n"
            "Miniforge Prompt (temporary):  set OPENAI_API_KEY=YOUR_KEY\n"
            "Persistent (Windows):         setx OPENAI_API_KEY \"YOUR_KEY\"  (then reopen prompt)"
        )
    return key

client = OpenAI(api_key=_get_api_key())

# ============================================================
# STRICT JSON SCHEMA FOR ATOMS (model output)
# ============================================================
ATOM_SCHEMA_WRAPPER: Dict[str, Any] = {
    "name": "MechanisticAtoms",
    "schema": {
        "type": "object",
        "additionalProperties": False,
        "required": ["atoms", "warnings"],
        "properties": {
            "atoms": {
                "type": "array",
                "items": {
                    "type": "object",
                    "additionalProperties": False,
                    "required": [
                        "intervention",
                        "system",
                        "readout",
                        "effect",
                        "strength_cues",
                        "evidence",
                        "confidence",
                    ],
                    "properties": {
                        "intervention": {
                            "type": "object",
                            "additionalProperties": False,
                            "required": ["category", "raw_text", "target", "modality"],
                            "properties": {
                                "category": {
                                    "type": "string",
                                    "enum": [
                                        "GENETIC_KO",
                                        "CRISPR_KO",
                                        "CRISPRi",
                                        "CRISPRa",
                                        "KNOCKDOWN_RNAI",
                                        "SPLICING_MODULATION",
                                        "OVEREXPRESSION",
                                        "RESCUE_ADD_BACK",
                                        "DOMINANT_NEGATIVE",
                                        "MUTANT_VARIANT",
                                        "CHEMICAL_INHIBITOR",
                                        "CHEMICAL_ACTIVATOR",
                                        "CHEMICAL_DEGRADER",
                                        "STIMULUS_TREATMENT",
                                        "NEUTRALIZING_ANTIBODY",
                                        "UNKNOWN",
                                    ],
                                },
                                "raw_text": {"type": "string", "minLength": 1},
                                "target": {
                                    "anyOf": [
                                        {
                                            "type": "object",
                                            "additionalProperties": False,
                                            "required": ["name", "entity_type"],
                                            "properties": {
                                                "name": {"type": "string"},
                                                "entity_type": {
                                                    "type": "string",
                                                    "enum": [
                                                        "gene",
                                                        "protein",
                                                        "chemical",
                                                        "stimulus",
                                                        "antibody",
                                                        "unknown",
                                                    ],
                                                },
                                            },
                                        },
                                        {"type": "null"},
                                    ]
                                },
                                "modality": {
                                    "type": "string",
                                    "enum": [
                                        "LOF",
                                        "GOF",
                                        "INHIBITION",
                                        "ACTIVATION",
                                        "DEGRADATION",
                                        "RESCUE",
                                        "UNKNOWN",
                                    ],
                                },
                            },
                        },
                        "system": {
                            "type": "object",
                            "additionalProperties": False,
                            "required": [
                                "species",
                                "cell_type",
                                "cell_lines",
                                "genotype_context",
                                "disease_context",
                            ],
                            "properties": {
                                "species": {"type": ["string", "null"]},
                                "cell_type": {"type": ["string", "null"]},
                                "cell_lines": {"type": "array", "items": {"type": "string"}},
                                "genotype_context": {"type": ["string", "null"]},
                                "disease_context": {"type": ["string", "null"]},
                            },
                        },
                        "readout": {
                            "type": "object",
                            "additionalProperties": False,
                            "required": ["name", "assay", "figure_refs"],
                            "properties": {
                                "name": {"type": "string"},
                                "assay": {"type": ["string", "null"]},
                                "figure_refs": {"type": "array", "items": {"type": "string"}},
                            },
                        },
                        "effect": {
                            "type": "object",
                            "additionalProperties": False,
                            "required": ["direction", "timepoint", "magnitude", "comparison"],
                            "properties": {
                                "direction": {
                                    "type": "string",
                                    "enum": ["increase", "decrease", "no_change", "mixed", "unknown"],
                                },
                                "timepoint": {"type": ["string", "null"]},
                                "magnitude": {"type": ["string", "null"]},
                                "comparison": {"type": ["string", "null"]},
                            },
                        },
                        "strength_cues": {
                            "type": "object",
                            "additionalProperties": False,
                            "required": ["has_rescue", "has_control", "has_multiple_lines", "other"],
                            "properties": {
                                "has_rescue": {"type": "boolean"},
                                "has_control": {"type": "boolean"},
                                "has_multiple_lines": {"type": "boolean"},
                                "other": {"type": "array", "items": {"type": "string"}},
                            },
                        },
                        "evidence": {
                            "type": "object",
                            "additionalProperties": False,
                            "required": ["supporting_quote", "notes"],
                            "properties": {
                                "supporting_quote": {"type": "string"},
                                "notes": {"type": ["string", "null"]},
                            },
                        },
                        "confidence": {"type": "number", "minimum": 0, "maximum": 1},
                    },
                },
            },
            "warnings": {"type": "array", "items": {"type": "string"}},
        },
    },
}

# ============================================================
# LIGHTWEIGHT HINTS
# ============================================================
FIGREF_REGEX = re.compile(r"\b(Fig\.?\s*\d+[A-Za-z]?)\b", re.IGNORECASE)
SPECIES_REGEX = re.compile(r"\b(human|mouse|murine|rat)\b", re.IGNORECASE)

def _uniq_preserve(seq: List[str]) -> List[str]:
    seen = set()
    out = []
    for x in seq:
        k = x.lower()
        if k not in seen:
            seen.add(k)
            out.append(x)
    return out

def hint_figrefs(text: str) -> List[str]:
    return _uniq_preserve([m.group(1) for m in FIGREF_REGEX.finditer(text or "")])

def hint_species(text: str) -> Optional[str]:
    m = SPECIES_REGEX.search(text or "")
    if not m:
        return None
    s = m.group(1).lower()
    return "mouse" if s == "murine" else s

def compact_mentions(mentions: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    out = []
    for i, m in enumerate(mentions or [], start=1):
        out.append({
            "i": i,
            "category": m.get("category"),
            "raw_text": m.get("raw_text"),
            "target_guess": m.get("target_guess"),
            "method_cues": m.get("method_cues", []),
        })
    return out

# ============================================================
# DOC_ID DERIVATION (PMID → DOI → FILE → TITLEHASH)
# ============================================================
_DOI_PREFIX_RE = re.compile(r"^(https?://(dx\.)?doi\.org/|doi:\s*)", re.IGNORECASE)

def _stable_hash(text: str, n: int = 12) -> str:
    return hashlib.sha1(text.encode("utf-8")).hexdigest()[:n]

def _get_nested(rec: Dict[str, Any], path: List[str]) -> Optional[Any]:
    cur: Any = rec
    for k in path:
        if not isinstance(cur, dict) or k not in cur:
            return None
        cur = cur[k]
    return cur

def _first_str_value(rec: Dict[str, Any], key_paths: List[List[str]]) -> Optional[str]:
    for path in key_paths:
        v = _get_nested(rec, path)
        if isinstance(v, str) and v.strip():
            return v.strip()
    return None

def _first_intish_value(rec: Dict[str, Any], key_paths: List[List[str]]) -> Optional[str]:
    """
    Return digits-only string if a PMID-like field exists.
    """
    for path in key_paths:
        v = _get_nested(rec, path)
        if v is None:
            continue
        if isinstance(v, int):
            return str(v)
        if isinstance(v, str):
            s = v.strip()
            m = re.search(r"\d+", s)
            if m:
                return m.group(0)
    return None

def derive_doc_id(rec: Dict[str, Any]) -> Optional[str]:
    """
    Prefer PMID:<number> when available.
    Else DOI:<doi-string>.
    Else FILE:<pdf_filename> (basename).
    Else TITLEHASH:<hash> if title exists.
    Else None.
    """
    # 1) PMID
    pmid = _first_intish_value(rec, [
        ["pmid"], ["PMID"], ["pubmed_id"], ["pubmedId"], ["PubMedID"],
        ["metadata", "pmid"], ["metadata", "PMID"], ["paper", "pmid"], ["paper", "PMID"],
    ])
    if pmid:
        return f"PMID:{pmid}"

    # 2) DOI
    doi = _first_str_value(rec, [
        ["doi"], ["DOI"], ["metadata", "doi"], ["metadata", "DOI"], ["paper", "doi"], ["paper", "DOI"],
    ])
    if doi:
        doi2 = _DOI_PREFIX_RE.sub("", doi).strip()
        return f"DOI:{doi2}"

    # 3) FILE basename
    file_path = _first_str_value(rec, [
        ["source_file"], ["file"], ["filename"], ["pdf_file"],
        ["source", "file"], ["_source", "file"], ["metadata", "file"], ["metadata", "filename"],
    ])
    if file_path:
        name = Path(file_path).name.strip()
        if name:
            return f"FILE:{name}"
        return f"FILEHASH:{_stable_hash(file_path)}"

    # 4) TITLEHASH
    title = _first_str_value(rec, [
        ["title"], ["paper_title"], ["metadata", "title"], ["paper", "title"],
    ])
    if title:
        return f"TITLEHASH:{_stable_hash(title.lower().strip())}"

    return None

# ============================================================
# PROMPT
# ============================================================
SYSTEM_INSTRUCTIONS = (
    "Extract 'mechanistic atoms' from biomedical text.\n\n"
    "Definition: an atom MUST include an explicit effect on a readout.\n"
    "Format: [INTERVENTION] causes [EFFECT] in [READOUT] in a [SYSTEM].\n\n"
    "Hard rules:\n"
    "1) Do NOT invent facts.\n"
    "2) Do NOT assume knockdown succeeded unless the text explicitly says reduction/knockdown/confirmed.\n"
    "3) If the text only describes delivering siRNA/plasmid/drug but gives no stated change in any readout, output no atoms and add a warning.\n"
    "4) You may extract multiple readouts per intervention if they are explicitly stated.\n"
    "5) Rescue/add-back atoms must state what readout is rescued.\n"
    f"6) Keep at most {MAX_ATOMS_PER_CHUNK} atoms.\n"
)

# ============================================================
# MODEL CALLS + ROUTING
# ============================================================
def call_model(model: str, chunk_text: str, mentions: List[Dict[str, Any]]) -> Dict[str, Any]:
    payload = {
        "chunk_text": chunk_text,
        "mentions": compact_mentions(mentions),
        "hints": {
            "fig_refs": hint_figrefs(chunk_text),
            "species": hint_species(chunk_text),
        }
    }
    resp = client.responses.create(
        model=model,
        input=[
            {"role": "system", "content": SYSTEM_INSTRUCTIONS},
            {"role": "user", "content": json.dumps(payload, ensure_ascii=False)},
        ],
        text={
            "format": {
                "type": "json_schema",
                "name": ATOM_SCHEMA_WRAPPER["name"],
                "strict": True,
                "schema": ATOM_SCHEMA_WRAPPER["schema"],
            }
        },
    )
    return json.loads(resp.output_text)

def should_escalate(mentions: List[Dict[str, Any]], atoms: List[Dict[str, Any]]) -> bool:
    if len(mentions) > 0 and len(atoms) == 0:
        return True
    if len(atoms) > 0:
        avg_conf = sum(float(a.get("confidence", 0.0)) for a in atoms) / len(atoms)
        if avg_conf < 0.55:
            return True
    return False

def extract_atoms_with_routing(chunk_text: str, mentions: List[Dict[str, Any]]) -> Dict[str, Any]:
    routing = {"first_model": MODEL_FAST, "escalated": False, "final_model": MODEL_FAST, "reason": None}
    out_fast = call_model(MODEL_FAST, chunk_text, mentions)
    atoms_fast = out_fast.get("atoms", [])

    if should_escalate(mentions, atoms_fast):
        routing["escalated"] = True
        routing["final_model"] = MODEL_STRONG
        routing["reason"] = {"type": "low_confidence_or_empty", "details": "heuristics triggered"}
        out_strong = call_model(MODEL_STRONG, chunk_text, mentions)
        out_strong["_routing"] = routing
        return out_strong

    out_fast["_routing"] = routing
    return out_fast

# ============================================================
# POST-FILTER: explicit effect cue must appear in supporting quote
# ============================================================
EFFECT_CUE = re.compile(
    r"\b("
    r"inhibit|inhibited|inhibition|suppress|suppressed|suppressing|"
    r"reduce|reduced|reduces|reduction|decrease|decreased|decreases|"
    r"increase|increased|increases|elevate|elevated|"
    r"no effect|did not affect|had no effect|"
    r"rescue|rescued|restored|restore|"
    r"complete inhibition|abolish|abolished"
    r")\b",
    re.IGNORECASE,
)
SETUP_ONLY_READOUT = re.compile(r"\b(expression|function|knockdown|silencing)\b", re.IGNORECASE)

def looks_like_setup_only(atoms: List[Dict[str, Any]], warnings: List[str]) -> bool:
    if not atoms:
        return True
    wtxt = " ".join(warnings or []).lower()
    if "no explicit functional readouts" in wtxt or "only describes" in wtxt:
        return True
    for a in atoms:
        ro = (a.get("readout", {}) or {}).get("name", "")
        sq = (a.get("evidence", {}) or {}).get("supporting_quote", "")
        if (not SETUP_ONLY_READOUT.search(ro or "")) and EFFECT_CUE.search(sq or ""):
            return False
    return True

def post_filter_atoms(atoms: List[Dict[str, Any]]) -> Tuple[List[Dict[str, Any]], int]:
    kept: List[Dict[str, Any]] = []
    dropped = 0
    for a in atoms or []:
        sq = (a.get("evidence", {}) or {}).get("supporting_quote", "")
        if EFFECT_CUE.search(sq or ""):
            kept.append(a)
        else:
            dropped += 1
    return kept, dropped

# ============================================================
# DOC-AWARE BRIDGING GUARD (only same doc_id + adjacent chunk_index)
# ============================================================
def can_bridge_same_doc_adjacent(a: Dict[str, Any], b: Dict[str, Any]) -> Tuple[bool, str]:
    a_doc = a.get("doc_id")
    b_doc = b.get("doc_id")
    if not a_doc or not b_doc:
        return False, "missing_doc_id"
    if a_doc != b_doc:
        return False, "doc_id_mismatch"

    a_idx = a.get("chunk_index")
    b_idx = b.get("chunk_index")
    if a_idx is None or b_idx is None:
        return False, "missing_chunk_index"
    try:
        ai = int(a_idx)
        bi = int(b_idx)
    except Exception:
        return False, "non_integer_chunk_index"
    if abs(ai - bi) != 1:
        return False, "non_adjacent_chunk_index"
    return True, "ok"

def bridge_text(a_text: str, b_text: str) -> str:
    return (a_text or "").rstrip() + "\n\n" + (b_text or "").lstrip()

def bridge_mentions(a_mentions: List[Dict[str, Any]], b_mentions: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    return list(a_mentions or []) + list(b_mentions or [])

def choose_best_bridged(candidates: List[Tuple[str, Dict[str, Any], List[int], List[str]]]) -> Optional[Tuple[str, Dict[str, Any], List[int], List[str]]]:
    best = None
    for mode, outd, src_chunks, src_docs in candidates:
        atoms = outd.get("atoms", []) or []
        if best is None:
            best = (mode, outd, src_chunks, src_docs)
            continue
        best_atoms = best[1].get("atoms", []) or []
        if len(atoms) > len(best_atoms):
            best = (mode, outd, src_chunks, src_docs)
        elif len(atoms) == len(best_atoms) and len(atoms) > 0:
            avg = sum(float(a.get("confidence", 0.0)) for a in atoms) / len(atoms)
            bavg = sum(float(a.get("confidence", 0.0)) for a in best_atoms) / len(best_atoms)
            if avg > bavg:
                best = (mode, outd, src_chunks, src_docs)
    return best

# ============================================================
# MAIN
# ============================================================
def main() -> int:
    ap = argparse.ArgumentParser(description="PATHAI atoms extraction with PMID/DOI/FILE doc_id derivation and safe bridging switch")
    ap.add_argument("--infile", default=str(DEFAULT_INFILE), help="Input mentions.jsonl")
    ap.add_argument("--outfile", default=str(DEFAULT_OUTFILE), help="Output atoms.jsonl")

    ap.add_argument(
        "--bridge",
        action="store_true",
        help="Enable bridging (safe: only within same doc_id AND adjacent chunk_index). Default OFF.",
    )

    ap.add_argument(
        "--default_doc_id",
        default=None,
        help="If a record lacks doc_id and no PMID/DOI/FILE/title exists, set to this value.",
    )

    ap.add_argument(
        "--assign_chunk_index",
        action="store_true",
        help="If records have doc_id but lack chunk_index, assign sequential chunk_index per doc_id in file order.",
    )

    ap.add_argument("--no_bridge_forward", action="store_true", help="Disable forward bridging (if --bridge is set).")
    ap.add_argument("--no_bridge_backward", action="store_true", help="Disable backward bridging (if --bridge is set).")

    args = ap.parse_args()

    infile = Path(args.infile)
    outfile = Path(args.outfile)

    enable_bridging = bool(args.bridge)
    try_forward = (not args.no_bridge_forward)
    try_backward = (not args.no_bridge_backward)

    if not infile.exists():
        raise FileNotFoundError(f"Cannot find {infile.resolve()}")

    # Load records
    records: List[Dict[str, Any]] = []
    for ln in infile.read_text(encoding="utf-8", errors="ignore").splitlines():
        ln = ln.strip()
        if not ln:
            continue
        records.append(json.loads(ln))

    # --- IMPORTANT: doc_id derivation happens HERE (before anything else) ---
    derived_count = 0
    defaulted_count = 0
    missing_doc_id_count = 0

    for r in records:
        if not r.get("doc_id"):
            d = derive_doc_id(r)
            if d:
                r["doc_id"] = d
                derived_count += 1
            elif args.default_doc_id:
                r["doc_id"] = args.default_doc_id
                defaulted_count += 1
            else:
                missing_doc_id_count += 1

    # Optionally assign chunk_index per doc_id (safe only if file is grouped per doc, but harmless otherwise)
    if args.assign_chunk_index:
        counters: Dict[str, int] = {}
        for r in records:
            doc = r.get("doc_id")
            if not doc:
                continue
            if r.get("chunk_index") is None:
                counters.setdefault(doc, 0)
                r["chunk_index"] = counters[doc]
                counters[doc] += 1

    total_atoms = 0
    escalations = 0
    bridges_used = 0
    bridges_attempted = 0
    dropped_total = 0

    with outfile.open("w", encoding="utf-8", newline="\n") as fout:
        for idx, rec in enumerate(records):
            chunk_id = rec.get("chunk_id")
            doc_id = rec.get("doc_id")
            chunk_index = rec.get("chunk_index")

            if "error" in rec:
                out_rec = {
                    "doc_id": doc_id,
                    "chunk_index": chunk_index,
                    "chunk_id": chunk_id,
                    "atoms": [],
                    "warnings": ["Skipped due to upstream error."],
                    "bridge": {
                        "enabled": enable_bridging,
                        "attempted": False,
                        "used": False,
                        "mode": None,
                        "source_doc_ids": [doc_id] if doc_id else [],
                        "source_chunk_ids": [chunk_id],
                        "skipped_reason": "upstream_error",
                    },
                    "_routing": {"skipped": True},
                    "_post": {"dropped_atoms": 0},
                }
                fout.write(json.dumps(out_rec, ensure_ascii=False) + "\n")
                continue

            chunk_text = rec.get("chunk_text", "")
            mentions = rec.get("mentions", [])

            out = extract_atoms_with_routing(chunk_text, mentions)
            atoms = out.get("atoms", []) or []
            warnings = out.get("warnings", []) or []
            routing = out.get("_routing", {}) or {}

            atoms, dropped = post_filter_atoms(atoms)
            dropped_total += dropped

            used_bridge = False
            attempted_bridge = False
            bridge_mode = None
            skipped_reason = None
            source_chunk_ids = [chunk_id]
            source_doc_ids = [doc_id] if doc_id else []

            need_bridge = (len(mentions or []) > 0 and (len(atoms) == 0 or looks_like_setup_only(atoms, warnings)))

            if enable_bridging and need_bridge:
                attempted_bridge = True
                bridges_attempted += 1
                candidates: List[Tuple[str, Dict[str, Any], List[int], List[str]]] = []

                # forward candidate
                if try_forward and idx + 1 < len(records):
                    nxt = records[idx + 1]
                    ok, why = can_bridge_same_doc_adjacent(rec, nxt)
                    if ok and "error" not in nxt:
                        t = bridge_text(chunk_text, nxt.get("chunk_text", ""))
                        m = bridge_mentions(mentions, nxt.get("mentions", []))
                        bout = extract_atoms_with_routing(t, m)
                        batoms = bout.get("atoms", []) or []
                        bwarn = bout.get("warnings", []) or []
                        batoms, bdropped = post_filter_atoms(batoms)
                        bout["atoms"] = batoms
                        bout["warnings"] = bwarn
                        bout["_post"] = {"dropped_atoms": bdropped}
                        candidates.append((
                            "forward",
                            bout,
                            [chunk_id, nxt.get("chunk_id")],
                            [rec.get("doc_id"), nxt.get("doc_id")],
                        ))
                    else:
                        skipped_reason = skipped_reason or f"forward_{why}"

                # backward candidate
                if try_backward and idx - 1 >= 0:
                    prv = records[idx - 1]
                    ok, why = can_bridge_same_doc_adjacent(prv, rec)
                    if ok and "error" not in prv:
                        t = bridge_text(prv.get("chunk_text", ""), chunk_text)
                        m = bridge_mentions(prv.get("mentions", []), mentions)
                        bout = extract_atoms_with_routing(t, m)
                        batoms = bout.get("atoms", []) or []
                        bwarn = bout.get("warnings", []) or []
                        batoms, bdropped = post_filter_atoms(batoms)
                        bout["atoms"] = batoms
                        bout["warnings"] = bwarn
                        bout["_post"] = {"dropped_atoms": bdropped}
                        candidates.append((
                            "backward",
                            bout,
                            [prv.get("chunk_id"), chunk_id],
                            [prv.get("doc_id"), rec.get("doc_id")],
                        ))
                    else:
                        skipped_reason = skipped_reason or f"backward_{why}"

                best = choose_best_bridged(candidates)
                if best is not None and len(best[1].get("atoms", []) or []) > 0:
                    used_bridge = True
                    bridge_mode = best[0]
                    out = best[1]
                    atoms = out.get("atoms", []) or []
                    warnings = out.get("warnings", []) or []
                    routing = out.get("_routing", routing) or routing
                    source_chunk_ids = best[2]
                    source_doc_ids = [d for d in best[3] if d]
                    bridges_used += 1
                else:
                    if skipped_reason is None:
                        skipped_reason = "no_viable_bridge_candidate"

            if routing.get("escalated"):
                escalations += 1

            total_atoms += len(atoms)

            out_rec = {
                "doc_id": doc_id,
                "chunk_index": chunk_index,
                "chunk_id": chunk_id,
                "atoms": atoms,
                "warnings": warnings,
                "bridge": {
                    "enabled": enable_bridging,
                    "attempted": attempted_bridge,
                    "used": used_bridge,
                    "mode": bridge_mode,
                    "source_doc_ids": source_doc_ids,
                    "source_chunk_ids": source_chunk_ids,
                    "skipped_reason": skipped_reason,
                },
                "_routing": routing,
                "_post": {"dropped_atoms": dropped},
            }

            fout.write(json.dumps(out_rec, ensure_ascii=False) + "\n")

            print(
                f"chunk {chunk_id} doc_id={doc_id} idx={chunk_index} "
                f"atoms={len(atoms)} escalated={routing.get('escalated', False)} "
                f"bridge_enabled={enable_bridging} bridged={used_bridge} dropped={dropped}"
            )

    print(
        f"Done. total_atoms={total_atoms}, escalations={escalations}, "
        f"bridges_attempted={bridges_attempted}, bridges_used={bridges_used}, dropped_total={dropped_total}"
    )
    print(f"doc_id derivation: derived={derived_count}, defaulted={defaulted_count}, still_missing={missing_doc_id_count}")
    if not enable_bridging:
        print("Note: bridging was OFF (recommended for mixed/random chunks).")
    else:
        print("Note: bridging ON uses strict guard: same doc_id + adjacent chunk_index.")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
```

### How to run (bridging OFF, doc_id auto-derived if fields exist)

```bat
conda activate pathai
cd "C:\Users\Prem Subramaniam\Documents\Pathway AI"
python make_atoms_docaware_v4.py
```

### What you should do next upstream (so doc_id can actually be derived)

Right now your sample `mentions.jsonl` lines don’t include PMID/DOI/FILE/title fields, so `doc_id` will remain missing unless you add one of these at ingestion time. The easiest is:

* add `pmid` when you pull from PubMed (best), or
* add `doi` if available, or
* add `source_file` when you process a PDF.

Once those exist, this script will automatically produce `doc_id` like:

* `PMID:12345678`
* `DOI:10.1016/j.cell.2024.01.012`
* `FILE:paper123.pdf`

And bridging will still remain OFF unless you explicitly turn it on with `--bridge`.

* * *

**You:**

DOC_ID can also be from jorunal name + volume +date+page numbers.  Can that be incorporated

* * *

**ChatGPT:**

TAG: **PATHAI-0060** — Yes, we can incorporate **Journal + Volume + Date + Pages** as another `doc_id` source

Absolutely. We’ll extend the `doc_id` derivation rule to:

1. `PMID:<number>`
2. `DOI:<doi-string>`
3. `JVP:<journal>:<year>:<volume>:<pages>` _(JVP = journal/volume/pages; i.e., bibliographic ID built from citation fields)_
4. `FILE:<pdf_filename>`
5. `TITLEHASH:<hash>`

Below is the full updated script with that logic added.

* * *

## Full script (v5): `make_atoms_docaware_v5.py`

**TAG: PATHAI-0060**  
Save as: **`make_atoms_docaware_v5.py`**

```Python
#!/usr/bin/env python3
import os
import json
import re
import argparse
import hashlib
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple
from openai import OpenAI

# ============================================================
# DEFAULTS
# ============================================================
DEFAULT_INFILE = Path("mentions.jsonl")
DEFAULT_OUTFILE = Path("atoms.jsonl")

MODEL_FAST = "gpt-4o-mini"
MODEL_STRONG = "gpt-4.1"

MAX_ATOMS_PER_CHUNK = 30

# Bridging is OFF by default (safe for mixed/random chunk streams)
DEFAULT_ENABLE_BRIDGING = False

# ============================================================
# OPENAI CLIENT
# ============================================================
def _get_api_key() -> str:
    key = os.getenv("OPENAI_API_KEY")
    if not key:
        raise RuntimeError(
            "OPENAI_API_KEY is not set.\n"
            "Miniforge Prompt (temporary):  set OPENAI_API_KEY=YOUR_KEY\n"
            "Persistent (Windows):         setx OPENAI_API_KEY \"YOUR_KEY\"  (then reopen prompt)"
        )
    return key

client = OpenAI(api_key=_get_api_key())

# ============================================================
# STRICT JSON SCHEMA FOR ATOMS (model output)
# ============================================================
ATOM_SCHEMA_WRAPPER: Dict[str, Any] = {
    "name": "MechanisticAtoms",
    "schema": {
        "type": "object",
        "additionalProperties": False,
        "required": ["atoms", "warnings"],
        "properties": {
            "atoms": {
                "type": "array",
                "items": {
                    "type": "object",
                    "additionalProperties": False,
                    "required": [
                        "intervention",
                        "system",
                        "readout",
                        "effect",
                        "strength_cues",
                        "evidence",
                        "confidence",
                    ],
                    "properties": {
                        "intervention": {
                            "type": "object",
                            "additionalProperties": False,
                            "required": ["category", "raw_text", "target", "modality"],
                            "properties": {
                                "category": {
                                    "type": "string",
                                    "enum": [
                                        "GENETIC_KO",
                                        "CRISPR_KO",
                                        "CRISPRi",
                                        "CRISPRa",
                                        "KNOCKDOWN_RNAI",
                                        "SPLICING_MODULATION",
                                        "OVEREXPRESSION",
                                        "RESCUE_ADD_BACK",
                                        "DOMINANT_NEGATIVE",
                                        "MUTANT_VARIANT",
                                        "CHEMICAL_INHIBITOR",
                                        "CHEMICAL_ACTIVATOR",
                                        "CHEMICAL_DEGRADER",
                                        "STIMULUS_TREATMENT",
                                        "NEUTRALIZING_ANTIBODY",
                                        "UNKNOWN",
                                    ],
                                },
                                "raw_text": {"type": "string", "minLength": 1},
                                "target": {
                                    "anyOf": [
                                        {
                                            "type": "object",
                                            "additionalProperties": False,
                                            "required": ["name", "entity_type"],
                                            "properties": {
                                                "name": {"type": "string"},
                                                "entity_type": {
                                                    "type": "string",
                                                    "enum": [
                                                        "gene",
                                                        "protein",
                                                        "chemical",
                                                        "stimulus",
                                                        "antibody",
                                                        "unknown",
                                                    ],
                                                },
                                            },
                                        },
                                        {"type": "null"},
                                    ]
                                },
                                "modality": {
                                    "type": "string",
                                    "enum": [
                                        "LOF",
                                        "GOF",
                                        "INHIBITION",
                                        "ACTIVATION",
                                        "DEGRADATION",
                                        "RESCUE",
                                        "UNKNOWN",
                                    ],
                                },
                            },
                        },
                        "system": {
                            "type": "object",
                            "additionalProperties": False,
                            "required": [
                                "species",
                                "cell_type",
                                "cell_lines",
                                "genotype_context",
                                "disease_context",
                            ],
                            "properties": {
                                "species": {"type": ["string", "null"]},
                                "cell_type": {"type": ["string", "null"]},
                                "cell_lines": {"type": "array", "items": {"type": "string"}},
                                "genotype_context": {"type": ["string", "null"]},
                                "disease_context": {"type": ["string", "null"]},
                            },
                        },
                        "readout": {
                            "type": "object",
                            "additionalProperties": False,
                            "required": ["name", "assay", "figure_refs"],
                            "properties": {
                                "name": {"type": "string"},
                                "assay": {"type": ["string", "null"]},
                                "figure_refs": {"type": "array", "items": {"type": "string"}},
                            },
                        },
                        "effect": {
                            "type": "object",
                            "additionalProperties": False,
                            "required": ["direction", "timepoint", "magnitude", "comparison"],
                            "properties": {
                                "direction": {
                                    "type": "string",
                                    "enum": ["increase", "decrease", "no_change", "mixed", "unknown"],
                                },
                                "timepoint": {"type": ["string", "null"]},
                                "magnitude": {"type": ["string", "null"]},
                                "comparison": {"type": ["string", "null"]},
                            },
                        },
                        "strength_cues": {
                            "type": "object",
                            "additionalProperties": False,
                            "required": ["has_rescue", "has_control", "has_multiple_lines", "other"],
                            "properties": {
                                "has_rescue": {"type": "boolean"},
                                "has_control": {"type": "boolean"},
                                "has_multiple_lines": {"type": "boolean"},
                                "other": {"type": "array", "items": {"type": "string"}},
                            },
                        },
                        "evidence": {
                            "type": "object",
                            "additionalProperties": False,
                            "required": ["supporting_quote", "notes"],
                            "properties": {
                                "supporting_quote": {"type": "string"},
                                "notes": {"type": ["string", "null"]},
                            },
                        },
                        "confidence": {"type": "number", "minimum": 0, "maximum": 1},
                    },
                },
            },
            "warnings": {"type": "array", "items": {"type": "string"}},
        },
    },
}

# ============================================================
# LIGHTWEIGHT HINTS
# ============================================================
FIGREF_REGEX = re.compile(r"\b(Fig\.?\s*\d+[A-Za-z]?)\b", re.IGNORECASE)
SPECIES_REGEX = re.compile(r"\b(human|mouse|murine|rat)\b", re.IGNORECASE)

def _uniq_preserve(seq: List[str]) -> List[str]:
    seen = set()
    out = []
    for x in seq:
        k = x.lower()
        if k not in seen:
            seen.add(k)
            out.append(x)
    return out

def hint_figrefs(text: str) -> List[str]:
    return _uniq_preserve([m.group(1) for m in FIGREF_REGEX.finditer(text or "")])

def hint_species(text: str) -> Optional[str]:
    m = SPECIES_REGEX.search(text or "")
    if not m:
        return None
    s = m.group(1).lower()
    return "mouse" if s == "murine" else s

def compact_mentions(mentions: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    out = []
    for i, m in enumerate(mentions or [], start=1):
        out.append({
            "i": i,
            "category": m.get("category"),
            "raw_text": m.get("raw_text"),
            "target_guess": m.get("target_guess"),
            "method_cues": m.get("method_cues", []),
        })
    return out

# ============================================================
# DOC_ID DERIVATION (PMID → DOI → JVP → FILE → TITLEHASH)
# ============================================================
_DOI_PREFIX_RE = re.compile(r"^(https?://(dx\.)?doi\.org/|doi:\s*)", re.IGNORECASE)
_YEAR_RE = re.compile(r"\b(19\d{2}|20\d{2})\b")
_PAGES_RE = re.compile(r"^\s*(\d+)\s*[-–—]\s*(\d+)\s*$")

def _stable_hash(text: str, n: int = 12) -> str:
    return hashlib.sha1(text.encode("utf-8")).hexdigest()[:n]

def _get_nested(rec: Dict[str, Any], path: List[str]) -> Optional[Any]:
    cur: Any = rec
    for k in path:
        if not isinstance(cur, dict) or k not in cur:
            return None
        cur = cur[k]
    return cur

def _first_str_value(rec: Dict[str, Any], key_paths: List[List[str]]) -> Optional[str]:
    for path in key_paths:
        v = _get_nested(rec, path)
        if isinstance(v, str) and v.strip():
            return v.strip()
    return None

def _first_intish_value(rec: Dict[str, Any], key_paths: List[List[str]]) -> Optional[str]:
    for path in key_paths:
        v = _get_nested(rec, path)
        if v is None:
            continue
        if isinstance(v, int):
            return str(v)
        if isinstance(v, str):
            s = v.strip()
            m = re.search(r"\d+", s)
            if m:
                return m.group(0)
    return None

def _normalize_journal(j: str) -> str:
    # Keep alnum only, collapse; cap length to keep doc_id readable
    s = re.sub(r"[^A-Za-z0-9]+", "", (j or "").lower())
    return s[:32] if s else ""

def _extract_year(rec: Dict[str, Any]) -> Optional[str]:
    # Prefer explicit year fields; else parse from date-like strings
    year = _first_intish_value(rec, [
        ["year"], ["pub_year"], ["publication_year"],
        ["metadata", "year"], ["metadata", "pub_year"], ["paper", "year"],
    ])
    if year and len(year) == 4:
        return year

    date_str = _first_str_value(rec, [
        ["date"], ["publication_date"], ["pub_date"],
        ["metadata", "date"], ["metadata", "publication_date"], ["paper", "date"],
    ])
    if date_str:
        m = _YEAR_RE.search(date_str)
        if m:
            return m.group(1)
    return None

def _extract_volume(rec: Dict[str, Any]) -> Optional[str]:
    vol = _first_str_value(rec, [
        ["volume"], ["vol"], ["metadata", "volume"], ["paper", "volume"],
    ])
    if not vol:
        return None
    # keep digits/letters commonly used in volumes (e.g., "12", "12S")
    vol2 = re.sub(r"[^0-9A-Za-z]+", "", vol)
    return vol2 or None

def _extract_pages(rec: Dict[str, Any]) -> Optional[str]:
    pages = _first_str_value(rec, [
        ["pages"], ["page_range"], ["pagination"], ["pageNumbers"],
        ["metadata", "pages"], ["metadata", "page_range"], ["paper", "pages"],
    ])
    if pages:
        s = pages.strip()
        # Normalize unicode dashes to "-"
        s = s.replace("–", "-").replace("—", "-")
        # If it's a simple range, normalize spacing
        m = _PAGES_RE.match(s)
        if m:
            return f"{m.group(1)}-{m.group(2)}"
        # else keep a compact safe version
        s2 = re.sub(r"\s+", "", s)
        s2 = re.sub(r"[^0-9A-Za-z\-]+", "", s2)
        return s2 or None

    # Try start/end fields
    p1 = _first_intish_value(rec, [
        ["page_start"], ["first_page"], ["start_page"],
        ["metadata", "page_start"], ["paper", "page_start"],
    ])
    p2 = _first_intish_value(rec, [
        ["page_end"], ["last_page"], ["end_page"],
        ["metadata", "page_end"], ["paper", "page_end"],
    ])
    if p1 and p2:
        return f"{p1}-{p2}"
    if p1:
        return p1
    return None

def _extract_journal(rec: Dict[str, Any]) -> Optional[str]:
    j = _first_str_value(rec, [
        ["journal"], ["journal_name"], ["journalTitle"],
        ["metadata", "journal"], ["metadata", "journal_name"], ["paper", "journal"],
    ])
    return j

def derive_doc_id(rec: Dict[str, Any]) -> Optional[str]:
    """
    Prefer PMID:<number> when available.
    Else DOI:<doi-string>.
    Else JVP:<journal>:<year>:<volume>:<pages> when fields exist.
    Else FILE:<pdf_filename> (basename).
    Else TITLEHASH:<hash> if title exists.
    Else None.
    """
    # 1) PMID
    pmid = _first_intish_value(rec, [
        ["pmid"], ["PMID"], ["pubmed_id"], ["pubmedId"], ["PubMedID"],
        ["metadata", "pmid"], ["metadata", "PMID"], ["paper", "pmid"], ["paper", "PMID"],
    ])
    if pmid:
        return f"PMID:{pmid}"

    # 2) DOI
    doi = _first_str_value(rec, [
        ["doi"], ["DOI"], ["metadata", "doi"], ["metadata", "DOI"], ["paper", "doi"], ["paper", "DOI"],
    ])
    if doi:
        doi2 = _DOI_PREFIX_RE.sub("", doi).strip()
        return f"DOI:{doi2}"

    # 3) Journal/Volume/Date/Pages (JVP)
    journal = _extract_journal(rec)
    year = _extract_year(rec)
    volume = _extract_volume(rec)
    pages = _extract_pages(rec)

    jnorm = _normalize_journal(journal or "")
    if jnorm and year and volume and pages:
        # Keep it human-readable and stable
        return f"JVP:{jnorm}:{year}:{volume}:{pages}"

    # 4) FILE basename
    file_path = _first_str_value(rec, [
        ["source_file"], ["file"], ["filename"], ["pdf_file"],
        ["source", "file"], ["_source", "file"], ["metadata", "file"], ["metadata", "filename"],
    ])
    if file_path:
        name = Path(file_path).name.strip()
        if name:
            return f"FILE:{name}"
        return f"FILEHASH:{_stable_hash(file_path)}"

    # 5) TITLEHASH
    title = _first_str_value(rec, [
        ["title"], ["paper_title"], ["metadata", "title"], ["paper", "title"],
    ])
    if title:
        return f"TITLEHASH:{_stable_hash(title.lower().strip())}"

    return None

# ============================================================
# PROMPT
# ============================================================
SYSTEM_INSTRUCTIONS = (
    "Extract 'mechanistic atoms' from biomedical text.\n\n"
    "Definition: an atom MUST include an explicit effect on a readout.\n"
    "Format: [INTERVENTION] causes [EFFECT] in [READOUT] in a [SYSTEM].\n\n"
    "Hard rules:\n"
    "1) Do NOT invent facts.\n"
    "2) Do NOT assume knockdown succeeded unless the text explicitly says reduction/knockdown/confirmed.\n"
    "3) If the text only describes delivering siRNA/plasmid/drug but gives no stated change in any readout, output no atoms and add a warning.\n"
    "4) You may extract multiple readouts per intervention if they are explicitly stated.\n"
    "5) Rescue/add-back atoms must state what readout is rescued.\n"
    f"6) Keep at most {MAX_ATOMS_PER_CHUNK} atoms.\n"
)

# ============================================================
# MODEL CALLS + ROUTING
# ============================================================
def call_model(model: str, chunk_text: str, mentions: List[Dict[str, Any]]) -> Dict[str, Any]:
    payload = {
        "chunk_text": chunk_text,
        "mentions": compact_mentions(mentions),
        "hints": {
            "fig_refs": hint_figrefs(chunk_text),
            "species": hint_species(chunk_text),
        }
    }
    resp = client.responses.create(
        model=model,
        input=[
            {"role": "system", "content": SYSTEM_INSTRUCTIONS},
            {"role": "user", "content": json.dumps(payload, ensure_ascii=False)},
        ],
        text={
            "format": {
                "type": "json_schema",
                "name": ATOM_SCHEMA_WRAPPER["name"],
                "strict": True,
                "schema": ATOM_SCHEMA_WRAPPER["schema"],
            }
        },
    )
    return json.loads(resp.output_text)

def should_escalate(mentions: List[Dict[str, Any]], atoms: List[Dict[str, Any]]) -> bool:
    if len(mentions) > 0 and len(atoms) == 0:
        return True
    if len(atoms) > 0:
        avg_conf = sum(float(a.get("confidence", 0.0)) for a in atoms) / len(atoms)
        if avg_conf < 0.55:
            return True
    return False

def extract_atoms_with_routing(chunk_text: str, mentions: List[Dict[str, Any]]) -> Dict[str, Any]:
    routing = {"first_model": MODEL_FAST, "escalated": False, "final_model": MODEL_FAST, "reason": None}
    out_fast = call_model(MODEL_FAST, chunk_text, mentions)
    atoms_fast = out_fast.get("atoms", [])

    if should_escalate(mentions, atoms_fast):
        routing["escalated"] = True
        routing["final_model"] = MODEL_STRONG
        routing["reason"] = {"type": "low_confidence_or_empty", "details": "heuristics triggered"}
        out_strong = call_model(MODEL_STRONG, chunk_text, mentions)
        out_strong["_routing"] = routing
        return out_strong

    out_fast["_routing"] = routing
    return out_fast

# ============================================================
# POST-FILTER: explicit effect cue must appear in supporting quote
# ============================================================
EFFECT_CUE = re.compile(
    r"\b("
    r"inhibit|inhibited|inhibition|suppress|suppressed|suppressing|"
    r"reduce|reduced|reduces|reduction|decrease|decreased|decreases|"
    r"increase|increased|increases|elevate|elevated|"
    r"no effect|did not affect|had no effect|"
    r"rescue|rescued|restored|restore|"
    r"complete inhibition|abolish|abolished"
    r")\b",
    re.IGNORECASE,
)
SETUP_ONLY_READOUT = re.compile(r"\b(expression|function|knockdown|silencing)\b", re.IGNORECASE)

def looks_like_setup_only(atoms: List[Dict[str, Any]], warnings: List[str]) -> bool:
    if not atoms:
        return True
    wtxt = " ".join(warnings or []).lower()
    if "no explicit functional readouts" in wtxt or "only describes" in wtxt:
        return True
    for a in atoms:
        ro = (a.get("readout", {}) or {}).get("name", "")
        sq = (a.get("evidence", {}) or {}).get("supporting_quote", "")
        if (not SETUP_ONLY_READOUT.search(ro or "")) and EFFECT_CUE.search(sq or ""):
            return False
    return True

def post_filter_atoms(atoms: List[Dict[str, Any]]) -> Tuple[List[Dict[str, Any]], int]:
    kept: List[Dict[str, Any]] = []
    dropped = 0
    for a in atoms or []:
        sq = (a.get("evidence", {}) or {}).get("supporting_quote", "")
        if EFFECT_CUE.search(sq or ""):
            kept.append(a)
        else:
            dropped += 1
    return kept, dropped

# ============================================================
# DOC-AWARE BRIDGING GUARD (only same doc_id + adjacent chunk_index)
# ============================================================
def can_bridge_same_doc_adjacent(a: Dict[str, Any], b: Dict[str, Any]) -> Tuple[bool, str]:
    a_doc = a.get("doc_id")
    b_doc = b.get("doc_id")
    if not a_doc or not b_doc:
        return False, "missing_doc_id"
    if a_doc != b_doc:
        return False, "doc_id_mismatch"

    a_idx = a.get("chunk_index")
    b_idx = b.get("chunk_index")
    if a_idx is None or b_idx is None:
        return False, "missing_chunk_index"
    try:
        ai = int(a_idx)
        bi = int(b_idx)
    except Exception:
        return False, "non_integer_chunk_index"
    if abs(ai - bi) != 1:
        return False, "non_adjacent_chunk_index"
    return True, "ok"

def bridge_text(a_text: str, b_text: str) -> str:
    return (a_text or "").rstrip() + "\n\n" + (b_text or "").lstrip()

def bridge_mentions(a_mentions: List[Dict[str, Any]], b_mentions: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    return list(a_mentions or []) + list(b_mentions or [])

def choose_best_bridged(candidates: List[Tuple[str, Dict[str, Any], List[int], List[str]]]) -> Optional[Tuple[str, Dict[str, Any], List[int], List[str]]]:
    best = None
    for mode, outd, src_chunks, src_docs in candidates:
        atoms = outd.get("atoms", []) or []
        if best is None:
            best = (mode, outd, src_chunks, src_docs)
            continue
        best_atoms = best[1].get("atoms", []) or []
        if len(atoms) > len(best_atoms):
            best = (mode, outd, src_chunks, src_docs)
        elif len(atoms) == len(best_atoms) and len(atoms) > 0:
            avg = sum(float(a.get("confidence", 0.0)) for a in atoms) / len(atoms)
            bavg = sum(float(a.get("confidence", 0.0)) for a in best_atoms) / len(best_atoms)
            if avg > bavg:
                best = (mode, outd, src_chunks, src_docs)
    return best

# ============================================================
# MAIN
# ============================================================
def main() -> int:
    ap = argparse.ArgumentParser(description="PATHAI atoms extraction with PMID/DOI/JVP/FILE doc_id derivation and safe bridging switch")
    ap.add_argument("--infile", default=str(DEFAULT_INFILE), help="Input mentions.jsonl")
    ap.add_argument("--outfile", default=str(DEFAULT_OUTFILE), help="Output atoms.jsonl")

    ap.add_argument(
        "--bridge",
        action="store_true",
        help="Enable bridging (safe: only within same doc_id AND adjacent chunk_index). Default OFF.",
    )

    ap.add_argument(
        "--default_doc_id",
        default=None,
        help="If a record lacks doc_id and cannot derive PMID/DOI/JVP/FILE/title, set to this value.",
    )

    ap.add_argument(
        "--assign_chunk_index",
        action="store_true",
        help="If records have doc_id but lack chunk_index, assign sequential chunk_index per doc_id in file order.",
    )

    ap.add_argument("--no_bridge_forward", action="store_true", help="Disable forward bridging (if --bridge is set).")
    ap.add_argument("--no_bridge_backward", action="store_true", help="Disable backward bridging (if --bridge is set).")

    args = ap.parse_args()

    infile = Path(args.infile)
    outfile = Path(args.outfile)

    enable_bridging = bool(args.bridge)
    try_forward = (not args.no_bridge_forward)
    try_backward = (not args.no_bridge_backward)

    if not infile.exists():
        raise FileNotFoundError(f"Cannot find {infile.resolve()}")

    # Load records
    records: List[Dict[str, Any]] = []
    for ln in infile.read_text(encoding="utf-8", errors="ignore").splitlines():
        ln = ln.strip()
        if not ln:
            continue
        records.append(json.loads(ln))

    # doc_id derivation happens here
    derived_count = 0
    defaulted_count = 0
    missing_doc_id_count = 0

    for r in records:
        if not r.get("doc_id"):
            d = derive_doc_id(r)
            if d:
                r["doc_id"] = d
                derived_count += 1
            elif args.default_doc_id:
                r["doc_id"] = args.default_doc_id
                defaulted_count += 1
            else:
                missing_doc_id_count += 1

    # Optional chunk_index assignment per doc_id
    if args.assign_chunk_index:
        counters: Dict[str, int] = {}
        for r in records:
            doc = r.get("doc_id")
            if not doc:
                continue
            if r.get("chunk_index") is None:
                counters.setdefault(doc, 0)
                r["chunk_index"] = counters[doc]
                counters[doc] += 1

    total_atoms = 0
    escalations = 0
    bridges_used = 0
    bridges_attempted = 0
    dropped_total = 0

    with outfile.open("w", encoding="utf-8", newline="\n") as fout:
        for idx, rec in enumerate(records):
            chunk_id = rec.get("chunk_id")
            doc_id = rec.get("doc_id")
            chunk_index = rec.get("chunk_index")

            if "error" in rec:
                out_rec = {
                    "doc_id": doc_id,
                    "chunk_index": chunk_index,
                    "chunk_id": chunk_id,
                    "atoms": [],
                    "warnings": ["Skipped due to upstream error."],
                    "bridge": {
                        "enabled": enable_bridging,
                        "attempted": False,
                        "used": False,
                        "mode": None,
                        "source_doc_ids": [doc_id] if doc_id else [],
                        "source_chunk_ids": [chunk_id],
                        "skipped_reason": "upstream_error",
                    },
                    "_routing": {"skipped": True},
                    "_post": {"dropped_atoms": 0},
                }
                fout.write(json.dumps(out_rec, ensure_ascii=False) + "\n")
                continue

            chunk_text = rec.get("chunk_text", "")
            mentions = rec.get("mentions", [])

            out = extract_atoms_with_routing(chunk_text, mentions)
            atoms = out.get("atoms", []) or []
            warnings = out.get("warnings", []) or []
            routing = out.get("_routing", {}) or {}

            atoms, dropped = post_filter_atoms(atoms)
            dropped_total += dropped

            used_bridge = False
            attempted_bridge = False
            bridge_mode = None
            skipped_reason = None
            source_chunk_ids = [chunk_id]
            source_doc_ids = [doc_id] if doc_id else []

            need_bridge = (len(mentions or []) > 0 and (len(atoms) == 0 or looks_like_setup_only(atoms, warnings)))

            if enable_bridging and need_bridge:
                attempted_bridge = True
                bridges_attempted += 1
                candidates: List[Tuple[str, Dict[str, Any], List[int], List[str]]] = []

                if try_forward and idx + 1 < len(records):
                    nxt = records[idx + 1]
                    ok, why = can_bridge_same_doc_adjacent(rec, nxt)
                    if ok and "error" not in nxt:
                        t = bridge_text(chunk_text, nxt.get("chunk_text", ""))
                        m = bridge_mentions(mentions, nxt.get("mentions", []))
                        bout = extract_atoms_with_routing(t, m)
                        batoms = bout.get("atoms", []) or []
                        bwarn = bout.get("warnings", []) or []
                        batoms, bdropped = post_filter_atoms(batoms)
                        bout["atoms"] = batoms
                        bout["warnings"] = bwarn
                        bout["_post"] = {"dropped_atoms": bdropped}
                        candidates.append((
                            "forward",
                            bout,
                            [chunk_id, nxt.get("chunk_id")],
                            [rec.get("doc_id"), nxt.get("doc_id")],
                        ))
                    else:
                        skipped_reason = skipped_reason or f"forward_{why}"

                if try_backward and idx - 1 >= 0:
                    prv = records[idx - 1]
                    ok, why = can_bridge_same_doc_adjacent(prv, rec)
                    if ok and "error" not in prv:
                        t = bridge_text(prv.get("chunk_text", ""), chunk_text)
                        m = bridge_mentions(prv.get("mentions", []), mentions)
                        bout = extract_atoms_with_routing(t, m)
                        batoms = bout.get("atoms", []) or []
                        bwarn = bout.get("warnings", []) or []
                        batoms, bdropped = post_filter_atoms(batoms)
                        bout["atoms"] = batoms
                        bout["warnings"] = bwarn
                        bout["_post"] = {"dropped_atoms": bdropped}
                        candidates.append((
                            "backward",
                            bout,
                            [prv.get("chunk_id"), chunk_id],
                            [prv.get("doc_id"), rec.get("doc_id")],
                        ))
                    else:
                        skipped_reason = skipped_reason or f"backward_{why}"

                best = choose_best_bridged(candidates)
                if best is not None and len(best[1].get("atoms", []) or []) > 0:
                    used_bridge = True
                    bridge_mode = best[0]
                    out = best[1]
                    atoms = out.get("atoms", []) or []
                    warnings = out.get("warnings", []) or []
                    routing = out.get("_routing", routing) or routing
                    source_chunk_ids = best[2]
                    source_doc_ids = [d for d in best[3] if d]
                    bridges_used += 1
                else:
                    if skipped_reason is None:
                        skipped_reason = "no_viable_bridge_candidate"

            if routing.get("escalated"):
                escalations += 1

            total_atoms += len(atoms)

            out_rec = {
                "doc_id": doc_id,
                "chunk_index": chunk_index,
                "chunk_id": chunk_id,
                "atoms": atoms,
                "warnings": warnings,
                "bridge": {
                    "enabled": enable_bridging,
                    "attempted": attempted_bridge,
                    "used": used_bridge,
                    "mode": bridge_mode,
                    "source_doc_ids": source_doc_ids,
                    "source_chunk_ids": source_chunk_ids,
                    "skipped_reason": skipped_reason,
                },
                "_routing": routing,
                "_post": {"dropped_atoms": dropped},
            }

            fout.write(json.dumps(out_rec, ensure_ascii=False) + "\n")

            print(
                f"chunk {chunk_id} doc_id={doc_id} idx={chunk_index} "
                f"atoms={len(atoms)} escalated={routing.get('escalated', False)} "
                f"bridge_enabled={enable_bridging} bridged={used_bridge} dropped={dropped}"
            )

    print(
        f"Done. total_atoms={total_atoms}, escalations={escalations}, "
        f"bridges_attempted={bridges_attempted}, bridges_used={bridges_used}, dropped_total={dropped_total}"
    )
    print(f"doc_id derivation: derived={derived_count}, defaulted={defaulted_count}, still_missing={missing_doc_id_count}")
    if not enable_bridging:
        print("Note: bridging was OFF (recommended for mixed/random chunks).")
    else:
        print("Note: bridging ON uses strict guard: same doc_id + adjacent chunk_index.")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
```

### What needs to be present in your JSONL for JVP to work

For the `JVP:` doc_id to be derived, the record needs (at least) fields like:

* `journal` (or `metadata.journal`, etc.)
* `volume`
* a year/date (`year` or `publication_date`)
* `pages` (or `page_start` + `page_end`)

If those aren’t present yet, `JVP:` won’t trigger—then it will fall back to `FILE:` or `TITLEHASH:` as available.

If you tell me what your ingestion step will output for bibliographic metadata (field names), I can add those exact key names into the lookup list so derivation works immediately.

* * *

**You:**

I don't know what my ingestion data will ouput since I have not done any besides the trial chunks.  You should now that from our entire conversation.  SO where to now?

* * *

**ChatGPT:**

TAG: **PATHAI-0061** — Where to go next (given ingestion is still TBD)

You’re in a good place. You **don’t need ingestion finalized** to keep moving—what you need is a **stable “contract” (a minimal set of fields your downstream code can rely on)** and safe defaults.

### What we do now

1. **Run in “CORPUS mode” (mixed papers): bridging OFF.**  
    This prevents cross-paper mixing.
2. **Still add `doc_id` now**, even if ingestion metadata isn’t available yet, by using your preference order when possible (PMID → DOI → JVP → FILE), **and a safe fallback when none exists**.
3. **Then proceed to graph later** with correct evidence accounting:
    * if `doc_id` is real (PMID/DOI/JVP/FILE), we can count “papers supporting an edge”
    * if `doc_id` is a fallback, we treat it as “unknown paper identity” (so we _don’t_ accidentally inflate multi-paper support)
4. Separately (soon): fix the **span mismatch** warnings in your mention-miner (they don’t block atoms/graph, but they hurt auditability).

* * *

## The key missing piece: safe `doc_id` fallback

Right now your trial chunks have **no PMID/DOI/journal/pages/file/title fields**, so doc_id derivation won’t trigger.

So we should add this rule:

> If no PMID/DOI/JVP/FILE/TITLEHASH can be derived, set `doc_id = "CHUNK:<chunk_id>"` (chunk fallback = unique per record, prevents any accidental within-doc operations).

That gives you **doc_id always**, without pretending you know paper identity.

Below is the full finalized script with:

* PMID → DOI → JVP → FILE → TITLEHASH → **CHUNK fallback**
* `doc_id_source` (doc_id_source = where the doc_id came from, e.g., “pmid”, “doi”, “jvp”, “file”, “titlehash”, “chunk_fallback”)
* bridging still **OFF by default** and still doc-aware if enabled later

* * *

## Full script v6

**TAG: PATHAI-0061**  
Save as: **`make_atoms_docaware_v6.py`**

```Python
#!/usr/bin/env python3
import os
import json
import re
import argparse
import hashlib
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple
from openai import OpenAI

# ============================================================
# DEFAULTS
# ============================================================
DEFAULT_INFILE = Path("mentions.jsonl")
DEFAULT_OUTFILE = Path("atoms.jsonl")

MODEL_FAST = "gpt-4o-mini"
MODEL_STRONG = "gpt-4.1"

MAX_ATOMS_PER_CHUNK = 30

# Bridging is OFF by default (safe for mixed/random chunk streams)
DEFAULT_ENABLE_BRIDGING = False

# ============================================================
# OPENAI CLIENT
# ============================================================
def _get_api_key() -> str:
    key = os.getenv("OPENAI_API_KEY")
    if not key:
        raise RuntimeError(
            "OPENAI_API_KEY is not set.\n"
            "Miniforge Prompt (temporary):  set OPENAI_API_KEY=YOUR_KEY\n"
            "Persistent (Windows):         setx OPENAI_API_KEY \"YOUR_KEY\"  (then reopen prompt)"
        )
    return key

client = OpenAI(api_key=_get_api_key())

# ============================================================
# STRICT JSON SCHEMA FOR ATOMS (model output)
# ============================================================
ATOM_SCHEMA_WRAPPER: Dict[str, Any] = {
    "name": "MechanisticAtoms",
    "schema": {
        "type": "object",
        "additionalProperties": False,
        "required": ["atoms", "warnings"],
        "properties": {
            "atoms": {
                "type": "array",
                "items": {
                    "type": "object",
                    "additionalProperties": False,
                    "required": [
                        "intervention",
                        "system",
                        "readout",
                        "effect",
                        "strength_cues",
                        "evidence",
                        "confidence",
                    ],
                    "properties": {
                        "intervention": {
                            "type": "object",
                            "additionalProperties": False,
                            "required": ["category", "raw_text", "target", "modality"],
                            "properties": {
                                "category": {
                                    "type": "string",
                                    "enum": [
                                        "GENETIC_KO",
                                        "CRISPR_KO",
                                        "CRISPRi",
                                        "CRISPRa",
                                        "KNOCKDOWN_RNAI",
                                        "SPLICING_MODULATION",
                                        "OVEREXPRESSION",
                                        "RESCUE_ADD_BACK",
                                        "DOMINANT_NEGATIVE",
                                        "MUTANT_VARIANT",
                                        "CHEMICAL_INHIBITOR",
                                        "CHEMICAL_ACTIVATOR",
                                        "CHEMICAL_DEGRADER",
                                        "STIMULUS_TREATMENT",
                                        "NEUTRALIZING_ANTIBODY",
                                        "UNKNOWN",
                                    ],
                                },
                                "raw_text": {"type": "string", "minLength": 1},
                                "target": {
                                    "anyOf": [
                                        {
                                            "type": "object",
                                            "additionalProperties": False,
                                            "required": ["name", "entity_type"],
                                            "properties": {
                                                "name": {"type": "string"},
                                                "entity_type": {
                                                    "type": "string",
                                                    "enum": [
                                                        "gene",
                                                        "protein",
                                                        "chemical",
                                                        "stimulus",
                                                        "antibody",
                                                        "unknown",
                                                    ],
                                                },
                                            },
                                        },
                                        {"type": "null"},
                                    ]
                                },
                                "modality": {
                                    "type": "string",
                                    "enum": [
                                        "LOF",
                                        "GOF",
                                        "INHIBITION",
                                        "ACTIVATION",
                                        "DEGRADATION",
                                        "RESCUE",
                                        "UNKNOWN",
                                    ],
                                },
                            },
                        },
                        "system": {
                            "type": "object",
                            "additionalProperties": False,
                            "required": [
                                "species",
                                "cell_type",
                                "cell_lines",
                                "genotype_context",
                                "disease_context",
                            ],
                            "properties": {
                                "species": {"type": ["string", "null"]},
                                "cell_type": {"type": ["string", "null"]},
                                "cell_lines": {"type": "array", "items": {"type": "string"}},
                                "genotype_context": {"type": ["string", "null"]},
                                "disease_context": {"type": ["string", "null"]},
                            },
                        },
                        "readout": {
                            "type": "object",
                            "additionalProperties": False,
                            "required": ["name", "assay", "figure_refs"],
                            "properties": {
                                "name": {"type": "string"},
                                "assay": {"type": ["string", "null"]},
                                "figure_refs": {"type": "array", "items": {"type": "string"}},
                            },
                        },
                        "effect": {
                            "type": "object",
                            "additionalProperties": False,
                            "required": ["direction", "timepoint", "magnitude", "comparison"],
                            "properties": {
                                "direction": {
                                    "type": "string",
                                    "enum": ["increase", "decrease", "no_change", "mixed", "unknown"],
                                },
                                "timepoint": {"type": ["string", "null"]},
                                "magnitude": {"type": ["string", "null"]},
                                "comparison": {"type": ["string", "null"]},
                            },
                        },
                        "strength_cues": {
                            "type": "object",
                            "additionalProperties": False,
                            "required": ["has_rescue", "has_control", "has_multiple_lines", "other"],
                            "properties": {
                                "has_rescue": {"type": "boolean"},
                                "has_control": {"type": "boolean"},
                                "has_multiple_lines": {"type": "boolean"},
                                "other": {"type": "array", "items": {"type": "string"}},
                            },
                        },
                        "evidence": {
                            "type": "object",
                            "additionalProperties": False,
                            "required": ["supporting_quote", "notes"],
                            "properties": {
                                "supporting_quote": {"type": "string"},
                                "notes": {"type": ["string", "null"]},
                            },
                        },
                        "confidence": {"type": "number", "minimum": 0, "maximum": 1},
                    },
                },
            },
            "warnings": {"type": "array", "items": {"type": "string"}},
        },
    },
}

# ============================================================
# LIGHTWEIGHT HINTS
# ============================================================
FIGREF_REGEX = re.compile(r"\b(Fig\.?\s*\d+[A-Za-z]?)\b", re.IGNORECASE)
SPECIES_REGEX = re.compile(r"\b(human|mouse|murine|rat)\b", re.IGNORECASE)

def _uniq_preserve(seq: List[str]) -> List[str]:
    seen = set()
    out = []
    for x in seq:
        k = x.lower()
        if k not in seen:
            seen.add(k)
            out.append(x)
    return out

def hint_figrefs(text: str) -> List[str]:
    return _uniq_preserve([m.group(1) for m in FIGREF_REGEX.finditer(text or "")])

def hint_species(text: str) -> Optional[str]:
    m = SPECIES_REGEX.search(text or "")
    if not m:
        return None
    s = m.group(1).lower()
    return "mouse" if s == "murine" else s

def compact_mentions(mentions: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    out = []
    for i, m in enumerate(mentions or [], start=1):
        out.append({
            "i": i,
            "category": m.get("category"),
            "raw_text": m.get("raw_text"),
            "target_guess": m.get("target_guess"),
            "method_cues": m.get("method_cues", []),
        })
    return out

# ============================================================
# DOC_ID DERIVATION (PMID → DOI → JVP → FILE → TITLEHASH → CHUNK)
# ============================================================
_DOI_PREFIX_RE = re.compile(r"^(https?://(dx\.)?doi\.org/|doi:\s*)", re.IGNORECASE)
_YEAR_RE = re.compile(r"\b(19\d{2}|20\d{2})\b")
_PAGES_RE = re.compile(r"^\s*(\d+)\s*[-–—]\s*(\d+)\s*$")

def _stable_hash(text: str, n: int = 12) -> str:
    return hashlib.sha1(text.encode("utf-8")).hexdigest()[:n]

def _get_nested(rec: Dict[str, Any], path: List[str]) -> Optional[Any]:
    cur: Any = rec
    for k in path:
        if not isinstance(cur, dict) or k not in cur:
            return None
        cur = cur[k]
    return cur

def _first_str_value(rec: Dict[str, Any], key_paths: List[List[str]]) -> Optional[str]:
    for path in key_paths:
        v = _get_nested(rec, path)
        if isinstance(v, str) and v.strip():
            return v.strip()
    return None

def _first_intish_value(rec: Dict[str, Any], key_paths: List[List[str]]) -> Optional[str]:
    for path in key_paths:
        v = _get_nested(rec, path)
        if v is None:
            continue
        if isinstance(v, int):
            return str(v)
        if isinstance(v, str):
            s = v.strip()
            m = re.search(r"\d+", s)
            if m:
                return m.group(0)
    return None

def _normalize_journal(j: str) -> str:
    s = re.sub(r"[^A-Za-z0-9]+", "", (j or "").lower())
    return s[:32] if s else ""

def _extract_year(rec: Dict[str, Any]) -> Optional[str]:
    year = _first_intish_value(rec, [
        ["year"], ["pub_year"], ["publication_year"],
        ["metadata", "year"], ["metadata", "pub_year"], ["paper", "year"],
    ])
    if year and len(year) == 4:
        return year

    date_str = _first_str_value(rec, [
        ["date"], ["publication_date"], ["pub_date"],
        ["metadata", "date"], ["metadata", "publication_date"], ["paper", "date"],
    ])
    if date_str:
        m = _YEAR_RE.search(date_str)
        if m:
            return m.group(1)
    return None

def _extract_volume(rec: Dict[str, Any]) -> Optional[str]:
    vol = _first_str_value(rec, [
        ["volume"], ["vol"], ["metadata", "volume"], ["paper", "volume"],
    ])
    if not vol:
        return None
    vol2 = re.sub(r"[^0-9A-Za-z]+", "", vol)
    return vol2 or None

def _extract_pages(rec: Dict[str, Any]) -> Optional[str]:
    pages = _first_str_value(rec, [
        ["pages"], ["page_range"], ["pagination"], ["pageNumbers"],
        ["metadata", "pages"], ["metadata", "page_range"], ["paper", "pages"],
    ])
    if pages:
        s = pages.strip().replace("–", "-").replace("—", "-")
        m = _PAGES_RE.match(s)
        if m:
            return f"{m.group(1)}-{m.group(2)}"
        s2 = re.sub(r"\s+", "", s)
        s2 = re.sub(r"[^0-9A-Za-z\-]+", "", s2)
        return s2 or None

    p1 = _first_intish_value(rec, [
        ["page_start"], ["first_page"], ["start_page"],
        ["metadata", "page_start"], ["paper", "page_start"],
    ])
    p2 = _first_intish_value(rec, [
        ["page_end"], ["last_page"], ["end_page"],
        ["metadata", "page_end"], ["paper", "page_end"],
    ])
    if p1 and p2:
        return f"{p1}-{p2}"
    if p1:
        return p1
    return None

def _extract_journal(rec: Dict[str, Any]) -> Optional[str]:
    return _first_str_value(rec, [
        ["journal"], ["journal_name"], ["journalTitle"],
        ["metadata", "journal"], ["metadata", "journal_name"], ["paper", "journal"],
    ])

def derive_doc_id_with_source(rec: Dict[str, Any]) -> Tuple[Optional[str], str]:
    """
    Return (doc_id, doc_id_source).
    doc_id_source: pmid | doi | jvp | file | titlehash | none
    """
    pmid = _first_intish_value(rec, [
        ["pmid"], ["PMID"], ["pubmed_id"], ["pubmedId"], ["PubMedID"],
        ["metadata", "pmid"], ["metadata", "PMID"], ["paper", "pmid"], ["paper", "PMID"],
    ])
    if pmid:
        return f"PMID:{pmid}", "pmid"

    doi = _first_str_value(rec, [
        ["doi"], ["DOI"], ["metadata", "doi"], ["metadata", "DOI"], ["paper", "doi"], ["paper", "DOI"],
    ])
    if doi:
        doi2 = _DOI_PREFIX_RE.sub("", doi).strip()
        return f"DOI:{doi2}", "doi"

    journal = _extract_journal(rec)
    year = _extract_year(rec)
    volume = _extract_volume(rec)
    pages = _extract_pages(rec)
    jnorm = _normalize_journal(journal or "")
    if jnorm and year and volume and pages:
        return f"JVP:{jnorm}:{year}:{volume}:{pages}", "jvp"

    file_path = _first_str_value(rec, [
        ["source_file"], ["file"], ["filename"], ["pdf_file"],
        ["source", "file"], ["_source", "file"], ["metadata", "file"], ["metadata", "filename"],
    ])
    if file_path:
        name = Path(file_path).name.strip()
        if name:
            return f"FILE:{name}", "file"
        return f"FILEHASH:{_stable_hash(file_path)}", "file"

    title = _first_str_value(rec, [
        ["title"], ["paper_title"], ["metadata", "title"], ["paper", "title"],
    ])
    if title:
        return f"TITLEHASH:{_stable_hash(title.lower().strip())}", "titlehash"

    return None, "none"

# ============================================================
# PROMPT
# ============================================================
SYSTEM_INSTRUCTIONS = (
    "Extract 'mechanistic atoms' from biomedical text.\n\n"
    "Definition: an atom MUST include an explicit effect on a readout.\n"
    "Format: [INTERVENTION] causes [EFFECT] in [READOUT] in a [SYSTEM].\n\n"
    "Hard rules:\n"
    "1) Do NOT invent facts.\n"
    "2) Do NOT assume knockdown succeeded unless the text explicitly says reduction/knockdown/confirmed.\n"
    "3) If the text only describes delivering siRNA/plasmid/drug but gives no stated change in any readout, output no atoms and add a warning.\n"
    "4) You may extract multiple readouts per intervention if they are explicitly stated.\n"
    "5) Rescue/add-back atoms must state what readout is rescued.\n"
    f"6) Keep at most {MAX_ATOMS_PER_CHUNK} atoms.\n"
)

# ============================================================
# MODEL CALLS + ROUTING
# ============================================================
def call_model(model: str, chunk_text: str, mentions: List[Dict[str, Any]]) -> Dict[str, Any]:
    payload = {
        "chunk_text": chunk_text,
        "mentions": compact_mentions(mentions),
        "hints": {"fig_refs": hint_figrefs(chunk_text), "species": hint_species(chunk_text)},
    }
    resp = client.responses.create(
        model=model,
        input=[
            {"role": "system", "content": SYSTEM_INSTRUCTIONS},
            {"role": "user", "content": json.dumps(payload, ensure_ascii=False)},
        ],
        text={
            "format": {
                "type": "json_schema",
                "name": ATOM_SCHEMA_WRAPPER["name"],
                "strict": True,
                "schema": ATOM_SCHEMA_WRAPPER["schema"],
            }
        },
    )
    return json.loads(resp.output_text)

def should_escalate(mentions: List[Dict[str, Any]], atoms: List[Dict[str, Any]]) -> bool:
    if len(mentions) > 0 and len(atoms) == 0:
        return True
    if len(atoms) > 0:
        avg_conf = sum(float(a.get("confidence", 0.0)) for a in atoms) / len(atoms)
        if avg_conf < 0.55:
            return True
    return False

def extract_atoms_with_routing(chunk_text: str, mentions: List[Dict[str, Any]]) -> Dict[str, Any]:
    routing = {"first_model": MODEL_FAST, "escalated": False, "final_model": MODEL_FAST, "reason": None}
    out_fast = call_model(MODEL_FAST, chunk_text, mentions)
    atoms_fast = out_fast.get("atoms", [])

    if should_escalate(mentions, atoms_fast):
        routing["escalated"] = True
        routing["final_model"] = MODEL_STRONG
        routing["reason"] = {"type": "low_confidence_or_empty", "details": "heuristics triggered"}
        out_strong = call_model(MODEL_STRONG, chunk_text, mentions)
        out_strong["_routing"] = routing
        return out_strong

    out_fast["_routing"] = routing
    return out_fast

# ============================================================
# POST-FILTER
# ============================================================
EFFECT_CUE = re.compile(
    r"\b("
    r"inhibit|inhibited|inhibition|suppress|suppressed|suppressing|"
    r"reduce|reduced|reduces|reduction|decrease|decreased|decreases|"
    r"increase|increased|increases|elevate|elevated|"
    r"no effect|did not affect|had no effect|"
    r"rescue|rescued|restored|restore|"
    r"complete inhibition|abolish|abolished"
    r")\b",
    re.IGNORECASE,
)
SETUP_ONLY_READOUT = re.compile(r"\b(expression|function|knockdown|silencing)\b", re.IGNORECASE)

def looks_like_setup_only(atoms: List[Dict[str, Any]], warnings: List[str]) -> bool:
    if not atoms:
        return True
    wtxt = " ".join(warnings or []).lower()
    if "no explicit functional readouts" in wtxt or "only describes" in wtxt:
        return True
    for a in atoms:
        ro = (a.get("readout", {}) or {}).get("name", "")
        sq = (a.get("evidence", {}) or {}).get("supporting_quote", "")
        if (not SETUP_ONLY_READOUT.search(ro or "")) and EFFECT_CUE.search(sq or ""):
            return False
    return True

def post_filter_atoms(atoms: List[Dict[str, Any]]) -> Tuple[List[Dict[str, Any]], int]:
    kept: List[Dict[str, Any]] = []
    dropped = 0
    for a in atoms or []:
        sq = (a.get("evidence", {}) or {}).get("supporting_quote", "")
        if EFFECT_CUE.search(sq or ""):
            kept.append(a)
        else:
            dropped += 1
    return kept, dropped

# ============================================================
# DOC-AWARE BRIDGING GUARD
# ============================================================
def can_bridge_same_doc_adjacent(a: Dict[str, Any], b: Dict[str, Any]) -> Tuple[bool, str]:
    a_doc = a.get("doc_id")
    b_doc = b.get("doc_id")
    if not a_doc or not b_doc:
        return False, "missing_doc_id"
    if a_doc != b_doc:
        return False, "doc_id_mismatch"

    a_idx = a.get("chunk_index")
    b_idx = b.get("chunk_index")
    if a_idx is None or b_idx is None:
        return False, "missing_chunk_index"
    try:
        ai = int(a_idx)
        bi = int(b_idx)
    except Exception:
        return False, "non_integer_chunk_index"
    if abs(ai - bi) != 1:
        return False, "non_adjacent_chunk_index"
    return True, "ok"

def bridge_text(a_text: str, b_text: str) -> str:
    return (a_text or "").rstrip() + "\n\n" + (b_text or "").lstrip()

def bridge_mentions(a_mentions: List[Dict[str, Any]], b_mentions: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    return list(a_mentions or []) + list(b_mentions or [])

def choose_best_bridged(candidates: List[Tuple[str, Dict[str, Any], List[int], List[str]]]) -> Optional[Tuple[str, Dict[str, Any], List[int], List[str]]]:
    best = None
    for mode, outd, src_chunks, src_docs in candidates:
        atoms = outd.get("atoms", []) or []
        if best is None:
            best = (mode, outd, src_chunks, src_docs)
            continue
        best_atoms = best[1].get("atoms", []) or []
        if len(atoms) > len(best_atoms):
            best = (mode, outd, src_chunks, src_docs)
        elif len(atoms) == len(best_atoms) and len(atoms) > 0:
            avg = sum(float(a.get("confidence", 0.0)) for a in atoms) / len(atoms)
            bavg = sum(float(a.get("confidence", 0.0)) for a in best_atoms) / len(best_atoms)
            if avg > bavg:
                best = (mode, outd, src_chunks, src_docs)
    return best

# ============================================================
# MAIN
# ============================================================
def main() -> int:
    ap = argparse.ArgumentParser(description="PATHAI atoms extraction with robust doc_id derivation and safe bridging switch")
    ap.add_argument("--infile", default=str(DEFAULT_INFILE), help="Input mentions.jsonl")
    ap.add_argument("--outfile", default=str(DEFAULT_OUTFILE), help="Output atoms.jsonl")
    ap.add_argument("--bridge", action="store_true", help="Enable bridging (safe: same doc_id + adjacent chunk_index). Default OFF.")
    ap.add_argument("--default_doc_id", default=None, help="If cannot derive doc_id, use this (otherwise falls back to CHUNK:<chunk_id>).")
    ap.add_argument("--assign_chunk_index", action="store_true", help="Assign chunk_index per doc_id if missing (sequential in file order).")
    ap.add_argument("--no_bridge_forward", action="store_true")
    ap.add_argument("--no_bridge_backward", action="store_true")
    args = ap.parse_args()

    infile = Path(args.infile)
    outfile = Path(args.outfile)
    enable_bridging = bool(args.bridge)
    try_forward = (not args.no_bridge_forward)
    try_backward = (not args.no_bridge_backward)

    if not infile.exists():
        raise FileNotFoundError(f"Cannot find {infile.resolve()}")

    records: List[Dict[str, Any]] = []
    for ln in infile.read_text(encoding="utf-8", errors="ignore").splitlines():
        ln = ln.strip()
        if ln:
            records.append(json.loads(ln))

    # ---- doc_id derivation happens HERE ----
    src_counts: Dict[str, int] = {}
    for r in records:
        if not r.get("doc_id"):
            doc_id, src = derive_doc_id_with_source(r)
            if doc_id:
                r["doc_id"] = doc_id
                r["doc_id_source"] = src
                src_counts[src] = src_counts.get(src, 0) + 1
            else:
                if args.default_doc_id:
                    r["doc_id"] = args.default_doc_id
                    r["doc_id_source"] = "default"
                    src_counts["default"] = src_counts.get("default", 0) + 1
                else:
                    # SAFE fallback for mixed corpora: unique per line
                    cid = r.get("chunk_id")
                    r["doc_id"] = f"CHUNK:{cid}"
                    r["doc_id_source"] = "chunk_fallback"
                    src_counts["chunk_fallback"] = src_counts.get("chunk_fallback", 0) + 1

    # Optional chunk_index assignment per doc_id
    if args.assign_chunk_index:
        counters: Dict[str, int] = {}
        for r in records:
            doc = r.get("doc_id")
            if not doc:
                continue
            if r.get("chunk_index") is None:
                counters.setdefault(doc, 0)
                r["chunk_index"] = counters[doc]
                counters[doc] += 1

    total_atoms = 0
    escalations = 0
    bridges_used = 0
    bridges_attempted = 0
    dropped_total = 0

    with outfile.open("w", encoding="utf-8", newline="\n") as fout:
        for idx, rec in enumerate(records):
            chunk_id = rec.get("chunk_id")
            doc_id = rec.get("doc_id")
            doc_id_source = rec.get("doc_id_source")
            chunk_index = rec.get("chunk_index")

            if "error" in rec:
                out_rec = {
                    "doc_id": doc_id,
                    "doc_id_source": doc_id_source,
                    "chunk_index": chunk_index,
                    "chunk_id": chunk_id,
                    "atoms": [],
                    "warnings": ["Skipped due to upstream error."],
                    "bridge": {
                        "enabled": enable_bridging,
                        "attempted": False,
                        "used": False,
                        "mode": None,
                        "source_doc_ids": [doc_id] if doc_id else [],
                        "source_chunk_ids": [chunk_id],
                        "skipped_reason": "upstream_error",
                    },
                    "_routing": {"skipped": True},
                    "_post": {"dropped_atoms": 0},
                }
                fout.write(json.dumps(out_rec, ensure_ascii=False) + "\n")
                continue

            chunk_text = rec.get("chunk_text", "")
            mentions = rec.get("mentions", [])

            out = extract_atoms_with_routing(chunk_text, mentions)
            atoms = out.get("atoms", []) or []
            warnings = out.get("warnings", []) or []
            routing = out.get("_routing", {}) or {}

            atoms, dropped = post_filter_atoms(atoms)
            dropped_total += dropped

            used_bridge = False
            attempted_bridge = False
            bridge_mode = None
            skipped_reason = None
            source_chunk_ids = [chunk_id]
            source_doc_ids = [doc_id] if doc_id else []

            need_bridge = (len(mentions or []) > 0 and (len(atoms) == 0 or looks_like_setup_only(atoms, warnings)))

            if enable_bridging and need_bridge:
                attempted_bridge = True
                bridges_attempted += 1
                candidates: List[Tuple[str, Dict[str, Any], List[int], List[str]]] = []

                if try_forward and idx + 1 < len(records):
                    nxt = records[idx + 1]
                    ok, why = can_bridge_same_doc_adjacent(rec, nxt)
                    if ok and "error" not in nxt:
                        t = bridge_text(chunk_text, nxt.get("chunk_text", ""))
                        m = bridge_mentions(mentions, nxt.get("mentions", []))
                        bout = extract_atoms_with_routing(t, m)
                        batoms = bout.get("atoms", []) or []
                        bwarn = bout.get("warnings", []) or []
                        batoms, bdropped = post_filter_atoms(batoms)
                        bout["atoms"] = batoms
                        bout["warnings"] = bwarn
                        bout["_post"] = {"dropped_atoms": bdropped}
                        candidates.append(("forward", bout, [chunk_id, nxt.get("chunk_id")], [rec.get("doc_id"), nxt.get("doc_id")]))
                    else:
                        skipped_reason = skipped_reason or f"forward_{why}"

                if try_backward and idx - 1 >= 0:
                    prv = records[idx - 1]
                    ok, why = can_bridge_same_doc_adjacent(prv, rec)
                    if ok and "error" not in prv:
                        t = bridge_text(prv.get("chunk_text", ""), chunk_text)
                        m = bridge_mentions(prv.get("mentions", []), mentions)
                        bout = extract_atoms_with_routing(t, m)
                        batoms = bout.get("atoms", []) or []
                        bwarn = bout.get("warnings", []) or []
                        batoms, bdropped = post_filter_atoms(batoms)
                        bout["atoms"] = batoms
                        bout["warnings"] = bwarn
                        bout["_post"] = {"dropped_atoms": bdropped}
                        candidates.append(("backward", bout, [prv.get("chunk_id"), chunk_id], [prv.get("doc_id"), rec.get("doc_id")]))
                    else:
                        skipped_reason = skipped_reason or f"backward_{why}"

                best = choose_best_bridged(candidates)
                if best is not None and len(best[1].get("atoms", []) or []) > 0:
                    used_bridge = True
                    bridge_mode = best[0]
                    out = best[1]
                    atoms = out.get("atoms", []) or []
                    warnings = out.get("warnings", []) or []
                    routing = out.get("_routing", routing) or routing
                    source_chunk_ids = best[2]
                    source_doc_ids = [d for d in best[3] if d]
                    bridges_used += 1
                else:
                    if skipped_reason is None:
                        skipped_reason = "no_viable_bridge_candidate"

            if routing.get("escalated"):
                escalations += 1
            total_atoms += len(atoms)

            out_rec = {
                "doc_id": doc_id,
                "doc_id_source": doc_id_source,
                "chunk_index": chunk_index,
                "chunk_id": chunk_id,
                "atoms": atoms,
                "warnings": warnings,
                "bridge": {
                    "enabled": enable_bridging,
                    "attempted": attempted_bridge,
                    "used": used_bridge,
                    "mode": bridge_mode,
                    "source_doc_ids": source_doc_ids,
                    "source_chunk_ids": source_chunk_ids,
                    "skipped_reason": skipped_reason,
                },
                "_routing": routing,
                "_post": {"dropped_atoms": dropped},
            }
            fout.write(json.dumps(out_rec, ensure_ascii=False) + "\n")

            print(
                f"chunk {chunk_id} doc_id={doc_id}({doc_id_source}) idx={chunk_index} "
                f"atoms={len(atoms)} escalated={routing.get('escalated', False)} "
                f"bridge_enabled={enable_bridging} bridged={used_bridge} dropped={dropped}"
            )

    print(
        f"Done. total_atoms={total_atoms}, escalations={escalations}, "
        f"bridges_attempted={bridges_attempted}, bridges_used={bridges_used}, dropped_total={dropped_total}"
    )
    print("doc_id sources:", ", ".join(f"{k}={v}" for k, v in sorted(src_counts.items())))
    if not enable_bridging:
        print("Note: bridging was OFF (recommended for mixed/random chunks).")
    else:
        print("Note: bridging ON uses strict guard: same doc_id + adjacent chunk_index.")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
```

### Run now (safe for mixed chunks; bridging OFF)

```bat
conda activate pathai
cd "C:\Users\Prem Subramaniam\Documents\Pathway AI"
python make_atoms_docaware_v6.py
```

* * *

## So “where to now?” (next concrete milestone)

1. Run v6 once and confirm you see `doc_id_source=chunk_fallback` for these trial chunks (that’s expected right now).
2. Then we tackle the **span mismatch** in your mention miner (span mismatch = the reported character offsets don’t match the `raw_text` in `chunk_text`), because it’s the last thing that will keep your pipeline truly auditable at scale.
3. After that, we can go to **graph building** with confidence—because doc-aware evidence counting will already be in place (`doc_id` + `doc_id_source` carried through), even before ingestion is “perfect.”

If you paste 2–3 lines of your current `mine_with_routing.py` output (a mentions.jsonl line that includes the bad span mismatch), I’ll write the full “span repair” update as the next script step (and I’ll print the full script, tagged).

* * *

**You:**

Here is the ouput of v6:  (pathai) C:\Users\Prem Subramaniam\Documents\Pathway AI>python make_atoms_docaware_v6.py
chunk 1 doc_id=CHUNK:1(chunk_fallback) idx=None atoms=0 escalated=False bridge_enabled=False bridged=False dropped=2
chunk 2 doc_id=CHUNK:2(chunk_fallback) idx=None atoms=9 escalated=False bridge_enabled=False bridged=False dropped=1
chunk 3 doc_id=CHUNK:3(chunk_fallback) idx=None atoms=0 escalated=True bridge_enabled=False bridged=False dropped=0
chunk 4 doc_id=CHUNK:4(chunk_fallback) idx=None atoms=0 escalated=False bridge_enabled=False bridged=False dropped=2
chunk 5 doc_id=CHUNK:5(chunk_fallback) idx=None atoms=0 escalated=False bridge_enabled=False bridged=False dropped=0
chunk 6 doc_id=CHUNK:6(chunk_fallback) idx=None atoms=0 escalated=False bridge_enabled=False bridged=False dropped=4
chunk 7 doc_id=CHUNK:7(chunk_fallback) idx=None atoms=1 escalated=False bridge_enabled=False bridged=False dropped=4
chunk 8 doc_id=CHUNK:8(chunk_fallback) idx=None atoms=3 escalated=False bridge_enabled=False bridged=False dropped=1
chunk 9 doc_id=CHUNK:9(chunk_fallback) idx=None atoms=2 escalated=False bridge_enabled=False bridged=False dropped=0
chunk 10 doc_id=CHUNK:10(chunk_fallback) idx=None atoms=4 escalated=False bridge_enabled=False bridged=False dropped=1
Done. total_atoms=19, escalations=1, bridges_attempted=0, bridges_used=0, dropped_total=15
doc_id sources: chunk_fallback=10
Note: bridging was OFF (recommended for mixed/random chunks).

* * *

**ChatGPT:**

TAG: **PATHAI-0062**

Nice — this output is exactly what we hoped v6 would do in “mixed-corpus, no-ingestion-metadata-yet” mode.

### What your v6 run _means_

* **`doc_id=CHUNK:N (chunk_fallback)`**  
    _chunk_fallback_ (meaning: “we don’t actually know the paper ID yet, so we assign a safe unique ID per chunk”) forces every chunk to behave like its own “document.” That **prevents any within-paper bridging** and also prevents us from accidentally treating two different papers as the same paper.
* **`idx=None`**  
    No `chunk_index` exists yet (chunk order within a paper), which is fine right now.
* **`atoms=…`**  
    Atoms that survived the “explicit effect in quote” filter.
* **`dropped=…` and `dropped_total=15`**  
    The model _did_ output atoms for those chunks, but **15 of them were thrown away** because their `supporting_quote` didn’t contain an explicit effect cue (reduce/decrease/inhibit/no effect/rescue/restore/etc.). This is the “no assumed knockdown / no invented outcomes” guard doing its job.
* **`escalated=1` (chunk 3)**  
    The fast model returned nothing useful, so it escalated to the stronger model, but still ended up with **0 atoms** after filtering. That usually means the chunk is genuinely “setup/background” or the effects weren’t stated explicitly.

### Why this looks different from your earlier audit (25 atoms → now 19 atoms)

Two reasons, both normal:

1. **Re-extraction is stochastic** (same input can yield slightly different atoms across runs/models).
2. v6 is **strict about effect language in the quote**, and you can see that strictness in the high `dropped_total=15`. Earlier you had a run where fewer got dropped (or bridging helped in 2 cases).

### Did we achieve what we needed?

Yes:

* **Bridging is effectively impossible right now**, because each chunk has a unique doc_id (`CHUNK:N`). That’s exactly the “be fair” constraint you laid out: _no cross-paper bridging_.
* The pipeline is now safe against “assumed knockdown” style atoms — at the cost of dropping some borderline cases.

### So where to now?

You have two clean options (both valid):

**Option A — Keep strictness, proceed.**  
This is defensible if your priority is “only keep atoms with explicit outcome language.” You can move forward and accept that many chunks will be `atoms=[]` until ingestion adds better metadata and/or you tune extraction.

**Option B — Slightly widen what counts as an “explicit effect.”**  
Right now your effect-cue list misses some very common biology verbs like **“induced,” “promoted,” “attenuated,” “enhanced,” “blocked,” “activated,”** etc. If many of the 15 dropped atoms had quotes like “induced autophagy” (which is absolutely an explicit effect), then the filter is too narrow and you’re losing good signal.

The _right next step before changing anything_ is to **audit the dropped atoms** (chunk_id + supporting_quote + readout) so we can see whether they were:

* legitimately weak/assumed (good to drop), or
* legitimately explicit but using verbs we didn’t include (we should keep).

### One important note about the graph stage

You _can_ prototype graph building now, but with `doc_id_source=chunk_fallback`, you **cannot** compute “multi-paper support” correctly yet (because every chunk looks like its own “paper”). That will undercount the “independent evidence across papers” strength you care about.

So the most efficient path is:

1. **Add minimal ingestion metadata later** (even just `source_file` or PMID) → real `doc_id` starts working.
2. Then graph scoring can properly count **distinct doc_id** support.

If you want, I’ll write the next small script as the immediate follow-on: a **dropped-atoms report** (CSV + top examples) so we can decide whether to expand the effect cue list _without weakening rigor_.

* * *

**You:**

Please explain in real laymans language: Add minimal ingestion metadata later (even just source_file or PMID) → real doc_id starts working.

* * *

**ChatGPT:**

TAG: **PATHAI-0063**

Sure. Here’s what that sentence means in plain language.

Right now, each “chunk” of text you feed in is basically a **stand-alone anonymous snippet**. It has the text, but it doesn’t reliably say _which paper it came from_. Because of that, the script can’t label the paper, so it uses a safe placeholder like:

* `doc_id = CHUNK:7`

That’s like saying: “I don’t know the real source; I’ll just call it _Snippet #7_.”

### What “minimal ingestion metadata” means

When you eventually “ingest” papers (i.e., bring papers into your system), you should attach **just one small piece of source info** to every chunk so the script can tell which chunks came from the same paper.

Two easy examples:

1. **PMID**  
    If the paper came from PubMed, it has a PubMed ID (PMID).  
    So you’d store something like:

* `pmid: 12345678`

Then the script can make:

* `doc_id = PMID:12345678`

2. **source_file**  
    If you extracted chunks from a PDF on disk, store the file name:

* `source_file: "some_paper.pdf"`

Then the script can make:

* `doc_id = FILE:some_paper.pdf`

### Why this matters

Once every chunk carries **PMID or source_file**, the script can stop guessing and can reliably say:

* “Chunks 12, 13, 14 all came from **the same paper**.”

That unlocks two things you care about:

1. **Correct within-paper bridging (later)**  
    Bridging only makes sense if two chunks are from the **same paper** and near each other. With a real `doc_id`, the code can enforce that.
2. **Correct multi-paper evidence counting (for graph strength)**  
    You said the pathway should get stronger only when **multiple different papers** support it.  
    That requires knowing whether two atoms came from:

* the _same_ paper (same `doc_id`) or
* _different_ papers (different `doc_id`)

Without PMID/source_file, the system can’t tell, so it can’t fairly count “independent evidence.”

### One-sentence takeaway

Adding “source_file” or “PMID” is just giving each snippet a **name tag for which paper it came from**, so everything downstream (bridging + cross-paper evidence strength) can behave correctly.

* * *

**You:**

OK, so I introduced the PMID in the original selected chunks ingested.  We should also include PMCID in the doc_id.  The chunks file is pisk_mtor_seed_texts.txt.

* * *

**ChatGPT:**

TAG: **PATHAI-0064**

Yes — adding **PMCID** is a good idea.

* **PMID** = the PubMed record ID (good for bibliographic identity)
* **PMCID** = the PubMed Central full-text ID (useful because it often tells you you can fetch the full paper from PMC)

So the plan is: keep `doc_id` primarily anchored on PMID when present, but **append PMCID when available**, e.g.:

* `doc_id = "PMID:37123456|PMCID:PMC10987654"`
* if there’s no PMID but there is PMCID: `doc_id = "PMCID:PMC10987654"`

One practical note: `make_atoms_docaware_v6.py` reads **`mentions.jsonl`**, not `pisk_mtor_seed_texts.txt`. So whatever you’ve added (PMID/PMCID) in `pisk_mtor_seed_texts.txt` must be **carried through into each JSONL record** in `mentions.jsonl` (top-level fields like `"pmid": "..."`, `"pmcid": "..."`).

Below is the updated script (v7) that incorporates PMCID into `doc_id`.

* * *

## Full script v7: `make_atoms_docaware_v7.py`

**TAG: PATHAI-0064**  
Save as: **`make_atoms_docaware_v7.py`**

```Python
#!/usr/bin/env python3
import os
import json
import re
import argparse
import hashlib
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple
from openai import OpenAI

# ============================================================
# DEFAULTS
# ============================================================
DEFAULT_INFILE = Path("mentions.jsonl")
DEFAULT_OUTFILE = Path("atoms.jsonl")

MODEL_FAST = "gpt-4o-mini"
MODEL_STRONG = "gpt-4.1"

MAX_ATOMS_PER_CHUNK = 30

# Bridging is OFF by default (safe for mixed/random chunk streams)
DEFAULT_ENABLE_BRIDGING = False

# ============================================================
# OPENAI CLIENT
# ============================================================
def _get_api_key() -> str:
    key = os.getenv("OPENAI_API_KEY")
    if not key:
        raise RuntimeError(
            "OPENAI_API_KEY is not set.\n"
            "Miniforge Prompt (temporary):  set OPENAI_API_KEY=YOUR_KEY\n"
            "Persistent (Windows):         setx OPENAI_API_KEY \"YOUR_KEY\"  (then reopen prompt)"
        )
    return key

client = OpenAI(api_key=_get_api_key())

# ============================================================
# STRICT JSON SCHEMA FOR ATOMS (model output)
# ============================================================
ATOM_SCHEMA_WRAPPER: Dict[str, Any] = {
    "name": "MechanisticAtoms",
    "schema": {
        "type": "object",
        "additionalProperties": False,
        "required": ["atoms", "warnings"],
        "properties": {
            "atoms": {
                "type": "array",
                "items": {
                    "type": "object",
                    "additionalProperties": False,
                    "required": [
                        "intervention",
                        "system",
                        "readout",
                        "effect",
                        "strength_cues",
                        "evidence",
                        "confidence",
                    ],
                    "properties": {
                        "intervention": {
                            "type": "object",
                            "additionalProperties": False,
                            "required": ["category", "raw_text", "target", "modality"],
                            "properties": {
                                "category": {
                                    "type": "string",
                                    "enum": [
                                        "GENETIC_KO",
                                        "CRISPR_KO",
                                        "CRISPRi",
                                        "CRISPRa",
                                        "KNOCKDOWN_RNAI",
                                        "SPLICING_MODULATION",
                                        "OVEREXPRESSION",
                                        "RESCUE_ADD_BACK",
                                        "DOMINANT_NEGATIVE",
                                        "MUTANT_VARIANT",
                                        "CHEMICAL_INHIBITOR",
                                        "CHEMICAL_ACTIVATOR",
                                        "CHEMICAL_DEGRADER",
                                        "STIMULUS_TREATMENT",
                                        "NEUTRALIZING_ANTIBODY",
                                        "UNKNOWN",
                                    ],
                                },
                                "raw_text": {"type": "string", "minLength": 1},
                                "target": {
                                    "anyOf": [
                                        {
                                            "type": "object",
                                            "additionalProperties": False,
                                            "required": ["name", "entity_type"],
                                            "properties": {
                                                "name": {"type": "string"},
                                                "entity_type": {
                                                    "type": "string",
                                                    "enum": [
                                                        "gene",
                                                        "protein",
                                                        "chemical",
                                                        "stimulus",
                                                        "antibody",
                                                        "unknown",
                                                    ],
                                                },
                                            },
                                        },
                                        {"type": "null"},
                                    ]
                                },
                                "modality": {
                                    "type": "string",
                                    "enum": [
                                        "LOF",
                                        "GOF",
                                        "INHIBITION",
                                        "ACTIVATION",
                                        "DEGRADATION",
                                        "RESCUE",
                                        "UNKNOWN",
                                    ],
                                },
                            },
                        },
                        "system": {
                            "type": "object",
                            "additionalProperties": False,
                            "required": [
                                "species",
                                "cell_type",
                                "cell_lines",
                                "genotype_context",
                                "disease_context",
                            ],
                            "properties": {
                                "species": {"type": ["string", "null"]},
                                "cell_type": {"type": ["string", "null"]},
                                "cell_lines": {"type": "array", "items": {"type": "string"}},
                                "genotype_context": {"type": ["string", "null"]},
                                "disease_context": {"type": ["string", "null"]},
                            },
                        },
                        "readout": {
                            "type": "object",
                            "additionalProperties": False,
                            "required": ["name", "assay", "figure_refs"],
                            "properties": {
                                "name": {"type": "string"},
                                "assay": {"type": ["string", "null"]},
                                "figure_refs": {"type": "array", "items": {"type": "string"}},
                            },
                        },
                        "effect": {
                            "type": "object",
                            "additionalProperties": False,
                            "required": ["direction", "timepoint", "magnitude", "comparison"],
                            "properties": {
                                "direction": {
                                    "type": "string",
                                    "enum": ["increase", "decrease", "no_change", "mixed", "unknown"],
                                },
                                "timepoint": {"type": ["string", "null"]},
                                "magnitude": {"type": ["string", "null"]},
                                "comparison": {"type": ["string", "null"]},
                            },
                        },
                        "strength_cues": {
                            "type": "object",
                            "additionalProperties": False,
                            "required": ["has_rescue", "has_control", "has_multiple_lines", "other"],
                            "properties": {
                                "has_rescue": {"type": "boolean"},
                                "has_control": {"type": "boolean"},
                                "has_multiple_lines": {"type": "boolean"},
                                "other": {"type": "array", "items": {"type": "string"}},
                            },
                        },
                        "evidence": {
                            "type": "object",
                            "additionalProperties": False,
                            "required": ["supporting_quote", "notes"],
                            "properties": {
                                "supporting_quote": {"type": "string"},
                                "notes": {"type": ["string", "null"]},
                            },
                        },
                        "confidence": {"type": "number", "minimum": 0, "maximum": 1},
                    },
                },
            },
            "warnings": {"type": "array", "items": {"type": "string"}},
        },
    },
}

# ============================================================
# LIGHTWEIGHT HINTS
# ============================================================
FIGREF_REGEX = re.compile(r"\b(Fig\.?\s*\d+[A-Za-z]?)\b", re.IGNORECASE)
SPECIES_REGEX = re.compile(r"\b(human|mouse|murine|rat)\b", re.IGNORECASE)

def _uniq_preserve(seq: List[str]) -> List[str]:
    seen = set()
    out = []
    for x in seq:
        k = x.lower()
        if k not in seen:
            seen.add(k)
            out.append(x)
    return out

def hint_figrefs(text: str) -> List[str]:
    return _uniq_preserve([m.group(1) for m in FIGREF_REGEX.finditer(text or "")])

def hint_species(text: str) -> Optional[str]:
    m = SPECIES_REGEX.search(text or "")
    if not m:
        return None
    s = m.group(1).lower()
    return "mouse" if s == "murine" else s

def compact_mentions(mentions: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    out = []
    for i, m in enumerate(mentions or [], start=1):
        out.append({
            "i": i,
            "category": m.get("category"),
            "raw_text": m.get("raw_text"),
            "target_guess": m.get("target_guess"),
            "method_cues": m.get("method_cues", []),
        })
    return out

# ============================================================
# DOC_ID DERIVATION (PMID(+PMCID) → PMCID → DOI → JVP → FILE → TITLEHASH → CHUNK)
# ============================================================
_DOI_PREFIX_RE = re.compile(r"^(https?://(dx\.)?doi\.org/|doi:\s*)", re.IGNORECASE)
_YEAR_RE = re.compile(r"\b(19\d{2}|20\d{2})\b")
_PAGES_RE = re.compile(r"^\s*(\d+)\s*[-–—]\s*(\d+)\s*$")

def _stable_hash(text: str, n: int = 12) -> str:
    return hashlib.sha1(text.encode("utf-8")).hexdigest()[:n]

def _get_nested(rec: Dict[str, Any], path: List[str]) -> Optional[Any]:
    cur: Any = rec
    for k in path:
        if not isinstance(cur, dict) or k not in cur:
            return None
        cur = cur[k]
    return cur

def _first_str_value(rec: Dict[str, Any], key_paths: List[List[str]]) -> Optional[str]:
    for path in key_paths:
        v = _get_nested(rec, path)
        if isinstance(v, str) and v.strip():
            return v.strip()
    return None

def _first_intish_value(rec: Dict[str, Any], key_paths: List[List[str]]) -> Optional[str]:
    for path in key_paths:
        v = _get_nested(rec, path)
        if v is None:
            continue
        if isinstance(v, int):
            return str(v)
        if isinstance(v, str):
            s = v.strip()
            m = re.search(r"\d+", s)
            if m:
                return m.group(0)
    return None

def _normalize_pmcid(x: str) -> Optional[str]:
    if not x:
        return None
    s = x.strip()
    # allow "PMC123", "pmc123", or "123"
    if s.lower().startswith("pmc"):
        digits = re.sub(r"\D+", "", s)
        return f"PMC{digits}" if digits else None
    digits = re.sub(r"\D+", "", s)
    return f"PMC{digits}" if digits else None

def _normalize_journal(j: str) -> str:
    s = re.sub(r"[^A-Za-z0-9]+", "", (j or "").lower())
    return s[:32] if s else ""

def _extract_year(rec: Dict[str, Any]) -> Optional[str]:
    year = _first_intish_value(rec, [
        ["year"], ["pub_year"], ["publication_year"],
        ["metadata", "year"], ["metadata", "pub_year"], ["paper", "year"],
    ])
    if year and len(year) == 4:
        return year

    date_str = _first_str_value(rec, [
        ["date"], ["publication_date"], ["pub_date"],
        ["metadata", "date"], ["metadata", "publication_date"], ["paper", "date"],
    ])
    if date_str:
        m = _YEAR_RE.search(date_str)
        if m:
            return m.group(1)
    return None

def _extract_volume(rec: Dict[str, Any]) -> Optional[str]:
    vol = _first_str_value(rec, [
        ["volume"], ["vol"], ["metadata", "volume"], ["paper", "volume"],
    ])
    if not vol:
        return None
    vol2 = re.sub(r"[^0-9A-Za-z]+", "", vol)
    return vol2 or None

def _extract_pages(rec: Dict[str, Any]) -> Optional[str]:
    pages = _first_str_value(rec, [
        ["pages"], ["page_range"], ["pagination"], ["pageNumbers"],
        ["metadata", "pages"], ["metadata", "page_range"], ["paper", "pages"],
    ])
    if pages:
        s = pages.strip().replace("–", "-").replace("—", "-")
        m = _PAGES_RE.match(s)
        if m:
            return f"{m.group(1)}-{m.group(2)}"
        s2 = re.sub(r"\s+", "", s)
        s2 = re.sub(r"[^0-9A-Za-z\-]+", "", s2)
        return s2 or None

    p1 = _first_intish_value(rec, [
        ["page_start"], ["first_page"], ["start_page"],
        ["metadata", "page_start"], ["paper", "page_start"],
    ])
    p2 = _first_intish_value(rec, [
        ["page_end"], ["last_page"], ["end_page"],
        ["metadata", "page_end"], ["paper", "page_end"],
    ])
    if p1 and p2:
        return f"{p1}-{p2}"
    if p1:
        return p1
    return None

def _extract_journal(rec: Dict[str, Any]) -> Optional[str]:
    return _first_str_value(rec, [
        ["journal"], ["journal_name"], ["journalTitle"],
        ["metadata", "journal"], ["metadata", "journal_name"], ["paper", "journal"],
    ])

def derive_doc_id_with_source(rec: Dict[str, Any]) -> Tuple[Optional[str], str]:
    """
    Returns (doc_id, doc_id_source).
    doc_id_source: pmid_pmcid | pmid | pmcid | doi | jvp | file | titlehash | none
    """
    pmid = _first_intish_value(rec, [
        ["pmid"], ["PMID"], ["pubmed_id"], ["pubmedId"], ["PubMedID"],
        ["metadata", "pmid"], ["metadata", "PMID"], ["paper", "pmid"], ["paper", "PMID"],
    ])
    pmcid_raw = _first_str_value(rec, [
        ["pmcid"], ["PMCID"], ["pubmed_central_id"], ["pmc_id"], ["pmcId"],
        ["metadata", "pmcid"], ["metadata", "PMCID"], ["paper", "pmcid"], ["paper", "PMCID"],
    ])
    pmcid = _normalize_pmcid(pmcid_raw or "")

    if pmid and pmcid:
        return f"PMID:{pmid}|PMCID:{pmcid}", "pmid_pmcid"
    if pmid:
        return f"PMID:{pmid}", "pmid"
    if pmcid:
        return f"PMCID:{pmcid}", "pmcid"

    doi = _first_str_value(rec, [
        ["doi"], ["DOI"], ["metadata", "doi"], ["metadata", "DOI"], ["paper", "doi"], ["paper", "DOI"],
    ])
    if doi:
        doi2 = _DOI_PREFIX_RE.sub("", doi).strip()
        return f"DOI:{doi2}", "doi"

    journal = _extract_journal(rec)
    year = _extract_year(rec)
    volume = _extract_volume(rec)
    pages = _extract_pages(rec)
    jnorm = _normalize_journal(journal or "")
    if jnorm and year and volume and pages:
        return f"JVP:{jnorm}:{year}:{volume}:{pages}", "jvp"

    file_path = _first_str_value(rec, [
        ["source_file"], ["file"], ["filename"], ["pdf_file"],
        ["source", "file"], ["_source", "file"], ["metadata", "file"], ["metadata", "filename"],
    ])
    if file_path:
        name = Path(file_path).name.strip()
        if name:
            return f"FILE:{name}", "file"
        return f"FILEHASH:{_stable_hash(file_path)}", "file"

    title = _first_str_value(rec, [
        ["title"], ["paper_title"], ["metadata", "title"], ["paper", "title"],
    ])
    if title:
        return f"TITLEHASH:{_stable_hash(title.lower().strip())}", "titlehash"

    return None, "none"

# ============================================================
# PROMPT
# ============================================================
SYSTEM_INSTRUCTIONS = (
    "Extract 'mechanistic atoms' from biomedical text.\n\n"
    "Definition: an atom MUST include an explicit effect on a readout.\n"
    "Format: [INTERVENTION] causes [EFFECT] in [READOUT] in a [SYSTEM].\n\n"
    "Hard rules:\n"
    "1) Do NOT invent facts.\n"
    "2) Do NOT assume knockdown succeeded unless the text explicitly says reduction/knockdown/confirmed.\n"
    "3) If the text only describes delivering siRNA/plasmid/drug but gives no stated change in any readout, output no atoms and add a warning.\n"
    "4) You may extract multiple readouts per intervention if they are explicitly stated.\n"
    "5) Rescue/add-back atoms must state what readout is rescued.\n"
    f"6) Keep at most {MAX_ATOMS_PER_CHUNK} atoms.\n"
)

# ============================================================
# MODEL CALLS + ROUTING
# ============================================================
def call_model(model: str, chunk_text: str, mentions: List[Dict[str, Any]]) -> Dict[str, Any]:
    payload = {
        "chunk_text": chunk_text,
        "mentions": compact_mentions(mentions),
        "hints": {"fig_refs": hint_figrefs(chunk_text), "species": hint_species(chunk_text)},
    }
    resp = client.responses.create(
        model=model,
        input=[
            {"role": "system", "content": SYSTEM_INSTRUCTIONS},
            {"role": "user", "content": json.dumps(payload, ensure_ascii=False)},
        ],
        text={
            "format": {
                "type": "json_schema",
                "name": ATOM_SCHEMA_WRAPPER["name"],
                "strict": True,
                "schema": ATOM_SCHEMA_WRAPPER["schema"],
            }
        },
    )
    return json.loads(resp.output_text)

def should_escalate(mentions: List[Dict[str, Any]], atoms: List[Dict[str, Any]]) -> bool:
    if len(mentions) > 0 and len(atoms) == 0:
        return True
    if len(atoms) > 0:
        avg_conf = sum(float(a.get("confidence", 0.0)) for a in atoms) / len(atoms)
        if avg_conf < 0.55:
            return True
    return False

def extract_atoms_with_routing(chunk_text: str, mentions: List[Dict[str, Any]]) -> Dict[str, Any]:
    routing = {"first_model": MODEL_FAST, "escalated": False, "final_model": MODEL_FAST, "reason": None}
    out_fast = call_model(MODEL_FAST, chunk_text, mentions)
    atoms_fast = out_fast.get("atoms", [])

    if should_escalate(mentions, atoms_fast):
        routing["escalated"] = True
        routing["final_model"] = MODEL_STRONG
        routing["reason"] = {"type": "low_confidence_or_empty", "details": "heuristics triggered"}
        out_strong = call_model(MODEL_STRONG, chunk_text, mentions)
        out_strong["_routing"] = routing
        return out_strong

    out_fast["_routing"] = routing
    return out_fast

# ============================================================
# POST-FILTER
# ============================================================
EFFECT_CUE = re.compile(
    r"\b("
    r"inhibit|inhibited|inhibition|suppress|suppressed|suppressing|"
    r"reduce|reduced|reduces|reduction|decrease|decreased|decreases|"
    r"increase|increased|increases|elevate|elevated|"
    r"no effect|did not affect|had no effect|"
    r"rescue|rescued|restored|restore|"
    r"complete inhibition|abolish|abolished"
    r")\b",
    re.IGNORECASE,
)
SETUP_ONLY_READOUT = re.compile(r"\b(expression|function|knockdown|silencing)\b", re.IGNORECASE)

def looks_like_setup_only(atoms: List[Dict[str, Any]], warnings: List[str]) -> bool:
    if not atoms:
        return True
    wtxt = " ".join(warnings or []).lower()
    if "no explicit functional readouts" in wtxt or "only describes" in wtxt:
        return True
    for a in atoms:
        ro = (a.get("readout", {}) or {}).get("name", "")
        sq = (a.get("evidence", {}) or {}).get("supporting_quote", "")
        if (not SETUP_ONLY_READOUT.search(ro or "")) and EFFECT_CUE.search(sq or ""):
            return False
    return True

def post_filter_atoms(atoms: List[Dict[str, Any]]) -> Tuple[List[Dict[str, Any]], int]:
    kept: List[Dict[str, Any]] = []
    dropped = 0
    for a in atoms or []:
        sq = (a.get("evidence", {}) or {}).get("supporting_quote", "")
        if EFFECT_CUE.search(sq or ""):
            kept.append(a)
        else:
            dropped += 1
    return kept, dropped

# ============================================================
# DOC-AWARE BRIDGING GUARD
# ============================================================
def can_bridge_same_doc_adjacent(a: Dict[str, Any], b: Dict[str, Any]) -> Tuple[bool, str]:
    a_doc = a.get("doc_id")
    b_doc = b.get("doc_id")
    if not a_doc or not b_doc:
        return False, "missing_doc_id"
    if a_doc != b_doc:
        return False, "doc_id_mismatch"

    a_idx = a.get("chunk_index")
    b_idx = b.get("chunk_index")
    if a_idx is None or b_idx is None:
        return False, "missing_chunk_index"
    try:
        ai = int(a_idx)
        bi = int(b_idx)
    except Exception:
        return False, "non_integer_chunk_index"
    if abs(ai - bi) != 1:
        return False, "non_adjacent_chunk_index"
    return True, "ok"

def bridge_text(a_text: str, b_text: str) -> str:
    return (a_text or "").rstrip() + "\n\n" + (b_text or "").lstrip()

def bridge_mentions(a_mentions: List[Dict[str, Any]], b_mentions: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    return list(a_mentions or []) + list(b_mentions or [])

def choose_best_bridged(candidates: List[Tuple[str, Dict[str, Any], List[int], List[str]]]) -> Optional[Tuple[str, Dict[str, Any], List[int], List[str]]]:
    best = None
    for mode, outd, src_chunks, src_docs in candidates:
        atoms = outd.get("atoms", []) or []
        if best is None:
            best = (mode, outd, src_chunks, src_docs)
            continue
        best_atoms = best[1].get("atoms", []) or []
        if len(atoms) > len(best_atoms):
            best = (mode, outd, src_chunks, src_docs)
        elif len(atoms) == len(best_atoms) and len(atoms) > 0:
            avg = sum(float(a.get("confidence", 0.0)) for a in atoms) / len(atoms)
            bavg = sum(float(a.get("confidence", 0.0)) for a in best_atoms) / len(best_atoms)
            if avg > bavg:
                best = (mode, outd, src_chunks, src_docs)
    return best

# ============================================================
# MAIN
# ============================================================
def main() -> int:
    ap = argparse.ArgumentParser(description="PATHAI atoms extraction with PMID/PMCID doc_id derivation and safe bridging switch")
    ap.add_argument("--infile", default=str(DEFAULT_INFILE), help="Input mentions.jsonl")
    ap.add_argument("--outfile", default=str(DEFAULT_OUTFILE), help="Output atoms.jsonl")
    ap.add_argument("--bridge", action="store_true", help="Enable bridging (safe: same doc_id + adjacent chunk_index). Default OFF.")
    ap.add_argument("--default_doc_id", default=None, help="If cannot derive doc_id, use this (otherwise falls back to CHUNK:<chunk_id>).")
    ap.add_argument("--assign_chunk_index", action="store_true", help="Assign chunk_index per doc_id if missing (sequential in file order).")
    ap.add_argument("--no_bridge_forward", action="store_true")
    ap.add_argument("--no_bridge_backward", action="store_true")
    args = ap.parse_args()

    infile = Path(args.infile)
    outfile = Path(args.outfile)
    enable_bridging = bool(args.bridge)
    try_forward = (not args.no_bridge_forward)
    try_backward = (not args.no_bridge_backward)

    if not infile.exists():
        raise FileNotFoundError(f"Cannot find {infile.resolve()}")

    records: List[Dict[str, Any]] = []
    for ln in infile.read_text(encoding="utf-8", errors="ignore").splitlines():
        ln = ln.strip()
        if ln:
            records.append(json.loads(ln))

    # ---- doc_id derivation happens HERE ----
    src_counts: Dict[str, int] = {}
    for r in records:
        if not r.get("doc_id"):
            doc_id, src = derive_doc_id_with_source(r)
            if doc_id:
                r["doc_id"] = doc_id
                r["doc_id_source"] = src
                src_counts[src] = src_counts.get(src, 0) + 1
            else:
                if args.default_doc_id:
                    r["doc_id"] = args.default_doc_id
                    r["doc_id_source"] = "default"
                    src_counts["default"] = src_counts.get("default", 0) + 1
                else:
                    cid = r.get("chunk_id")
                    r["doc_id"] = f"CHUNK:{cid}"
                    r["doc_id_source"] = "chunk_fallback"
                    src_counts["chunk_fallback"] = src_counts.get("chunk_fallback", 0) + 1

    # Optional chunk_index assignment per doc_id
    if args.assign_chunk_index:
        counters: Dict[str, int] = {}
        for r in records:
            doc = r.get("doc_id")
            if not doc:
                continue
            if r.get("chunk_index") is None:
                counters.setdefault(doc, 0)
                r["chunk_index"] = counters[doc]
                counters[doc] += 1

    total_atoms = 0
    escalations = 0
    bridges_used = 0
    bridges_attempted = 0
    dropped_total = 0

    with outfile.open("w", encoding="utf-8", newline="\n") as fout:
        for idx, rec in enumerate(records):
            chunk_id = rec.get("chunk_id")
            doc_id = rec.get("doc_id")
            doc_id_source = rec.get("doc_id_source")
            chunk_index = rec.get("chunk_index")

            if "error" in rec:
                out_rec = {
                    "doc_id": doc_id,
                    "doc_id_source": doc_id_source,
                    "chunk_index": chunk_index,
                    "chunk_id": chunk_id,
                    "atoms": [],
                    "warnings": ["Skipped due to upstream error."],
                    "bridge": {
                        "enabled": enable_bridging,
                        "attempted": False,
                        "used": False,
                        "mode": None,
                        "source_doc_ids": [doc_id] if doc_id else [],
                        "source_chunk_ids": [chunk_id],
                        "skipped_reason": "upstream_error",
                    },
                    "_routing": {"skipped": True},
                    "_post": {"dropped_atoms": 0},
                }
                fout.write(json.dumps(out_rec, ensure_ascii=False) + "\n")
                continue

            chunk_text = rec.get("chunk_text", "")
            mentions = rec.get("mentions", [])

            out = extract_atoms_with_routing(chunk_text, mentions)
            atoms = out.get("atoms", []) or []
            warnings = out.get("warnings", []) or []
            routing = out.get("_routing", {}) or {}

            atoms, dropped = post_filter_atoms(atoms)
            dropped_total += dropped

            used_bridge = False
            attempted_bridge = False
            bridge_mode = None
            skipped_reason = None
            source_chunk_ids = [chunk_id]
            source_doc_ids = [doc_id] if doc_id else []

            need_bridge = (len(mentions or []) > 0 and (len(atoms) == 0 or looks_like_setup_only(atoms, warnings)))

            # bridging disabled by default; kept for future use
            if enable_bridging and need_bridge:
                attempted_bridge = True
                bridges_attempted += 1
                candidates: List[Tuple[str, Dict[str, Any], List[int], List[str]]] = []

                if try_forward and idx + 1 < len(records):
                    nxt = records[idx + 1]
                    ok, why = can_bridge_same_doc_adjacent(rec, nxt)
                    if ok and "error" not in nxt:
                        t = bridge_text(chunk_text, nxt.get("chunk_text", ""))
                        m = bridge_mentions(mentions, nxt.get("mentions", []))
                        bout = extract_atoms_with_routing(t, m)
                        batoms = bout.get("atoms", []) or []
                        bwarn = bout.get("warnings", []) or []
                        batoms, bdropped = post_filter_atoms(batoms)
                        bout["atoms"] = batoms
                        bout["warnings"] = bwarn
                        bout["_post"] = {"dropped_atoms": bdropped}
                        candidates.append(("forward", bout, [chunk_id, nxt.get("chunk_id")], [rec.get("doc_id"), nxt.get("doc_id")]))
                    else:
                        skipped_reason = skipped_reason or f"forward_{why}"

                if try_backward and idx - 1 >= 0:
                    prv = records[idx - 1]
                    ok, why = can_bridge_same_doc_adjacent(prv, rec)
                    if ok and "error" not in prv:
                        t = bridge_text(prv.get("chunk_text", ""), chunk_text)
                        m = bridge_mentions(prv.get("mentions", []), mentions)
                        bout = extract_atoms_with_routing(t, m)
                        batoms = bout.get("atoms", []) or []
                        bwarn = bout.get("warnings", []) or []
                        batoms, bdropped = post_filter_atoms(batoms)
                        bout["atoms"] = batoms
                        bout["warnings"] = bwarn
                        bout["_post"] = {"dropped_atoms": bdropped}
                        candidates.append(("backward", bout, [prv.get("chunk_id"), chunk_id], [prv.get("doc_id"), rec.get("doc_id")]))
                    else:
                        skipped_reason = skipped_reason or f"backward_{why}"

                best = choose_best_bridged(candidates)
                if best is not None and len(best[1].get("atoms", []) or []) > 0:
                    used_bridge = True
                    bridge_mode = best[0]
                    out = best[1]
                    atoms = out.get("atoms", []) or []
                    warnings = out.get("warnings", []) or []
                    routing = out.get("_routing", routing) or routing
                    source_chunk_ids = best[2]
                    source_doc_ids = [d for d in best[3] if d]
                    bridges_used += 1
                else:
                    if skipped_reason is None:
                        skipped_reason = "no_viable_bridge_candidate"

            if routing.get("escalated"):
                escalations += 1
            total_atoms += len(atoms)

            # Pass-through pmid/pmcid if present (helps auditing)
            pmid_pt = rec.get("pmid") or rec.get("PMID") or rec.get("pubmed_id") or rec.get("pubmedId")
            pmcid_pt = rec.get("pmcid") or rec.get("PMCID") or rec.get("pubmed_central_id") or rec.get("pmcId") or rec.get("pmc_id")

            out_rec = {
                "doc_id": doc_id,
                "doc_id_source": doc_id_source,
                "pmid": pmid_pt,
                "pmcid": pmcid_pt,
                "chunk_index": chunk_index,
                "chunk_id": chunk_id,
                "atoms": atoms,
                "warnings": warnings,
                "bridge": {
                    "enabled": enable_bridging,
                    "attempted": attempted_bridge,
                    "used": used_bridge,
                    "mode": bridge_mode,
                    "source_doc_ids": source_doc_ids,
                    "source_chunk_ids": source_chunk_ids,
                    "skipped_reason": skipped_reason,
                },
                "_routing": routing,
                "_post": {"dropped_atoms": dropped},
            }
            fout.write(json.dumps(out_rec, ensure_ascii=False) + "\n")

            print(
                f"chunk {chunk_id} doc_id={doc_id}({doc_id_source}) idx={chunk_index} "
                f"atoms={len(atoms)} escalated={routing.get('escalated', False)} "
                f"bridge_enabled={enable_bridging} bridged={used_bridge} dropped={dropped}"
            )

    print(
        f"Done. total_atoms={total_atoms}, escalations={escalations}, "
        f"bridges_attempted={bridges_attempted}, bridges_used={bridges_used}, dropped_total={dropped_total}"
    )
    print("doc_id sources:", ", ".join(f"{k}={v}" for k, v in sorted(src_counts.items())))
    if not enable_bridging:
        print("Note: bridging was OFF (recommended for mixed/random chunks).")
    else:
        print("Note: bridging ON uses strict guard: same doc_id + adjacent chunk_index.")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
```

### Run it

```bat
conda activate pathai
cd "C:\Users\Prem Subramaniam\Documents\Pathway AI"
python make_atoms_docaware_v7.py
```

### Quick sanity check (no new code needed)

Open `mentions.jsonl` and confirm each line has something like:

* `"pmid": "12345678"` (or as an int)
* and optionally `"pmcid": "PMC1234567"`

If those fields are present, your log lines should start showing doc_ids like:

* `doc_id=PMID:12345678|PMCID:PMC1234567(pmid_pmcid)`

If you paste **one** `mentions.jsonl` line that includes your new `pmid` and `pmcid`, I’ll verify the field names match what the script is looking for (so you don’t lose time chasing a key mismatch).

* * *

**You:**

In v7 does (PMID/PMCID) in pisk_mtor_seed_texts.txt carried through into each JSONL record in mentions.jsonl (top-level fields like "pmid": "...", "pmcid": "...").

* * *

**ChatGPT:**

TAG: **PATHAI-0065**

No — **v7 does not “carry” PMID/PMCID from `pisk_mtor_seed_texts.txt` into `mentions.jsonl` by itself.**

### What v7 actually does

* v7 **only reads** `mentions.jsonl`.
* If a `mentions.jsonl` record already contains **`pmid` / `pmcid` as top-level fields** (top-level fields = keys that sit directly in the outer JSON object, not nested inside another object), then v7 will:
    1. use them to build a real `doc_id` like `PMID:...|PMCID:...`, and
    2. pass them through into `atoms.jsonl` for auditing.

### What v7 does _not_ do

It does **not** open `pisk_mtor_seed_texts.txt`, and it does **not** “reach backward” to fetch metadata from there.

So the only way PMID/PMCID “carry through” is if your **upstream step** (your miner / chunk loader) already copied them into each `mentions.jsonl` line.

### How to check in 10 seconds

Open `mentions.jsonl` and see whether lines look like this (example shape):

* has `"pmid": "..."` and/or `"pmcid": "..."` **next to** `"chunk_id"` and `"chunk_text"`.

If those keys are missing in `mentions.jsonl`, v7 cannot use them.

### So what should happen upstream (the right “contract”)

Your ingestion/mining step should produce `mentions.jsonl` lines shaped like:

* `chunk_id`
* `chunk_text`
* **pmid / pmcid** (and later, optionally `chunk_index`)
* `mentions: [...]`

In other words: **PMID/PMCID need to be attached to the chunk _before_ the miner writes `mentions.jsonl`.**

### Important detail about `pisk_mtor_seed_texts.txt`

If that file is _just plain text chunks_, it can’t reliably “carry” metadata unless you’ve embedded it in a structured way (like JSON lines or a header format the miner parses). If you _have_ embedded PMID/PMCID there, the miner still needs explicit logic to read it and copy it into the JSON records.

If you paste **one actual line (or header+chunk block) from `pisk_mtor_seed_texts.txt` showing how you stored PMID/PMCID**, I’ll tell you the most practical way to propagate it into `mentions.jsonl` (either by updating the miner or by a small “attach metadata” pre-step).

* * *

**You:**

Here is one from the chunk fil:  PMID: 41332195  The phosphoinositide 3-kinase (PI3K)/protein kinase B (AKT)/mammalian target of rapamycin (mTOR) pathway is a critical regulator of cell growth and metabolism, and its dysregulation is implicated in various cancers. In this study, a series of dual-target degraders simultaneously targeting PI3K and mTOR was designed and synthesized. Compound GP262 was identified as a potent dual-degrader of both PI3K and mTOR, with DC50 values of 42.23–227.4 nM (PI3K) and 45.4 nM (mTOR) in MDA-MB-231 cells, GP262 also exhibited robust antiproliferative activity in multiple breast cancer cell lines. Mechanistic studies confirmed that GP262 achieved degradation through the ubiquitin-proteasome system (UPS). DIA proteomics and RNA-seq confirmed the on-target pathway modulation and revealed potential antileukemia activity. In vivo validation showed GP262’s significant tumor growth suppression capability. These findings indicated that GP262, as the first dual-targeted degrader of PI3K and mTOR, had great potential in the treatment of breast cancer and leukemia.

* * *

**ChatGPT:**

TAG: **PATHAI-0066**

Got it — that example line makes it very clear what’s happening.

Right now, your **PMID is present in the seed text file as plain text** (`PMID: 41332195 ...`). But unless your miner _explicitly copies that PMID into a JSON field_, it gets treated like just part of the sentence and is effectively “lost” once you write `mentions.jsonl`.

So:

* `pisk_mtor_seed_texts.txt` contains: **PMID embedded in the text**
* `mentions.jsonl` currently contains: **chunk_text + mentions**, but **no `pmid` field**
* v6/v7 can only build real `doc_id` if the PMID/PMCID appears as a **top-level JSON field** (top-level field = `"pmid": "41332195"` sitting next to `"chunk_id"` in the outer JSON object).

### The clean fix (no changes to your miner needed)

Add a tiny “attach metadata” step:

1. Read `pisk_mtor_seed_texts.txt`
2. Parse out `PMID:` (and optionally `PMCID:` / `DOI:` if you start adding them)
3. Match each seed chunk to each `mentions.jsonl` record (by `chunk_id` and also by text fingerprint)
4. Write a new `mentions.jsonl` with `pmid` (and pmcid/doi if present) inserted

Then v7 will start printing doc_ids like:

* `doc_id=PMID:41332195(pmid)`

* * *

## Full script: attach PMID/PMCID/DOI from seed file into `mentions.jsonl`

**TAG: PATHAI-0066**  
Save as: **`attach_docmeta_to_mentions.py`**

```Python
#!/usr/bin/env python3
import argparse
import json
import re
from pathlib import Path
from typing import Dict, List, Optional, Tuple

PMID_RE = re.compile(r"^\s*PMID\s*:\s*(\d+)\s+(.*)$", re.IGNORECASE)
PMCID_RE = re.compile(r"^\s*PMCID\s*:\s*(PMC\d+|\d+)\s+(.*)$", re.IGNORECASE)
DOI_RE = re.compile(r"^\s*DOI\s*:\s*([^\s]+)\s+(.*)$", re.IGNORECASE)

def norm_space(s: str) -> str:
    return re.sub(r"\s+", " ", (s or "")).strip()

def text_fingerprint(s: str, n: int = 120) -> str:
    """
    A lightweight fingerprint: normalize whitespace, lowercase, take first n chars.
    Good enough to match seed chunk lines to mentions chunk_text in most cases.
    """
    s2 = norm_space(s).lower()
    return s2[:n]

def normalize_pmcid(x: str) -> Optional[str]:
    if not x:
        return None
    s = x.strip()
    if s.lower().startswith("pmc"):
        digits = re.sub(r"\D+", "", s)
        return f"PMC{digits}" if digits else None
    digits = re.sub(r"\D+", "", s)
    return f"PMC{digits}" if digits else None

def parse_seed_line(line: str) -> Tuple[Optional[str], Optional[str], Optional[str], str]:
    """
    Returns (pmid, pmcid, doi, clean_text)
    clean_text is the chunk text without the leading metadata prefix.
    If no metadata prefix exists, (None, None, None, original_line)
    """
    line = line.rstrip("\n")
    if not line.strip():
        return None, None, None, ""

    m = PMID_RE.match(line)
    if m:
        pmid = m.group(1)
        txt = m.group(2)
        return pmid, None, None, txt

    m = PMCID_RE.match(line)
    if m:
        pmcid = normalize_pmcid(m.group(1))
        txt = m.group(2)
        return None, pmcid, None, txt

    m = DOI_RE.match(line)
    if m:
        doi = m.group(1)
        txt = m.group(2)
        return None, None, doi, txt

    # No prefix recognized
    return None, None, None, line

def load_seed(seed_path: Path) -> List[Dict[str, str]]:
    out: List[Dict[str, str]] = []
    for raw in seed_path.read_text(encoding="utf-8", errors="ignore").splitlines():
        pmid, pmcid, doi, txt = parse_seed_line(raw)
        txt = norm_space(txt)
        if not txt:
            continue
        out.append({
            "pmid": pmid or "",
            "pmcid": pmcid or "",
            "doi": doi or "",
            "text": txt,
            "fp": text_fingerprint(txt),
        })
    return out

def load_mentions_jsonl(path: Path) -> List[Dict]:
    recs: List[Dict] = []
    for ln in path.read_text(encoding="utf-8", errors="ignore").splitlines():
        ln = ln.strip()
        if not ln:
            continue
        recs.append(json.loads(ln))
    return recs

def main() -> int:
    ap = argparse.ArgumentParser(description="Attach PMID/PMCID/DOI from seed text file into mentions.jsonl records")
    ap.add_argument("--seed", default="pisk_mtor_seed_texts.txt", help="Seed chunk text file (one chunk per line)")
    ap.add_argument("--mentions", default="mentions.jsonl", help="Input mentions.jsonl")
    ap.add_argument("--out", default="mentions.with_docmeta.jsonl", help="Output JSONL with pmid/pmcid/doi added")
    ap.add_argument("--inplace", action="store_true", help="Overwrite mentions.jsonl (creates .bak first)")
    args = ap.parse_args()

    seed_path = Path(args.seed)
    mentions_path = Path(args.mentions)

    if not seed_path.exists():
        raise FileNotFoundError(f"Seed file not found: {seed_path.resolve()}")
    if not mentions_path.exists():
        raise FileNotFoundError(f"Mentions file not found: {mentions_path.resolve()}")

    seed = load_seed(seed_path)

    # Map by fingerprint (best)
    fp_map: Dict[str, Dict[str, str]] = {s["fp"]: s for s in seed}

    # Also map by 1-based index position (fallback)
    idx_map: Dict[int, Dict[str, str]] = {}
    for i, s in enumerate(seed, start=1):
        idx_map[i] = s

    recs = load_mentions_jsonl(mentions_path)

    attached = 0
    matched_by_fp = 0
    matched_by_chunkid = 0
    already_had = 0
    no_match = 0

    out_recs: List[Dict] = []

    for r in recs:
        chunk_id = r.get("chunk_id")

        # If it already has metadata, keep it (don’t overwrite)
        has_any = any(k in r and str(r.get(k)).strip() for k in ["pmid", "pmcid", "doi", "PMID", "PMCID", "DOI"])
        if has_any:
            already_had += 1
            out_recs.append(r)
            continue

        chunk_text = norm_space(r.get("chunk_text", ""))
        fp = text_fingerprint(chunk_text)

        meta = fp_map.get(fp)
        if meta:
            matched_by_fp += 1
        elif isinstance(chunk_id, int) and chunk_id in idx_map:
            meta = idx_map[chunk_id]
            matched_by_chunkid += 1

        if meta:
            # Attach only if available
            if meta["pmid"]:
                r["pmid"] = meta["pmid"]
            if meta["pmcid"]:
                r["pmcid"] = meta["pmcid"]
            if meta["doi"]:
                r["doi"] = meta["doi"]
            attached += 1
        else:
            no_match += 1

        out_recs.append(r)

    out_path = Path(args.out)

    if args.inplace:
        bak = mentions_path.with_suffix(mentions_path.suffix + ".bak")
        bak.write_text(mentions_path.read_text(encoding="utf-8", errors="ignore"), encoding="utf-8")
        out_path = mentions_path

    with out_path.open("w", encoding="utf-8", newline="\n") as f:
        for r in out_recs:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")

    print("Docmeta attach report")
    print(f"  seed chunks loaded: {len(seed)}")
    print(f"  mentions records:   {len(recs)}")
    print(f"  attached:           {attached}")
    print(f"    matched by text fingerprint: {matched_by_fp}")
    print(f"    matched by chunk_id fallback: {matched_by_chunkid}")
    print(f"  already had meta:   {already_had}")
    print(f"  no match:           {no_match}")
    print(f"  output:             {out_path.resolve()}")
    if args.inplace:
        print(f"  backup:             {mentions_path.with_suffix(mentions_path.suffix + '.bak').resolve()}")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
```

### Run it (recommended: overwrite mentions.jsonl with a backup)

```bat
conda activate pathai
cd "C:\Users\Prem Subramaniam\Documents\Pathway AI"
python attach_docmeta_to_mentions.py --inplace
```

### Then rerun v7

```bat
python make_atoms_docaware_v7.py
```

You should now see lines like:

* `doc_id=PMID:41332195(pmid)`  
    instead of `CHUNK:1(chunk_fallback)`.

* * *

If you paste **one updated line from `mentions.jsonl` after running the attach script**, I’ll sanity-check that the `pmid` field is exactly where v7 expects it.

* * *

**You:**

RUn with bridging off: (pathai) C:\Users\Prem Subramaniam\Documents\Pathway AI>python make_atoms_docaware_v7.py
chunk 1 doc_id=PMID:41332195(pmid) idx=None atoms=0 escalated=False bridge_enabled=False bridged=False dropped=3
chunk 2 doc_id=PMID:39682777(pmid) idx=None atoms=5 escalated=False bridge_enabled=False bridged=False dropped=0
chunk 3 doc_id=PMID:39682777(pmid) idx=None atoms=0 escalated=True bridge_enabled=False bridged=False dropped=0
chunk 4 doc_id=PMID:39682777(pmid) idx=None atoms=0 escalated=False bridge_enabled=False bridged=False dropped=2
chunk 5 doc_id=PMID:39682777(pmid) idx=None atoms=0 escalated=False bridge_enabled=False bridged=False dropped=0
chunk 6 doc_id=PMID:39682777(pmid) idx=None atoms=0 escalated=False bridge_enabled=False bridged=False dropped=4
chunk 7 doc_id=PMID:39682777(pmid) idx=None atoms=3 escalated=False bridge_enabled=False bridged=False dropped=3
chunk 8 doc_id=PMID:37931033(pmid) idx=None atoms=3 escalated=False bridge_enabled=False bridged=False dropped=1
chunk 9 doc_id=PMID:37931033(pmid) idx=None atoms=1 escalated=False bridge_enabled=False bridged=False dropped=1
chunk 10 doc_id=PMID:37931033(pmid) idx=None atoms=3 escalated=False bridge_enabled=False bridged=False dropped=2
Done. total_atoms=15, escalations=1, bridges_attempted=0, bridges_used=0, dropped_total=16
doc_id sources: pmid=10
Note: bridging was OFF (recommended for mixed/random chunks).

* * *

**ChatGPT:**

TAG: **PATHAI-0067**

This is a really important milestone — you’ve now done the _core thing_ we needed: your chunks have **real paper identity**.

### What your v7 output is telling us (in plain terms)

#### 1) Doc identity is now working correctly ✅

You can see the same paper repeated across multiple chunks:

* `PMID:39682777` appears for chunks **2–7**
* `PMID:37931033` appears for chunks **8–10**
* `PMID:41332195` is chunk **1** alone

So the pipeline now knows: “chunks 2–7 are from the _same paper_.”  
That is exactly what we need later for:

* within-paper bridging (only within the same paper),
* and counting _independent papers_ supporting a pathway edge.

#### 2) Bridging is OFF (as intended) ✅

`bridges_attempted=0`. No cross-chunk mixing is happening.

That’s correct for now, because you don’t have `chunk_index` yet (the within-paper order). Bridging without order is risky even if doc_id matches.

#### 3) Why are there many `atoms=0` chunks?

For the paper `PMID:39682777`, you have chunks 2–7, but several give `atoms=0`.

That usually means one of these is true:

* the chunk is **background / definitions / methods** (no explicit outcomes), OR
* it contains outcomes but your **effect-cue filter** didn’t recognize the wording, so it dropped them.

We can’t tell which yet just from the counts.

#### 4) Why did total atoms drop to 15 and dropped_total rise to 16?

You now have stronger filtering behavior in play, plus some model variance.

`dropped_total=16` means: across the 10 chunks, the model produced 16 candidate atoms that got rejected because the quote didn’t contain one of the “effect verbs” we’re currently looking for.

That’s _not automatically bad_ — it might be blocking weak/invented atoms — but it might also be too strict.

* * *

## What should we do next?

### Next step A (recommended): Add `chunk_index` so bridging can be safe later

Right now `idx=None` for all chunks. That means we know the paper (PMID), but not the order within the paper.

To enable bridging _within a paper only_, we need a `chunk_index` per `doc_id` that reflects the order the chunks appear in that paper (0,1,2,…). That can be approximated _right now_ using file order **within each PMID**.

You already have this option in v7:

* run it with `--assign_chunk_index`

Example:

```bat
python make_atoms_docaware_v7.py --assign_chunk_index
```

That will assign chunk_index sequentially **per PMID**, using the order your records appear in `mentions.jsonl`.

Then later (when you’re ready) bridging can be turned on and it will only bridge:

* same `doc_id` (same PMID),
* adjacent `chunk_index` (e.g., 3 with 4).

### Next step B (also important): Decide if your effect-cue filter is too narrow

Before we change your filter, we should look at what got dropped.

A very common situation: the quote says **“induced autophagy”** or **“promoted apoptosis”** which is a real outcome, but your effect list doesn’t include “induce/promote/attenuate/activate/block.”

So the best move is: generate a small report of the dropped quotes (top 30) so you can judge whether the filter is being _appropriately strict_ or _too strict_.

* * *

## Answering the “are we ready for the graph stage?”

**Not quite yet**, but we’re close.

You _can_ build a graph from atoms now, but two things will improve quality a lot:

1. Add `chunk_index` (even approximate) so bridging is possible _safely_ later.
2. Validate the drop filter so you don’t throw away good biology outcomes.

* * *

If you want me to pick the next concrete coding step without asking you questions:  
**I’d do “dropped-atoms audit report” next**, because it tells us whether we should widen the effect-cue list.

* * *

**You:**

From mentions with bridge off: {"chunk_id": 1, "chunk_text": "The phosphoinositide 3-kinase (PI3K)/protein kinase B (AKT)/mammalian target of rapamycin (mTOR) pathway is a critical regulator of cell growth and metabolism, and its dysregulation is implicated in various cancers. In this study, a series of dual-target degraders simultaneously targeting PI3K and mTOR was designed and synthesized. Compound GP262 was identified as a potent dual-degrader of both PI3K and mTOR, with DC50 values of 42.23–227.4 nM (PI3K) and 45.4 nM (mTOR) in MDA-MB-231 cells, GP262 also exhibited robust antiproliferative activity in multiple breast cancer cell lines. Mechanistic studies confirmed that GP262 achieved degradation through the ubiquitin-proteasome system (UPS). DIA proteomics and RNA-seq confirmed the on-target pathway modulation and revealed potential antileukemia activity. In vivo validation showed GP262’s significant tumor growth suppression capability. These findings indicated that GP262, as the first dual-targeted degrader of PI3K and mTOR, had great potential in the treatment of breast cancer and leukemia.", "mentions": [{"raw_text": "dual-target degraders simultaneously targeting PI3K and mTOR", "category": "CHEMICAL_INHIBITOR", "span": {"start": 140, "end": 188}, "target_guess": {"name": "PI3K and mTOR", "entity_type": "protein"}, "method_cues": ["degraders", "targeting"], "notes": "Described as dual-target degraders, which indicates chemical-induced degradation/inhibition."}, {"raw_text": "Compound GP262 was identified as a potent dual-degrader of both PI3K and mTOR", "category": "CHEMICAL_INHIBITOR", "span": {"start": 190, "end": 256}, "target_guess": {"name": "PI3K and mTOR", "entity_type": "protein"}, "method_cues": ["degrader", "dual-degrader"], "notes": "GP262 is a chemical that targets both PI3K and mTOR for degradation."}, {"raw_text": "GP262 achieved degradation through the ubiquitin-proteasome system (UPS)", "category": "CHEMICAL_INHIBITOR", "span": {"start": 367, "end": 423}, "target_guess": {"name": "PI3K and mTOR", "entity_type": "protein"}, "method_cues": ["degradation", "ubiquitin-proteasome system"], "notes": "Specifies the mechanism of action of GP262 as UPS-mediated degradation of PI3K and mTOR."}, {"raw_text": "in vivo validation showed GP262’s significant tumor growth suppression capability", "category": "CHEMICAL_INHIBITOR", "span": {"start": 495, "end": 557}, "target_guess": null, "method_cues": ["tumor growth suppression", "validation"], "notes": "Tumor growth suppression caused by GP262, consistent with its action as a PI3K/mTOR degrader."}], "_routing": {"first_model": "gpt-4o-mini", "escalated": true, "final_model": "gpt-4.1", "reason": {"type": "validation_error", "details": ["mention[0] span mismatch: expected substring 'lation is implicated in various cancers. In this st' vs raw_text 'compound GP262 was identified as a potent dual-degrader of both PI3K and mTOR'", "mention[1] span mismatch: expected substring 'dy, a series of dual-target degraders simultaneou' vs raw_text 'achieved degradation through the ubiquitin-proteasome system (UPS)'", "mention[2] span mismatch: expected substring 'ompound GP262 was identified as a potent ' vs raw_text 'GP262’s significant tumor growth suppression capability'"]}, "mini_output": {"mentions": [{"raw_text": "compound GP262 was identified as a potent dual-degrader of both PI3K and mTOR", "category": "CHEMICAL_INHIBITOR", "span": {"start": 175, "end": 226}, "target_guess": null, "method_cues": [], "notes": null}, {"raw_text": "achieved degradation through the ubiquitin-proteasome system (UPS)", "category": "CHEMICAL_INHIBITOR", "span": {"start": 227, "end": 276}, "target_guess": null, "method_cues": [], "notes": null}, {"raw_text": "GP262’s significant tumor growth suppression capability", "category": "CHEMICAL_INHIBITOR", "span": {"start": 335, "end": 376}, "target_guess": null, "method_cues": [], "notes": null}]}}, "pmid": "41332195"}

* * *

**ChatGPT:**

TAG: **PATHAI-0067**

Perfect example — this one line explains _exactly_ why chunk 1 ended up as `atoms=0` in your run.

### Why chunk 1 produced `atoms=0` even though the abstract clearly has outcomes

Your chunk text contains outcome phrases like:

* “**robust antiproliferative activity**”
* “**significant tumor growth suppression**”

Those are real biological effects. But in v7, the **post-filter** only keeps atoms if the model’s `supporting_quote` contains one of a specific set of “effect cue” words (effect cue = a keyword like “increased/decreased/inhibited” that proves the text explicitly stated a change).

In your run you saw:

* `chunk 1 ... atoms=0 ... dropped=3`

That means: the model likely proposed **3 atoms**, but all **3 got dropped** because the quote used words like **“antiproliferative”** or **“suppression”** (noun form), and **our regex didn’t include those forms**.

Concretely:

* We had `suppress/suppressed/suppressing` but **not** `suppression`
* We did **not** include `antiproliferative`
* We did **not** include `tumor growth suppression` as a phrase
* We also didn’t include `degradation/degraded` (which appears in your abstract as “achieved degradation”)

So the filter was **too strict in a way that throws out good atoms**.

### The other thing you see here: “span mismatch”

That span mismatch warning is coming from the miner stage saying: “the character positions don’t match the quoted text.” It doesn’t stop atom extraction (we mostly ignore spans later), but it _does_ hurt auditability. We can fix that next, but it’s separate from why chunk 1 got zero atoms.

* * *

## Fix: expand the effect-cue filter to cover real biology language

Below is v8, identical to v7 **except** the `EFFECT_CUE` regex is expanded to include:

* `suppression`
* `antiproliferative`
* `growth suppression`
* `degradation / degraded`
* common verbs like `induce/induced`, `promote/promoted`, `attenuate/attenuated`, `block/blocked`, `activate/activated`, `inactivate/inactivated`, `enhance/enhanced`, `impair/impaired`, `abrogate/abrogated`

This should immediately recover atoms from chunk 1.

* * *

## Full script v8: `make_atoms_docaware_v8.py`

TAG: **PATHAI-0068**  
Save as: **`make_atoms_docaware_v8.py`**

```Python
#!/usr/bin/env python3
import os
import json
import re
import argparse
import hashlib
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple
from openai import OpenAI

# ============================================================
# DEFAULTS
# ============================================================
DEFAULT_INFILE = Path("mentions.jsonl")
DEFAULT_OUTFILE = Path("atoms.jsonl")

MODEL_FAST = "gpt-4o-mini"
MODEL_STRONG = "gpt-4.1"

MAX_ATOMS_PER_CHUNK = 30

# Bridging is OFF by default (safe for mixed/random chunk streams)
DEFAULT_ENABLE_BRIDGING = False

# ============================================================
# OPENAI CLIENT
# ============================================================
def _get_api_key() -> str:
    key = os.getenv("OPENAI_API_KEY")
    if not key:
        raise RuntimeError(
            "OPENAI_API_KEY is not set.\n"
            "Miniforge Prompt (temporary):  set OPENAI_API_KEY=YOUR_KEY\n"
            "Persistent (Windows):         setx OPENAI_API_KEY \"YOUR_KEY\"  (then reopen prompt)"
        )
    return key

client = OpenAI(api_key=_get_api_key())

# ============================================================
# STRICT JSON SCHEMA FOR ATOMS (model output)
# ============================================================
ATOM_SCHEMA_WRAPPER: Dict[str, Any] = {
    "name": "MechanisticAtoms",
    "schema": {
        "type": "object",
        "additionalProperties": False,
        "required": ["atoms", "warnings"],
        "properties": {
            "atoms": {
                "type": "array",
                "items": {
                    "type": "object",
                    "additionalProperties": False,
                    "required": [
                        "intervention",
                        "system",
                        "readout",
                        "effect",
                        "strength_cues",
                        "evidence",
                        "confidence",
                    ],
                    "properties": {
                        "intervention": {
                            "type": "object",
                            "additionalProperties": False,
                            "required": ["category", "raw_text", "target", "modality"],
                            "properties": {
                                "category": {
                                    "type": "string",
                                    "enum": [
                                        "GENETIC_KO",
                                        "CRISPR_KO",
                                        "CRISPRi",
                                        "CRISPRa",
                                        "KNOCKDOWN_RNAI",
                                        "SPLICING_MODULATION",
                                        "OVEREXPRESSION",
                                        "RESCUE_ADD_BACK",
                                        "DOMINANT_NEGATIVE",
                                        "MUTANT_VARIANT",
                                        "CHEMICAL_INHIBITOR",
                                        "CHEMICAL_ACTIVATOR",
                                        "CHEMICAL_DEGRADER",
                                        "STIMULUS_TREATMENT",
                                        "NEUTRALIZING_ANTIBODY",
                                        "UNKNOWN",
                                    ],
                                },
                                "raw_text": {"type": "string", "minLength": 1},
                                "target": {
                                    "anyOf": [
                                        {
                                            "type": "object",
                                            "additionalProperties": False,
                                            "required": ["name", "entity_type"],
                                            "properties": {
                                                "name": {"type": "string"},
                                                "entity_type": {
                                                    "type": "string",
                                                    "enum": [
                                                        "gene",
                                                        "protein",
                                                        "chemical",
                                                        "stimulus",
                                                        "antibody",
                                                        "unknown",
                                                    ],
                                                },
                                            },
                                        },
                                        {"type": "null"},
                                    ]
                                },
                                "modality": {
                                    "type": "string",
                                    "enum": [
                                        "LOF",
                                        "GOF",
                                        "INHIBITION",
                                        "ACTIVATION",
                                        "DEGRADATION",
                                        "RESCUE",
                                        "UNKNOWN",
                                    ],
                                },
                            },
                        },
                        "system": {
                            "type": "object",
                            "additionalProperties": False,
                            "required": [
                                "species",
                                "cell_type",
                                "cell_lines",
                                "genotype_context",
                                "disease_context",
                            ],
                            "properties": {
                                "species": {"type": ["string", "null"]},
                                "cell_type": {"type": ["string", "null"]},
                                "cell_lines": {"type": "array", "items": {"type": "string"}},
                                "genotype_context": {"type": ["string", "null"]},
                                "disease_context": {"type": ["string", "null"]},
                            },
                        },
                        "readout": {
                            "type": "object",
                            "additionalProperties": False,
                            "required": ["name", "assay", "figure_refs"],
                            "properties": {
                                "name": {"type": "string"},
                                "assay": {"type": ["string", "null"]},
                                "figure_refs": {"type": "array", "items": {"type": "string"}},
                            },
                        },
                        "effect": {
                            "type": "object",
                            "additionalProperties": False,
                            "required": ["direction", "timepoint", "magnitude", "comparison"],
                            "properties": {
                                "direction": {
                                    "type": "string",
                                    "enum": ["increase", "decrease", "no_change", "mixed", "unknown"],
                                },
                                "timepoint": {"type": ["string", "null"]},
                                "magnitude": {"type": ["string", "null"]},
                                "comparison": {"type": ["string", "null"]},
                            },
                        },
                        "strength_cues": {
                            "type": "object",
                            "additionalProperties": False,
                            "required": ["has_rescue", "has_control", "has_multiple_lines", "other"],
                            "properties": {
                                "has_rescue": {"type": "boolean"},
                                "has_control": {"type": "boolean"},
                                "has_multiple_lines": {"type": "boolean"},
                                "other": {"type": "array", "items": {"type": "string"}},
                            },
                        },
                        "evidence": {
                            "type": "object",
                            "additionalProperties": False,
                            "required": ["supporting_quote", "notes"],
                            "properties": {
                                "supporting_quote": {"type": "string"},
                                "notes": {"type": ["string", "null"]},
                            },
                        },
                        "confidence": {"type": "number", "minimum": 0, "maximum": 1},
                    },
                },
            },
            "warnings": {"type": "array", "items": {"type": "string"}},
        },
    },
}

# ============================================================
# LIGHTWEIGHT HINTS
# ============================================================
FIGREF_REGEX = re.compile(r"\b(Fig\.?\s*\d+[A-Za-z]?)\b", re.IGNORECASE)
SPECIES_REGEX = re.compile(r"\b(human|mouse|murine|rat)\b", re.IGNORECASE)

def _uniq_preserve(seq: List[str]) -> List[str]:
    seen = set()
    out = []
    for x in seq:
        k = x.lower()
        if k not in seen:
            seen.add(k)
            out.append(x)
    return out

def hint_figrefs(text: str) -> List[str]:
    return _uniq_preserve([m.group(1) for m in FIGREF_REGEX.finditer(text or "")])

def hint_species(text: str) -> Optional[str]:
    m = SPECIES_REGEX.search(text or "")
    if not m:
        return None
    s = m.group(1).lower()
    return "mouse" if s == "murine" else s

def compact_mentions(mentions: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    out = []
    for i, m in enumerate(mentions or [], start=1):
        out.append({
            "i": i,
            "category": m.get("category"),
            "raw_text": m.get("raw_text"),
            "target_guess": m.get("target_guess"),
            "method_cues": m.get("method_cues", []),
        })
    return out

# ============================================================
# DOC_ID DERIVATION (PMID(+PMCID) → PMCID → DOI → JVP → FILE → TITLEHASH → CHUNK)
# ============================================================
_DOI_PREFIX_RE = re.compile(r"^(https?://(dx\.)?doi\.org/|doi:\s*)", re.IGNORECASE)
_YEAR_RE = re.compile(r"\b(19\d{2}|20\d{2})\b")
_PAGES_RE = re.compile(r"^\s*(\d+)\s*[-–—]\s*(\d+)\s*$")

def _stable_hash(text: str, n: int = 12) -> str:
    return hashlib.sha1(text.encode("utf-8")).hexdigest()[:n]

def _get_nested(rec: Dict[str, Any], path: List[str]) -> Optional[Any]:
    cur: Any = rec
    for k in path:
        if not isinstance(cur, dict) or k not in cur:
            return None
        cur = cur[k]
    return cur

def _first_str_value(rec: Dict[str, Any], key_paths: List[List[str]]) -> Optional[str]:
    for path in key_paths:
        v = _get_nested(rec, path)
        if isinstance(v, str) and v.strip():
            return v.strip()
    return None

def _first_intish_value(rec: Dict[str, Any], key_paths: List[List[str]]) -> Optional[str]:
    for path in key_paths:
        v = _get_nested(rec, path)
        if v is None:
            continue
        if isinstance(v, int):
            return str(v)
        if isinstance(v, str):
            s = v.strip()
            m = re.search(r"\d+", s)
            if m:
                return m.group(0)
    return None

def _normalize_pmcid(x: str) -> Optional[str]:
    if not x:
        return None
    s = x.strip()
    if s.lower().startswith("pmc"):
        digits = re.sub(r"\D+", "", s)
        return f"PMC{digits}" if digits else None
    digits = re.sub(r"\D+", "", s)
    return f"PMC{digits}" if digits else None

def _normalize_journal(j: str) -> str:
    s = re.sub(r"[^A-Za-z0-9]+", "", (j or "").lower())
    return s[:32] if s else ""

def _extract_year(rec: Dict[str, Any]) -> Optional[str]:
    year = _first_intish_value(rec, [
        ["year"], ["pub_year"], ["publication_year"],
        ["metadata", "year"], ["metadata", "pub_year"], ["paper", "year"],
    ])
    if year and len(year) == 4:
        return year

    date_str = _first_str_value(rec, [
        ["date"], ["publication_date"], ["pub_date"],
        ["metadata", "date"], ["metadata", "publication_date"], ["paper", "date"],
    ])
    if date_str:
        m = _YEAR_RE.search(date_str)
        if m:
            return m.group(1)
    return None

def _extract_volume(rec: Dict[str, Any]) -> Optional[str]:
    vol = _first_str_value(rec, [
        ["volume"], ["vol"], ["metadata", "volume"], ["paper", "volume"],
    ])
    if not vol:
        return None
    vol2 = re.sub(r"[^0-9A-Za-z]+", "", vol)
    return vol2 or None

def _extract_pages(rec: Dict[str, Any]) -> Optional[str]:
    pages = _first_str_value(rec, [
        ["pages"], ["page_range"], ["pagination"], ["pageNumbers"],
        ["metadata", "pages"], ["metadata", "page_range"], ["paper", "pages"],
    ])
    if pages:
        s = pages.strip().replace("–", "-").replace("—", "-")
        m = _PAGES_RE.match(s)
        if m:
            return f"{m.group(1)}-{m.group(2)}"
        s2 = re.sub(r"\s+", "", s)
        s2 = re.sub(r"[^0-9A-Za-z\-]+", "", s2)
        return s2 or None

    p1 = _first_intish_value(rec, [
        ["page_start"], ["first_page"], ["start_page"],
        ["metadata", "page_start"], ["paper", "page_start"],
    ])
    p2 = _first_intish_value(rec, [
        ["page_end"], ["last_page"], ["end_page"],
        ["metadata", "page_end"], ["paper", "page_end"],
    ])
    if p1 and p2:
        return f"{p1}-{p2}"
    if p1:
        return p1
    return None

def _extract_journal(rec: Dict[str, Any]) -> Optional[str]:
    return _first_str_value(rec, [
        ["journal"], ["journal_name"], ["journalTitle"],
        ["metadata", "journal"], ["metadata", "journal_name"], ["paper", "journal"],
    ])

def derive_doc_id_with_source(rec: Dict[str, Any]) -> Tuple[Optional[str], str]:
    pmid = _first_intish_value(rec, [
        ["pmid"], ["PMID"], ["pubmed_id"], ["pubmedId"], ["PubMedID"],
        ["metadata", "pmid"], ["metadata", "PMID"], ["paper", "pmid"], ["paper", "PMID"],
    ])
    pmcid_raw = _first_str_value(rec, [
        ["pmcid"], ["PMCID"], ["pubmed_central_id"], ["pmc_id"], ["pmcId"],
        ["metadata", "pmcid"], ["metadata", "PMCID"], ["paper", "pmcid"], ["paper", "PMCID"],
    ])
    pmcid = _normalize_pmcid(pmcid_raw or "")

    if pmid and pmcid:
        return f"PMID:{pmid}|PMCID:{pmcid}", "pmid_pmcid"
    if pmid:
        return f"PMID:{pmid}", "pmid"
    if pmcid:
        return f"PMCID:{pmcid}", "pmcid"

    doi = _first_str_value(rec, [
        ["doi"], ["DOI"], ["metadata", "doi"], ["metadata", "DOI"], ["paper", "doi"], ["paper", "DOI"],
    ])
    if doi:
        doi2 = _DOI_PREFIX_RE.sub("", doi).strip()
        return f"DOI:{doi2}", "doi"

    journal = _extract_journal(rec)
    year = _extract_year(rec)
    volume = _extract_volume(rec)
    pages = _extract_pages(rec)
    jnorm = _normalize_journal(journal or "")
    if jnorm and year and volume and pages:
        return f"JVP:{jnorm}:{year}:{volume}:{pages}", "jvp"

    file_path = _first_str_value(rec, [
        ["source_file"], ["file"], ["filename"], ["pdf_file"],
        ["source", "file"], ["_source", "file"], ["metadata", "file"], ["metadata", "filename"],
    ])
    if file_path:
        name = Path(file_path).name.strip()
        if name:
            return f"FILE:{name}", "file"
        return f"FILEHASH:{_stable_hash(file_path)}", "file"

    title = _first_str_value(rec, [
        ["title"], ["paper_title"], ["metadata", "title"], ["paper", "title"],
    ])
    if title:
        return f"TITLEHASH:{_stable_hash(title.lower().strip())}", "titlehash"

    return None, "none"

# ============================================================
# PROMPT
# ============================================================
SYSTEM_INSTRUCTIONS = (
    "Extract 'mechanistic atoms' from biomedical text.\n\n"
    "Definition: an atom MUST include an explicit effect on a readout.\n"
    "Format: [INTERVENTION] causes [EFFECT] in [READOUT] in a [SYSTEM].\n\n"
    "Hard rules:\n"
    "1) Do NOT invent facts.\n"
    "2) Do NOT assume knockdown succeeded unless the text explicitly says reduction/knockdown/confirmed.\n"
    "3) If the text only describes delivering siRNA/plasmid/drug but gives no stated change in any readout, output no atoms and add a warning.\n"
    "4) You may extract multiple readouts per intervention if they are explicitly stated.\n"
    "5) Rescue/add-back atoms must state what readout is rescued.\n"
    f"6) Keep at most {MAX_ATOMS_PER_CHUNK} atoms.\n"
)

# ============================================================
# MODEL CALLS + ROUTING
# ============================================================
def call_model(model: str, chunk_text: str, mentions: List[Dict[str, Any]]) -> Dict[str, Any]:
    payload = {
        "chunk_text": chunk_text,
        "mentions": compact_mentions(mentions),
        "hints": {"fig_refs": hint_figrefs(chunk_text), "species": hint_species(chunk_text)},
    }
    resp = client.responses.create(
        model=model,
        input=[
            {"role": "system", "content": SYSTEM_INSTRUCTIONS},
            {"role": "user", "content": json.dumps(payload, ensure_ascii=False)},
        ],
        text={
            "format": {
                "type": "json_schema",
                "name": ATOM_SCHEMA_WRAPPER["name"],
                "strict": True,
                "schema": ATOM_SCHEMA_WRAPPER["schema"],
            }
        },
    )
    return json.loads(resp.output_text)

def should_escalate(mentions: List[Dict[str, Any]], atoms: List[Dict[str, Any]]) -> bool:
    if len(mentions) > 0 and len(atoms) == 0:
        return True
    if len(atoms) > 0:
        avg_conf = sum(float(a.get("confidence", 0.0)) for a in atoms) / len(atoms)
        if avg_conf < 0.55:
            return True
    return False

def extract_atoms_with_routing(chunk_text: str, mentions: List[Dict[str, Any]]) -> Dict[str, Any]:
    routing = {"first_model": MODEL_FAST, "escalated": False, "final_model": MODEL_FAST, "reason": None}
    out_fast = call_model(MODEL_FAST, chunk_text, mentions)
    atoms_fast = out_fast.get("atoms", [])

    if should_escalate(mentions, atoms_fast):
        routing["escalated"] = True
        routing["final_model"] = MODEL_STRONG
        routing["reason"] = {"type": "low_confidence_or_empty", "details": "heuristics triggered"}
        out_strong = call_model(MODEL_STRONG, chunk_text, mentions)
        out_strong["_routing"] = routing
        return out_strong

    out_fast["_routing"] = routing
    return out_fast

# ============================================================
# POST-FILTER (expanded effect cues)
# ============================================================
EFFECT_CUE = re.compile(
    r"\b("
    # classic increase/decrease/no-change signals
    r"inhibit|inhibited|inhibition|"
    r"suppress|suppressed|suppressing|suppression|"
    r"reduce|reduced|reduces|reduction|"
    r"decrease|decreased|decreases|"
    r"increase|increased|increases|"
    r"elevate|elevated|"
    r"no effect|did not affect|had no effect|no significant|unchanged|"
    # common biomedical verbs
    r"induce|induced|induction|"
    r"promote|promoted|promotion|"
    r"attenuate|attenuated|attenuation|"
    r"block|blocked|blocking|"
    r"activate|activated|activation|"
    r"inactivate|inactivated|inactivation|"
    r"enhance|enhanced|enhancement|"
    r"impair|impaired|impairment|"
    r"abrogate|abrogated|abrogation|"
    r"abolish|abolished|abolition|"
    # growth/viability language
    r"antiproliferative|anti-proliferative|"
    r"cytotoxic|cytotoxicity|"
    r"tumor growth suppression|growth suppression|"
    # explicit target engagement language
    r"degradation|degraded|degrade|"
    r"depletion|deplete|depleted|"
    r"knockdown|knocked down|silencing|silenced"
    r")\b",
    re.IGNORECASE,
)

SETUP_ONLY_READOUT = re.compile(r"\b(expression|function|knockdown|silencing)\b", re.IGNORECASE)

def looks_like_setup_only(atoms: List[Dict[str, Any]], warnings: List[str]) -> bool:
    if not atoms:
        return True
    wtxt = " ".join(warnings or []).lower()
    if "no explicit functional readouts" in wtxt or "only describes" in wtxt:
        return True
    for a in atoms:
        ro = (a.get("readout", {}) or {}).get("name", "")
        sq = (a.get("evidence", {}) or {}).get("supporting_quote", "")
        if (not SETUP_ONLY_READOUT.search(ro or "")) and EFFECT_CUE.search(sq or ""):
            return False
    return True

def post_filter_atoms(atoms: List[Dict[str, Any]]) -> Tuple[List[Dict[str, Any]], int]:
    kept: List[Dict[str, Any]] = []
    dropped = 0
    for a in atoms or []:
        sq = (a.get("evidence", {}) or {}).get("supporting_quote", "")
        if EFFECT_CUE.search(sq or ""):
            kept.append(a)
        else:
            dropped += 1
    return kept, dropped

# ============================================================
# DOC-AWARE BRIDGING GUARD
# ============================================================
def can_bridge_same_doc_adjacent(a: Dict[str, Any], b: Dict[str, Any]) -> Tuple[bool, str]:
    a_doc = a.get("doc_id")
    b_doc = b.get("doc_id")
    if not a_doc or not b_doc:
        return False, "missing_doc_id"
    if a_doc != b_doc:
        return False, "doc_id_mismatch"

    a_idx = a.get("chunk_index")
    b_idx = b.get("chunk_index")
    if a_idx is None or b_idx is None:
        return False, "missing_chunk_index"
    try:
        ai = int(a_idx)
        bi = int(b_idx)
    except Exception:
        return False, "non_integer_chunk_index"
    if abs(ai - bi) != 1:
        return False, "non_adjacent_chunk_index"
    return True, "ok"

def bridge_text(a_text: str, b_text: str) -> str:
    return (a_text or "").rstrip() + "\n\n" + (b_text or "").lstrip()

def bridge_mentions(a_mentions: List[Dict[str, Any]], b_mentions: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    return list(a_mentions or []) + list(b_mentions or [])

def choose_best_bridged(candidates: List[Tuple[str, Dict[str, Any], List[int], List[str]]]) -> Optional[Tuple[str, Dict[str, Any], List[int], List[str]]]:
    best = None
    for mode, outd, src_chunks, src_docs in candidates:
        atoms = outd.get("atoms", []) or []
        if best is None:
            best = (mode, outd, src_chunks, src_docs)
            continue
        best_atoms = best[1].get("atoms", []) or []
        if len(atoms) > len(best_atoms):
            best = (mode, outd, src_chunks, src_docs)
        elif len(atoms) == len(best_atoms) and len(atoms) > 0:
            avg = sum(float(a.get("confidence", 0.0)) for a in atoms) / len(atoms)
            bavg = sum(float(a.get("confidence", 0.0)) for a in best_atoms) / len(best_atoms)
            if avg > bavg:
                best = (mode, outd, src_chunks, src_docs)
    return best

# ============================================================
# MAIN
# ============================================================
def main() -> int:
    ap = argparse.ArgumentParser(description="PATHAI atoms extraction with PMID/PMCID doc_id derivation and safe bridging switch")
    ap.add_argument("--infile", default="mentions.jsonl", help="Input mentions.jsonl")
    ap.add_argument("--outfile", default="atoms.jsonl", help="Output atoms.jsonl")
    ap.add_argument("--bridge", action="store_true", help="Enable bridging (safe: same doc_id + adjacent chunk_index). Default OFF.")
    ap.add_argument("--default_doc_id", default=None, help="If cannot derive doc_id, use this (otherwise falls back to CHUNK:<chunk_id>).")
    ap.add_argument("--assign_chunk_index", action="store_true", help="Assign chunk_index per doc_id if missing (sequential in file order).")
    ap.add_argument("--no_bridge_forward", action="store_true")
    ap.add_argument("--no_bridge_backward", action="store_true")
    args = ap.parse_args()

    infile = Path(args.infile)
    outfile = Path(args.outfile)
    enable_bridging = bool(args.bridge)
    try_forward = (not args.no_bridge_forward)
    try_backward = (not args.no_bridge_backward)

    if not infile.exists():
        raise FileNotFoundError(f"Cannot find {infile.resolve()}")

    records: List[Dict[str, Any]] = []
    for ln in infile.read_text(encoding="utf-8", errors="ignore").splitlines():
        ln = ln.strip()
        if ln:
            records.append(json.loads(ln))

    src_counts: Dict[str, int] = {}
    for r in records:
        if not r.get("doc_id"):
            doc_id, src = derive_doc_id_with_source(r)
            if doc_id:
                r["doc_id"] = doc_id
                r["doc_id_source"] = src
                src_counts[src] = src_counts.get(src, 0) + 1
            else:
                if args.default_doc_id:
                    r["doc_id"] = args.default_doc_id
                    r["doc_id_source"] = "default"
                    src_counts["default"] = src_counts.get("default", 0) + 1
                else:
                    cid = r.get("chunk_id")
                    r["doc_id"] = f"CHUNK:{cid}"
                    r["doc_id_source"] = "chunk_fallback"
                    src_counts["chunk_fallback"] = src_counts.get("chunk_fallback", 0) + 1

    if args.assign_chunk_index:
        counters: Dict[str, int] = {}
        for r in records:
            doc = r.get("doc_id")
            if not doc:
                continue
            if r.get("chunk_index") is None:
                counters.setdefault(doc, 0)
                r["chunk_index"] = counters[doc]
                counters[doc] += 1

    total_atoms = 0
    escalations = 0
    bridges_used = 0
    bridges_attempted = 0
    dropped_total = 0

    with outfile.open("w", encoding="utf-8", newline="\n") as fout:
        for idx, rec in enumerate(records):
            chunk_id = rec.get("chunk_id")
            doc_id = rec.get("doc_id")
            doc_id_source = rec.get("doc_id_source")
            chunk_index = rec.get("chunk_index")

            if "error" in rec:
                out_rec = {
                    "doc_id": doc_id,
                    "doc_id_source": doc_id_source,
                    "chunk_index": chunk_index,
                    "chunk_id": chunk_id,
                    "atoms": [],
                    "warnings": ["Skipped due to upstream error."],
                    "bridge": {
                        "enabled": enable_bridging,
                        "attempted": False,
                        "used": False,
                        "mode": None,
                        "source_doc_ids": [doc_id] if doc_id else [],
                        "source_chunk_ids": [chunk_id],
                        "skipped_reason": "upstream_error",
                    },
                    "_routing": {"skipped": True},
                    "_post": {"dropped_atoms": 0},
                }
                fout.write(json.dumps(out_rec, ensure_ascii=False) + "\n")
                continue

            chunk_text = rec.get("chunk_text", "")
            mentions = rec.get("mentions", [])

            out = extract_atoms_with_routing(chunk_text, mentions)
            atoms = out.get("atoms", []) or []
            warnings = out.get("warnings", []) or []
            routing = out.get("_routing", {}) or {}

            atoms, dropped = post_filter_atoms(atoms)
            dropped_total += dropped

            used_bridge = False
            attempted_bridge = False
            bridge_mode = None
            skipped_reason = None
            source_chunk_ids = [chunk_id]
            source_doc_ids = [doc_id] if doc_id else []

            need_bridge = (len(mentions or []) > 0 and (len(atoms) == 0 or looks_like_setup_only(atoms, warnings)))

            if enable_bridging and need_bridge:
                attempted_bridge = True
                bridges_attempted += 1
                candidates: List[Tuple[str, Dict[str, Any], List[int], List[str]]] = []

                if try_forward and idx + 1 < len(records):
                    nxt = records[idx + 1]
                    ok, why = can_bridge_same_doc_adjacent(rec, nxt)
                    if ok and "error" not in nxt:
                        t = bridge_text(chunk_text, nxt.get("chunk_text", ""))
                        m = bridge_mentions(mentions, nxt.get("mentions", []))
                        bout = extract_atoms_with_routing(t, m)
                        batoms = bout.get("atoms", []) or []
                        bwarn = bout.get("warnings", []) or []
                        batoms, bdropped = post_filter_atoms(batoms)
                        bout["atoms"] = batoms
                        bout["warnings"] = bwarn
                        bout["_post"] = {"dropped_atoms": bdropped}
                        candidates.append(("forward", bout, [chunk_id, nxt.get("chunk_id")], [rec.get("doc_id"), nxt.get("doc_id")]))
                    else:
                        skipped_reason = skipped_reason or f"forward_{why}"

                if try_backward and idx - 1 >= 0:
                    prv = records[idx - 1]
                    ok, why = can_bridge_same_doc_adjacent(prv, rec)
                    if ok and "error" not in prv:
                        t = bridge_text(prv.get("chunk_text", ""), chunk_text)
                        m = bridge_mentions(prv.get("mentions", []), mentions)
                        bout = extract_atoms_with_routing(t, m)
                        batoms = bout.get("atoms", []) or []
                        bwarn = bout.get("warnings", []) or []
                        batoms, bdropped = post_filter_atoms(batoms)
                        bout["atoms"] = batoms
                        bout["warnings"] = bwarn
                        bout["_post"] = {"dropped_atoms": bdropped}
                        candidates.append(("backward", bout, [prv.get("chunk_id"), chunk_id], [prv.get("doc_id"), rec.get("doc_id")]))
                    else:
                        skipped_reason = skipped_reason or f"backward_{why}"

                best = choose_best_bridged(candidates)
                if best is not None and len(best[1].get("atoms", []) or []) > 0:
                    used_bridge = True
                    bridge_mode = best[0]
                    out = best[1]
                    atoms = out.get("atoms", []) or []
                    warnings = out.get("warnings", []) or []
                    routing = out.get("_routing", routing) or routing
                    source_chunk_ids = best[2]
                    source_doc_ids = [d for d in best[3] if d]
                    bridges_used += 1
                else:
                    if skipped_reason is None:
                        skipped_reason = "no_viable_bridge_candidate"

            if routing.get("escalated"):
                escalations += 1
            total_atoms += len(atoms)

            pmid_pt = rec.get("pmid") or rec.get("PMID") or rec.get("pubmed_id") or rec.get("pubmedId")
            pmcid_pt = rec.get("pmcid") or rec.get("PMCID") or rec.get("pubmed_central_id") or rec.get("pmcId") or rec.get("pmc_id")

            out_rec = {
                "doc_id": doc_id,
                "doc_id_source": doc_id_source,
                "pmid": pmid_pt,
                "pmcid": pmcid_pt,
                "chunk_index": chunk_index,
                "chunk_id": chunk_id,
                "atoms": atoms,
                "warnings": warnings,
                "bridge": {
                    "enabled": enable_bridging,
                    "attempted": attempted_bridge,
                    "used": used_bridge,
                    "mode": bridge_mode,
                    "source_doc_ids": source_doc_ids,
                    "source_chunk_ids": source_chunk_ids,
                    "skipped_reason": skipped_reason,
                },
                "_routing": routing,
                "_post": {"dropped_atoms": dropped},
            }
            fout.write(json.dumps(out_rec, ensure_ascii=False) + "\n")

            print(
                f"chunk {chunk_id} doc_id={doc_id}({doc_id_source}) idx={chunk_index} "
                f"atoms={len(atoms)} escalated={routing.get('escalated', False)} "
                f"bridge_enabled={enable_bridging} bridged={used_bridge} dropped={dropped}"
            )

    print(
        f"Done. total_atoms={total_atoms}, escalations={escalations}, "
        f"bridges_attempted={bridges_attempted}, bridges_used={bridges_used}, dropped_total={dropped_total}"
    )
    print("doc_id sources:", ", ".join(f"{k}={v}" for k, v in sorted(src_counts.items())))
    if not enable_bridging:
        print("Note: bridging was OFF (recommended for mixed/random chunks).")
    else:
        print("Note: bridging ON uses strict guard: same doc_id + adjacent chunk_index.")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
```

### Run (still with bridging off)

```bat
conda activate pathai
cd "C:\Users\Prem Subramaniam\Documents\Pathway AI"
python make_atoms_docaware_v8.py
```

### What you should see for chunk 1 after v8

Chunk 1 should no longer be `atoms=0 dropped=3`. You should get **some atoms retained**, because “antiproliferative” and “suppression” are now recognized.

* * *

If you paste the new `atoms.jsonl` line for **chunk_id 1** after running v8, we can confirm it’s now capturing the “antiproliferative” and “tumor growth suppression” effects cleanly.

* * *

**You:**

{"doc_id": "PMID:41332195", "doc_id_source": "pmid", "pmid": "41332195", "pmcid": null, "chunk_index": null, "chunk_id": 1, "atoms": [{"intervention": {"category": "CHEMICAL_INHIBITOR", "raw_text": "Compound GP262 was identified as a potent dual-degrader of both PI3K and mTOR", "target": {"name": "PI3K and mTOR", "entity_type": "protein"}, "modality": "DEGRADATION"}, "system": {"species": null, "cell_type": null, "cell_lines": ["MDA-MB-231"], "genotype_context": null, "disease_context": null}, "readout": {"name": "tumor growth suppression", "assay": null, "figure_refs": []}, "effect": {"direction": "decrease", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "in vivo validation showed GP262’s significant tumor growth suppression capability.", "notes": null}, "confidence": 0.9}], "warnings": ["No explicit changes in readouts were mentioned for the degradation of PI3K and mTOR, aside from tumor growth suppression."], "bridge": {"enabled": false, "attempted": false, "used": false, "mode": null, "source_doc_ids": ["PMID:41332195"], "source_chunk_ids": [1], "skipped_reason": null}, "_routing": {"first_model": "gpt-4o-mini", "escalated": false, "final_model": "gpt-4o-mini", "reason": null}, "_post": {"dropped_atoms": 0}}

* * *

**ChatGPT:**

TAG: **PATHAI-0069**

Yes — this is exactly the outcome we wanted from the v8 filter change.

### What improved (and why it matters)

* Before v8, chunk 1 had real effects (“tumor growth suppression”, “antiproliferative”) but the filter didn’t recognize that wording, so it dropped everything.
* Now you got **1 retained atom** with:
    * **Intervention:** GP262 (dual degrader of PI3K/mTOR)
    * **Readout:** tumor growth suppression
    * **Direction:** decrease (tumor growth goes down)
    * **Evidence quote:** the exact sentence that states the effect
    * **Confidence:** 0.9
* `_post.dropped_atoms = 0` means the filter is no longer “over-pruning” this chunk.

So: we successfully fixed the _false negative_ problem.

### The warning is also useful (and honest)

> “No explicit changes in readouts were mentioned for the degradation of PI3K and mTOR, aside from tumor growth suppression.”

That’s the model telling you: “I see a phenotypic outcome (tumor growth), but I don’t see direct biochemical target-engagement readouts (like ‘mTOR protein decreased’, ‘pAKT decreased’, etc.) in this chunk.”

That’s correct for an abstract-style chunk: it mentions degradation and pathway modulation, but doesn’t give explicit readouts/quotes beyond the tumor growth effect.

### One thing to tweak (optional but good)

Right now the atom labels the intervention category as `CHEMICAL_INHIBITOR`. Since the text explicitly calls it a **dual-degrader**, it would be cleaner if the category were `CHEMICAL_DEGRADER` (category = what kind of perturbation it is). Your schema already allows that enum.

You can enforce that as a simple rule in the prompt (no post-hoc hacking):  
“If the text says degrader/degradation/DC50 for degradation, use CHEMICAL_DEGRADER.”

Not required for progress, but it will make downstream graphs cleaner.

### Are we ready to move forward now?

**Yes, for the next step in the pipeline (doc-aware extraction and later graphing), you’re now in a safe place**, because:

* `doc_id` is real (PMID works),
* your effect cue filter is no longer throwing out obvious biology effects,
* bridging is off (so no cross-chunk contamination),
* and atoms now have clear evidence quotes.

### What I’d do next (pragmatic)

1. Run v8 across all chunks and re-check:
    * how many `atoms=0` remain,
    * how many get dropped,
    * and whether the remaining “0 atom” chunks are truly background or still false negatives.
2. Add `--assign_chunk_index` (still with bridging off) so your output carries chunk order per PMID, ready for safe bridging later.

If you paste the `atoms.jsonl` line for **chunk_id 2** (from PMID:39682777), I can tell you immediately whether it’s capturing the key functional outcomes cleanly or still missing obvious effect language.

* * *

**You:**

{"doc_id": "PMID:39682777", "doc_id_source": "pmid", "pmid": "39682777", "pmcid": null, "chunk_index": null, "chunk_id": 2, "atoms": [{"intervention": {"category": "KNOCKDOWN_RNAI", "raw_text": "siRNA targeting mTOR, RAPTOR, or RICTOR", "target": {"name": "mTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": "human", "cell_type": null, "cell_lines": [], "genotype_context": null, "disease_context": null}, "readout": {"name": "autophagy", "assay": null, "figure_refs": []}, "effect": {"direction": "increase", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all induced autophagy", "notes": null}, "confidence": 0.8}, {"intervention": {"category": "KNOCKDOWN_RNAI", "raw_text": "siRNA targeting mTOR, RAPTOR, or RICTOR", "target": {"name": "RAPTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": "human", "cell_type": null, "cell_lines": [], "genotype_context": null, "disease_context": null}, "readout": {"name": "apoptosis", "assay": null, "figure_refs": []}, "effect": {"direction": "decrease", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR... inhibited apoptosis", "notes": null}, "confidence": 0.8}, {"intervention": {"category": "KNOCKDOWN_RNAI", "raw_text": "siRNA targeting mTOR, RAPTOR, or RICTOR", "target": {"name": "RAPTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": "human", "cell_type": null, "cell_lines": [], "genotype_context": null, "disease_context": null}, "readout": {"name": "senescence", "assay": null, "figure_refs": []}, "effect": {"direction": "decrease", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR... inhibited senescence", "notes": null}, "confidence": 0.8}, {"intervention": {"category": "KNOCKDOWN_RNAI", "raw_text": "siRNA targeting mTOR, RAPTOR, or RICTOR", "target": {"name": "RAPTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": "human", "cell_type": null, "cell_lines": [], "genotype_context": null, "disease_context": null}, "readout": {"name": "pyroptosis", "assay": null, "figure_refs": []}, "effect": {"direction": "decrease", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR... inhibited pyroptosis", "notes": null}, "confidence": 0.8}, {"intervention": {"category": "KNOCKDOWN_RNAI", "raw_text": "siRNA targeting mTOR, RAPTOR, or RICTOR", "target": {"name": "RAPTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": "human", "cell_type": null, "cell_lines": [], "genotype_context": null, "disease_context": null}, "readout": {"name": "matrix catabolism", "assay": null, "figure_refs": []}, "effect": {"direction": "decrease", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR... inhibited matrix catabolism", "notes": null}, "confidence": 0.8}, {"intervention": {"category": "CRISPR_KO", "raw_text": "CRISPR–Cas9 plasmid targeting mTOR, RAPTOR, or RICTOR", "target": {"name": "mTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": "human", "cell_type": null, "cell_lines": [], "genotype_context": null, "disease_context": null}, "readout": {"name": "autophagy", "assay": null, "figure_refs": []}, "effect": {"direction": "increase", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all induced autophagy", "notes": null}, "confidence": 0.8}, {"intervention": {"category": "CRISPR_KO", "raw_text": "CRISPR–Cas9 plasmid targeting mTOR, RAPTOR, or RICTOR", "target": {"name": "RAPTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": "human", "cell_type": null, "cell_lines": [], "genotype_context": null, "disease_context": null}, "readout": {"name": "apoptosis", "assay": null, "figure_refs": []}, "effect": {"direction": "decrease", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR... inhibited apoptosis", "notes": null}, "confidence": 0.8}, {"intervention": {"category": "CRISPR_KO", "raw_text": "CRISPR–Cas9 plasmid targeting mTOR, RAPTOR, or RICTOR", "target": {"name": "RAPTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": "human", "cell_type": null, "cell_lines": [], "genotype_context": null, "disease_context": null}, "readout": {"name": "senescence", "assay": null, "figure_refs": []}, "effect": {"direction": "decrease", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR... inhibited senescence", "notes": null}, "confidence": 0.8}, {"intervention": {"category": "CRISPR_KO", "raw_text": "CRISPR–Cas9 plasmid targeting mTOR, RAPTOR, or RICTOR", "target": {"name": "RAPTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": "human", "cell_type": null, "cell_lines": [], "genotype_context": null, "disease_context": null}, "readout": {"name": "pyroptosis", "assay": null, "figure_refs": []}, "effect": {"direction": "decrease", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR... inhibited pyroptosis", "notes": null}, "confidence": 0.8}, {"intervention": {"category": "CRISPR_KO", "raw_text": "CRISPR–Cas9 plasmid targeting mTOR, RAPTOR, or RICTOR", "target": {"name": "RAPTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": "human", "cell_type": null, "cell_lines": [], "genotype_context": null, "disease_context": null}, "readout": {"name": "matrix catabolism", "assay": null, "figure_refs": []}, "effect": {"direction": "decrease", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR... inhibited matrix catabolism", "notes": null}, "confidence": 0.8}], "warnings": [], "bridge": {"enabled": false, "attempted": false, "used": false, "mode": null, "source_doc_ids": ["PMID:39682777"], "source_chunk_ids": [2], "skipped_reason": null}, "_routing": {"first_model": "gpt-4o-mini", "escalated": false, "final_model": "gpt-4o-mini", "reason": null}, "_post": {"dropped_atoms": 0}}

* * *

**ChatGPT:**

TAG: **PATHAI-0070**

Thanks — this chunk 2 output is **mostly capturing the biology correctly**, but it also shows **two structural issues** that will matter later (especially for graph scoring).

## What this chunk 2 extraction got right ✅

* It pulled out the **real functional outcomes** stated in the text:
    * **Autophagy increased** (“induced autophagy”)
    * **Apoptosis / senescence / pyroptosis / matrix catabolism decreased** (“inhibited …”)
* It did this for **both perturbation types**:
    * RNAi/siRNA (`KNOCKDOWN_RNAI`)
    * CRISPR–Cas9 (`CRISPR_KO`)
* It kept **evidence quotes** that actually contain the effect language, and `_post.dropped_atoms = 0` means your expanded effect-cue filter is no longer discarding valid biology here.

So the pipeline is working in the sense of “find real outcomes and don’t invent.”

## The two problems to fix before graphing ⚠️

### 1) Target attribution is inconsistent (and could mislead your graph)

Your evidence quote says:

> “Targeting **mTOR, RAPTOR, and RICTOR** all induced autophagy … inhibited apoptosis …”

That statement is **not distinguishing which target causes which effect** — it’s describing a combined result for a set of targets.

But your atoms do this:

* Autophagy is attached to **mTOR** (siRNA + CRISPR)
* The other outcomes are attached to **RAPTOR** (siRNA + CRISPR)
* **RICTOR** is not represented at all

That’s a mismatch between what the sentence actually says and what the atom list implies.

**Why it matters:** a graph builder will read this as “RAPTOR inhibits apoptosis/senescence/…” as if it’s uniquely RAPTOR-driven, and it will _under-represent_ mTOR/RICTOR.

**What we want instead:** when the paper says “targeting A/B/C did X” without separating them, we should store the target as a **multi-target string** (e.g., `"mTOR; RAPTOR; RICTOR"`) or create a controlled multi-target structure later — so we don’t accidentally “choose” RAPTOR for most of the effects.

### 2) You’re missing important context that the chunk actually contains

The chunk text includes strong “supporting” details like:

* target protein suppression and time-course (e.g., RAPTOR suppression ratio 83.2% vs 8.8%)
* “most prominent effects observed with RAPTOR CRISPR–Cas9”
* transfection efficiency differences

Your atoms currently capture the **phenotypes**, but not:

* the **quantified target engagement** (protein expression suppression), which is valuable as “this perturbation actually worked”
* the **RAPTOR-most-prominent** nuance, which is important mechanistically

You don’t _have_ to include these as atoms for the pathway graph — but you probably want them captured somewhere (even if flagged as “target engagement” rather than “functional consequence”).

## Is this “good enough to move on”?

You _can_ move forward, but I’d strongly recommend fixing **(1) target attribution for multi-target statements** first, because otherwise your graph will encode wrong causal assignments.

A very practical rule:

* If a quote mentions multiple targets in one breath (“mTOR, RAPTOR, RICTOR all…”), then **don’t assign the effect to just one** target unless the text explicitly separates them.

If you want, I’ll implement that as the next version (and per your rule I’ll post the **full script**) so:

* multi-target sentences become `"target.name": "mTOR; RAPTOR; RICTOR"` (single atom per readout per modality), and
* the “RAPTOR CRISPR is most prominent” line becomes a **separate RAPTOR-specific atom** with its own quote.

That would make your downstream graph _much more faithful_ to what the paper actually says.

* * *

**You:**

“Targeting mTOR, RAPTOR, and RICTOR all induced autophagy … inhibited apoptosis …”  means any of the 3 targets when targeted unduced autophagy and inhibitied apopotosis.  It does not imply the combination of the 3, but wither one alone.

* * *

**ChatGPT:**

TAG: **PATHAI-0071**

You’re right about the _biology meaning_ of that sentence.

When a paper says:

> “Targeting **mTOR, RAPTOR, and RICTOR all** induced autophagy … inhibited apoptosis …”

the natural reading is: **each target, when perturbed on its own, showed those effects** (it’s not saying “only the triple-combination did it”). The word **“all”** is doing a lot of work there.

### So what was the real problem in our extraction?

Not the biology meaning — the problem is **how the atoms were encoded**:

* The model **didn’t replicate the effect across all three targets** consistently.
* It attached some effects to **mTOR**, most others to **RAPTOR**, and **dropped RICTOR entirely**.
* That’s bad, because it makes the downstream graph think “RAPTOR uniquely drives everything,” which is not what the sentence says.

### The right rule for PATHAI (so the graph is faithful)

We should implement this extraction rule:

* If the text lists multiple targets and uses language like **“all,” “each,” “respectively,”** or otherwise clearly implies **individual targeting**, then **emit parallel atoms**:
    * Same readout/effect/evidence quote
    * One atom per target (mTOR, RAPTOR, RICTOR)
    * For each modality (siRNA and CRISPR), if both are covered by the statement

In your chunk 2, that means we _should_ end up with atoms for:

* **mTOR → autophagy ↑; apoptosis ↓; senescence ↓; pyroptosis ↓; matrix catabolism ↓**
* **RAPTOR → same set**
* **RICTOR → same set**  
    …and duplicated for **siRNA** and **CRISPR**, if the sentence is meant to cover both approaches.

That’s up to **30 atoms**, which fits your `MAX_ATOMS_PER_CHUNK=30`.

### Why I still sometimes prefer a “multi-target atom” (multi-target atom = a single atom whose target field lists multiple targets together)

Only for cases where the wording is ambiguous, like:

* “Targeting mTOR, RAPTOR, and RICTOR was performed…” (no “all/each,” and no explicit separation)

In those ambiguous cases, emitting three separate target-specific atoms can **over-commit**. But your specific sentence is _not_ ambiguous — “all” strongly implies each individually.

### What this changes for the graph (important)

Even if we emit 30 atoms, the graph scorer must **not treat them as 30 independent pieces of evidence**. They’re all from:

* the **same paper** (`doc_id=PMID:39682777`)
* and often the **same sentence/quote**

So they should count as:

* one paper supporting multiple target→outcome edges,  
    not “30 separate papers.”

* * *

If you want the pipeline to be correct “with finality,” the next concrete step is for me to update the extraction script so it **never arbitrarily picks one target** when a sentence says “A, B, and C all did X,” and instead emits the parallel atoms systematically.

* * *

**You:**

Please update the extraction script so it never arbitrarily picks one target when a sentence says “A, B, and C all did X,” and instead emits the parallel atoms systematically.

* * *

**ChatGPT:**

TAG: **PATHAI-0072**

Absolutely — you’re asking for the right safeguard. Below is a **full updated extraction script** that adds a **post-processing expansion step**:

> If an atom’s evidence quote contains language like **“A, B, and C all …”** (or “each …”), the script will **emit parallel atoms** for **each target** (A, B, C) instead of letting the model “pick one.”

This is done **systematically in code**, so it doesn’t depend on model whim.

* * *

## Full script v9: `make_atoms_docaware_v9.py`

**What’s new vs v8**

* Adds a `multi-target expansion` step:
    * Builds a candidate target list from `mentions[*].target_guess.name`
    * Detects multi-target “all/each” statements in the supporting quote
    * Expands each affected atom into **one atom per target**
    * Deduplicates identical atoms after expansion
    * Enforces `MAX_ATOMS_PER_CHUNK` with an explicit warning if truncation occurs
* Also slightly strengthens the prompt to encourage parallel atoms, but the real enforcement is the post-step.

Save as **`make_atoms_docaware_v9.py`**:

```Python
#!/usr/bin/env python3
import os
import json
import re
import argparse
import hashlib
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple
from copy import deepcopy
from openai import OpenAI

# ============================================================
# DEFAULTS
# ============================================================
DEFAULT_INFILE = Path("mentions.jsonl")
DEFAULT_OUTFILE = Path("atoms.jsonl")

MODEL_FAST = "gpt-4o-mini"
MODEL_STRONG = "gpt-4.1"

MAX_ATOMS_PER_CHUNK = 30

# Bridging is OFF by default (safe for mixed/random chunk streams)
DEFAULT_ENABLE_BRIDGING = False

# ============================================================
# OPENAI CLIENT
# ============================================================
def _get_api_key() -> str:
    key = os.getenv("OPENAI_API_KEY")
    if not key:
        raise RuntimeError(
            "OPENAI_API_KEY is not set.\n"
            "Miniforge Prompt (temporary):  set OPENAI_API_KEY=YOUR_KEY\n"
            "Persistent (Windows):         setx OPENAI_API_KEY \"YOUR_KEY\"  (then reopen prompt)"
        )
    return key

client = OpenAI(api_key=_get_api_key())

# ============================================================
# STRICT JSON SCHEMA FOR ATOMS (model output)
# ============================================================
ATOM_SCHEMA_WRAPPER: Dict[str, Any] = {
    "name": "MechanisticAtoms",
    "schema": {
        "type": "object",
        "additionalProperties": False,
        "required": ["atoms", "warnings"],
        "properties": {
            "atoms": {
                "type": "array",
                "items": {
                    "type": "object",
                    "additionalProperties": False,
                    "required": [
                        "intervention",
                        "system",
                        "readout",
                        "effect",
                        "strength_cues",
                        "evidence",
                        "confidence",
                    ],
                    "properties": {
                        "intervention": {
                            "type": "object",
                            "additionalProperties": False,
                            "required": ["category", "raw_text", "target", "modality"],
                            "properties": {
                                "category": {
                                    "type": "string",
                                    "enum": [
                                        "GENETIC_KO",
                                        "CRISPR_KO",
                                        "CRISPRi",
                                        "CRISPRa",
                                        "KNOCKDOWN_RNAI",
                                        "SPLICING_MODULATION",
                                        "OVEREXPRESSION",
                                        "RESCUE_ADD_BACK",
                                        "DOMINANT_NEGATIVE",
                                        "MUTANT_VARIANT",
                                        "CHEMICAL_INHIBITOR",
                                        "CHEMICAL_ACTIVATOR",
                                        "CHEMICAL_DEGRADER",
                                        "STIMULUS_TREATMENT",
                                        "NEUTRALIZING_ANTIBODY",
                                        "UNKNOWN",
                                    ],
                                },
                                "raw_text": {"type": "string", "minLength": 1},
                                "target": {
                                    "anyOf": [
                                        {
                                            "type": "object",
                                            "additionalProperties": False,
                                            "required": ["name", "entity_type"],
                                            "properties": {
                                                "name": {"type": "string"},
                                                "entity_type": {
                                                    "type": "string",
                                                    "enum": [
                                                        "gene",
                                                        "protein",
                                                        "chemical",
                                                        "stimulus",
                                                        "antibody",
                                                        "unknown",
                                                    ],
                                                },
                                            },
                                        },
                                        {"type": "null"},
                                    ]
                                },
                                "modality": {
                                    "type": "string",
                                    "enum": [
                                        "LOF",
                                        "GOF",
                                        "INHIBITION",
                                        "ACTIVATION",
                                        "DEGRADATION",
                                        "RESCUE",
                                        "UNKNOWN",
                                    ],
                                },
                            },
                        },
                        "system": {
                            "type": "object",
                            "additionalProperties": False,
                            "required": [
                                "species",
                                "cell_type",
                                "cell_lines",
                                "genotype_context",
                                "disease_context",
                            ],
                            "properties": {
                                "species": {"type": ["string", "null"]},
                                "cell_type": {"type": ["string", "null"]},
                                "cell_lines": {"type": "array", "items": {"type": "string"}},
                                "genotype_context": {"type": ["string", "null"]},
                                "disease_context": {"type": ["string", "null"]},
                            },
                        },
                        "readout": {
                            "type": "object",
                            "additionalProperties": False,
                            "required": ["name", "assay", "figure_refs"],
                            "properties": {
                                "name": {"type": "string"},
                                "assay": {"type": ["string", "null"]},
                                "figure_refs": {"type": "array", "items": {"type": "string"}},
                            },
                        },
                        "effect": {
                            "type": "object",
                            "additionalProperties": False,
                            "required": ["direction", "timepoint", "magnitude", "comparison"],
                            "properties": {
                                "direction": {
                                    "type": "string",
                                    "enum": ["increase", "decrease", "no_change", "mixed", "unknown"],
                                },
                                "timepoint": {"type": ["string", "null"]},
                                "magnitude": {"type": ["string", "null"]},
                                "comparison": {"type": ["string", "null"]},
                            },
                        },
                        "strength_cues": {
                            "type": "object",
                            "additionalProperties": False,
                            "required": ["has_rescue", "has_control", "has_multiple_lines", "other"],
                            "properties": {
                                "has_rescue": {"type": "boolean"},
                                "has_control": {"type": "boolean"},
                                "has_multiple_lines": {"type": "boolean"},
                                "other": {"type": "array", "items": {"type": "string"}},
                            },
                        },
                        "evidence": {
                            "type": "object",
                            "additionalProperties": False,
                            "required": ["supporting_quote", "notes"],
                            "properties": {
                                "supporting_quote": {"type": "string"},
                                "notes": {"type": ["string", "null"]},
                            },
                        },
                        "confidence": {"type": "number", "minimum": 0, "maximum": 1},
                    },
                },
            },
            "warnings": {"type": "array", "items": {"type": "string"}},
        },
    },
}

# ============================================================
# LIGHTWEIGHT HINTS
# ============================================================
FIGREF_REGEX = re.compile(r"\b(Fig\.?\s*\d+[A-Za-z]?)\b", re.IGNORECASE)
SPECIES_REGEX = re.compile(r"\b(human|mouse|murine|rat)\b", re.IGNORECASE)

def _uniq_preserve(seq: List[str]) -> List[str]:
    seen = set()
    out = []
    for x in seq:
        k = x.lower()
        if k not in seen:
            seen.add(k)
            out.append(x)
    return out

def hint_figrefs(text: str) -> List[str]:
    return _uniq_preserve([m.group(1) for m in FIGREF_REGEX.finditer(text or "")])

def hint_species(text: str) -> Optional[str]:
    m = SPECIES_REGEX.search(text or "")
    if not m:
        return None
    s = m.group(1).lower()
    return "mouse" if s == "murine" else s

def compact_mentions(mentions: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    out = []
    for i, m in enumerate(mentions or [], start=1):
        out.append({
            "i": i,
            "category": m.get("category"),
            "raw_text": m.get("raw_text"),
            "target_guess": m.get("target_guess"),
            "method_cues": m.get("method_cues", []),
        })
    return out

# ============================================================
# DOC_ID DERIVATION (PMID(+PMCID) → PMCID → DOI → JVP → FILE → TITLEHASH → CHUNK)
# ============================================================
_DOI_PREFIX_RE = re.compile(r"^(https?://(dx\.)?doi\.org/|doi:\s*)", re.IGNORECASE)
_YEAR_RE = re.compile(r"\b(19\d{2}|20\d{2})\b")
_PAGES_RE = re.compile(r"^\s*(\d+)\s*[-–—]\s*(\d+)\s*$")

def _stable_hash(text: str, n: int = 12) -> str:
    return hashlib.sha1(text.encode("utf-8")).hexdigest()[:n]

def _get_nested(rec: Dict[str, Any], path: List[str]) -> Optional[Any]:
    cur: Any = rec
    for k in path:
        if not isinstance(cur, dict) or k not in cur:
            return None
        cur = cur[k]
    return cur

def _first_str_value(rec: Dict[str, Any], key_paths: List[List[str]]) -> Optional[str]:
    for path in key_paths:
        v = _get_nested(rec, path)
        if isinstance(v, str) and v.strip():
            return v.strip()
    return None

def _first_intish_value(rec: Dict[str, Any], key_paths: List[List[str]]) -> Optional[str]:
    for path in key_paths:
        v = _get_nested(rec, path)
        if v is None:
            continue
        if isinstance(v, int):
            return str(v)
        if isinstance(v, str):
            s = v.strip()
            m = re.search(r"\d+", s)
            if m:
                return m.group(0)
    return None

def _normalize_pmcid(x: str) -> Optional[str]:
    if not x:
        return None
    s = x.strip()
    if s.lower().startswith("pmc"):
        digits = re.sub(r"\D+", "", s)
        return f"PMC{digits}" if digits else None
    digits = re.sub(r"\D+", "", s)
    return f"PMC{digits}" if digits else None

def _normalize_journal(j: str) -> str:
    s = re.sub(r"[^A-Za-z0-9]+", "", (j or "").lower())
    return s[:32] if s else ""

def _extract_year(rec: Dict[str, Any]) -> Optional[str]:
    year = _first_intish_value(rec, [
        ["year"], ["pub_year"], ["publication_year"],
        ["metadata", "year"], ["metadata", "pub_year"], ["paper", "year"],
    ])
    if year and len(year) == 4:
        return year

    date_str = _first_str_value(rec, [
        ["date"], ["publication_date"], ["pub_date"],
        ["metadata", "date"], ["metadata", "publication_date"], ["paper", "date"],
    ])
    if date_str:
        m = _YEAR_RE.search(date_str)
        if m:
            return m.group(1)
    return None

def _extract_volume(rec: Dict[str, Any]) -> Optional[str]:
    vol = _first_str_value(rec, [
        ["volume"], ["vol"], ["metadata", "volume"], ["paper", "volume"],
    ])
    if not vol:
        return None
    vol2 = re.sub(r"[^0-9A-Za-z]+", "", vol)
    return vol2 or None

def _extract_pages(rec: Dict[str, Any]) -> Optional[str]:
    pages = _first_str_value(rec, [
        ["pages"], ["page_range"], ["pagination"], ["pageNumbers"],
        ["metadata", "pages"], ["metadata", "page_range"], ["paper", "pages"],
    ])
    if pages:
        s = pages.strip().replace("–", "-").replace("—", "-")
        m = _PAGES_RE.match(s)
        if m:
            return f"{m.group(1)}-{m.group(2)}"
        s2 = re.sub(r"\s+", "", s)
        s2 = re.sub(r"[^0-9A-Za-z\-]+", "", s2)
        return s2 or None

    p1 = _first_intish_value(rec, [
        ["page_start"], ["first_page"], ["start_page"],
        ["metadata", "page_start"], ["paper", "page_start"],
    ])
    p2 = _first_intish_value(rec, [
        ["page_end"], ["last_page"], ["end_page"],
        ["metadata", "page_end"], ["paper", "page_end"],
    ])
    if p1 and p2:
        return f"{p1}-{p2}"
    if p1:
        return p1
    return None

def _extract_journal(rec: Dict[str, Any]) -> Optional[str]:
    return _first_str_value(rec, [
        ["journal"], ["journal_name"], ["journalTitle"],
        ["metadata", "journal"], ["metadata", "journal_name"], ["paper", "journal"],
    ])

def derive_doc_id_with_source(rec: Dict[str, Any]) -> Tuple[Optional[str], str]:
    pmid = _first_intish_value(rec, [
        ["pmid"], ["PMID"], ["pubmed_id"], ["pubmedId"], ["PubMedID"],
        ["metadata", "pmid"], ["metadata", "PMID"], ["paper", "pmid"], ["paper", "PMID"],
    ])
    pmcid_raw = _first_str_value(rec, [
        ["pmcid"], ["PMCID"], ["pubmed_central_id"], ["pmc_id"], ["pmcId"],
        ["metadata", "pmcid"], ["metadata", "PMCID"], ["paper", "pmcid"], ["paper", "PMCID"],
    ])
    pmcid = _normalize_pmcid(pmcid_raw or "")

    if pmid and pmcid:
        return f"PMID:{pmid}|PMCID:{pmcid}", "pmid_pmcid"
    if pmid:
        return f"PMID:{pmid}", "pmid"
    if pmcid:
        return f"PMCID:{pmcid}", "pmcid"

    doi = _first_str_value(rec, [
        ["doi"], ["DOI"], ["metadata", "doi"], ["metadata", "DOI"], ["paper", "doi"], ["paper", "DOI"],
    ])
    if doi:
        doi2 = _DOI_PREFIX_RE.sub("", doi).strip()
        return f"DOI:{doi2}", "doi"

    journal = _extract_journal(rec)
    year = _extract_year(rec)
    volume = _extract_volume(rec)
    pages = _extract_pages(rec)
    jnorm = _normalize_journal(journal or "")
    if jnorm and year and volume and pages:
        return f"JVP:{jnorm}:{year}:{volume}:{pages}", "jvp"

    file_path = _first_str_value(rec, [
        ["source_file"], ["file"], ["filename"], ["pdf_file"],
        ["source", "file"], ["_source", "file"], ["metadata", "file"], ["metadata", "filename"],
    ])
    if file_path:
        name = Path(file_path).name.strip()
        if name:
            return f"FILE:{name}", "file"
        return f"FILEHASH:{_stable_hash(file_path)}", "file"

    title = _first_str_value(rec, [
        ["title"], ["paper_title"], ["metadata", "title"], ["paper", "title"],
    ])
    if title:
        return f"TITLEHASH:{_stable_hash(title.lower().strip())}", "titlehash"

    return None, "none"

# ============================================================
# PROMPT
# ============================================================
SYSTEM_INSTRUCTIONS = (
    "Extract 'mechanistic atoms' from biomedical text.\n\n"
    "Definition: an atom MUST include an explicit effect on a readout.\n"
    "Format: [INTERVENTION] causes [EFFECT] in [READOUT] in a [SYSTEM].\n\n"
    "Hard rules:\n"
    "1) Do NOT invent facts.\n"
    "2) Do NOT assume knockdown succeeded unless the text explicitly says reduction/knockdown/confirmed.\n"
    "3) If the text only describes delivering siRNA/plasmid/drug but gives no stated change in any readout, output no atoms and add a warning.\n"
    "4) If a sentence says targeting A, B, and C 'all' (or 'each') causes an effect, emit parallel atoms for each target (A and B and C) rather than picking one.\n"
    "5) Rescue/add-back atoms must state what readout is rescued.\n"
    f"6) Keep at most {MAX_ATOMS_PER_CHUNK} atoms.\n"
)

# ============================================================
# MODEL CALLS + ROUTING
# ============================================================
def call_model(model: str, chunk_text: str, mentions: List[Dict[str, Any]]) -> Dict[str, Any]:
    payload = {
        "chunk_text": chunk_text,
        "mentions": compact_mentions(mentions),
        "hints": {"fig_refs": hint_figrefs(chunk_text), "species": hint_species(chunk_text)},
    }
    resp = client.responses.create(
        model=model,
        input=[
            {"role": "system", "content": SYSTEM_INSTRUCTIONS},
            {"role": "user", "content": json.dumps(payload, ensure_ascii=False)},
        ],
        text={
            "format": {
                "type": "json_schema",
                "name": ATOM_SCHEMA_WRAPPER["name"],
                "strict": True,
                "schema": ATOM_SCHEMA_WRAPPER["schema"],
            }
        },
    )
    return json.loads(resp.output_text)

def should_escalate(mentions: List[Dict[str, Any]], atoms: List[Dict[str, Any]]) -> bool:
    if len(mentions) > 0 and len(atoms) == 0:
        return True
    if len(atoms) > 0:
        avg_conf = sum(float(a.get("confidence", 0.0)) for a in atoms) / len(atoms)
        if avg_conf < 0.55:
            return True
    return False

def extract_atoms_with_routing(chunk_text: str, mentions: List[Dict[str, Any]]) -> Dict[str, Any]:
    routing = {"first_model": MODEL_FAST, "escalated": False, "final_model": MODEL_FAST, "reason": None}
    out_fast = call_model(MODEL_FAST, chunk_text, mentions)
    atoms_fast = out_fast.get("atoms", [])

    if should_escalate(mentions, atoms_fast):
        routing["escalated"] = True
        routing["final_model"] = MODEL_STRONG
        routing["reason"] = {"type": "low_confidence_or_empty", "details": "heuristics triggered"}
        out_strong = call_model(MODEL_STRONG, chunk_text, mentions)
        out_strong["_routing"] = routing
        return out_strong

    out_fast["_routing"] = routing
    return out_fast

# ============================================================
# POST-FILTER (expanded effect cues)
# ============================================================
EFFECT_CUE = re.compile(
    r"\b("
    r"inhibit|inhibited|inhibition|"
    r"suppress|suppressed|suppressing|suppression|"
    r"reduce|reduced|reduces|reduction|"
    r"decrease|decreased|decreases|"
    r"increase|increased|increases|"
    r"elevate|elevated|"
    r"no effect|did not affect|had no effect|no significant|unchanged|"
    r"induce|induced|induction|"
    r"promote|promoted|promotion|"
    r"attenuate|attenuated|attenuation|"
    r"block|blocked|blocking|"
    r"activate|activated|activation|"
    r"inactivate|inactivated|inactivation|"
    r"enhance|enhanced|enhancement|"
    r"impair|impaired|impairment|"
    r"abrogate|abrogated|abrogation|"
    r"abolish|abolished|abolition|"
    r"antiproliferative|anti-proliferative|"
    r"cytotoxic|cytotoxicity|"
    r"tumor growth suppression|growth suppression|"
    r"degradation|degraded|degrade|"
    r"depletion|deplete|depleted|"
    r"knockdown|knocked down|silencing|silenced"
    r")\b",
    re.IGNORECASE,
)

SETUP_ONLY_READOUT = re.compile(r"\b(expression|function|knockdown|silencing)\b", re.IGNORECASE)

def looks_like_setup_only(atoms: List[Dict[str, Any]], warnings: List[str]) -> bool:
    if not atoms:
        return True
    wtxt = " ".join(warnings or []).lower()
    if "no explicit functional readouts" in wtxt or "only describes" in wtxt:
        return True
    for a in atoms:
        ro = (a.get("readout", {}) or {}).get("name", "")
        sq = (a.get("evidence", {}) or {}).get("supporting_quote", "")
        if (not SETUP_ONLY_READOUT.search(ro or "")) and EFFECT_CUE.search(sq or ""):
            return False
    return True

def post_filter_atoms(atoms: List[Dict[str, Any]]) -> Tuple[List[Dict[str, Any]], int]:
    kept: List[Dict[str, Any]] = []
    dropped = 0
    for a in atoms or []:
        sq = (a.get("evidence", {}) or {}).get("supporting_quote", "")
        if EFFECT_CUE.search(sq or ""):
            kept.append(a)
        else:
            dropped += 1
    return kept, dropped

# ============================================================
# MULTI-TARGET EXPANSION (the requested safeguard)
# ============================================================
MULTI_TARGET_CUE = re.compile(r"\b(all|each)\b", re.IGNORECASE)

def _norm_space(s: str) -> str:
    return re.sub(r"\s+", " ", (s or "")).strip()

def _split_target_list(s: str) -> List[str]:
    """
    Split a target_guess like:
      "mTOR, RAPTOR, or RICTOR"  -> ["mTOR","RAPTOR","RICTOR"]
      "PI3K and mTOR"            -> ["PI3K","mTOR"]
    """
    if not s:
        return []
    x = _norm_space(s)
    x = x.replace("/", " / ")
    x = re.sub(r"\(", " ( ", x)
    x = re.sub(r"\)", " ) ", x)
    # unify delimiters
    x = re.sub(r"\band\b", ",", x, flags=re.IGNORECASE)
    x = re.sub(r"\bor\b", ",", x, flags=re.IGNORECASE)
    x = x.replace(";", ",").replace("/", ",")
    parts = [p.strip(" ,.;:()[]{}<>\"'") for p in x.split(",")]
    out = []
    for p in parts:
        if not p:
            continue
        # exclude obvious non-target tokens
        if p.lower() in {"and", "or", "the", "a", "an"}:
            continue
        out.append(p)
    return out

def _targets_from_mentions(mentions: List[Dict[str, Any]]) -> Tuple[List[str], Dict[str, str]]:
    """
    Returns:
      - candidate_targets: unique list of target names seen in mentions target_guess
      - type_map: lower(target)->entity_type (best guess)
    """
    cand: List[str] = []
    type_map: Dict[str, str] = {}
    for m in mentions or []:
        tg = m.get("target_guess") or {}
        name = tg.get("name")
        et = tg.get("entity_type") or "protein"
        for t in _split_target_list(str(name) if name else ""):
            key = t.lower()
            if key not in type_map:
                type_map[key] = et
            if t not in cand:
                cand.append(t)
    return cand, type_map

def _find_targets_in_text(candidate_targets: List[str], text: str) -> List[str]:
    found: List[str] = []
    hay = text or ""
    for t in candidate_targets:
        # word-boundary match to avoid partial hits
        pat = r"\b" + re.escape(t) + r"\b"
        if re.search(pat, hay, flags=re.IGNORECASE):
            found.append(t)
    return found

def _atom_key(a: Dict[str, Any]) -> Tuple:
    iv = a.get("intervention", {}) or {}
    tg = iv.get("target") or {}
    rd = a.get("readout", {}) or {}
    ef = a.get("effect", {}) or {}
    ev = a.get("evidence", {}) or {}
    return (
        str(iv.get("category") or "").lower(),
        str(iv.get("modality") or "").lower(),
        str((tg.get("name") if isinstance(tg, dict) else "") or "").lower(),
        str(rd.get("name") or "").lower(),
        str(ef.get("direction") or "").lower(),
        _norm_space(str(ev.get("supporting_quote") or "")).lower(),
    )

def expand_multi_target_atoms(
    atoms: List[Dict[str, Any]],
    mentions: List[Dict[str, Any]],
    max_atoms: int,
) -> Tuple[List[Dict[str, Any]], Dict[str, Any], List[str]]:
    """
    If supporting_quote + cue word ('all'/'each') indicates multiple targets,
    emit parallel atoms for each target rather than letting the model pick one.

    Returns: (new_atoms, expansion_meta, extra_warnings)
    """
    candidate_targets, type_map = _targets_from_mentions(mentions)
    if not candidate_targets:
        return atoms, {"enabled": True, "expanded_atoms": 0, "events": 0}, []

    new_atoms: List[Dict[str, Any]] = []
    events = 0
    expanded_atoms = 0
    extra_warnings: List[str] = []

    for a in atoms or []:
        ev = a.get("evidence", {}) or {}
        sq = _norm_space(ev.get("supporting_quote") or "")
        iv = a.get("intervention", {}) or {}
        raw = _norm_space(iv.get("raw_text") or "")
        combined = (sq + " " + raw).strip()

        # Only expand when:
        #  - cue word present ('all'/'each'), AND
        #  - multiple candidate targets are explicitly present in the quote/raw_text
        found = _find_targets_in_text(candidate_targets, combined)
        if MULTI_TARGET_CUE.search(combined) and len(found) >= 2:
            events += 1
            # Expand into one atom per found target
            for t in found:
                aa = deepcopy(a)
                et = type_map.get(t.lower(), None)

                if not aa.get("intervention"):
                    aa["intervention"] = {}
                if aa["intervention"].get("target") is None or not isinstance(aa["intervention"].get("target"), dict):
                    aa["intervention"]["target"] = {"name": t, "entity_type": et or "protein"}
                else:
                    aa["intervention"]["target"]["name"] = t
                    # keep existing entity_type if present; else fill
                    if not aa["intervention"]["target"].get("entity_type"):
                        aa["intervention"]["target"]["entity_type"] = et or "protein"

                new_atoms.append(aa)
                expanded_atoms += 1
        else:
            new_atoms.append(a)

    # Deduplicate after expansion
    deduped: List[Dict[str, Any]] = []
    seen = set()
    for a in new_atoms:
        k = _atom_key(a)
        if k in seen:
            continue
        seen.add(k)
        deduped.append(a)

    # Enforce max atoms (auditably)
    if len(deduped) > max_atoms:
        extra_warnings.append(
            f"Truncated atoms after multi-target expansion: {len(deduped)} -> {max_atoms} due to MAX_ATOMS_PER_CHUNK."
        )
        deduped = deduped[:max_atoms]

    meta = {
        "enabled": True,
        "candidate_targets": candidate_targets[:50],
        "events": events,
        "expanded_atoms": expanded_atoms,
        "deduped_atoms": len(deduped),
    }
    return deduped, meta, extra_warnings

# ============================================================
# DOC-AWARE BRIDGING GUARD
# ============================================================
def can_bridge_same_doc_adjacent(a: Dict[str, Any], b: Dict[str, Any]) -> Tuple[bool, str]:
    a_doc = a.get("doc_id")
    b_doc = b.get("doc_id")
    if not a_doc or not b_doc:
        return False, "missing_doc_id"
    if a_doc != b_doc:
        return False, "doc_id_mismatch"

    a_idx = a.get("chunk_index")
    b_idx = b.get("chunk_index")
    if a_idx is None or b_idx is None:
        return False, "missing_chunk_index"
    try:
        ai = int(a_idx)
        bi = int(b_idx)
    except Exception:
        return False, "non_integer_chunk_index"
    if abs(ai - bi) != 1:
        return False, "non_adjacent_chunk_index"
    return True, "ok"

def bridge_text(a_text: str, b_text: str) -> str:
    return (a_text or "").rstrip() + "\n\n" + (b_text or "").lstrip()

def bridge_mentions(a_mentions: List[Dict[str, Any]], b_mentions: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    return list(a_mentions or []) + list(b_mentions or [])

def choose_best_bridged(candidates: List[Tuple[str, Dict[str, Any], List[int], List[str]]]) -> Optional[Tuple[str, Dict[str, Any], List[int], List[str]]]:
    best = None
    for mode, outd, src_chunks, src_docs in candidates:
        atoms = outd.get("atoms", []) or []
        if best is None:
            best = (mode, outd, src_chunks, src_docs)
            continue
        best_atoms = best[1].get("atoms", []) or []
        if len(atoms) > len(best_atoms):
            best = (mode, outd, src_chunks, src_docs)
        elif len(atoms) == len(best_atoms) and len(atoms) > 0:
            avg = sum(float(a.get("confidence", 0.0)) for a in atoms) / len(atoms)
            bavg = sum(float(a.get("confidence", 0.0)) for a in best_atoms) / len(best_atoms)
            if avg > bavg:
                best = (mode, outd, src_chunks, src_docs)
    return best

# ============================================================
# MAIN
# ============================================================
def main() -> int:
    ap = argparse.ArgumentParser(description="PATHAI atoms extraction with doc_id + expanded effect cues + multi-target expansion")
    ap.add_argument("--infile", default="mentions.jsonl", help="Input mentions.jsonl")
    ap.add_argument("--outfile", default="atoms.jsonl", help="Output atoms.jsonl")
    ap.add_argument("--bridge", action="store_true", help="Enable bridging (safe: same doc_id + adjacent chunk_index). Default OFF.")
    ap.add_argument("--default_doc_id", default=None, help="If cannot derive doc_id, use this (otherwise falls back to CHUNK:<chunk_id>).")
    ap.add_argument("--assign_chunk_index", action="store_true", help="Assign chunk_index per doc_id if missing (sequential in file order).")
    ap.add_argument("--no_bridge_forward", action="store_true")
    ap.add_argument("--no_bridge_backward", action="store_true")
    args = ap.parse_args()

    infile = Path(args.infile)
    outfile = Path(args.outfile)
    enable_bridging = bool(args.bridge)
    try_forward = (not args.no_bridge_forward)
    try_backward = (not args.no_bridge_backward)

    if not infile.exists():
        raise FileNotFoundError(f"Cannot find {infile.resolve()}")

    records: List[Dict[str, Any]] = []
    for ln in infile.read_text(encoding="utf-8", errors="ignore").splitlines():
        ln = ln.strip()
        if ln:
            records.append(json.loads(ln))

    # doc_id fill-in
    src_counts: Dict[str, int] = {}
    for r in records:
        if not r.get("doc_id"):
            doc_id, src = derive_doc_id_with_source(r)
            if doc_id:
                r["doc_id"] = doc_id
                r["doc_id_source"] = src
                src_counts[src] = src_counts.get(src, 0) + 1
            else:
                if args.default_doc_id:
                    r["doc_id"] = args.default_doc_id
                    r["doc_id_source"] = "default"
                    src_counts["default"] = src_counts.get("default", 0) + 1
                else:
                    cid = r.get("chunk_id")
                    r["doc_id"] = f"CHUNK:{cid}"
                    r["doc_id_source"] = "chunk_fallback"
                    src_counts["chunk_fallback"] = src_counts.get("chunk_fallback", 0) + 1

    # Optional chunk_index assignment per doc_id
    if args.assign_chunk_index:
        counters: Dict[str, int] = {}
        for r in records:
            doc = r.get("doc_id")
            if not doc:
                continue
            if r.get("chunk_index") is None:
                counters.setdefault(doc, 0)
                r["chunk_index"] = counters[doc]
                counters[doc] += 1

    total_atoms = 0
    escalations = 0
    bridges_used = 0
    bridges_attempted = 0
    dropped_total = 0
    mt_events_total = 0
    mt_expanded_total = 0

    with outfile.open("w", encoding="utf-8", newline="\n") as fout:
        for idx, rec in enumerate(records):
            chunk_id = rec.get("chunk_id")
            doc_id = rec.get("doc_id")
            doc_id_source = rec.get("doc_id_source")
            chunk_index = rec.get("chunk_index")

            if "error" in rec:
                out_rec = {
                    "doc_id": doc_id,
                    "doc_id_source": doc_id_source,
                    "chunk_index": chunk_index,
                    "chunk_id": chunk_id,
                    "atoms": [],
                    "warnings": ["Skipped due to upstream error."],
                    "bridge": {
                        "enabled": enable_bridging,
                        "attempted": False,
                        "used": False,
                        "mode": None,
                        "source_doc_ids": [doc_id] if doc_id else [],
                        "source_chunk_ids": [chunk_id],
                        "skipped_reason": "upstream_error",
                    },
                    "_routing": {"skipped": True},
                    "_post": {"dropped_atoms": 0, "multi_target": {"enabled": True, "events": 0, "expanded_atoms": 0}},
                }
                fout.write(json.dumps(out_rec, ensure_ascii=False) + "\n")
                continue

            chunk_text = rec.get("chunk_text", "")
            mentions = rec.get("mentions", [])

            out = extract_atoms_with_routing(chunk_text, mentions)
            atoms = out.get("atoms", []) or []
            warnings = out.get("warnings", []) or []
            routing = out.get("_routing", {}) or {}

            # Filter on explicit effect language
            atoms, dropped = post_filter_atoms(atoms)
            dropped_total += dropped

            # Expand multi-target statements (the requested behavior)
            atoms, mt_meta, mt_warn = expand_multi_target_atoms(atoms, mentions, MAX_ATOMS_PER_CHUNK)
            if mt_warn:
                warnings.extend(mt_warn)
            mt_events_total += int(mt_meta.get("events", 0))
            mt_expanded_total += int(mt_meta.get("expanded_atoms", 0))

            used_bridge = False
            attempted_bridge = False
            bridge_mode = None
            skipped_reason = None
            source_chunk_ids = [chunk_id]
            source_doc_ids = [doc_id] if doc_id else []

            need_bridge = (len(mentions or []) > 0 and (len(atoms) == 0 or looks_like_setup_only(atoms, warnings)))

            # Bridging (still optional; OFF by default)
            if enable_bridging and need_bridge:
                attempted_bridge = True
                bridges_attempted += 1
                candidates: List[Tuple[str, Dict[str, Any], List[int], List[str]]] = []

                if try_forward and idx + 1 < len(records):
                    nxt = records[idx + 1]
                    ok, why = can_bridge_same_doc_adjacent(rec, nxt)
                    if ok and "error" not in nxt:
                        t = bridge_text(chunk_text, nxt.get("chunk_text", ""))
                        m = bridge_mentions(mentions, nxt.get("mentions", []))
                        bout = extract_atoms_with_routing(t, m)
                        batoms = bout.get("atoms", []) or []
                        bwarn = bout.get("warnings", []) or []
                        batoms, bdropped = post_filter_atoms(batoms)
                        batoms, bmt_meta, bmt_warn = expand_multi_target_atoms(batoms, m, MAX_ATOMS_PER_CHUNK)
                        if bmt_warn:
                            bwarn.extend(bmt_warn)
                        bout["atoms"] = batoms
                        bout["warnings"] = bwarn
                        bout["_post"] = {"dropped_atoms": bdropped, "multi_target": bmt_meta}
                        candidates.append(("forward", bout, [chunk_id, nxt.get("chunk_id")], [rec.get("doc_id"), nxt.get("doc_id")]))
                    else:
                        skipped_reason = skipped_reason or f"forward_{why}"

                if try_backward and idx - 1 >= 0:
                    prv = records[idx - 1]
                    ok, why = can_bridge_same_doc_adjacent(prv, rec)
                    if ok and "error" not in prv:
                        t = bridge_text(prv.get("chunk_text", ""), chunk_text)
                        m = bridge_mentions(prv.get("mentions", []), mentions)
                        bout = extract_atoms_with_routing(t, m)
                        batoms = bout.get("atoms", []) or []
                        bwarn = bout.get("warnings", []) or []
                        batoms, bdropped = post_filter_atoms(batoms)
                        batoms, bmt_meta, bmt_warn = expand_multi_target_atoms(batoms, m, MAX_ATOMS_PER_CHUNK)
                        if bmt_warn:
                            bwarn.extend(bmt_warn)
                        bout["atoms"] = batoms
                        bout["warnings"] = bwarn
                        bout["_post"] = {"dropped_atoms": bdropped, "multi_target": bmt_meta}
                        candidates.append(("backward", bout, [prv.get("chunk_id"), chunk_id], [prv.get("doc_id"), rec.get("doc_id")]))
                    else:
                        skipped_reason = skipped_reason or f"backward_{why}"

                best = choose_best_bridged(candidates)
                if best is not None and len(best[1].get("atoms", []) or []) > 0:
                    used_bridge = True
                    bridge_mode = best[0]
                    out = best[1]
                    atoms = out.get("atoms", []) or []
                    warnings = out.get("warnings", []) or []
                    routing = out.get("_routing", routing) or routing
                    source_chunk_ids = best[2]
                    source_doc_ids = [d for d in best[3] if d]
                    bridges_used += 1
                else:
                    if skipped_reason is None:
                        skipped_reason = "no_viable_bridge_candidate"

            if routing.get("escalated"):
                escalations += 1
            total_atoms += len(atoms)

            pmid_pt = rec.get("pmid") or rec.get("PMID") or rec.get("pubmed_id") or rec.get("pubmedId")
            pmcid_pt = rec.get("pmcid") or rec.get("PMCID") or rec.get("pubmed_central_id") or rec.get("pmcId") or rec.get("pmc_id")

            out_rec = {
                "doc_id": doc_id,
                "doc_id_source": doc_id_source,
                "pmid": pmid_pt,
                "pmcid": pmcid_pt,
                "chunk_index": chunk_index,
                "chunk_id": chunk_id,
                "atoms": atoms,
                "warnings": warnings,
                "bridge": {
                    "enabled": enable_bridging,
                    "attempted": attempted_bridge,
                    "used": used_bridge,
                    "mode": bridge_mode,
                    "source_doc_ids": source_doc_ids,
                    "source_chunk_ids": source_chunk_ids,
                    "skipped_reason": skipped_reason,
                },
                "_routing": routing,
                "_post": {"dropped_atoms": dropped, "multi_target": mt_meta},
            }
            fout.write(json.dumps(out_rec, ensure_ascii=False) + "\n")

            print(
                f"chunk {chunk_id} doc_id={doc_id}({doc_id_source}) idx={chunk_index} "
                f"atoms={len(atoms)} escalated={routing.get('escalated', False)} "
                f"bridge_enabled={enable_bridging} bridged={used_bridge} dropped={dropped} "
                f"mt_events={mt_meta.get('events',0)}"
            )

    print(
        f"Done. total_atoms={total_atoms}, escalations={escalations}, "
        f"bridges_attempted={bridges_attempted}, bridges_used={bridges_used}, dropped_total={dropped_total}"
    )
    print(f"multi-target expansion: events={mt_events_total}, expanded_atoms={mt_expanded_total}")
    if src_counts:
        print("doc_id sources:", ", ".join(f"{k}={v}" for k, v in sorted(src_counts.items())))
    if not enable_bridging:
        print("Note: bridging was OFF (recommended for mixed/random chunks).")
    else:
        print("Note: bridging ON uses strict guard: same doc_id + adjacent chunk_index.")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
```

* * *

## Run (bridging still off)

```bat
conda activate pathai
cd "C:\Users\Prem Subramaniam\Documents\Pathway AI"
python make_atoms_docaware_v9.py
```

### What you should expect for your chunk 2 now

Because your supporting quotes include:

* “Targeting mTOR, RAPTOR, and RICTOR **all** …”

the script should expand so that **RICTOR is no longer missing**, and effects won’t be “stuck” mostly on RAPTOR.

If you paste the new `atoms.jsonl` line for **chunk_id 2**, I’ll sanity-check that:

* autophagy/apoptosis/etc appear for **mTOR + RAPTOR + RICTOR** (for siRNA and CRISPR),
* and we didn’t hit the `MAX_ATOMS_PER_CHUNK` truncation warning.

* * *

**You:**

{"doc_id": "PMID:39682777", "doc_id_source": "pmid", "pmid": "39682777", "pmcid": null, "chunk_index": null, "chunk_id": 2, "atoms": [{"intervention": {"category": "KNOCKDOWN_RNAI", "raw_text": "siRNA targeting mTOR, RAPTOR", "target": {"name": "mTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": "human", "cell_type": null, "cell_lines": [], "genotype_context": null, "disease_context": null}, "readout": {"name": "autophagy", "assay": null, "figure_refs": []}, "effect": {"direction": "increase", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all induced autophagy", "notes": null}, "confidence": 0.95}, {"intervention": {"category": "KNOCKDOWN_RNAI", "raw_text": "siRNA targeting mTOR, RAPTOR", "target": {"name": "RAPTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": "human", "cell_type": null, "cell_lines": [], "genotype_context": null, "disease_context": null}, "readout": {"name": "autophagy", "assay": null, "figure_refs": []}, "effect": {"direction": "increase", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all induced autophagy", "notes": null}, "confidence": 0.95}, {"intervention": {"category": "KNOCKDOWN_RNAI", "raw_text": "siRNA targeting mTOR, RAPTOR", "target": {"name": "RICTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": "human", "cell_type": null, "cell_lines": [], "genotype_context": null, "disease_context": null}, "readout": {"name": "autophagy", "assay": null, "figure_refs": []}, "effect": {"direction": "increase", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all induced autophagy", "notes": null}, "confidence": 0.95}, {"intervention": {"category": "CRISPR_KO", "raw_text": "CRISPR–Cas9 targeting mTOR, RAPTOR", "target": {"name": "mTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": "human", "cell_type": null, "cell_lines": [], "genotype_context": null, "disease_context": null}, "readout": {"name": "autophagy", "assay": null, "figure_refs": []}, "effect": {"direction": "increase", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all induced autophagy", "notes": null}, "confidence": 0.95}, {"intervention": {"category": "CRISPR_KO", "raw_text": "CRISPR–Cas9 targeting mTOR, RAPTOR", "target": {"name": "RAPTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": "human", "cell_type": null, "cell_lines": [], "genotype_context": null, "disease_context": null}, "readout": {"name": "autophagy", "assay": null, "figure_refs": []}, "effect": {"direction": "increase", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all induced autophagy", "notes": null}, "confidence": 0.95}, {"intervention": {"category": "CRISPR_KO", "raw_text": "CRISPR–Cas9 targeting mTOR, RAPTOR", "target": {"name": "RICTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": "human", "cell_type": null, "cell_lines": [], "genotype_context": null, "disease_context": null}, "readout": {"name": "autophagy", "assay": null, "figure_refs": []}, "effect": {"direction": "increase", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all induced autophagy", "notes": null}, "confidence": 0.95}, {"intervention": {"category": "KNOCKDOWN_RNAI", "raw_text": "siRNA targeting mTOR, RAPTOR", "target": {"name": "mTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": "human", "cell_type": null, "cell_lines": [], "genotype_context": null, "disease_context": null}, "readout": {"name": "apoptosis", "assay": null, "figure_refs": []}, "effect": {"direction": "decrease", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR...inhibited apoptosis", "notes": null}, "confidence": 0.95}, {"intervention": {"category": "KNOCKDOWN_RNAI", "raw_text": "siRNA targeting mTOR, RAPTOR", "target": {"name": "RAPTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": "human", "cell_type": null, "cell_lines": [], "genotype_context": null, "disease_context": null}, "readout": {"name": "apoptosis", "assay": null, "figure_refs": []}, "effect": {"direction": "decrease", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR...inhibited apoptosis", "notes": null}, "confidence": 0.95}, {"intervention": {"category": "KNOCKDOWN_RNAI", "raw_text": "siRNA targeting mTOR, RAPTOR", "target": {"name": "RICTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": "human", "cell_type": null, "cell_lines": [], "genotype_context": null, "disease_context": null}, "readout": {"name": "apoptosis", "assay": null, "figure_refs": []}, "effect": {"direction": "decrease", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR...inhibited apoptosis", "notes": null}, "confidence": 0.95}, {"intervention": {"category": "CRISPR_KO", "raw_text": "CRISPR–Cas9 targeting mTOR, RAPTOR", "target": {"name": "mTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": "human", "cell_type": null, "cell_lines": [], "genotype_context": null, "disease_context": null}, "readout": {"name": "apoptosis", "assay": null, "figure_refs": []}, "effect": {"direction": "decrease", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR...inhibited apoptosis", "notes": null}, "confidence": 0.95}, {"intervention": {"category": "CRISPR_KO", "raw_text": "CRISPR–Cas9 targeting mTOR, RAPTOR", "target": {"name": "RAPTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": "human", "cell_type": null, "cell_lines": [], "genotype_context": null, "disease_context": null}, "readout": {"name": "apoptosis", "assay": null, "figure_refs": []}, "effect": {"direction": "decrease", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR...inhibited apoptosis", "notes": null}, "confidence": 0.95}, {"intervention": {"category": "CRISPR_KO", "raw_text": "CRISPR–Cas9 targeting mTOR, RAPTOR", "target": {"name": "RICTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": "human", "cell_type": null, "cell_lines": [], "genotype_context": null, "disease_context": null}, "readout": {"name": "apoptosis", "assay": null, "figure_refs": []}, "effect": {"direction": "decrease", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR...inhibited apoptosis", "notes": null}, "confidence": 0.95}], "warnings": ["Text discusses targeting mTOR, RAPTOR, RICTOR with no explicit readout effect stated for siRNA or CRISPR on markers other than autophagy, apoptosis."], "bridge": {"enabled": false, "attempted": false, "used": false, "mode": null, "source_doc_ids": ["PMID:39682777"], "source_chunk_ids": [2], "skipped_reason": null}, "_routing": {"first_model": "gpt-4o-mini", "escalated": false, "final_model": "gpt-4o-mini", "reason": null}, "_post": {"dropped_atoms": 0, "multi_target": {"enabled": true, "candidate_targets": ["mTOR", "RAPTOR", "RICTOR"], "events": 6, "expanded_atoms": 18, "deduped_atoms": 12}}}

* * *

**ChatGPT:**

TAG: **PATHAI-0073**

You did it — the **multi-target safeguard is working** now.

### What your new chunk 2 line proves

* The sentence “mTOR, RAPTOR, and RICTOR **all** …” is now being represented as **parallel atoms**:
    * For **siRNA**: mTOR + RAPTOR + RICTOR each → autophagy ↑, apoptosis ↓
    * For **CRISPR**: mTOR + RAPTOR + RICTOR each → autophagy ↑, apoptosis ↓
* `_post.multi_target` confirms the expansion fired:
    * `candidate_targets = ["mTOR","RAPTOR","RICTOR"]`
    * `events = 6`, `expanded_atoms = 18`
    * `deduped_atoms = 12` (deduped = “duplicates removed after expansion”)

So the “don’t arbitrarily pick one target” requirement is satisfied.

* * *

## But there’s one real issue to fix before graphing

Your earlier extraction (v8) also captured **senescence, pyroptosis, matrix catabolism** as decreased. In this v9 output, those readouts are missing.

Why? Two reasons visible in your record:

1. Your supporting quotes include **ellipsis**:  
    `"Targeting mTOR, RAPTOR, and RICTOR...inhibited apoptosis"`  
    That often causes the model to give a **partial clause**, and then it simply never lists the full readout list (“apoptosis, senescence, pyroptosis, matrix catabolism”).
2. The multi-target code can only replicate what exists. It **multiplies targets**, but it doesn’t invent missing readouts.

So we should lock down one more rule:

> **Evidence quotes must be exact contiguous text from the chunk — no “…”**  
> This improves auditability and helps the model include the full readout list so we can split it.

Below is a v10 script that adds:

* **No-ellipsis quote enforcement** (forces escalation if any quote contains “…”)
* **Multi-readout splitting** (if the quote is “inhibited apoptosis, senescence, pyroptosis…” it emits one atom per readout)
* Then it applies your **multi-target expansion** (so you get mTOR/RAPTOR/RICTOR for each readout), with dedupe + truncation.

* * *

# Full script v10: `make_atoms_docaware_v10.py`

TAG: **PATHAI-0073**  
Save as **`make_atoms_docaware_v10.py`**

```Python
#!/usr/bin/env python3
import os
import json
import re
import argparse
import hashlib
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple
from copy import deepcopy
from openai import OpenAI

# ============================================================
# DEFAULTS
# ============================================================
MODEL_FAST = "gpt-4o-mini"
MODEL_STRONG = "gpt-4.1"

MAX_ATOMS_PER_CHUNK = 30

# ============================================================
# OPENAI CLIENT
# ============================================================
def _get_api_key() -> str:
    key = os.getenv("OPENAI_API_KEY")
    if not key:
        raise RuntimeError(
            "OPENAI_API_KEY is not set.\n"
            "Miniforge Prompt (temporary):  set OPENAI_API_KEY=YOUR_KEY\n"
            "Persistent (Windows):         setx OPENAI_API_KEY \"YOUR_KEY\"  (then reopen prompt)"
        )
    return key

client = OpenAI(api_key=_get_api_key())

# ============================================================
# STRICT JSON SCHEMA FOR ATOMS (model output)
# ============================================================
ATOM_SCHEMA_WRAPPER: Dict[str, Any] = {
    "name": "MechanisticAtoms",
    "schema": {
        "type": "object",
        "additionalProperties": False,
        "required": ["atoms", "warnings"],
        "properties": {
            "atoms": {
                "type": "array",
                "items": {
                    "type": "object",
                    "additionalProperties": False,
                    "required": [
                        "intervention",
                        "system",
                        "readout",
                        "effect",
                        "strength_cues",
                        "evidence",
                        "confidence",
                    ],
                    "properties": {
                        "intervention": {
                            "type": "object",
                            "additionalProperties": False,
                            "required": ["category", "raw_text", "target", "modality"],
                            "properties": {
                                "category": {
                                    "type": "string",
                                    "enum": [
                                        "GENETIC_KO",
                                        "CRISPR_KO",
                                        "CRISPRi",
                                        "CRISPRa",
                                        "KNOCKDOWN_RNAI",
                                        "SPLICING_MODULATION",
                                        "OVEREXPRESSION",
                                        "RESCUE_ADD_BACK",
                                        "DOMINANT_NEGATIVE",
                                        "MUTANT_VARIANT",
                                        "CHEMICAL_INHIBITOR",
                                        "CHEMICAL_ACTIVATOR",
                                        "CHEMICAL_DEGRADER",
                                        "STIMULUS_TREATMENT",
                                        "NEUTRALIZING_ANTIBODY",
                                        "UNKNOWN",
                                    ],
                                },
                                "raw_text": {"type": "string", "minLength": 1},
                                "target": {
                                    "anyOf": [
                                        {
                                            "type": "object",
                                            "additionalProperties": False,
                                            "required": ["name", "entity_type"],
                                            "properties": {
                                                "name": {"type": "string"},
                                                "entity_type": {
                                                    "type": "string",
                                                    "enum": [
                                                        "gene",
                                                        "protein",
                                                        "chemical",
                                                        "stimulus",
                                                        "antibody",
                                                        "unknown",
                                                    ],
                                                },
                                            },
                                        },
                                        {"type": "null"},
                                    ]
                                },
                                "modality": {
                                    "type": "string",
                                    "enum": [
                                        "LOF",
                                        "GOF",
                                        "INHIBITION",
                                        "ACTIVATION",
                                        "DEGRADATION",
                                        "RESCUE",
                                        "UNKNOWN",
                                    ],
                                },
                            },
                        },
                        "system": {
                            "type": "object",
                            "additionalProperties": False,
                            "required": [
                                "species",
                                "cell_type",
                                "cell_lines",
                                "genotype_context",
                                "disease_context",
                            ],
                            "properties": {
                                "species": {"type": ["string", "null"]},
                                "cell_type": {"type": ["string", "null"]},
                                "cell_lines": {"type": "array", "items": {"type": "string"}},
                                "genotype_context": {"type": ["string", "null"]},
                                "disease_context": {"type": ["string", "null"]},
                            },
                        },
                        "readout": {
                            "type": "object",
                            "additionalProperties": False,
                            "required": ["name", "assay", "figure_refs"],
                            "properties": {
                                "name": {"type": "string"},
                                "assay": {"type": ["string", "null"]},
                                "figure_refs": {"type": "array", "items": {"type": "string"}},
                            },
                        },
                        "effect": {
                            "type": "object",
                            "additionalProperties": False,
                            "required": ["direction", "timepoint", "magnitude", "comparison"],
                            "properties": {
                                "direction": {
                                    "type": "string",
                                    "enum": ["increase", "decrease", "no_change", "mixed", "unknown"],
                                },
                                "timepoint": {"type": ["string", "null"]},
                                "magnitude": {"type": ["string", "null"]},
                                "comparison": {"type": ["string", "null"]},
                            },
                        },
                        "strength_cues": {
                            "type": "object",
                            "additionalProperties": False,
                            "required": ["has_rescue", "has_control", "has_multiple_lines", "other"],
                            "properties": {
                                "has_rescue": {"type": "boolean"},
                                "has_control": {"type": "boolean"},
                                "has_multiple_lines": {"type": "boolean"},
                                "other": {"type": "array", "items": {"type": "string"}},
                            },
                        },
                        "evidence": {
                            "type": "object",
                            "additionalProperties": False,
                            "required": ["supporting_quote", "notes"],
                            "properties": {
                                "supporting_quote": {"type": "string"},
                                "notes": {"type": ["string", "null"]},
                            },
                        },
                        "confidence": {"type": "number", "minimum": 0, "maximum": 1},
                    },
                },
            },
            "warnings": {"type": "array", "items": {"type": "string"}},
        },
    },
}

# ============================================================
# HINTS
# ============================================================
FIGREF_REGEX = re.compile(r"\b(Fig\.?\s*\d+[A-Za-z]?)\b", re.IGNORECASE)
SPECIES_REGEX = re.compile(r"\b(human|mouse|murine|rat)\b", re.IGNORECASE)

def _uniq_preserve(seq: List[str]) -> List[str]:
    seen = set()
    out = []
    for x in seq:
        k = x.lower()
        if k not in seen:
            seen.add(k)
            out.append(x)
    return out

def hint_figrefs(text: str) -> List[str]:
    return _uniq_preserve([m.group(1) for m in FIGREF_REGEX.finditer(text or "")])

def hint_species(text: str) -> Optional[str]:
    m = SPECIES_REGEX.search(text or "")
    if not m:
        return None
    s = m.group(1).lower()
    return "mouse" if s == "murine" else s

def compact_mentions(mentions: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    out = []
    for i, m in enumerate(mentions or [], start=1):
        out.append({
            "i": i,
            "category": m.get("category"),
            "raw_text": m.get("raw_text"),
            "target_guess": m.get("target_guess"),
            "method_cues": m.get("method_cues", []),
        })
    return out

# ============================================================
# DOC_ID DERIVATION (PMID(+PMCID) → PMCID → DOI → JVP → FILE → TITLEHASH → CHUNK)
# ============================================================
_DOI_PREFIX_RE = re.compile(r"^(https?://(dx\.)?doi\.org/|doi:\s*)", re.IGNORECASE)
_YEAR_RE = re.compile(r"\b(19\d{2}|20\d{2})\b")
_PAGES_RE = re.compile(r"^\s*(\d+)\s*[-–—]\s*(\d+)\s*$")

def _stable_hash(text: str, n: int = 12) -> str:
    return hashlib.sha1(text.encode("utf-8")).hexdigest()[:n]

def _get_nested(rec: Dict[str, Any], path: List[str]) -> Optional[Any]:
    cur: Any = rec
    for k in path:
        if not isinstance(cur, dict) or k not in cur:
            return None
        cur = cur[k]
    return cur

def _first_str_value(rec: Dict[str, Any], key_paths: List[List[str]]) -> Optional[str]:
    for path in key_paths:
        v = _get_nested(rec, path)
        if isinstance(v, str) and v.strip():
            return v.strip()
    return None

def _first_intish_value(rec: Dict[str, Any], key_paths: List[List[str]]) -> Optional[str]:
    for path in key_paths:
        v = _get_nested(rec, path)
        if v is None:
            continue
        if isinstance(v, int):
            return str(v)
        if isinstance(v, str):
            s = v.strip()
            m = re.search(r"\d+", s)
            if m:
                return m.group(0)
    return None

def _normalize_pmcid(x: str) -> Optional[str]:
    if not x:
        return None
    s = x.strip()
    if s.lower().startswith("pmc"):
        digits = re.sub(r"\D+", "", s)
        return f"PMC{digits}" if digits else None
    digits = re.sub(r"\D+", "", s)
    return f"PMC{digits}" if digits else None

def _normalize_journal(j: str) -> str:
    s = re.sub(r"[^A-Za-z0-9]+", "", (j or "").lower())
    return s[:32] if s else ""

def _extract_year(rec: Dict[str, Any]) -> Optional[str]:
    year = _first_intish_value(rec, [
        ["year"], ["pub_year"], ["publication_year"],
        ["metadata", "year"], ["metadata", "pub_year"], ["paper", "year"],
    ])
    if year and len(year) == 4:
        return year

    date_str = _first_str_value(rec, [
        ["date"], ["publication_date"], ["pub_date"],
        ["metadata", "date"], ["metadata", "publication_date"], ["paper", "date"],
    ])
    if date_str:
        m = _YEAR_RE.search(date_str)
        if m:
            return m.group(1)
    return None

def _extract_volume(rec: Dict[str, Any]) -> Optional[str]:
    vol = _first_str_value(rec, [
        ["volume"], ["vol"], ["metadata", "volume"], ["paper", "volume"],
    ])
    if not vol:
        return None
    vol2 = re.sub(r"[^0-9A-Za-z]+", "", vol)
    return vol2 or None

def _extract_pages(rec: Dict[str, Any]) -> Optional[str]:
    pages = _first_str_value(rec, [
        ["pages"], ["page_range"], ["pagination"], ["pageNumbers"],
        ["metadata", "pages"], ["metadata", "page_range"], ["paper", "pages"],
    ])
    if pages:
        s = pages.strip().replace("–", "-").replace("—", "-")
        m = _PAGES_RE.match(s)
        if m:
            return f"{m.group(1)}-{m.group(2)}"
        s2 = re.sub(r"\s+", "", s)
        s2 = re.sub(r"[^0-9A-Za-z\-]+", "", s2)
        return s2 or None

    p1 = _first_intish_value(rec, [
        ["page_start"], ["first_page"], ["start_page"],
        ["metadata", "page_start"], ["paper", "page_start"],
    ])
    p2 = _first_intish_value(rec, [
        ["page_end"], ["last_page"], ["end_page"],
        ["metadata", "page_end"], ["paper", "page_end"],
    ])
    if p1 and p2:
        return f"{p1}-{p2}"
    if p1:
        return p1
    return None

def _extract_journal(rec: Dict[str, Any]) -> Optional[str]:
    return _first_str_value(rec, [
        ["journal"], ["journal_name"], ["journalTitle"],
        ["metadata", "journal"], ["metadata", "journal_name"], ["paper", "journal"],
    ])

def derive_doc_id_with_source(rec: Dict[str, Any]) -> Tuple[Optional[str], str]:
    pmid = _first_intish_value(rec, [
        ["pmid"], ["PMID"], ["pubmed_id"], ["pubmedId"], ["PubMedID"],
        ["metadata", "pmid"], ["metadata", "PMID"], ["paper", "pmid"], ["paper", "PMID"],
    ])
    pmcid_raw = _first_str_value(rec, [
        ["pmcid"], ["PMCID"], ["pubmed_central_id"], ["pmc_id"], ["pmcId"],
        ["metadata", "pmcid"], ["metadata", "PMCID"], ["paper", "pmcid"], ["paper", "PMCID"],
    ])
    pmcid = _normalize_pmcid(pmcid_raw or "")

    if pmid and pmcid:
        return f"PMID:{pmid}|PMCID:{pmcid}", "pmid_pmcid"
    if pmid:
        return f"PMID:{pmid}", "pmid"
    if pmcid:
        return f"PMCID:{pmcid}", "pmcid"

    doi = _first_str_value(rec, [
        ["doi"], ["DOI"], ["metadata", "doi"], ["metadata", "DOI"], ["paper", "doi"], ["paper", "DOI"],
    ])
    if doi:
        doi2 = _DOI_PREFIX_RE.sub("", doi).strip()
        return f"DOI:{doi2}", "doi"

    journal = _extract_journal(rec)
    year = _extract_year(rec)
    volume = _extract_volume(rec)
    pages = _extract_pages(rec)
    jnorm = _normalize_journal(journal or "")
    if jnorm and year and volume and pages:
        return f"JVP:{jnorm}:{year}:{volume}:{pages}", "jvp"

    file_path = _first_str_value(rec, [
        ["source_file"], ["file"], ["filename"], ["pdf_file"],
        ["source", "file"], ["_source", "file"], ["metadata", "file"], ["metadata", "filename"],
    ])
    if file_path:
        name = Path(file_path).name.strip()
        if name:
            return f"FILE:{name}", "file"
        return f"FILEHASH:{_stable_hash(file_path)}", "file"

    title = _first_str_value(rec, [
        ["title"], ["paper_title"], ["metadata", "title"], ["paper", "title"],
    ])
    if title:
        return f"TITLEHASH:{_stable_hash(title.lower().strip())}", "titlehash"

    return None, "none"

# ============================================================
# PROMPT (tightened: no ellipses in quotes + parallel atoms)
# ============================================================
SYSTEM_INSTRUCTIONS = (
    "Extract 'mechanistic atoms' from biomedical text.\n\n"
    "Definition: an atom MUST include an explicit effect on a readout.\n"
    "Format: [INTERVENTION] causes [EFFECT] in [READOUT] in a [SYSTEM].\n\n"
    "Hard rules:\n"
    "1) Do NOT invent facts.\n"
    "2) Do NOT assume knockdown succeeded unless the text explicitly says reduction/knockdown/confirmed.\n"
    "3) If the text only describes delivering siRNA/plasmid/drug but gives no stated change in any readout, output no atoms and add a warning.\n"
    "4) If a sentence says targeting A, B, and C 'all' (or 'each') causes an effect, emit parallel atoms for each target (A and B and C) rather than picking one.\n"
    "5) IMPORTANT: evidence.supporting_quote MUST be an exact contiguous substring from the chunk_text. Do NOT use ellipses (...).\n"
    "6) If a sentence lists multiple readouts (e.g., 'inhibited apoptosis, senescence, pyroptosis...'), extract one atom per readout.\n"
    f"7) Keep at most {MAX_ATOMS_PER_CHUNK} atoms.\n"
)

# ============================================================
# MODEL CALLS + ROUTING
# ============================================================
def call_model(model: str, chunk_text: str, mentions: List[Dict[str, Any]]) -> Dict[str, Any]:
    payload = {
        "chunk_text": chunk_text,
        "mentions": compact_mentions(mentions),
        "hints": {"fig_refs": hint_figrefs(chunk_text), "species": hint_species(chunk_text)},
    }
    resp = client.responses.create(
        model=model,
        input=[
            {"role": "system", "content": SYSTEM_INSTRUCTIONS},
            {"role": "user", "content": json.dumps(payload, ensure_ascii=False)},
        ],
        text={
            "format": {
                "type": "json_schema",
                "name": ATOM_SCHEMA_WRAPPER["name"],
                "strict": True,
                "schema": ATOM_SCHEMA_WRAPPER["schema"],
            }
        },
    )
    return json.loads(resp.output_text)

def _has_ellipsis_quotes(atoms: List[Dict[str, Any]]) -> bool:
    for a in atoms or []:
        sq = ((a.get("evidence") or {}).get("supporting_quote") or "")
        if "..." in sq or "…" in sq:
            return True
    return False

def should_escalate(mentions: List[Dict[str, Any]], atoms: List[Dict[str, Any]]) -> bool:
    if len(mentions) > 0 and len(atoms) == 0:
        return True
    if _has_ellipsis_quotes(atoms):
        return True
    if len(atoms) > 0:
        avg_conf = sum(float(a.get("confidence", 0.0)) for a in atoms) / len(atoms)
        if avg_conf < 0.55:
            return True
    return False

def extract_atoms_with_routing(chunk_text: str, mentions: List[Dict[str, Any]]) -> Dict[str, Any]:
    routing = {"first_model": MODEL_FAST, "escalated": False, "final_model": MODEL_FAST, "reason": None}
    out_fast = call_model(MODEL_FAST, chunk_text, mentions)
    atoms_fast = out_fast.get("atoms", []) or []

    if should_escalate(mentions, atoms_fast):
        routing["escalated"] = True
        routing["final_model"] = MODEL_STRONG
        routing["reason"] = {"type": "low_confidence_or_empty_or_bad_quotes", "details": "heuristics triggered"}
        out_strong = call_model(MODEL_STRONG, chunk_text, mentions)
        out_strong["_routing"] = routing
        return out_strong

    out_fast["_routing"] = routing
    return out_fast

# ============================================================
# POST-FILTER (expanded effect cues)
# ============================================================
EFFECT_CUE = re.compile(
    r"\b("
    r"inhibit|inhibited|inhibition|"
    r"suppress|suppressed|suppressing|suppression|"
    r"reduce|reduced|reduces|reduction|"
    r"decrease|decreased|decreases|"
    r"increase|increased|increases|"
    r"elevate|elevated|"
    r"no effect|did not affect|had no effect|no significant|unchanged|"
    r"induce|induced|induction|"
    r"promote|promoted|promotion|"
    r"attenuate|attenuated|attenuation|"
    r"block|blocked|blocking|"
    r"activate|activated|activation|"
    r"inactivate|inactivated|inactivation|"
    r"enhance|enhanced|enhancement|"
    r"impair|impaired|impairment|"
    r"abrogate|abrogated|abrogation|"
    r"abolish|abolished|abolition|"
    r"antiproliferative|anti-proliferative|"
    r"cytotoxic|cytotoxicity|"
    r"tumor growth suppression|growth suppression|"
    r"degradation|degraded|degrade|"
    r"depletion|deplete|depleted|"
    r"knockdown|knocked down|silencing|silenced"
    r")\b",
    re.IGNORECASE,
)

SETUP_ONLY_READOUT = re.compile(r"\b(expression|function|knockdown|silencing)\b", re.IGNORECASE)

def looks_like_setup_only(atoms: List[Dict[str, Any]], warnings: List[str]) -> bool:
    if not atoms:
        return True
    wtxt = " ".join(warnings or []).lower()
    if "no explicit functional readouts" in wtxt or "only describes" in wtxt:
        return True
    for a in atoms:
        ro = (a.get("readout", {}) or {}).get("name", "")
        sq = (a.get("evidence", {}) or {}).get("supporting_quote", "")
        if (not SETUP_ONLY_READOUT.search(ro or "")) and EFFECT_CUE.search(sq or ""):
            return False
    return True

def post_filter_atoms(atoms: List[Dict[str, Any]]) -> Tuple[List[Dict[str, Any]], int]:
    kept: List[Dict[str, Any]] = []
    dropped = 0
    for a in atoms or []:
        sq = (a.get("evidence", {}) or {}).get("supporting_quote", "")
        if EFFECT_CUE.search(sq or ""):
            kept.append(a)
        else:
            dropped += 1
    return kept, dropped

# ============================================================
# MULTI-READOUT SPLITTING
# ============================================================
_VERB_SPLIT = re.compile(
    r"\b(inhibited|inhibit|induced|induce|promoted|promote|suppressed|suppress|reduced|reduce|decreased|decrease|increased|increase|attenuated|attenuate|blocked|block)\b",
    re.IGNORECASE,
)

def _norm_space(s: str) -> str:
    return re.sub(r"\s+", " ", (s or "")).strip()

def _extract_readout_list_from_quote(quote: str) -> List[str]:
    """
    Conservative extractor: looks for patterns like:
      "inhibited apoptosis, senescence, pyroptosis, and matrix catabolism"
    Returns list of readout strings (>=2) or [].
    """
    q = _norm_space(quote)
    m = _VERB_SPLIT.search(q)
    if not m:
        return []
    verb_end = m.end()
    tail = q[verb_end:].strip(" :;-")
    if not tail:
        return []
    # stop at sentence end-ish
    tail = re.split(r"[.;]", tail, maxsplit=1)[0]
    # remove leading "the" etc
    tail = re.sub(r"^\s*(the|a|an)\s+", "", tail, flags=re.IGNORECASE)

    # split by commas / and / or
    tmp = re.sub(r"\band\b", ",", tail, flags=re.IGNORECASE)
    tmp = re.sub(r"\bor\b", ",", tmp, flags=re.IGNORECASE)
    parts = [p.strip(" ,.;:()[]{}<>\"'") for p in tmp.split(",")]
    parts = [p for p in parts if p]
    # require >=2 to qualify as a list
    if len(parts) >= 2:
        return parts
    return []

def split_multi_readout_atoms(atoms: List[Dict[str, Any]], max_atoms: int) -> Tuple[List[Dict[str, Any]], Dict[str, Any], List[str]]:
    new_atoms: List[Dict[str, Any]] = []
    events = 0
    expanded = 0
    warnings: List[str] = []

    for a in atoms or []:
        sq = _norm_space(((a.get("evidence") or {}).get("supporting_quote") or ""))
        ro0 = _norm_space(((a.get("readout") or {}).get("name") or ""))
        ro_list = _extract_readout_list_from_quote(sq)

        if ro_list and ro0:
            # only split if the current readout appears in the list (prevents wild splits)
            if any(ro0.lower() == r.lower() for r in ro_list):
                events += 1
                for rname in ro_list:
                    aa = deepcopy(a)
                    aa["readout"]["name"] = rname
                    # annotate
                    notes = (aa.get("evidence", {}) or {}).get("notes")
                    add = "Split multi-readout list from quote."
                    aa["evidence"]["notes"] = (notes + " " + add).strip() if notes else add
                    new_atoms.append(aa)
                    expanded += 1
                continue

        new_atoms.append(a)

    # enforce max
    if len(new_atoms) > max_atoms:
        warnings.append(f"Truncated atoms after multi-readout splitting: {len(new_atoms)} -> {max_atoms}.")
        new_atoms = new_atoms[:max_atoms]

    meta = {"enabled": True, "events": events, "expanded_atoms": expanded, "atoms_after": len(new_atoms)}
    return new_atoms, meta, warnings

# ============================================================
# MULTI-TARGET EXPANSION (your safeguard)
# ============================================================
MULTI_TARGET_CUE = re.compile(r"\b(all|each)\b", re.IGNORECASE)

def _split_target_list(s: str) -> List[str]:
    if not s:
        return []
    x = _norm_space(s)
    x = x.replace("/", " / ")
    x = re.sub(r"\band\b", ",", x, flags=re.IGNORECASE)
    x = re.sub(r"\bor\b", ",", x, flags=re.IGNORECASE)
    x = x.replace(";", ",").replace("/", ",")
    parts = [p.strip(" ,.;:()[]{}<>\"'") for p in x.split(",")]
    out = []
    for p in parts:
        if not p:
            continue
        if p.lower() in {"and", "or", "the", "a", "an"}:
            continue
        out.append(p)
    return out

def _targets_from_mentions(mentions: List[Dict[str, Any]]) -> Tuple[List[str], Dict[str, str]]:
    cand: List[str] = []
    type_map: Dict[str, str] = {}
    for m in mentions or []:
        tg = m.get("target_guess") or {}
        name = tg.get("name")
        et = tg.get("entity_type") or "protein"
        for t in _split_target_list(str(name) if name else ""):
            key = t.lower()
            if key not in type_map:
                type_map[key] = et
            if t not in cand:
                cand.append(t)
    return cand, type_map

def _find_targets_in_text(candidate_targets: List[str], text: str) -> List[str]:
    found: List[str] = []
    hay = text or ""
    for t in candidate_targets:
        pat = r"\b" + re.escape(t) + r"\b"
        if re.search(pat, hay, flags=re.IGNORECASE):
            found.append(t)
    return found

def _atom_key(a: Dict[str, Any]) -> Tuple:
    iv = a.get("intervention", {}) or {}
    tg = iv.get("target") or {}
    rd = a.get("readout", {}) or {}
    ef = a.get("effect", {}) or {}
    ev = a.get("evidence", {}) or {}
    return (
        str(iv.get("category") or "").lower(),
        str(iv.get("modality") or "").lower(),
        str((tg.get("name") if isinstance(tg, dict) else "") or "").lower(),
        str(rd.get("name") or "").lower(),
        str(ef.get("direction") or "").lower(),
        _norm_space(str(ev.get("supporting_quote") or "")).lower(),
    )

def expand_multi_target_atoms(
    atoms: List[Dict[str, Any]],
    mentions: List[Dict[str, Any]],
    max_atoms: int,
) -> Tuple[List[Dict[str, Any]], Dict[str, Any], List[str]]:
    candidate_targets, type_map = _targets_from_mentions(mentions)
    if not candidate_targets:
        return atoms, {"enabled": True, "events": 0, "expanded_atoms": 0, "deduped_atoms": len(atoms or [])}, []

    new_atoms: List[Dict[str, Any]] = []
    events = 0
    expanded_atoms = 0
    extra_warnings: List[str] = []

    for a in atoms or []:
        ev = a.get("evidence", {}) or {}
        sq = _norm_space(ev.get("supporting_quote") or "")
        iv = a.get("intervention", {}) or {}
        raw = _norm_space(iv.get("raw_text") or "")
        combined = (sq + " " + raw).strip()

        found = _find_targets_in_text(candidate_targets, combined)
        if MULTI_TARGET_CUE.search(combined) and len(found) >= 2:
            events += 1
            for t in found:
                aa = deepcopy(a)
                et = type_map.get(t.lower(), None)

                if not aa.get("intervention"):
                    aa["intervention"] = {}
                if aa["intervention"].get("target") is None or not isinstance(aa["intervention"].get("target"), dict):
                    aa["intervention"]["target"] = {"name": t, "entity_type": et or "protein"}
                else:
                    aa["intervention"]["target"]["name"] = t
                    if not aa["intervention"]["target"].get("entity_type"):
                        aa["intervention"]["target"]["entity_type"] = et or "protein"

                # annotate
                notes = (aa.get("evidence", {}) or {}).get("notes")
                add = "Expanded per multi-target 'all/each' statement."
                aa["evidence"]["notes"] = (notes + " " + add).strip() if notes else add

                new_atoms.append(aa)
                expanded_atoms += 1
        else:
            new_atoms.append(a)

    deduped: List[Dict[str, Any]] = []
    seen = set()
    for a in new_atoms:
        k = _atom_key(a)
        if k in seen:
            continue
        seen.add(k)
        deduped.append(a)

    if len(deduped) > max_atoms:
        extra_warnings.append(
            f"Truncated atoms after multi-target expansion: {len(deduped)} -> {max_atoms} due to MAX_ATOMS_PER_CHUNK."
        )
        deduped = deduped[:max_atoms]

    meta = {
        "enabled": True,
        "candidate_targets": candidate_targets[:50],
        "events": events,
        "expanded_atoms": expanded_atoms,
        "deduped_atoms": len(deduped),
    }
    return deduped, meta, extra_warnings

# ============================================================
# MAIN (bridging intentionally omitted here; keep it off in your runs)
# ============================================================
def main() -> int:
    ap = argparse.ArgumentParser(description="PATHAI atoms extraction: doc_id + no-ellipsis quotes + multi-readout + multi-target expansion")
    ap.add_argument("--infile", default="mentions.jsonl", help="Input mentions.jsonl")
    ap.add_argument("--outfile", default="atoms.jsonl", help="Output atoms.jsonl")
    ap.add_argument("--default_doc_id", default=None, help="If cannot derive doc_id, use this (otherwise falls back to CHUNK:<chunk_id>).")
    ap.add_argument("--assign_chunk_index", action="store_true", help="Assign chunk_index per doc_id if missing (sequential in file order).")
    args = ap.parse_args()

    infile = Path(args.infile)
    outfile = Path(args.outfile)

    if not infile.exists():
        raise FileNotFoundError(f"Cannot find {infile.resolve()}")

    records: List[Dict[str, Any]] = []
    for ln in infile.read_text(encoding="utf-8", errors="ignore").splitlines():
        ln = ln.strip()
        if ln:
            records.append(json.loads(ln))

    src_counts: Dict[str, int] = {}
    for r in records:
        if not r.get("doc_id"):
            doc_id, src = derive_doc_id_with_source(r)
            if doc_id:
                r["doc_id"] = doc_id
                r["doc_id_source"] = src
                src_counts[src] = src_counts.get(src, 0) + 1
            else:
                if args.default_doc_id:
                    r["doc_id"] = args.default_doc_id
                    r["doc_id_source"] = "default"
                    src_counts["default"] = src_counts.get("default", 0) + 1
                else:
                    cid = r.get("chunk_id")
                    r["doc_id"] = f"CHUNK:{cid}"
                    r["doc_id_source"] = "chunk_fallback"
                    src_counts["chunk_fallback"] = src_counts.get("chunk_fallback", 0) + 1

    if args.assign_chunk_index:
        counters: Dict[str, int] = {}
        for r in records:
            doc = r.get("doc_id")
            if not doc:
                continue
            if r.get("chunk_index") is None:
                counters.setdefault(doc, 0)
                r["chunk_index"] = counters[doc]
                counters[doc] += 1

    total_atoms = 0
    escalations = 0
    dropped_total = 0
    mr_events_total = 0
    mr_expanded_total = 0
    mt_events_total = 0
    mt_expanded_total = 0

    with outfile.open("w", encoding="utf-8", newline="\n") as fout:
        for rec in records:
            chunk_id = rec.get("chunk_id")
            doc_id = rec.get("doc_id")
            doc_id_source = rec.get("doc_id_source")
            chunk_index = rec.get("chunk_index")

            if "error" in rec:
                out_rec = {
                    "doc_id": doc_id,
                    "doc_id_source": doc_id_source,
                    "chunk_index": chunk_index,
                    "chunk_id": chunk_id,
                    "atoms": [],
                    "warnings": ["Skipped due to upstream error."],
                    "_routing": {"skipped": True},
                    "_post": {"dropped_atoms": 0, "multi_readout": {"enabled": True, "events": 0, "expanded_atoms": 0},
                              "multi_target": {"enabled": True, "events": 0, "expanded_atoms": 0}},
                }
                fout.write(json.dumps(out_rec, ensure_ascii=False) + "\n")
                continue

            chunk_text = rec.get("chunk_text", "")
            mentions = rec.get("mentions", [])

            out = extract_atoms_with_routing(chunk_text, mentions)
            atoms = out.get("atoms", []) or []
            warnings = out.get("warnings", []) or []
            routing = out.get("_routing", {}) or {}

            if routing.get("escalated"):
                escalations += 1

            atoms, dropped = post_filter_atoms(atoms)
            dropped_total += dropped

            # split multi-readout lists
            atoms, mr_meta, mr_warn = split_multi_readout_atoms(atoms, MAX_ATOMS_PER_CHUNK)
            if mr_warn:
                warnings.extend(mr_warn)
            mr_events_total += int(mr_meta.get("events", 0))
            mr_expanded_total += int(mr_meta.get("expanded_atoms", 0))

            # expand multi-target
            atoms, mt_meta, mt_warn = expand_multi_target_atoms(atoms, mentions, MAX_ATOMS_PER_CHUNK)
            if mt_warn:
                warnings.extend(mt_warn)
            mt_events_total += int(mt_meta.get("events", 0))
            mt_expanded_total += int(mt_meta.get("expanded_atoms", 0))

            total_atoms += len(atoms)

            pmid_pt = rec.get("pmid") or rec.get("PMID") or rec.get("pubmed_id") or rec.get("pubmedId")
            pmcid_pt = rec.get("pmcid") or rec.get("PMCID") or rec.get("pubmed_central_id") or rec.get("pmcId") or rec.get("pmc_id")

            out_rec = {
                "doc_id": doc_id,
                "doc_id_source": doc_id_source,
                "pmid": pmid_pt,
                "pmcid": pmcid_pt,
                "chunk_index": chunk_index,
                "chunk_id": chunk_id,
                "atoms": atoms,
                "warnings": warnings,
                "_routing": routing,
                "_post": {"dropped_atoms": dropped, "multi_readout": mr_meta, "multi_target": mt_meta},
            }
            fout.write(json.dumps(out_rec, ensure_ascii=False) + "\n")

            print(
                f"chunk {chunk_id} doc_id={doc_id}({doc_id_source}) idx={chunk_index} "
                f"atoms={len(atoms)} escalated={routing.get('escalated', False)} dropped={dropped} "
                f"mr_events={mr_meta.get('events',0)} mt_events={mt_meta.get('events',0)}"
            )

    print(
        f"Done. total_atoms={total_atoms}, escalations={escalations}, dropped_total={dropped_total}"
    )
    print(f"multi-readout: events={mr_events_total}, expanded_atoms={mr_expanded_total}")
    print(f"multi-target:  events={mt_events_total}, expanded_atoms={mt_expanded_total}")
    if src_counts:
        print("doc_id sources:", ", ".join(f"{k}={v}" for k, v in sorted(src_counts.items())))
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
```

### Run it

```bat
conda activate pathai
cd "C:\Users\Prem Subramaniam\Documents\Pathway AI"
python make_atoms_docaware_v10.py
```

### What you should see for chunk 2 after v10

* The supporting quote should **not** contain `...`
* You should recover the full list so you end up with:
    * autophagy ↑
    * apoptosis ↓
    * senescence ↓
    * pyroptosis ↓
    * matrix catabolism ↓  
        …and then those will be expanded across **mTOR/RAPTOR/RICTOR** (and across siRNA/CRISPR where stated), potentially approaching your `MAX_ATOMS_PER_CHUNK`.

If it hits the 30 cap, you’ll get a clean warning telling you it truncated — that’s okay, and we can decide whether to raise the cap later.

If you paste the new `atoms.jsonl` line for **chunk_id 2** after v10, I’ll check that (1) ellipses are gone and (2) the missing readouts are back.

* * *

**You:**

{"doc_id": "PMID:39682777", "doc_id_source": "pmid", "pmid": "39682777", "pmcid": null, "chunk_index": null, "chunk_id": 2, "atoms": [{"intervention": {"category": "KNOCKDOWN_RNAI", "raw_text": "siRNA or CRISPR–Cas9 plasmid targeting mTOR, RAPTOR, or RICTOR", "target": {"name": "mTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": "human", "cell_type": "disk nucleus pulposus cells", "cell_lines": [], "genotype_context": null, "disease_context": "degenerative disk"}, "readout": {"name": "autophagy", "assay": null, "figure_refs": []}, "effect": {"direction": "increase", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": true, "has_multiple_lines": true, "other": ["in vitro comparative study", "specified transfection efficiency"]}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all induced autophagy and inhibited apoptosis, senescence, pyroptosis, and matrix catabolism", "notes": "Split multi-readout list from quote. Expanded per multi-target 'all/each' statement."}, "confidence": 0.95}, {"intervention": {"category": "KNOCKDOWN_RNAI", "raw_text": "siRNA or CRISPR–Cas9 plasmid targeting mTOR, RAPTOR, or RICTOR", "target": {"name": "RAPTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": "human", "cell_type": "disk nucleus pulposus cells", "cell_lines": [], "genotype_context": null, "disease_context": "degenerative disk"}, "readout": {"name": "autophagy", "assay": null, "figure_refs": []}, "effect": {"direction": "increase", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": true, "has_multiple_lines": true, "other": ["in vitro comparative study", "specified transfection efficiency"]}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all induced autophagy and inhibited apoptosis, senescence, pyroptosis, and matrix catabolism", "notes": "Split multi-readout list from quote. Expanded per multi-target 'all/each' statement."}, "confidence": 0.95}, {"intervention": {"category": "KNOCKDOWN_RNAI", "raw_text": "siRNA or CRISPR–Cas9 plasmid targeting mTOR, RAPTOR, or RICTOR", "target": {"name": "RICTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": "human", "cell_type": "disk nucleus pulposus cells", "cell_lines": [], "genotype_context": null, "disease_context": "degenerative disk"}, "readout": {"name": "autophagy", "assay": null, "figure_refs": []}, "effect": {"direction": "increase", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": true, "has_multiple_lines": true, "other": ["in vitro comparative study", "specified transfection efficiency"]}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all induced autophagy and inhibited apoptosis, senescence, pyroptosis, and matrix catabolism", "notes": "Split multi-readout list from quote. Expanded per multi-target 'all/each' statement."}, "confidence": 0.95}, {"intervention": {"category": "KNOCKDOWN_RNAI", "raw_text": "siRNA or CRISPR–Cas9 plasmid targeting mTOR, RAPTOR, or RICTOR", "target": {"name": "mTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": "human", "cell_type": "disk nucleus pulposus cells", "cell_lines": [], "genotype_context": null, "disease_context": "degenerative disk"}, "readout": {"name": "inhibited apoptosis", "assay": null, "figure_refs": []}, "effect": {"direction": "increase", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": true, "has_multiple_lines": true, "other": ["in vitro comparative study", "specified transfection efficiency"]}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all induced autophagy and inhibited apoptosis, senescence, pyroptosis, and matrix catabolism", "notes": "Split multi-readout list from quote. Expanded per multi-target 'all/each' statement."}, "confidence": 0.95}, {"intervention": {"category": "KNOCKDOWN_RNAI", "raw_text": "siRNA or CRISPR–Cas9 plasmid targeting mTOR, RAPTOR, or RICTOR", "target": {"name": "RAPTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": "human", "cell_type": "disk nucleus pulposus cells", "cell_lines": [], "genotype_context": null, "disease_context": "degenerative disk"}, "readout": {"name": "inhibited apoptosis", "assay": null, "figure_refs": []}, "effect": {"direction": "increase", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": true, "has_multiple_lines": true, "other": ["in vitro comparative study", "specified transfection efficiency"]}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all induced autophagy and inhibited apoptosis, senescence, pyroptosis, and matrix catabolism", "notes": "Split multi-readout list from quote. Expanded per multi-target 'all/each' statement."}, "confidence": 0.95}, {"intervention": {"category": "KNOCKDOWN_RNAI", "raw_text": "siRNA or CRISPR–Cas9 plasmid targeting mTOR, RAPTOR, or RICTOR", "target": {"name": "RICTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": "human", "cell_type": "disk nucleus pulposus cells", "cell_lines": [], "genotype_context": null, "disease_context": "degenerative disk"}, "readout": {"name": "inhibited apoptosis", "assay": null, "figure_refs": []}, "effect": {"direction": "increase", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": true, "has_multiple_lines": true, "other": ["in vitro comparative study", "specified transfection efficiency"]}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all induced autophagy and inhibited apoptosis, senescence, pyroptosis, and matrix catabolism", "notes": "Split multi-readout list from quote. Expanded per multi-target 'all/each' statement."}, "confidence": 0.95}, {"intervention": {"category": "KNOCKDOWN_RNAI", "raw_text": "siRNA or CRISPR–Cas9 plasmid targeting mTOR, RAPTOR, or RICTOR", "target": {"name": "mTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": "human", "cell_type": "disk nucleus pulposus cells", "cell_lines": [], "genotype_context": null, "disease_context": "degenerative disk"}, "readout": {"name": "senescence", "assay": null, "figure_refs": []}, "effect": {"direction": "increase", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": true, "has_multiple_lines": true, "other": ["in vitro comparative study", "specified transfection efficiency"]}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all induced autophagy and inhibited apoptosis, senescence, pyroptosis, and matrix catabolism", "notes": "Split multi-readout list from quote. Expanded per multi-target 'all/each' statement."}, "confidence": 0.95}, {"intervention": {"category": "KNOCKDOWN_RNAI", "raw_text": "siRNA or CRISPR–Cas9 plasmid targeting mTOR, RAPTOR, or RICTOR", "target": {"name": "RAPTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": "human", "cell_type": "disk nucleus pulposus cells", "cell_lines": [], "genotype_context": null, "disease_context": "degenerative disk"}, "readout": {"name": "senescence", "assay": null, "figure_refs": []}, "effect": {"direction": "increase", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": true, "has_multiple_lines": true, "other": ["in vitro comparative study", "specified transfection efficiency"]}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all induced autophagy and inhibited apoptosis, senescence, pyroptosis, and matrix catabolism", "notes": "Split multi-readout list from quote. Expanded per multi-target 'all/each' statement."}, "confidence": 0.95}, {"intervention": {"category": "KNOCKDOWN_RNAI", "raw_text": "siRNA or CRISPR–Cas9 plasmid targeting mTOR, RAPTOR, or RICTOR", "target": {"name": "RICTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": "human", "cell_type": "disk nucleus pulposus cells", "cell_lines": [], "genotype_context": null, "disease_context": "degenerative disk"}, "readout": {"name": "senescence", "assay": null, "figure_refs": []}, "effect": {"direction": "increase", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": true, "has_multiple_lines": true, "other": ["in vitro comparative study", "specified transfection efficiency"]}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all induced autophagy and inhibited apoptosis, senescence, pyroptosis, and matrix catabolism", "notes": "Split multi-readout list from quote. Expanded per multi-target 'all/each' statement."}, "confidence": 0.95}, {"intervention": {"category": "KNOCKDOWN_RNAI", "raw_text": "siRNA or CRISPR–Cas9 plasmid targeting mTOR, RAPTOR, or RICTOR", "target": {"name": "mTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": "human", "cell_type": "disk nucleus pulposus cells", "cell_lines": [], "genotype_context": null, "disease_context": "degenerative disk"}, "readout": {"name": "pyroptosis", "assay": null, "figure_refs": []}, "effect": {"direction": "increase", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": true, "has_multiple_lines": true, "other": ["in vitro comparative study", "specified transfection efficiency"]}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all induced autophagy and inhibited apoptosis, senescence, pyroptosis, and matrix catabolism", "notes": "Split multi-readout list from quote. Expanded per multi-target 'all/each' statement."}, "confidence": 0.95}, {"intervention": {"category": "KNOCKDOWN_RNAI", "raw_text": "siRNA or CRISPR–Cas9 plasmid targeting mTOR, RAPTOR, or RICTOR", "target": {"name": "RAPTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": "human", "cell_type": "disk nucleus pulposus cells", "cell_lines": [], "genotype_context": null, "disease_context": "degenerative disk"}, "readout": {"name": "pyroptosis", "assay": null, "figure_refs": []}, "effect": {"direction": "increase", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": true, "has_multiple_lines": true, "other": ["in vitro comparative study", "specified transfection efficiency"]}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all induced autophagy and inhibited apoptosis, senescence, pyroptosis, and matrix catabolism", "notes": "Split multi-readout list from quote. Expanded per multi-target 'all/each' statement."}, "confidence": 0.95}, {"intervention": {"category": "KNOCKDOWN_RNAI", "raw_text": "siRNA or CRISPR–Cas9 plasmid targeting mTOR, RAPTOR, or RICTOR", "target": {"name": "RICTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": "human", "cell_type": "disk nucleus pulposus cells", "cell_lines": [], "genotype_context": null, "disease_context": "degenerative disk"}, "readout": {"name": "pyroptosis", "assay": null, "figure_refs": []}, "effect": {"direction": "increase", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": true, "has_multiple_lines": true, "other": ["in vitro comparative study", "specified transfection efficiency"]}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all induced autophagy and inhibited apoptosis, senescence, pyroptosis, and matrix catabolism", "notes": "Split multi-readout list from quote. Expanded per multi-target 'all/each' statement."}, "confidence": 0.95}, {"intervention": {"category": "KNOCKDOWN_RNAI", "raw_text": "siRNA or CRISPR–Cas9 plasmid targeting mTOR, RAPTOR, or RICTOR", "target": {"name": "mTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": "human", "cell_type": "disk nucleus pulposus cells", "cell_lines": [], "genotype_context": null, "disease_context": "degenerative disk"}, "readout": {"name": "matrix catabolism", "assay": null, "figure_refs": []}, "effect": {"direction": "increase", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": true, "has_multiple_lines": true, "other": ["in vitro comparative study", "specified transfection efficiency"]}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all induced autophagy and inhibited apoptosis, senescence, pyroptosis, and matrix catabolism", "notes": "Split multi-readout list from quote. Expanded per multi-target 'all/each' statement."}, "confidence": 0.95}, {"intervention": {"category": "KNOCKDOWN_RNAI", "raw_text": "siRNA or CRISPR–Cas9 plasmid targeting mTOR, RAPTOR, or RICTOR", "target": {"name": "RAPTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": "human", "cell_type": "disk nucleus pulposus cells", "cell_lines": [], "genotype_context": null, "disease_context": "degenerative disk"}, "readout": {"name": "matrix catabolism", "assay": null, "figure_refs": []}, "effect": {"direction": "increase", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": true, "has_multiple_lines": true, "other": ["in vitro comparative study", "specified transfection efficiency"]}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all induced autophagy and inhibited apoptosis, senescence, pyroptosis, and matrix catabolism", "notes": "Split multi-readout list from quote. Expanded per multi-target 'all/each' statement."}, "confidence": 0.95}, {"intervention": {"category": "KNOCKDOWN_RNAI", "raw_text": "siRNA or CRISPR–Cas9 plasmid targeting mTOR, RAPTOR, or RICTOR", "target": {"name": "RICTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": "human", "cell_type": "disk nucleus pulposus cells", "cell_lines": [], "genotype_context": null, "disease_context": "degenerative disk"}, "readout": {"name": "matrix catabolism", "assay": null, "figure_refs": []}, "effect": {"direction": "increase", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": true, "has_multiple_lines": true, "other": ["in vitro comparative study", "specified transfection efficiency"]}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all induced autophagy and inhibited apoptosis, senescence, pyroptosis, and matrix catabolism", "notes": "Split multi-readout list from quote. Expanded per multi-target 'all/each' statement."}, "confidence": 0.95}, {"intervention": {"category": "KNOCKDOWN_RNAI", "raw_text": "siRNA or CRISPR–Cas9 plasmid targeting mTOR, RAPTOR, or RICTOR", "target": {"name": "mTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": "human", "cell_type": "disk nucleus pulposus cells", "cell_lines": [], "genotype_context": null, "disease_context": "degenerative disk"}, "readout": {"name": "autophagy", "assay": null, "figure_refs": []}, "effect": {"direction": "increase", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": true, "has_multiple_lines": true, "other": ["in vitro comparative study", "most prominent effect observed"]}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all induced autophagy and inhibited apoptosis, senescence, pyroptosis, and matrix catabolism, with the most prominent effects observed with RAPTOR CRISPR–Cas9", "notes": "Split multi-readout list from quote. Expanded per multi-target 'all/each' statement."}, "confidence": 0.98}, {"intervention": {"category": "KNOCKDOWN_RNAI", "raw_text": "siRNA or CRISPR–Cas9 plasmid targeting mTOR, RAPTOR, or RICTOR", "target": {"name": "RAPTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": "human", "cell_type": "disk nucleus pulposus cells", "cell_lines": [], "genotype_context": null, "disease_context": "degenerative disk"}, "readout": {"name": "autophagy", "assay": null, "figure_refs": []}, "effect": {"direction": "increase", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": true, "has_multiple_lines": true, "other": ["in vitro comparative study", "most prominent effect observed"]}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all induced autophagy and inhibited apoptosis, senescence, pyroptosis, and matrix catabolism, with the most prominent effects observed with RAPTOR CRISPR–Cas9", "notes": "Split multi-readout list from quote. Expanded per multi-target 'all/each' statement."}, "confidence": 0.98}, {"intervention": {"category": "KNOCKDOWN_RNAI", "raw_text": "siRNA or CRISPR–Cas9 plasmid targeting mTOR, RAPTOR, or RICTOR", "target": {"name": "RICTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": "human", "cell_type": "disk nucleus pulposus cells", "cell_lines": [], "genotype_context": null, "disease_context": "degenerative disk"}, "readout": {"name": "autophagy", "assay": null, "figure_refs": []}, "effect": {"direction": "increase", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": true, "has_multiple_lines": true, "other": ["in vitro comparative study", "most prominent effect observed"]}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all induced autophagy and inhibited apoptosis, senescence, pyroptosis, and matrix catabolism, with the most prominent effects observed with RAPTOR CRISPR–Cas9", "notes": "Split multi-readout list from quote. Expanded per multi-target 'all/each' statement."}, "confidence": 0.98}, {"intervention": {"category": "KNOCKDOWN_RNAI", "raw_text": "siRNA or CRISPR–Cas9 plasmid targeting mTOR, RAPTOR, or RICTOR", "target": {"name": "mTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": "human", "cell_type": "disk nucleus pulposus cells", "cell_lines": [], "genotype_context": null, "disease_context": "degenerative disk"}, "readout": {"name": "inhibited apoptosis", "assay": null, "figure_refs": []}, "effect": {"direction": "increase", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": true, "has_multiple_lines": true, "other": ["in vitro comparative study", "most prominent effect observed"]}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all induced autophagy and inhibited apoptosis, senescence, pyroptosis, and matrix catabolism, with the most prominent effects observed with RAPTOR CRISPR–Cas9", "notes": "Split multi-readout list from quote. Expanded per multi-target 'all/each' statement."}, "confidence": 0.98}, {"intervention": {"category": "KNOCKDOWN_RNAI", "raw_text": "siRNA or CRISPR–Cas9 plasmid targeting mTOR, RAPTOR, or RICTOR", "target": {"name": "RAPTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": "human", "cell_type": "disk nucleus pulposus cells", "cell_lines": [], "genotype_context": null, "disease_context": "degenerative disk"}, "readout": {"name": "inhibited apoptosis", "assay": null, "figure_refs": []}, "effect": {"direction": "increase", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": true, "has_multiple_lines": true, "other": ["in vitro comparative study", "most prominent effect observed"]}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all induced autophagy and inhibited apoptosis, senescence, pyroptosis, and matrix catabolism, with the most prominent effects observed with RAPTOR CRISPR–Cas9", "notes": "Split multi-readout list from quote. Expanded per multi-target 'all/each' statement."}, "confidence": 0.98}, {"intervention": {"category": "KNOCKDOWN_RNAI", "raw_text": "siRNA or CRISPR–Cas9 plasmid targeting mTOR, RAPTOR, or RICTOR", "target": {"name": "RICTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": "human", "cell_type": "disk nucleus pulposus cells", "cell_lines": [], "genotype_context": null, "disease_context": "degenerative disk"}, "readout": {"name": "inhibited apoptosis", "assay": null, "figure_refs": []}, "effect": {"direction": "increase", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": true, "has_multiple_lines": true, "other": ["in vitro comparative study", "most prominent effect observed"]}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all induced autophagy and inhibited apoptosis, senescence, pyroptosis, and matrix catabolism, with the most prominent effects observed with RAPTOR CRISPR–Cas9", "notes": "Split multi-readout list from quote. Expanded per multi-target 'all/each' statement."}, "confidence": 0.98}, {"intervention": {"category": "KNOCKDOWN_RNAI", "raw_text": "siRNA or CRISPR–Cas9 plasmid targeting mTOR, RAPTOR, or RICTOR", "target": {"name": "mTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": "human", "cell_type": "disk nucleus pulposus cells", "cell_lines": [], "genotype_context": null, "disease_context": "degenerative disk"}, "readout": {"name": "senescence", "assay": null, "figure_refs": []}, "effect": {"direction": "increase", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": true, "has_multiple_lines": true, "other": ["in vitro comparative study", "most prominent effect observed"]}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all induced autophagy and inhibited apoptosis, senescence, pyroptosis, and matrix catabolism, with the most prominent effects observed with RAPTOR CRISPR–Cas9", "notes": "Split multi-readout list from quote. Expanded per multi-target 'all/each' statement."}, "confidence": 0.98}, {"intervention": {"category": "KNOCKDOWN_RNAI", "raw_text": "siRNA or CRISPR–Cas9 plasmid targeting mTOR, RAPTOR, or RICTOR", "target": {"name": "RAPTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": "human", "cell_type": "disk nucleus pulposus cells", "cell_lines": [], "genotype_context": null, "disease_context": "degenerative disk"}, "readout": {"name": "senescence", "assay": null, "figure_refs": []}, "effect": {"direction": "increase", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": true, "has_multiple_lines": true, "other": ["in vitro comparative study", "most prominent effect observed"]}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all induced autophagy and inhibited apoptosis, senescence, pyroptosis, and matrix catabolism, with the most prominent effects observed with RAPTOR CRISPR–Cas9", "notes": "Split multi-readout list from quote. Expanded per multi-target 'all/each' statement."}, "confidence": 0.98}, {"intervention": {"category": "KNOCKDOWN_RNAI", "raw_text": "siRNA or CRISPR–Cas9 plasmid targeting mTOR, RAPTOR, or RICTOR", "target": {"name": "RICTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": "human", "cell_type": "disk nucleus pulposus cells", "cell_lines": [], "genotype_context": null, "disease_context": "degenerative disk"}, "readout": {"name": "senescence", "assay": null, "figure_refs": []}, "effect": {"direction": "increase", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": true, "has_multiple_lines": true, "other": ["in vitro comparative study", "most prominent effect observed"]}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all induced autophagy and inhibited apoptosis, senescence, pyroptosis, and matrix catabolism, with the most prominent effects observed with RAPTOR CRISPR–Cas9", "notes": "Split multi-readout list from quote. Expanded per multi-target 'all/each' statement."}, "confidence": 0.98}, {"intervention": {"category": "KNOCKDOWN_RNAI", "raw_text": "siRNA or CRISPR–Cas9 plasmid targeting mTOR, RAPTOR, or RICTOR", "target": {"name": "mTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": "human", "cell_type": "disk nucleus pulposus cells", "cell_lines": [], "genotype_context": null, "disease_context": "degenerative disk"}, "readout": {"name": "pyroptosis", "assay": null, "figure_refs": []}, "effect": {"direction": "increase", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": true, "has_multiple_lines": true, "other": ["in vitro comparative study", "most prominent effect observed"]}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all induced autophagy and inhibited apoptosis, senescence, pyroptosis, and matrix catabolism, with the most prominent effects observed with RAPTOR CRISPR–Cas9", "notes": "Split multi-readout list from quote. Expanded per multi-target 'all/each' statement."}, "confidence": 0.98}, {"intervention": {"category": "KNOCKDOWN_RNAI", "raw_text": "siRNA or CRISPR–Cas9 plasmid targeting mTOR, RAPTOR, or RICTOR", "target": {"name": "RAPTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": "human", "cell_type": "disk nucleus pulposus cells", "cell_lines": [], "genotype_context": null, "disease_context": "degenerative disk"}, "readout": {"name": "pyroptosis", "assay": null, "figure_refs": []}, "effect": {"direction": "increase", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": true, "has_multiple_lines": true, "other": ["in vitro comparative study", "most prominent effect observed"]}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all induced autophagy and inhibited apoptosis, senescence, pyroptosis, and matrix catabolism, with the most prominent effects observed with RAPTOR CRISPR–Cas9", "notes": "Split multi-readout list from quote. Expanded per multi-target 'all/each' statement."}, "confidence": 0.98}, {"intervention": {"category": "KNOCKDOWN_RNAI", "raw_text": "siRNA or CRISPR–Cas9 plasmid targeting mTOR, RAPTOR, or RICTOR", "target": {"name": "RICTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": "human", "cell_type": "disk nucleus pulposus cells", "cell_lines": [], "genotype_context": null, "disease_context": "degenerative disk"}, "readout": {"name": "pyroptosis", "assay": null, "figure_refs": []}, "effect": {"direction": "increase", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": true, "has_multiple_lines": true, "other": ["in vitro comparative study", "most prominent effect observed"]}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all induced autophagy and inhibited apoptosis, senescence, pyroptosis, and matrix catabolism, with the most prominent effects observed with RAPTOR CRISPR–Cas9", "notes": "Split multi-readout list from quote. Expanded per multi-target 'all/each' statement."}, "confidence": 0.98}, {"intervention": {"category": "KNOCKDOWN_RNAI", "raw_text": "siRNA or CRISPR–Cas9 plasmid targeting mTOR, RAPTOR, or RICTOR", "target": {"name": "mTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": "human", "cell_type": "disk nucleus pulposus cells", "cell_lines": [], "genotype_context": null, "disease_context": "degenerative disk"}, "readout": {"name": "matrix catabolism", "assay": null, "figure_refs": []}, "effect": {"direction": "increase", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": true, "has_multiple_lines": true, "other": ["in vitro comparative study", "most prominent effect observed"]}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all induced autophagy and inhibited apoptosis, senescence, pyroptosis, and matrix catabolism, with the most prominent effects observed with RAPTOR CRISPR–Cas9", "notes": "Split multi-readout list from quote. Expanded per multi-target 'all/each' statement."}, "confidence": 0.98}, {"intervention": {"category": "KNOCKDOWN_RNAI", "raw_text": "siRNA or CRISPR–Cas9 plasmid targeting mTOR, RAPTOR, or RICTOR", "target": {"name": "RAPTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": "human", "cell_type": "disk nucleus pulposus cells", "cell_lines": [], "genotype_context": null, "disease_context": "degenerative disk"}, "readout": {"name": "matrix catabolism", "assay": null, "figure_refs": []}, "effect": {"direction": "increase", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": true, "has_multiple_lines": true, "other": ["in vitro comparative study", "most prominent effect observed"]}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all induced autophagy and inhibited apoptosis, senescence, pyroptosis, and matrix catabolism, with the most prominent effects observed with RAPTOR CRISPR–Cas9", "notes": "Split multi-readout list from quote. Expanded per multi-target 'all/each' statement."}, "confidence": 0.98}, {"intervention": {"category": "KNOCKDOWN_RNAI", "raw_text": "siRNA or CRISPR–Cas9 plasmid targeting mTOR, RAPTOR, or RICTOR", "target": {"name": "RICTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": "human", "cell_type": "disk nucleus pulposus cells", "cell_lines": [], "genotype_context": null, "disease_context": "degenerative disk"}, "readout": {"name": "matrix catabolism", "assay": null, "figure_refs": []}, "effect": {"direction": "increase", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": true, "has_multiple_lines": true, "other": ["in vitro comparative study", "most prominent effect observed"]}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all induced autophagy and inhibited apoptosis, senescence, pyroptosis, and matrix catabolism, with the most prominent effects observed with RAPTOR CRISPR–Cas9", "notes": "Split multi-readout list from quote. Expanded per multi-target 'all/each' statement."}, "confidence": 0.98}], "warnings": ["Truncated atoms after multi-readout splitting: 67 -> 30.", "Truncated atoms after multi-target expansion: 72 -> 30 due to MAX_ATOMS_PER_CHUNK."], "_routing": {"first_model": "gpt-4o-mini", "escalated": true, "final_model": "gpt-4.1", "reason": {"type": "low_confidence_or_empty_or_bad_quotes", "details": "heuristics triggered"}}, "_post": {"dropped_atoms": 0, "multi_readout": {"enabled": true, "events": 12, "expanded_atoms": 64, "atoms_after": 30}, "multi_target": {"enabled": true, "candidate_targets": ["mTOR", "RAPTOR", "RICTOR"], "events": 30, "expanded_atoms": 90, "deduped_atoms": 30}}}

* * *

**ChatGPT:**

TAG: **PATHAI-0074**

Thanks for pasting the real output — this is **exactly** the kind of “truth serum” we need. Two big wins, and one clear bug:

## What’s now working (good)

1. **No ellipses in quotes** ✅  
    Your `supporting_quote` is a clean contiguous substring:

> “Targeting mTOR, RAPTOR, and RICTOR all induced autophagy and inhibited apoptosis, senescence, pyroptosis, and matrix catabolism”

2. **No arbitrary single-target choice** ✅  
    You’re getting **mTOR**, **RAPTOR**, **RICTOR** as parallel atoms (that’s the whole point of the safeguard).

## What’s wrong (needs fixing before graph)

### Bug A — readout name pollution

You have readouts like:

* `"readout": {"name": "inhibited apoptosis"}`

That should be just `"apoptosis"` (the verb belongs in the **effect**, not in the readout name).

### Bug B — wrong direction for inhibited outcomes

For apoptosis/senescence/pyroptosis/matrix catabolism you’re getting:

* `"effect": {"direction": "increase"}`

But the text says **inhibited**, so those should be **decrease**.

### Why it happened

Your v10 “splitter” grabbed the list after the **first verb** (“induced …”), then treated the rest as a comma list. So it accidentally turned **“inhibited apoptosis”** into a “readout item” and then **inherited the autophagy direction** (increase) for everything.

### Practical consequence

Your current chunk exploded to **72 candidate atoms** and then got chopped to 30:

* `Truncated atoms after multi-readout splitting: 67 -> 30`
* `Truncated atoms after multi-target expansion: 72 -> 30`

That truncation is _dangerous_ because it can randomly drop a readout/target combination you care about.

* * *

# Fix: clause-aware splitting + correct directions + cap only at the end

Below is a v11 script that fixes all of the above:

* **Clause-aware parsing**: understands “induced autophagy **and inhibited** apoptosis, senescence…” as **two verb clauses**.
* **Readout names cleaned**: you’ll get `apoptosis`, not `inhibited apoptosis`.
* **Directions corrected per clause**: induced/promoted → `increase`; inhibited/suppressed/reduced → `decrease`.
* **No early truncation**: it expands + dedupes first, then applies the max cap **at the end**, keeping the best-scored atoms.

* * *

## Full script v11: `make_atoms_docaware_v11.py`

TAG: **PATHAI-0074**  
Save as **`make_atoms_docaware_v11.py`**

```Python
#!/usr/bin/env python3
import os
import json
import re
import argparse
import hashlib
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple
from copy import deepcopy
from openai import OpenAI

# ============================================================
# DEFAULTS
# ============================================================
MODEL_FAST = "gpt-4o-mini"
MODEL_STRONG = "gpt-4.1"

MAX_ATOMS_PER_CHUNK = 30  # final cap (applied after expansions + dedupe)

# ============================================================
# OPENAI CLIENT
# ============================================================
def _get_api_key() -> str:
    key = os.getenv("OPENAI_API_KEY")
    if not key:
        raise RuntimeError(
            "OPENAI_API_KEY is not set.\n"
            "Miniforge Prompt (temporary):  set OPENAI_API_KEY=YOUR_KEY\n"
            "Persistent (Windows):         setx OPENAI_API_KEY \"YOUR_KEY\"  (then reopen prompt)"
        )
    return key

client = OpenAI(api_key=_get_api_key())

# ============================================================
# STRICT JSON SCHEMA FOR ATOMS (model output)
# ============================================================
ATOM_SCHEMA_WRAPPER: Dict[str, Any] = {
    "name": "MechanisticAtoms",
    "schema": {
        "type": "object",
        "additionalProperties": False,
        "required": ["atoms", "warnings"],
        "properties": {
            "atoms": {
                "type": "array",
                "items": {
                    "type": "object",
                    "additionalProperties": False,
                    "required": [
                        "intervention",
                        "system",
                        "readout",
                        "effect",
                        "strength_cues",
                        "evidence",
                        "confidence",
                    ],
                    "properties": {
                        "intervention": {
                            "type": "object",
                            "additionalProperties": False,
                            "required": ["category", "raw_text", "target", "modality"],
                            "properties": {
                                "category": {
                                    "type": "string",
                                    "enum": [
                                        "GENETIC_KO",
                                        "CRISPR_KO",
                                        "CRISPRi",
                                        "CRISPRa",
                                        "KNOCKDOWN_RNAI",
                                        "SPLICING_MODULATION",
                                        "OVEREXPRESSION",
                                        "RESCUE_ADD_BACK",
                                        "DOMINANT_NEGATIVE",
                                        "MUTANT_VARIANT",
                                        "CHEMICAL_INHIBITOR",
                                        "CHEMICAL_ACTIVATOR",
                                        "CHEMICAL_DEGRADER",
                                        "STIMULUS_TREATMENT",
                                        "NEUTRALIZING_ANTIBODY",
                                        "UNKNOWN",
                                    ],
                                },
                                "raw_text": {"type": "string", "minLength": 1},
                                "target": {
                                    "anyOf": [
                                        {
                                            "type": "object",
                                            "additionalProperties": False,
                                            "required": ["name", "entity_type"],
                                            "properties": {
                                                "name": {"type": "string"},
                                                "entity_type": {
                                                    "type": "string",
                                                    "enum": [
                                                        "gene",
                                                        "protein",
                                                        "chemical",
                                                        "stimulus",
                                                        "antibody",
                                                        "unknown",
                                                    ],
                                                },
                                            },
                                        },
                                        {"type": "null"},
                                    ]
                                },
                                "modality": {
                                    "type": "string",
                                    "enum": [
                                        "LOF",
                                        "GOF",
                                        "INHIBITION",
                                        "ACTIVATION",
                                        "DEGRADATION",
                                        "RESCUE",
                                        "UNKNOWN",
                                    ],
                                },
                            },
                        },
                        "system": {
                            "type": "object",
                            "additionalProperties": False,
                            "required": [
                                "species",
                                "cell_type",
                                "cell_lines",
                                "genotype_context",
                                "disease_context",
                            ],
                            "properties": {
                                "species": {"type": ["string", "null"]},
                                "cell_type": {"type": ["string", "null"]},
                                "cell_lines": {"type": "array", "items": {"type": "string"}},
                                "genotype_context": {"type": ["string", "null"]},
                                "disease_context": {"type": ["string", "null"]},
                            },
                        },
                        "readout": {
                            "type": "object",
                            "additionalProperties": False,
                            "required": ["name", "assay", "figure_refs"],
                            "properties": {
                                "name": {"type": "string"},
                                "assay": {"type": ["string", "null"]},
                                "figure_refs": {"type": "array", "items": {"type": "string"}},
                            },
                        },
                        "effect": {
                            "type": "object",
                            "additionalProperties": False,
                            "required": ["direction", "timepoint", "magnitude", "comparison"],
                            "properties": {
                                "direction": {
                                    "type": "string",
                                    "enum": ["increase", "decrease", "no_change", "mixed", "unknown"],
                                },
                                "timepoint": {"type": ["string", "null"]},
                                "magnitude": {"type": ["string", "null"]},
                                "comparison": {"type": ["string", "null"]},
                            },
                        },
                        "strength_cues": {
                            "type": "object",
                            "additionalProperties": False,
                            "required": ["has_rescue", "has_control", "has_multiple_lines", "other"],
                            "properties": {
                                "has_rescue": {"type": "boolean"},
                                "has_control": {"type": "boolean"},
                                "has_multiple_lines": {"type": "boolean"},
                                "other": {"type": "array", "items": {"type": "string"}},
                            },
                        },
                        "evidence": {
                            "type": "object",
                            "additionalProperties": False,
                            "required": ["supporting_quote", "notes"],
                            "properties": {
                                "supporting_quote": {"type": "string"},
                                "notes": {"type": ["string", "null"]},
                            },
                        },
                        "confidence": {"type": "number", "minimum": 0, "maximum": 1},
                    },
                },
            },
            "warnings": {"type": "array", "items": {"type": "string"}},
        },
    },
}

# ============================================================
# HINTS
# ============================================================
FIGREF_REGEX = re.compile(r"\b(Fig\.?\s*\d+[A-Za-z]?)\b", re.IGNORECASE)
SPECIES_REGEX = re.compile(r"\b(human|mouse|murine|rat)\b", re.IGNORECASE)

def _uniq_preserve(seq: List[str]) -> List[str]:
    seen = set()
    out = []
    for x in seq:
        k = x.lower()
        if k not in seen:
            seen.add(k)
            out.append(x)
    return out

def hint_figrefs(text: str) -> List[str]:
    return _uniq_preserve([m.group(1) for m in FIGREF_REGEX.finditer(text or "")])

def hint_species(text: str) -> Optional[str]:
    m = SPECIES_REGEX.search(text or "")
    if not m:
        return None
    s = m.group(1).lower()
    return "mouse" if s == "murine" else s

def compact_mentions(mentions: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    out = []
    for i, m in enumerate(mentions or [], start=1):
        out.append({
            "i": i,
            "category": m.get("category"),
            "raw_text": m.get("raw_text"),
            "target_guess": m.get("target_guess"),
            "method_cues": m.get("method_cues", []),
        })
    return out

# ============================================================
# DOC_ID DERIVATION (PMID(+PMCID) → PMCID → DOI → JVP → FILE → TITLEHASH → CHUNK)
# ============================================================
_DOI_PREFIX_RE = re.compile(r"^(https?://(dx\.)?doi\.org/|doi:\s*)", re.IGNORECASE)
_YEAR_RE = re.compile(r"\b(19\d{2}|20\d{2})\b")
_PAGES_RE = re.compile(r"^\s*(\d+)\s*[-–—]\s*(\d+)\s*$")

def _stable_hash(text: str, n: int = 12) -> str:
    return hashlib.sha1(text.encode("utf-8")).hexdigest()[:n]

def _get_nested(rec: Dict[str, Any], path: List[str]) -> Optional[Any]:
    cur: Any = rec
    for k in path:
        if not isinstance(cur, dict) or k not in cur:
            return None
        cur = cur[k]
    return cur

def _first_str_value(rec: Dict[str, Any], key_paths: List[List[str]]) -> Optional[str]:
    for path in key_paths:
        v = _get_nested(rec, path)
        if isinstance(v, str) and v.strip():
            return v.strip()
    return None

def _first_intish_value(rec: Dict[str, Any], key_paths: List[List[str]]) -> Optional[str]:
    for path in key_paths:
        v = _get_nested(rec, path)
        if v is None:
            continue
        if isinstance(v, int):
            return str(v)
        if isinstance(v, str):
            s = v.strip()
            m = re.search(r"\d+", s)
            if m:
                return m.group(0)
    return None

def _normalize_pmcid(x: str) -> Optional[str]:
    if not x:
        return None
    s = x.strip()
    if s.lower().startswith("pmc"):
        digits = re.sub(r"\D+", "", s)
        return f"PMC{digits}" if digits else None
    digits = re.sub(r"\D+", "", s)
    return f"PMC{digits}" if digits else None

def _normalize_journal(j: str) -> str:
    s = re.sub(r"[^A-Za-z0-9]+", "", (j or "").lower())
    return s[:32] if s else ""

def _extract_year(rec: Dict[str, Any]) -> Optional[str]:
    year = _first_intish_value(rec, [
        ["year"], ["pub_year"], ["publication_year"],
        ["metadata", "year"], ["metadata", "pub_year"], ["paper", "year"],
    ])
    if year and len(year) == 4:
        return year

    date_str = _first_str_value(rec, [
        ["date"], ["publication_date"], ["pub_date"],
        ["metadata", "date"], ["metadata", "publication_date"], ["paper", "date"],
    ])
    if date_str:
        m = _YEAR_RE.search(date_str)
        if m:
            return m.group(1)
    return None

def _extract_volume(rec: Dict[str, Any]) -> Optional[str]:
    vol = _first_str_value(rec, [
        ["volume"], ["vol"], ["metadata", "volume"], ["paper", "volume"],
    ])
    if not vol:
        return None
    vol2 = re.sub(r"[^0-9A-Za-z]+", "", vol)
    return vol2 or None

def _extract_pages(rec: Dict[str, Any]) -> Optional[str]:
    pages = _first_str_value(rec, [
        ["pages"], ["page_range"], ["pagination"], ["pageNumbers"],
        ["metadata", "pages"], ["metadata", "page_range"], ["paper", "pages"],
    ])
    if pages:
        s = pages.strip().replace("–", "-").replace("—", "-")
        m = _PAGES_RE.match(s)
        if m:
            return f"{m.group(1)}-{m.group(2)}"
        s2 = re.sub(r"\s+", "", s)
        s2 = re.sub(r"[^0-9A-Za-z\-]+", "", s2)
        return s2 or None

    p1 = _first_intish_value(rec, [
        ["page_start"], ["first_page"], ["start_page"],
        ["metadata", "page_start"], ["paper", "page_start"],
    ])
    p2 = _first_intish_value(rec, [
        ["page_end"], ["last_page"], ["end_page"],
        ["metadata", "page_end"], ["paper", "page_end"],
    ])
    if p1 and p2:
        return f"{p1}-{p2}"
    if p1:
        return p1
    return None

def _extract_journal(rec: Dict[str, Any]) -> Optional[str]:
    return _first_str_value(rec, [
        ["journal"], ["journal_name"], ["journalTitle"],
        ["metadata", "journal"], ["metadata", "journal_name"], ["paper", "journal"],
    ])

def derive_doc_id_with_source(rec: Dict[str, Any]) -> Tuple[Optional[str], str]:
    pmid = _first_intish_value(rec, [
        ["pmid"], ["PMID"], ["pubmed_id"], ["pubmedId"], ["PubMedID"],
        ["metadata", "pmid"], ["metadata", "PMID"], ["paper", "pmid"], ["paper", "PMID"],
    ])
    pmcid_raw = _first_str_value(rec, [
        ["pmcid"], ["PMCID"], ["pubmed_central_id"], ["pmc_id"], ["pmcId"],
        ["metadata", "pmcid"], ["metadata", "PMCID"], ["paper", "pmcid"], ["paper", "PMCID"],
    ])
    pmcid = _normalize_pmcid(pmcid_raw or "")

    if pmid and pmcid:
        return f"PMID:{pmid}|PMCID:{pmcid}", "pmid_pmcid"
    if pmid:
        return f"PMID:{pmid}", "pmid"
    if pmcid:
        return f"PMCID:{pmcid}", "pmcid"

    doi = _first_str_value(rec, [
        ["doi"], ["DOI"], ["metadata", "doi"], ["metadata", "DOI"], ["paper", "doi"], ["paper", "DOI"],
    ])
    if doi:
        doi2 = _DOI_PREFIX_RE.sub("", doi).strip()
        return f"DOI:{doi2}", "doi"

    journal = _extract_journal(rec)
    year = _extract_year(rec)
    volume = _extract_volume(rec)
    pages = _extract_pages(rec)
    jnorm = _normalize_journal(journal or "")
    if jnorm and year and volume and pages:
        return f"JVP:{jnorm}:{year}:{volume}:{pages}", "jvp"

    file_path = _first_str_value(rec, [
        ["source_file"], ["file"], ["filename"], ["pdf_file"],
        ["source", "file"], ["_source", "file"], ["metadata", "file"], ["metadata", "filename"],
    ])
    if file_path:
        name = Path(file_path).name.strip()
        if name:
            return f"FILE:{name}", "file"
        return f"FILEHASH:{_stable_hash(file_path)}", "file"

    title = _first_str_value(rec, [
        ["title"], ["paper_title"], ["metadata", "title"], ["paper", "title"],
    ])
    if title:
        return f"TITLEHASH:{_stable_hash(title.lower().strip())}", "titlehash"

    return None, "none"

# ============================================================
# PROMPT (tightened: no ellipses + parallel atoms)
# ============================================================
SYSTEM_INSTRUCTIONS = (
    "Extract 'mechanistic atoms' from biomedical text.\n\n"
    "Definition: an atom MUST include an explicit effect on a readout.\n"
    "Format: [INTERVENTION] causes [EFFECT] in [READOUT] in a [SYSTEM].\n\n"
    "Hard rules:\n"
    "1) Do NOT invent facts.\n"
    "2) Do NOT assume knockdown succeeded unless the text explicitly says reduction/knockdown/confirmed.\n"
    "3) If the text only describes delivering siRNA/plasmid/drug but gives no stated change in any readout, output no atoms and add a warning.\n"
    "4) If a sentence says targeting A, B, and C 'all' (or 'each') causes an effect, emit parallel atoms for each target (A and B and C) rather than picking one.\n"
    "5) evidence.supporting_quote MUST be an exact contiguous substring from the chunk_text. Do NOT use ellipses (...).\n"
    "6) If a sentence lists multiple readouts (e.g., 'inhibited apoptosis, senescence, pyroptosis...'), extract one atom per readout.\n"
    f"7) Keep at most {MAX_ATOMS_PER_CHUNK} atoms.\n"
)

# ============================================================
# MODEL CALLS + ROUTING
# ============================================================
def call_model(model: str, chunk_text: str, mentions: List[Dict[str, Any]]) -> Dict[str, Any]:
    payload = {
        "chunk_text": chunk_text,
        "mentions": compact_mentions(mentions),
        "hints": {"fig_refs": hint_figrefs(chunk_text), "species": hint_species(chunk_text)},
    }
    resp = client.responses.create(
        model=model,
        input=[
            {"role": "system", "content": SYSTEM_INSTRUCTIONS},
            {"role": "user", "content": json.dumps(payload, ensure_ascii=False)},
        ],
        text={
            "format": {
                "type": "json_schema",
                "name": ATOM_SCHEMA_WRAPPER["name"],
                "strict": True,
                "schema": ATOM_SCHEMA_WRAPPER["schema"],
            }
        },
    )
    return json.loads(resp.output_text)

def _has_ellipsis_quotes(atoms: List[Dict[str, Any]]) -> bool:
    for a in atoms or []:
        sq = ((a.get("evidence") or {}).get("supporting_quote") or "")
        if "..." in sq or "…" in sq:
            return True
    return False

def should_escalate(mentions: List[Dict[str, Any]], atoms: List[Dict[str, Any]]) -> bool:
    if len(mentions) > 0 and len(atoms) == 0:
        return True
    if _has_ellipsis_quotes(atoms):
        return True
    if len(atoms) > 0:
        avg_conf = sum(float(a.get("confidence", 0.0)) for a in atoms) / len(atoms)
        if avg_conf < 0.55:
            return True
    return False

def extract_atoms_with_routing(chunk_text: str, mentions: List[Dict[str, Any]]) -> Dict[str, Any]:
    routing = {"first_model": MODEL_FAST, "escalated": False, "final_model": MODEL_FAST, "reason": None}
    out_fast = call_model(MODEL_FAST, chunk_text, mentions)
    atoms_fast = out_fast.get("atoms", []) or []

    if should_escalate(mentions, atoms_fast):
        routing["escalated"] = True
        routing["final_model"] = MODEL_STRONG
        routing["reason"] = {"type": "low_confidence_or_empty_or_bad_quotes", "details": "heuristics triggered"}
        out_strong = call_model(MODEL_STRONG, chunk_text, mentions)
        out_strong["_routing"] = routing
        return out_strong

    out_fast["_routing"] = routing
    return out_fast

# ============================================================
# POST-FILTER (expanded effect cues)
# ============================================================
EFFECT_CUE = re.compile(
    r"\b("
    r"inhibit|inhibited|inhibition|"
    r"suppress|suppressed|suppressing|suppression|"
    r"reduce|reduced|reduces|reduction|"
    r"decrease|decreased|decreases|"
    r"increase|increased|increases|"
    r"elevate|elevated|"
    r"no effect|did not affect|had no effect|no significant|unchanged|"
    r"induce|induced|induction|"
    r"promote|promoted|promotion|"
    r"attenuate|attenuated|attenuation|"
    r"block|blocked|blocking|"
    r"activate|activated|activation|"
    r"inactivate|inactivated|inactivation|"
    r"enhance|enhanced|enhancement|"
    r"impair|impaired|impairment|"
    r"abrogate|abrogated|abrogation|"
    r"abolish|abolished|abolition|"
    r"antiproliferative|anti-proliferative|"
    r"cytotoxic|cytotoxicity|"
    r"tumor growth suppression|growth suppression|"
    r"degradation|degraded|degrade|"
    r"depletion|deplete|depleted|"
    r"knockdown|knocked down|silencing|silenced"
    r")\b",
    re.IGNORECASE,
)

def post_filter_atoms(atoms: List[Dict[str, Any]]) -> Tuple[List[Dict[str, Any]], int]:
    kept: List[Dict[str, Any]] = []
    dropped = 0
    for a in atoms or []:
        sq = (a.get("evidence", {}) or {}).get("supporting_quote", "")
        if EFFECT_CUE.search(sq or ""):
            kept.append(a)
        else:
            dropped += 1
    return kept, dropped

# ============================================================
# CLAUSE-AWARE MULTI-READOUT SPLITTING (fixes your bug)
# ============================================================
def _norm_space(s: str) -> str:
    return re.sub(r"\s+", " ", (s or "")).strip()

# Verb → direction mapping
VERB_DIR: List[Tuple[re.Pattern, str]] = [
    (re.compile(r"\b(induce|induced|increase|increased|promote|promoted|elevate|elevated|enhance|enhanced|activate|activated)\b", re.IGNORECASE), "increase"),
    (re.compile(r"\b(inhibit|inhibited|suppress|suppressed|reduce|reduced|decrease|decreased|attenuate|attenuated|block|blocked|impair|impaired|abrogate|abrogated|abolish|abolished)\b", re.IGNORECASE), "decrease"),
    (re.compile(r"\b(no effect|did not affect|had no effect|unchanged|no significant)\b", re.IGNORECASE), "no_change"),
]

# We find verb tokens in order, then attribute the phrase until the next verb token.
VERB_TOKEN = re.compile(
    r"\b("
    r"induce|induced|increase|increased|promote|promoted|elevate|elevated|enhance|enhanced|activate|activated|"
    r"inhibit|inhibited|suppress|suppressed|reduce|reduced|decrease|decreased|attenuate|attenuated|block|blocked|impair|impaired|abrogate|abrogated|abolish|abolished|"
    r"unchanged"
    r")\b",
    re.IGNORECASE,
)

def _direction_for_verb(verb: str) -> str:
    for pat, d in VERB_DIR:
        if pat.search(verb):
            return d
    return "unknown"

def _split_readout_list(text: str) -> List[str]:
    """
    Split a list like: 'apoptosis, senescence, pyroptosis, and matrix catabolism'
    """
    t = _norm_space(text)
    # cut at sentence end-ish
    t = re.split(r"[.;]", t, maxsplit=1)[0]
    # replace conjunctions with commas
    t = re.sub(r"\band\b", ",", t, flags=re.IGNORECASE)
    t = re.sub(r"\bor\b", ",", t, flags=re.IGNORECASE)
    t = t.replace(";", ",")
    parts = [p.strip(" ,.;:()[]{}<>\"'") for p in t.split(",")]
    parts = [p for p in parts if p]
    return parts

def parse_quote_into_effect_groups(quote: str) -> List[Tuple[str, List[str]]]:
    """
    Returns list of (direction, readouts[]) parsed from the quote.
    Example:
      "induced autophagy and inhibited apoptosis, senescence..."
      -> [("increase", ["autophagy"]), ("decrease", ["apoptosis","senescence",...])]
    """
    q = _norm_space(quote)
    if not q:
        return []

    matches = list(VERB_TOKEN.finditer(q))
    if not matches:
        return []

    groups: List[Tuple[str, List[str]]] = []
    for i, m in enumerate(matches):
        verb = m.group(0)
        d = _direction_for_verb(verb)
        start = m.end()
        end = matches[i + 1].start() if i + 1 < len(matches) else len(q)
        span = q[start:end].strip(" :;-,")

        # Remove leading filler like "the"
        span = re.sub(r"^\s*(the|a|an)\s+", "", span, flags=re.IGNORECASE)

        # If the span begins with another verb-like word due to punctuation, ignore
        if not span:
            continue

        # Special case: "induced autophagy and inhibited apoptosis..."
        # When the next verb exists, this already splits correctly.
        readouts = _split_readout_list(span)

        # Drop any items that still contain verb words (prevents "inhibited apoptosis" as a readout)
        cleaned: List[str] = []
        for r in readouts:
            rr = _norm_space(r)
            # Remove any leading verb that leaked in
            rr = re.sub(r"^(induce|induced|increase|increased|promote|promoted|elevate|elevated|enhance|enhanced|activate|activated|"
                        r"inhibit|inhibited|suppress|suppressed|reduce|reduced|decrease|decreased|attenuate|attenuated|block|blocked|impair|impaired|abrogate|abrogated|abolish|abolished)\s+",
                        "", rr, flags=re.IGNORECASE).strip()
            if rr:
                cleaned.append(rr)

        if cleaned:
            groups.append((d, cleaned))

    # Require at least one group with at least one readout
    return groups

def split_atoms_by_quote_clauses(atoms: List[Dict[str, Any]]) -> Tuple[List[Dict[str, Any]], Dict[str, Any]]:
    """
    For each atom, if its quote contains multiple readouts and/or multiple verbs,
    emit one atom per (direction, readout) found in the quote.
    """
    out: List[Dict[str, Any]] = []
    events = 0
    expanded = 0

    for a in atoms or []:
        sq = _norm_space(((a.get("evidence") or {}).get("supporting_quote") or ""))
        groups = parse_quote_into_effect_groups(sq)

        # If parsing yields nothing useful, keep atom
        if not groups:
            out.append(a)
            continue

        # Heuristic: only split if there is clearly multiplicity
        total_readouts = sum(len(rlist) for _, rlist in groups)
        if total_readouts <= 1:
            out.append(a)
            continue

        events += 1
        for direction, rlist in groups:
            for rname in rlist:
                aa = deepcopy(a)
                aa["readout"]["name"] = rname
                aa["effect"]["direction"] = direction  # critical fix
                notes = (aa.get("evidence", {}) or {}).get("notes")
                add = "Clause-aware split from supporting_quote (verb→direction + clean readout names)."
                aa["evidence"]["notes"] = (notes + " " + add).strip() if notes else add
                out.append(aa)
                expanded += 1

    meta = {"enabled": True, "events": events, "expanded_atoms": expanded, "atoms_after": len(out)}
    return out, meta

# ============================================================
# MULTI-TARGET EXPANSION (parallel targets) + BETTER DEDUPE
# ============================================================
MULTI_TARGET_CUE = re.compile(r"\b(all|each)\b", re.IGNORECASE)

def _split_target_list(s: str) -> List[str]:
    if not s:
        return []
    x = _norm_space(s)
    x = x.replace("/", " / ")
    x = re.sub(r"\band\b", ",", x, flags=re.IGNORECASE)
    x = re.sub(r"\bor\b", ",", x, flags=re.IGNORECASE)
    x = x.replace(";", ",").replace("/", ",")
    parts = [p.strip(" ,.;:()[]{}<>\"'") for p in x.split(",")]
    out = []
    for p in parts:
        if not p:
            continue
        if p.lower() in {"and", "or", "the", "a", "an"}:
            continue
        out.append(p)
    return out

def _targets_from_mentions(mentions: List[Dict[str, Any]]) -> Tuple[List[str], Dict[str, str]]:
    cand: List[str] = []
    type_map: Dict[str, str] = {}
    for m in mentions or []:
        tg = m.get("target_guess") or {}
        name = tg.get("name")
        et = tg.get("entity_type") or "protein"
        for t in _split_target_list(str(name) if name else ""):
            key = t.lower()
            if key not in type_map:
                type_map[key] = et
            if t not in cand:
                cand.append(t)
    return cand, type_map

def _find_targets_in_text(candidate_targets: List[str], text: str) -> List[str]:
    found: List[str] = []
    hay = text or ""
    for t in candidate_targets:
        pat = r"\b" + re.escape(t) + r"\b"
        if re.search(pat, hay, flags=re.IGNORECASE):
            found.append(t)
    return found

def _atom_key_noquote(a: Dict[str, Any]) -> Tuple:
    iv = a.get("intervention", {}) or {}
    tg = iv.get("target") or {}
    rd = a.get("readout", {}) or {}
    ef = a.get("effect", {}) or {}
    sys = a.get("system", {}) or {}
    return (
        str(iv.get("category") or "").lower(),
        str(iv.get("modality") or "").lower(),
        str((tg.get("name") if isinstance(tg, dict) else "") or "").lower(),
        str(rd.get("name") or "").lower(),
        str(ef.get("direction") or "").lower(),
        str(sys.get("species") or "").lower(),
        str(sys.get("cell_type") or "").lower(),
    )

def _pick_better(a: Dict[str, Any], b: Dict[str, Any]) -> Dict[str, Any]:
    """
    Choose the better representative when two atoms are duplicates ignoring quote.
    Prefer: higher confidence, then longer quote, then more strength_cues.
    """
    ca = float(a.get("confidence", 0.0))
    cb = float(b.get("confidence", 0.0))
    if ca != cb:
        return a if ca > cb else b

    qa = _norm_space(((a.get("evidence") or {}).get("supporting_quote") or ""))
    qb = _norm_space(((b.get("evidence") or {}).get("supporting_quote") or ""))
    if len(qa) != len(qb):
        return a if len(qa) > len(qb) else b

    sa = a.get("strength_cues", {}) or {}
    sb = b.get("strength_cues", {}) or {}
    score_a = int(bool(sa.get("has_control"))) + int(bool(sa.get("has_rescue"))) + int(bool(sa.get("has_multiple_lines")))
    score_b = int(bool(sb.get("has_control"))) + int(bool(sb.get("has_rescue"))) + int(bool(sb.get("has_multiple_lines")))
    if score_a != score_b:
        return a if score_a > score_b else b

    return a

def expand_multi_target_atoms(atoms: List[Dict[str, Any]], mentions: List[Dict[str, Any]]) -> Tuple[List[Dict[str, Any]], Dict[str, Any]]:
    candidate_targets, type_map = _targets_from_mentions(mentions)
    if not candidate_targets:
        return atoms, {"enabled": True, "events": 0, "expanded_atoms": 0, "deduped_atoms": len(atoms or [])}

    new_atoms: List[Dict[str, Any]] = []
    events = 0
    expanded_atoms = 0

    for a in atoms or []:
        ev = a.get("evidence", {}) or {}
        sq = _norm_space(ev.get("supporting_quote") or "")
        iv = a.get("intervention", {}) or {}
        raw = _norm_space(iv.get("raw_text") or "")
        combined = (sq + " " + raw).strip()

        found = _find_targets_in_text(candidate_targets, combined)
        if MULTI_TARGET_CUE.search(combined) and len(found) >= 2:
            events += 1
            for t in found:
                aa = deepcopy(a)
                et = type_map.get(t.lower(), None)

                if not aa.get("intervention"):
                    aa["intervention"] = {}
                if aa["intervention"].get("target") is None or not isinstance(aa["intervention"].get("target"), dict):
                    aa["intervention"]["target"] = {"name": t, "entity_type": et or "protein"}
                else:
                    aa["intervention"]["target"]["name"] = t
                    if not aa["intervention"]["target"].get("entity_type"):
                        aa["intervention"]["target"]["entity_type"] = et or "protein"

                notes = (aa.get("evidence", {}) or {}).get("notes")
                add = "Expanded per multi-target 'all/each' statement."
                aa["evidence"]["notes"] = (notes + " " + add).strip() if notes else add

                new_atoms.append(aa)
                expanded_atoms += 1
        else:
            new_atoms.append(a)

    # Dedupe ignoring quote (so “most prominent…” doesn’t create duplicate atoms)
    best_by_key: Dict[Tuple, Dict[str, Any]] = {}
    for a in new_atoms:
        k = _atom_key_noquote(a)
        if k not in best_by_key:
            best_by_key[k] = a
        else:
            best_by_key[k] = _pick_better(best_by_key[k], a)

    deduped = list(best_by_key.values())
    meta = {
        "enabled": True,
        "candidate_targets": candidate_targets[:50],
        "events": events,
        "expanded_atoms": expanded_atoms,
        "deduped_atoms": len(deduped),
    }
    return deduped, meta

# ============================================================
# FINAL CAP (after expansions + dedupe)
# ============================================================
def _final_score(a: Dict[str, Any]) -> Tuple:
    """
    Higher is better.
    Sort keys: confidence, has_control, has_rescue, has_multiple_lines, quote_len
    """
    conf = float(a.get("confidence", 0.0))
    sc = a.get("strength_cues", {}) or {}
    has_control = int(bool(sc.get("has_control")))
    has_rescue = int(bool(sc.get("has_rescue")))
    has_multi = int(bool(sc.get("has_multiple_lines")))
    qlen = len(_norm_space(((a.get("evidence") or {}).get("supporting_quote") or "")))
    return (conf, has_control, has_rescue, has_multi, qlen)

def apply_final_cap(atoms: List[Dict[str, Any]], max_atoms: int) -> Tuple[List[Dict[str, Any]], Optional[str]]:
    if len(atoms) <= max_atoms:
        return atoms, None
    atoms_sorted = sorted(atoms, key=_final_score, reverse=True)
    return atoms_sorted[:max_atoms], f"Truncated atoms at final cap: {len(atoms)} -> {max_atoms}."

# ============================================================
# MAIN
# ============================================================
def main() -> int:
    ap = argparse.ArgumentParser(description="PATHAI atoms extraction v11: clause-aware readout splitting + correct directions + multi-target + end-only cap")
    ap.add_argument("--infile", default="mentions.jsonl", help="Input mentions.jsonl")
    ap.add_argument("--outfile", default="atoms.jsonl", help="Output atoms.jsonl")
    ap.add_argument("--default_doc_id", default=None, help="If cannot derive doc_id, use this (otherwise falls back to CHUNK:<chunk_id>).")
    ap.add_argument("--assign_chunk_index", action="store_true", help="Assign chunk_index per doc_id if missing (sequential in file order).")
    args = ap.parse_args()

    infile = Path(args.infile)
    outfile = Path(args.outfile)

    if not infile.exists():
        raise FileNotFoundError(f"Cannot find {infile.resolve()}")

    records: List[Dict[str, Any]] = []
    for ln in infile.read_text(encoding="utf-8", errors="ignore").splitlines():
        ln = ln.strip()
        if ln:
            records.append(json.loads(ln))

    src_counts: Dict[str, int] = {}
    for r in records:
        if not r.get("doc_id"):
            doc_id, src = derive_doc_id_with_source(r)
            if doc_id:
                r["doc_id"] = doc_id
                r["doc_id_source"] = src
                src_counts[src] = src_counts.get(src, 0) + 1
            else:
                if args.default_doc_id:
                    r["doc_id"] = args.default_doc_id
                    r["doc_id_source"] = "default"
                    src_counts["default"] = src_counts.get("default", 0) + 1
                else:
                    cid = r.get("chunk_id")
                    r["doc_id"] = f"CHUNK:{cid}"
                    r["doc_id_source"] = "chunk_fallback"
                    src_counts["chunk_fallback"] = src_counts.get("chunk_fallback", 0) + 1

    if args.assign_chunk_index:
        counters: Dict[str, int] = {}
        for r in records:
            doc = r.get("doc_id")
            if not doc:
                continue
            if r.get("chunk_index") is None:
                counters.setdefault(doc, 0)
                r["chunk_index"] = counters[doc]
                counters[doc] += 1

    total_atoms = 0
    escalations = 0
    dropped_total = 0
    split_events_total = 0
    split_expanded_total = 0
    mt_events_total = 0
    mt_expanded_total = 0
    final_truncs = 0

    with outfile.open("w", encoding="utf-8", newline="\n") as fout:
        for rec in records:
            chunk_id = rec.get("chunk_id")
            doc_id = rec.get("doc_id")
            doc_id_source = rec.get("doc_id_source")
            chunk_index = rec.get("chunk_index")

            if "error" in rec:
                out_rec = {
                    "doc_id": doc_id,
                    "doc_id_source": doc_id_source,
                    "chunk_index": chunk_index,
                    "chunk_id": chunk_id,
                    "atoms": [],
                    "warnings": ["Skipped due to upstream error."],
                    "_routing": {"skipped": True},
                    "_post": {"dropped_atoms": 0,
                              "clause_split": {"enabled": True, "events": 0, "expanded_atoms": 0},
                              "multi_target": {"enabled": True, "events": 0, "expanded_atoms": 0}},
                }
                fout.write(json.dumps(out_rec, ensure_ascii=False) + "\n")
                continue

            chunk_text = rec.get("chunk_text", "")
            mentions = rec.get("mentions", [])

            out = extract_atoms_with_routing(chunk_text, mentions)
            atoms = out.get("atoms", []) or []
            warnings = out.get("warnings", []) or []
            routing = out.get("_routing", {}) or {}

            if routing.get("escalated"):
                escalations += 1

            atoms, dropped = post_filter_atoms(atoms)
            dropped_total += dropped

            # clause-aware splitting (fixes “inhibited apoptosis” + wrong directions)
            atoms, split_meta = split_atoms_by_quote_clauses(atoms)
            split_events_total += int(split_meta.get("events", 0))
            split_expanded_total += int(split_meta.get("expanded_atoms", 0))

            # multi-target expansion + better dedupe (ignores quote)
            atoms, mt_meta = expand_multi_target_atoms(atoms, mentions)
            mt_events_total += int(mt_meta.get("events", 0))
            mt_expanded_total += int(mt_meta.get("expanded_atoms", 0))

            # final cap only at the end
            atoms, trunc_warn = apply_final_cap(atoms, MAX_ATOMS_PER_CHUNK)
            if trunc_warn:
                warnings.append(trunc_warn)
                final_truncs += 1

            total_atoms += len(atoms)

            pmid_pt = rec.get("pmid") or rec.get("PMID") or rec.get("pubmed_id") or rec.get("pubmedId")
            pmcid_pt = rec.get("pmcid") or rec.get("PMCID") or rec.get("pubmed_central_id") or rec.get("pmcId") or rec.get("pmc_id")

            out_rec = {
                "doc_id": doc_id,
                "doc_id_source": doc_id_source,
                "pmid": pmid_pt,
                "pmcid": pmcid_pt,
                "chunk_index": chunk_index,
                "chunk_id": chunk_id,
                "atoms": atoms,
                "warnings": warnings,
                "_routing": routing,
                "_post": {
                    "dropped_atoms": dropped,
                    "clause_split": split_meta,
                    "multi_target": mt_meta,
                },
            }
            fout.write(json.dumps(out_rec, ensure_ascii=False) + "\n")

            print(
                f"chunk {chunk_id} doc_id={doc_id}({doc_id_source}) idx={chunk_index} "
                f"atoms={len(atoms)} escalated={routing.get('escalated', False)} dropped={dropped} "
                f"split_events={split_meta.get('events',0)} mt_events={mt_meta.get('events',0)}"
            )

    print(f"Done. total_atoms={total_atoms}, escalations={escalations}, dropped_total={dropped_total}")
    print(f"clause-split: events={split_events_total}, expanded_atoms={split_expanded_total}")
    print(f"multi-target: events={mt_events_total}, expanded_atoms={mt_expanded_total}")
    print(f"final truncations: {final_truncs}")
    if src_counts:
        print("doc_id sources:", ", ".join(f"{k}={v}" for k, v in sorted(src_counts.items())))
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
```

* * *

## What you should see for this chunk after v11

For this sentence, the _correct_ outcome is basically:

* For each of **mTOR**, **RAPTOR**, **RICTOR**:
    * **autophagy** → **increase**
    * **apoptosis** → **decrease**
    * **senescence** → **decrease**
    * **pyroptosis** → **decrease**
    * **matrix catabolism** → **decrease**

That’s **3 targets × 5 readouts = 15 atoms**, not 30+ and not truncated.

* * *

## Run

```bat
conda activate pathai
cd "C:\Users\Prem Subramaniam\Documents\Pathway AI"
python make_atoms_docaware_v11.py
```

Then paste the new `atoms.jsonl` line for **chunk_id 2** again — I’m looking specifically for:

* no `"readout": {"name": "inhibited apoptosis"}`
* apoptosis/senescence/pyroptosis/matrix catabolism all have `direction: "decrease"`
* truncation warnings should disappear (or at least be rare) for this chunk.

* * *

**You:**

{"doc_id": "PMID:39682777", "doc_id_source": "pmid", "pmid": "39682777", "pmcid": null, "chunk_index": null, "chunk_id": 2, "atoms": [{"intervention": {"category": "CRISPR_KO", "raw_text": "CRISPR–Cas9 plasmid targeting RAPTOR", "target": {"name": "mTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": "human", "cell_type": null, "cell_lines": [], "genotype_context": null, "disease_context": null}, "readout": {"name": "autophagy", "assay": null, "figure_refs": []}, "effect": {"direction": "increase", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all induced autophagy", "notes": "Expanded per multi-target 'all/each' statement."}, "confidence": 0.9}, {"intervention": {"category": "CRISPR_KO", "raw_text": "CRISPR–Cas9 plasmid targeting RAPTOR", "target": {"name": "RAPTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": "human", "cell_type": null, "cell_lines": [], "genotype_context": null, "disease_context": null}, "readout": {"name": "autophagy", "assay": null, "figure_refs": []}, "effect": {"direction": "increase", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all induced autophagy", "notes": "Expanded per multi-target 'all/each' statement."}, "confidence": 0.9}, {"intervention": {"category": "CRISPR_KO", "raw_text": "CRISPR–Cas9 plasmid targeting RAPTOR", "target": {"name": "RICTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": "human", "cell_type": null, "cell_lines": [], "genotype_context": null, "disease_context": null}, "readout": {"name": "autophagy", "assay": null, "figure_refs": []}, "effect": {"direction": "increase", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all induced autophagy", "notes": "Expanded per multi-target 'all/each' statement."}, "confidence": 0.9}, {"intervention": {"category": "CRISPR_KO", "raw_text": "CRISPR–Cas9 plasmid targeting RAPTOR", "target": {"name": "RAPTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": "human", "cell_type": null, "cell_lines": [], "genotype_context": null, "disease_context": null}, "readout": {"name": "apoptosis", "assay": null, "figure_refs": []}, "effect": {"direction": "decrease", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "induced autophagy and inhibited apoptosis", "notes": "Clause-aware split from supporting_quote (verb→direction + clean readout names)."}, "confidence": 0.9}, {"intervention": {"category": "CRISPR_KO", "raw_text": "CRISPR–Cas9 plasmid targeting RAPTOR", "target": {"name": "RAPTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": "human", "cell_type": null, "cell_lines": [], "genotype_context": null, "disease_context": null}, "readout": {"name": "senescence", "assay": null, "figure_refs": []}, "effect": {"direction": "decrease", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "induced autophagy and inhibited senescence", "notes": "Clause-aware split from supporting_quote (verb→direction + clean readout names)."}, "confidence": 0.9}, {"intervention": {"category": "CRISPR_KO", "raw_text": "CRISPR–Cas9 plasmid targeting RAPTOR", "target": {"name": "RAPTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": "human", "cell_type": null, "cell_lines": [], "genotype_context": null, "disease_context": null}, "readout": {"name": "pyroptosis", "assay": null, "figure_refs": []}, "effect": {"direction": "decrease", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "induced autophagy and inhibited pyroptosis", "notes": "Clause-aware split from supporting_quote (verb→direction + clean readout names)."}, "confidence": 0.9}, {"intervention": {"category": "CRISPR_KO", "raw_text": "CRISPR–Cas9 plasmid targeting RAPTOR", "target": {"name": "RAPTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": "human", "cell_type": null, "cell_lines": [], "genotype_context": null, "disease_context": null}, "readout": {"name": "matrix catabolism", "assay": null, "figure_refs": []}, "effect": {"direction": "decrease", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "induced autophagy and inhibited matrix catabolism", "notes": "Clause-aware split from supporting_quote (verb→direction + clean readout names)."}, "confidence": 0.9}, {"intervention": {"category": "CRISPR_KO", "raw_text": "CRISPR–Cas9 plasmid targeting mTOR", "target": {"name": "mTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": "human", "cell_type": null, "cell_lines": [], "genotype_context": null, "disease_context": null}, "readout": {"name": "apoptosis", "assay": null, "figure_refs": []}, "effect": {"direction": "decrease", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "induced autophagy and inhibited apoptosis", "notes": "Clause-aware split from supporting_quote (verb→direction + clean readout names)."}, "confidence": 0.9}, {"intervention": {"category": "CRISPR_KO", "raw_text": "CRISPR–Cas9 plasmid targeting mTOR", "target": {"name": "mTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": "human", "cell_type": null, "cell_lines": [], "genotype_context": null, "disease_context": null}, "readout": {"name": "senescence", "assay": null, "figure_refs": []}, "effect": {"direction": "decrease", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "induced autophagy and inhibited senescence", "notes": "Clause-aware split from supporting_quote (verb→direction + clean readout names)."}, "confidence": 0.9}, {"intervention": {"category": "CRISPR_KO", "raw_text": "CRISPR–Cas9 plasmid targeting mTOR", "target": {"name": "mTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": "human", "cell_type": null, "cell_lines": [], "genotype_context": null, "disease_context": null}, "readout": {"name": "pyroptosis", "assay": null, "figure_refs": []}, "effect": {"direction": "decrease", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "induced autophagy and inhibited pyroptosis", "notes": "Clause-aware split from supporting_quote (verb→direction + clean readout names)."}, "confidence": 0.9}, {"intervention": {"category": "CRISPR_KO", "raw_text": "CRISPR–Cas9 plasmid targeting mTOR", "target": {"name": "mTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": "human", "cell_type": null, "cell_lines": [], "genotype_context": null, "disease_context": null}, "readout": {"name": "matrix catabolism", "assay": null, "figure_refs": []}, "effect": {"direction": "decrease", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "induced autophagy and inhibited matrix catabolism", "notes": "Clause-aware split from supporting_quote (verb→direction + clean readout names)."}, "confidence": 0.9}, {"intervention": {"category": "KNOCKDOWN_RNAI", "raw_text": "siRNA targeting RAPTOR", "target": {"name": "mTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": "human", "cell_type": null, "cell_lines": [], "genotype_context": null, "disease_context": null}, "readout": {"name": "autophagy", "assay": null, "figure_refs": []}, "effect": {"direction": "increase", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all induced autophagy", "notes": "Expanded per multi-target 'all/each' statement."}, "confidence": 0.9}, {"intervention": {"category": "KNOCKDOWN_RNAI", "raw_text": "siRNA targeting RAPTOR", "target": {"name": "RAPTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": "human", "cell_type": null, "cell_lines": [], "genotype_context": null, "disease_context": null}, "readout": {"name": "autophagy", "assay": null, "figure_refs": []}, "effect": {"direction": "increase", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all induced autophagy", "notes": "Expanded per multi-target 'all/each' statement."}, "confidence": 0.9}, {"intervention": {"category": "KNOCKDOWN_RNAI", "raw_text": "siRNA targeting RAPTOR", "target": {"name": "RICTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": "human", "cell_type": null, "cell_lines": [], "genotype_context": null, "disease_context": null}, "readout": {"name": "autophagy", "assay": null, "figure_refs": []}, "effect": {"direction": "increase", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all induced autophagy", "notes": "Expanded per multi-target 'all/each' statement."}, "confidence": 0.9}, {"intervention": {"category": "KNOCKDOWN_RNAI", "raw_text": "siRNA targeting RAPTOR", "target": {"name": "RAPTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": "human", "cell_type": null, "cell_lines": [], "genotype_context": null, "disease_context": null}, "readout": {"name": "apoptosis", "assay": null, "figure_refs": []}, "effect": {"direction": "decrease", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "induced autophagy and inhibited apoptosis", "notes": "Clause-aware split from supporting_quote (verb→direction + clean readout names)."}, "confidence": 0.9}, {"intervention": {"category": "KNOCKDOWN_RNAI", "raw_text": "siRNA targeting RAPTOR", "target": {"name": "RAPTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": "human", "cell_type": null, "cell_lines": [], "genotype_context": null, "disease_context": null}, "readout": {"name": "senescence", "assay": null, "figure_refs": []}, "effect": {"direction": "decrease", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "induced autophagy and inhibited senescence", "notes": "Clause-aware split from supporting_quote (verb→direction + clean readout names)."}, "confidence": 0.9}, {"intervention": {"category": "KNOCKDOWN_RNAI", "raw_text": "siRNA targeting RAPTOR", "target": {"name": "RAPTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": "human", "cell_type": null, "cell_lines": [], "genotype_context": null, "disease_context": null}, "readout": {"name": "pyroptosis", "assay": null, "figure_refs": []}, "effect": {"direction": "decrease", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "induced autophagy and inhibited pyroptosis", "notes": "Clause-aware split from supporting_quote (verb→direction + clean readout names)."}, "confidence": 0.9}, {"intervention": {"category": "KNOCKDOWN_RNAI", "raw_text": "siRNA targeting RAPTOR", "target": {"name": "RAPTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": "human", "cell_type": null, "cell_lines": [], "genotype_context": null, "disease_context": null}, "readout": {"name": "matrix catabolism", "assay": null, "figure_refs": []}, "effect": {"direction": "decrease", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "induced autophagy and inhibited matrix catabolism", "notes": "Clause-aware split from supporting_quote (verb→direction + clean readout names)."}, "confidence": 0.9}, {"intervention": {"category": "KNOCKDOWN_RNAI", "raw_text": "siRNA targeting mTOR", "target": {"name": "mTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": "human", "cell_type": null, "cell_lines": [], "genotype_context": null, "disease_context": null}, "readout": {"name": "apoptosis", "assay": null, "figure_refs": []}, "effect": {"direction": "decrease", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "induced autophagy and inhibited apoptosis", "notes": "Clause-aware split from supporting_quote (verb→direction + clean readout names)."}, "confidence": 0.9}, {"intervention": {"category": "KNOCKDOWN_RNAI", "raw_text": "siRNA targeting mTOR", "target": {"name": "mTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": "human", "cell_type": null, "cell_lines": [], "genotype_context": null, "disease_context": null}, "readout": {"name": "senescence", "assay": null, "figure_refs": []}, "effect": {"direction": "decrease", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "induced autophagy and inhibited senescence", "notes": "Clause-aware split from supporting_quote (verb→direction + clean readout names)."}, "confidence": 0.9}, {"intervention": {"category": "KNOCKDOWN_RNAI", "raw_text": "siRNA targeting mTOR", "target": {"name": "mTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": "human", "cell_type": null, "cell_lines": [], "genotype_context": null, "disease_context": null}, "readout": {"name": "pyroptosis", "assay": null, "figure_refs": []}, "effect": {"direction": "decrease", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "induced autophagy and inhibited pyroptosis", "notes": "Clause-aware split from supporting_quote (verb→direction + clean readout names)."}, "confidence": 0.9}, {"intervention": {"category": "KNOCKDOWN_RNAI", "raw_text": "siRNA targeting mTOR", "target": {"name": "mTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": "human", "cell_type": null, "cell_lines": [], "genotype_context": null, "disease_context": null}, "readout": {"name": "matrix catabolism", "assay": null, "figure_refs": []}, "effect": {"direction": "decrease", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "induced autophagy and inhibited matrix catabolism", "notes": "Clause-aware split from supporting_quote (verb→direction + clean readout names)."}, "confidence": 0.9}], "warnings": ["The text describes delivering siRNA and plasmids but does not provide specific results on readouts for all of them."], "_routing": {"first_model": "gpt-4o-mini", "escalated": false, "final_model": "gpt-4o-mini", "reason": null}, "_post": {"dropped_atoms": 0, "clause_split": {"enabled": true, "events": 16, "expanded_atoms": 32, "atoms_after": 36}, "multi_target": {"enabled": true, "candidate_targets": ["mTOR", "RAPTOR", "RICTOR"], "events": 4, "expanded_atoms": 12, "deduped_atoms": 22}}}

* * *

**ChatGPT:**

You’re _very_ close — and thank you for sharing the full record. Also: I’m sorry I came off sharp earlier. I’m with you on learning this together, and I’ll keep the tone straightforward and respectful.

## What improved (this is good)

From your new output, the key fixes mostly worked:

* ✅ **“inhibited apoptosis …” now becomes** `readout="apoptosis"` + `direction="decrease"` (that’s correct)
* ✅ You’re getting clean readout names (`apoptosis`, `senescence`, `pyroptosis`, `matrix catabolism`)
* ✅ Directions for inhibited outcomes are now **decrease** (correct)

So the clause-aware logic is doing something real.

## What’s still wrong (and why it matters)

### 1) You are still missing the RICTOR “inhibited X” atoms

Right now you have **RICTOR only for autophagy**, but **not** for apoptosis/senescence/pyroptosis/matrix catabolism.

That’s why you end at **22 atoms**, not the expected **30**:

* 2 modalities (siRNA + CRISPR) × 3 targets (mTOR/RAPTOR/RICTOR) × 5 readouts = **30**
* You have the full 6 autophagy atoms (2×3), plus 16 inhibited-readout atoms (2 modalities × 2 targets × 4 readouts) = **22**
* Missing = 2 modalities × **1 target (RICTOR)** × 4 readouts = **8 atoms** → exactly what’s absent.

**Why it happens:**  
Your “inhibited apoptosis” atoms have `supporting_quote` like:

> “induced autophagy and inhibited apoptosis”

That quote **does not contain** the target list (“mTOR, RAPTOR, and RICTOR”), so your **multi-target expander can’t see that RICTOR is part of the ‘all’ statement**, and it never expands those atoms to include RICTOR.

### 2) Some atoms have an internal inconsistency (raw_text vs target)

Example:

* `raw_text`: “CRISPR–Cas9 plasmid targeting RAPTOR”
* but `target.name`: “mTOR” (or “RICTOR”)

This won’t necessarily break graph building (you should use `intervention.target.name` for nodes), but it **will confuse audits** and human review.

**Why it happens:**  
Your multi-target expansion is swapping `target.name` but leaving `raw_text` unchanged.

* * *

## The minimal fixes to make this “graph-ready”

You don’t need a redesign — just two surgical changes:

### Fix A — Don’t shrink the supporting_quote during clause-splitting

When you clause-split, **keep the original full sentence** as `supporting_quote`, and only change:

* `readout.name`
* `effect.direction`
* `evidence.notes`

That way, every split atom still carries:

> “Targeting mTOR, RAPTOR, and RICTOR all induced autophagy and inhibited apoptosis, …”

…and then the multi-target expansion will correctly add **RICTOR** for the inhibited readouts.

### Fix B — Expand targets before clause-splitting (recommended)

Pipeline order should be:

1. base extraction
2. post-filter
3. **multi-target expansion** (while the quote still contains the target list)
4. **clause/readout splitting**
5. dedupe + final cap

This avoids the big intermediate explosion and avoids losing the target context.

### Optional Fix C — Keep raw_text consistent with target

After multi-target expansion, if `raw_text` doesn’t mention the selected `target.name`, you can either:

* leave raw_text as-is but add a note like “target set by expansion,” **or**
* rewrite raw_text to a safe, text-derived prefix like “Targeting <target> …” based on the same supporting quote.

Not essential for the graph, but it makes your output far easier to trust/debug.

* * *

## Bottom line: are you ready to build the graph now?

**Almost**, but I’d fix this first.

If you graph it _as-is_, you will systematically **under-count RICTOR evidence** for apoptosis/senescence/pyroptosis/matrix catabolism — which is exactly the kind of silent bias that’s painful later.

Once Fix A (keep full supporting_quote) + Fix B (order) are in, this chunk should reliably yield the expected **30 atoms** without truncation, and then you’re in a much safer place to start graph construction.

If you paste just the `_post` section after your next run (events/expanded/deduped + any truncation warnings), I can sanity-check in one pass whether the pipeline is now behaving like “30 atoms expected → 30 atoms produced” for this sentence type.

* * *

**You:**

What do you want me to run exactly now?

* * *

**ChatGPT:**

Here’s exactly what I want you to run **now** — one clean “regenerate atoms” pass that fixes the specific problem you identified (losing the _“mTOR, RAPTOR, and RICTOR all …”_ context during clause-splitting).

### What you do now (2 commands)

1. **Save the script below** as:

**`C:\Users\Prem Subramaniam\Documents\Pathway AI\make_atoms_docaware_v8.py`**

2. Run it with bridging OFF (recommended while your chunks may be mixed/random):

```bat
conda activate pathai
cd "C:\Users\Prem Subramaniam\Documents\Pathway AI"
python make_atoms_docaware_v8.py --bridge off
```

### What to check immediately after

* In the console line for **chunk 2**, you should see `atoms=30` (or at least **no missing RICTOR inhibited readouts**).
* Then confirm RICTOR exists for inhibited readouts in chunk 2:

```bat
python make_atoms_docaware_v8.py --print-chunk 2
```

You should see entries where `target=RICTOR` with `readout=apoptosis/senescence/pyroptosis/matrix catabolism` and `direction=decrease`.

* * *

## Full script to save

**TAG: PATHAI-0050**  
Save as `make_atoms_docaware_v8.py`

```Python
import os
import json
import re
import argparse
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple
from copy import deepcopy
from openai import OpenAI

# ============================================================
# CONFIG
# ============================================================
INFILE = Path("mentions.jsonl")
OUTFILE = Path("atoms.jsonl")

MODEL_FAST = "gpt-4o-mini"
MODEL_STRONG = "gpt-4.1"

MAX_ATOMS_PER_CHUNK = 30

# ============================================================
# OPENAI CLIENT
# ============================================================
def _get_api_key() -> str:
    key = os.getenv("OPENAI_API_KEY")
    if not key:
        raise RuntimeError(
            "OPENAI_API_KEY is not set.\n"
            "Miniforge Prompt (temporary):  set OPENAI_API_KEY=YOUR_KEY\n"
            "Persistent (Windows):         setx OPENAI_API_KEY \"YOUR_KEY\"  (then reopen prompt)"
        )
    return key

client = OpenAI(api_key=_get_api_key())

# ============================================================
# JSON SCHEMA FOR ATOMS (model output)
# ============================================================
ATOM_SCHEMA_WRAPPER: Dict[str, Any] = {
    "name": "MechanisticAtoms",
    "schema": {
        "type": "object",
        "additionalProperties": False,
        "required": ["atoms", "warnings"],
        "properties": {
            "atoms": {
                "type": "array",
                "items": {
                    "type": "object",
                    "additionalProperties": False,
                    "required": [
                        "intervention",
                        "system",
                        "readout",
                        "effect",
                        "strength_cues",
                        "evidence",
                        "confidence",
                    ],
                    "properties": {
                        "intervention": {
                            "type": "object",
                            "additionalProperties": False,
                            "required": ["category", "raw_text", "target", "modality"],
                            "properties": {
                                "category": {
                                    "type": "string",
                                    "enum": [
                                        "GENETIC_KO",
                                        "CRISPR_KO",
                                        "CRISPRi",
                                        "CRISPRa",
                                        "KNOCKDOWN_RNAI",
                                        "SPLICING_MODULATION",
                                        "OVEREXPRESSION",
                                        "RESCUE_ADD_BACK",
                                        "DOMINANT_NEGATIVE",
                                        "MUTANT_VARIANT",
                                        "CHEMICAL_INHIBITOR",
                                        "CHEMICAL_ACTIVATOR",
                                        "CHEMICAL_DEGRADER",
                                        "STIMULUS_TREATMENT",
                                        "NEUTRALIZING_ANTIBODY",
                                        "UNKNOWN",
                                    ],
                                },
                                "raw_text": {"type": "string", "minLength": 1},
                                "target": {
                                    "anyOf": [
                                        {
                                            "type": "object",
                                            "additionalProperties": False,
                                            "required": ["name", "entity_type"],
                                            "properties": {
                                                "name": {"type": "string"},
                                                "entity_type": {
                                                    "type": "string",
                                                    "enum": [
                                                        "gene",
                                                        "protein",
                                                        "chemical",
                                                        "stimulus",
                                                        "antibody",
                                                        "unknown",
                                                    ],
                                                },
                                            },
                                        },
                                        {"type": "null"},
                                    ]
                                },
                                "modality": {
                                    "type": "string",
                                    "enum": [
                                        "LOF",
                                        "GOF",
                                        "INHIBITION",
                                        "ACTIVATION",
                                        "DEGRADATION",
                                        "RESCUE",
                                        "UNKNOWN",
                                    ],
                                },
                            },
                        },
                        "system": {
                            "type": "object",
                            "additionalProperties": False,
                            "required": [
                                "species",
                                "cell_type",
                                "cell_lines",
                                "genotype_context",
                                "disease_context",
                            ],
                            "properties": {
                                "species": {"type": ["string", "null"]},
                                "cell_type": {"type": ["string", "null"]},
                                "cell_lines": {"type": "array", "items": {"type": "string"}},
                                "genotype_context": {"type": ["string", "null"]},
                                "disease_context": {"type": ["string", "null"]},
                            },
                        },
                        "readout": {
                            "type": "object",
                            "additionalProperties": False,
                            "required": ["name", "assay", "figure_refs"],
                            "properties": {
                                "name": {"type": "string"},
                                "assay": {"type": ["string", "null"]},
                                "figure_refs": {"type": "array", "items": {"type": "string"}},
                            },
                        },
                        "effect": {
                            "type": "object",
                            "additionalProperties": False,
                            "required": ["direction", "timepoint", "magnitude", "comparison"],
                            "properties": {
                                "direction": {
                                    "type": "string",
                                    "enum": ["increase", "decrease", "no_change", "mixed", "unknown"],
                                },
                                "timepoint": {"type": ["string", "null"]},
                                "magnitude": {"type": ["string", "null"]},
                                "comparison": {"type": ["string", "null"]},
                            },
                        },
                        "strength_cues": {
                            "type": "object",
                            "additionalProperties": False,
                            "required": ["has_rescue", "has_control", "has_multiple_lines", "other"],
                            "properties": {
                                "has_rescue": {"type": "boolean"},
                                "has_control": {"type": "boolean"},
                                "has_multiple_lines": {"type": "boolean"},
                                "other": {"type": "array", "items": {"type": "string"}},
                            },
                        },
                        "evidence": {
                            "type": "object",
                            "additionalProperties": False,
                            "required": ["supporting_quote", "notes"],
                            "properties": {
                                "supporting_quote": {"type": "string"},
                                "notes": {"type": ["string", "null"]},
                            },
                        },
                        "confidence": {"type": "number", "minimum": 0, "maximum": 1},
                    },
                },
            },
            "warnings": {"type": "array", "items": {"type": "string"}},
        },
    },
}

# ============================================================
# UTIL: doc_id
# ============================================================
def build_doc_id(rec: Dict[str, Any]) -> Tuple[str, str]:
    pmid = rec.get("pmid")
    pmcid = rec.get("pmcid")
    doi = rec.get("doi")
    journal = rec.get("journal")
    volume = rec.get("volume")
    year = rec.get("year") or rec.get("date") or rec.get("pub_year")
    pages = rec.get("pages")
    source_file = rec.get("source_file") or rec.get("file") or rec.get("filename")

    if pmid:
        return f"PMID:{str(pmid).strip()}", "pmid"
    if pmcid:
        return f"PMCID:{str(pmcid).strip()}", "pmcid"
    if doi:
        return f"DOI:{str(doi).strip()}", "doi"
    if journal and volume and year and pages:
        jid = f"J:{str(journal).strip()}|V:{str(volume).strip()}|Y:{str(year).strip()}|P:{str(pages).strip()}"
        return jid, "journal_vol_year_pages"
    if source_file:
        return f"FILE:{Path(str(source_file)).name}", "file"
    return f"CHUNK:{rec.get('chunk_id')}", "chunk_fallback"

# ============================================================
# PROMPT
# ============================================================
SYSTEM_INSTRUCTIONS = (
    "Extract 'mechanistic atoms' from biomedical text.\n\n"
    "Definition: an atom MUST include an explicit effect on a readout.\n"
    "Format: [INTERVENTION] causes [EFFECT] in [READOUT] in a [SYSTEM].\n\n"
    "Hard rules:\n"
    "1) Do NOT invent facts.\n"
    "2) Do NOT assume knockdown succeeded unless the text explicitly says reduction/knockdown/confirmed.\n"
    "3) If the text says 'A, B, and C all did X', emit separate atoms for A, for B, and for C (do NOT pick one).\n"
    "4) If a sentence contains multiple readouts (e.g., 'induced autophagy and inhibited apoptosis, senescence...'), emit one atom per readout with correct direction.\n"
    "5) If the text only describes delivering siRNA/plasmid/drug but gives no stated change in any readout, output no atoms and add a warning.\n"
    f"6) Keep at most {MAX_ATOMS_PER_CHUNK} atoms.\n"
)

def compact_mentions(mentions: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    out = []
    for i, m in enumerate(mentions, start=1):
        out.append({
            "i": i,
            "category": m.get("category"),
            "raw_text": m.get("raw_text"),
            "target_guess": m.get("target_guess"),
            "method_cues": m.get("method_cues", []),
        })
    return out

def call_model(model: str, chunk_text: str, mentions: List[Dict[str, Any]]) -> Dict[str, Any]:
    payload = {
        "chunk_text": chunk_text,
        "mentions": compact_mentions(mentions),
    }
    resp = client.responses.create(
        model=model,
        input=[
            {"role": "system", "content": SYSTEM_INSTRUCTIONS},
            {"role": "user", "content": json.dumps(payload, ensure_ascii=False)},
        ],
        text={
            "format": {
                "type": "json_schema",
                "name": ATOM_SCHEMA_WRAPPER["name"],
                "strict": True,
                "schema": ATOM_SCHEMA_WRAPPER["schema"],
            }
        },
    )
    return json.loads(resp.output_text)

def should_escalate(mentions: List[Dict[str, Any]], atoms: List[Dict[str, Any]], warnings: List[str]) -> bool:
    if len(mentions) > 0 and len(atoms) == 0:
        return True
    if atoms:
        avg_conf = sum(a.get("confidence", 0) for a in atoms) / len(atoms)
        if avg_conf < 0.60:
            return True
    wtxt = " ".join(warnings).lower()
    if "no explicit" in wtxt and len(mentions) > 0:
        return True
    return False

def extract_atoms_with_routing(chunk_text: str, mentions: List[Dict[str, Any]]) -> Dict[str, Any]:
    routing = {"first_model": MODEL_FAST, "escalated": False, "final_model": MODEL_FAST, "reason": None}
    out_fast = call_model(MODEL_FAST, chunk_text, mentions)
    atoms_fast = out_fast.get("atoms", [])
    warnings_fast = out_fast.get("warnings", [])

    if should_escalate(mentions, atoms_fast, warnings_fast):
        routing["escalated"] = True
        routing["final_model"] = MODEL_STRONG
        routing["reason"] = {"type": "low_confidence_or_empty_or_warning", "details": "heuristics triggered"}
        out_strong = call_model(MODEL_STRONG, chunk_text, mentions)
        out_strong["_routing"] = routing
        return out_strong

    out_fast["_routing"] = routing
    return out_fast

# ============================================================
# POST-FILTER: explicit effect language in quote
# ============================================================
EFFECT_CUE = re.compile(
    r"\b("
    r"inhibit|inhibited|inhibition|suppress|suppressed|"
    r"reduce|reduced|reduces|reduction|decrease|decreased|decreases|"
    r"increase|increased|increases|elevate|elevated|"
    r"induce|induced|induces|promote|promoted|"
    r"no effect|did not affect|had no effect|"
    r"rescue|rescued|restored|restore|"
    r"abolish|abolished"
    r")\b",
    re.IGNORECASE,
)

def post_filter_atoms(atoms: List[Dict[str, Any]]) -> Tuple[List[Dict[str, Any]], int]:
    kept, dropped = [], 0
    for a in atoms:
        sq = ((a.get("evidence") or {}).get("supporting_quote") or "")
        if EFFECT_CUE.search(sq):
            kept.append(a)
        else:
            dropped += 1
    return kept, dropped

# ============================================================
# MULTI-TARGET expansion (Fix B enabler: do this BEFORE clause splitting)
# ============================================================
TARGET_LIST_PATTERNS = [
    re.compile(r"\b[Tt]argeting\s+([^.;:\n]+?)\s+\b(all|each|both)\b"),
    re.compile(r"\b([^.;:\n]+?)\s+\b(all|each|both)\b"),
]

def _tokenize_target_list(s: str) -> List[str]:
    s = s.strip()
    s = re.sub(r"\b(protein|gene|complex|pathway|signaling)\b", "", s, flags=re.IGNORECASE)
    # split on commas and and/or
    parts = re.split(r",|\band\b|\bor\b|/|;", s, flags=re.IGNORECASE)
    out = []
    for p in parts:
        t = p.strip()
        t = re.sub(r"[^A-Za-z0-9\-\_]+", "", t)
        if len(t) < 2:
            continue
        # reject obvious non-target words
        if t.lower() in {"targeting", "all", "each", "both", "cells", "cell"}:
            continue
        out.append(t)
    # unique preserve
    seen = set()
    uniq = []
    for x in out:
        k = x.lower()
        if k not in seen:
            seen.add(k)
            uniq.append(x)
    return uniq

def extract_candidate_targets(atom: Dict[str, Any]) -> Tuple[List[str], Optional[str]]:
    """
    Returns (targets, raw_text_override)
    raw_text_override is a text-derived phrase like 'Targeting A, B, and C' if found.
    """
    quote = ((atom.get("evidence") or {}).get("supporting_quote") or "")
    raw = ((atom.get("intervention") or {}).get("raw_text") or "")

    # Only expand if the quote strongly suggests per-target parallelism.
    if not re.search(r"\b(all|each|both)\b", quote, flags=re.IGNORECASE):
        return [], None

    for pat in TARGET_LIST_PATTERNS:
        m = pat.search(quote)
        if m:
            candidate = m.group(1)
            targets = _tokenize_target_list(candidate)
            if len(targets) >= 2:
                # If this was the 'Targeting ... all/each' pattern, make a nice raw_text override.
                if "targeting" in m.group(0).lower():
                    rt = "Targeting " + candidate.strip()
                else:
                    rt = None
                return targets, rt

    # fallback: try from raw_text if it contains targeting list
    m2 = re.search(r"\b[Tt]argeting\s+([^.;:\n]+)", raw)
    if m2:
        targets = _tokenize_target_list(m2.group(1))
        if len(targets) >= 2:
            return targets, raw

    return [], None

def expand_multi_target(atoms: List[Dict[str, Any]]) -> Tuple[List[Dict[str, Any]], Dict[str, Any]]:
    events = 0
    expanded = 0
    out: List[Dict[str, Any]] = []

    for a in atoms:
        targets, raw_override = extract_candidate_targets(a)
        if not targets:
            out.append(a)
            continue

        events += 1
        for t in targets:
            b = deepcopy(a)
            # set target name
            if b.get("intervention", {}).get("target") is None:
                b["intervention"]["target"] = {"name": t, "entity_type": "protein"}
            else:
                b["intervention"]["target"]["name"] = t

            # keep raw_text consistent and text-derived when possible
            if raw_override:
                b["intervention"]["raw_text"] = raw_override

            # annotate
            notes = (b.get("evidence", {}) or {}).get("notes")
            add = "Expanded per multi-target 'all/each' statement."
            b["evidence"]["notes"] = (notes + " " + add).strip() if notes else add

            out.append(b)
            expanded += 1

    return out, {"enabled": True, "events": events, "expanded_atoms": expanded, "candidate_targets_last": targets if atoms else []}

# ============================================================
# CLAUSE SPLITTING (Fix A: keep FULL supporting_quote)
# ============================================================
VERB_TO_DIR = {
    "inhibit": "decrease",
    "inhibited": "decrease",
    "suppress": "decrease",
    "suppressed": "decrease",
    "reduce": "decrease",
    "reduced": "decrease",
    "decrease": "decrease",
    "decreased": "decrease",
    "abolish": "decrease",
    "abolished": "decrease",
    "induce": "increase",
    "induced": "increase",
    "increase": "increase",
    "increased": "increase",
    "promote": "increase",
    "promoted": "increase",
    "enhance": "increase",
    "enhanced": "increase",
    "restore": "increase",
    "restored": "increase",
    "rescue": "increase",
    "rescued": "increase",
}

def _split_readout_list(s: str) -> List[str]:
    s = s.strip()
    # remove leading punctuation/connector words
    s = re.sub(r"^[\s,:;]+", "", s)
    s = re.sub(r"^(and|or)\s+", "", s, flags=re.IGNORECASE)
    # stop at parentheses-heavy trailing notes
    s = re.split(r"\(|;|\.|\n", s)[0]
    parts = re.split(r",|\band\b", s, flags=re.IGNORECASE)
    out = []
    for p in parts:
        t = p.strip()
        t = re.sub(r"\s+", " ", t)
        t = re.sub(r"^[\-\–\—]+", "", t).strip()
        if not t:
            continue
        # remove any lingering verb fragments
        t = re.sub(r"^(apoptosis|autophagy|senescence|pyroptosis|matrix catabolism)\b", r"\1", t, flags=re.IGNORECASE)
        # keep it short and clean
        out.append(t)
    # uniq preserve
    seen = set()
    uniq = []
    for x in out:
        k = x.lower()
        if k not in seen:
            seen.add(k)
            uniq.append(x)
    return uniq

def clause_split_atoms(atoms: List[Dict[str, Any]]) -> Tuple[List[Dict[str, Any]], Dict[str, Any]]:
    events = 0
    expanded = 0
    out: List[Dict[str, Any]] = []

    verb_pat = re.compile(r"\b(" + "|".join(map(re.escape, VERB_TO_DIR.keys())) + r")\b", re.IGNORECASE)

    for a in atoms:
        full_quote = ((a.get("evidence") or {}).get("supporting_quote") or "")
        if not full_quote:
            out.append(a)
            continue

        # Find verbs and clause segments
        matches = list(verb_pat.finditer(full_quote))
        if len(matches) == 0:
            out.append(a)
            continue

        # Heuristic: only attempt if quote likely contains multiple readouts (comma/and after a verb)
        if "," not in full_quote and " and " not in full_quote.lower():
            out.append(a)
            continue

        clauses: List[Tuple[str, str]] = []
        for i, m in enumerate(matches):
            v = m.group(1)
            start = m.end()
            end = matches[i + 1].start() if i + 1 < len(matches) else len(full_quote)
            span = full_quote[start:end]
            readouts = _split_readout_list(span)
            if readouts:
                clauses.append((v, ", ".join(readouts)))

        # if we couldn't produce anything useful, keep original
        if not clauses:
            out.append(a)
            continue

        # Build per-readout atoms
        new_atoms: List[Dict[str, Any]] = []
        for v, rolist in clauses:
            direction = VERB_TO_DIR.get(v.lower(), "unknown")
            for ro in _split_readout_list(rolist):
                b = deepcopy(a)

                # Fix: keep FULL supporting_quote (do not shrink it)
                b["evidence"]["supporting_quote"] = full_quote

                # Set readout name cleanly (no "inhibited apoptosis" strings)
                b["readout"]["name"] = ro

                # Set direction according to verb
                b["effect"]["direction"] = direction

                # Notes
                notes = (b.get("evidence", {}) or {}).get("notes")
                add = f"Clause-aware split (verb '{v}' -> {direction}, readout '{ro}')."
                b["evidence"]["notes"] = (notes + " " + add).strip() if notes else add

                new_atoms.append(b)

        # If splitting produced only 1 atom that looks identical, keep original to avoid churn
        if len(new_atoms) <= 1:
            out.append(a)
            continue

        events += 1
        expanded += len(new_atoms)
        out.extend(new_atoms)

    return out, {"enabled": True, "events": events, "expanded_atoms": expanded}

# ============================================================
# DEDUPE + CAP
# ============================================================
def atom_key(a: Dict[str, Any]) -> str:
    iv = a.get("intervention", {}) or {}
    tg = (iv.get("target") or {})
    sys = a.get("system", {}) or {}
    ro = a.get("readout", {}) or {}
    ef = a.get("effect", {}) or {}
    ev = a.get("evidence", {}) or {}
    return "|".join([
        (iv.get("category") or "").lower(),
        (iv.get("modality") or "").lower(),
        (iv.get("raw_text") or "").lower(),
        (tg.get("name") or "").lower(),
        (ro.get("name") or "").lower(),
        (ef.get("direction") or "").lower(),
        (";".join(sys.get("cell_lines", []) or [])).lower(),
        (sys.get("cell_type") or "").lower(),
        (sys.get("species") or "").lower(),
        (sys.get("disease_context") or "").lower(),
        (ev.get("supporting_quote") or "").lower(),
    ])

def dedupe_atoms(atoms: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    seen = set()
    out = []
    for a in atoms:
        k = atom_key(a)
        if k in seen:
            continue
        seen.add(k)
        out.append(a)
    return out

def cap_atoms(atoms: List[Dict[str, Any]], warnings: List[str]) -> Tuple[List[Dict[str, Any]], List[str]]:
    if len(atoms) <= MAX_ATOMS_PER_CHUNK:
        return atoms, warnings
    # deterministic: sort by confidence desc, then stable key
    atoms_sorted = sorted(atoms, key=lambda x: (-(x.get("confidence", 0) or 0), atom_key(x)))
    kept = atoms_sorted[:MAX_ATOMS_PER_CHUNK]
    warnings = list(warnings) + [f"Truncated atoms: {len(atoms)} -> {MAX_ATOMS_PER_CHUNK} due to MAX_ATOMS_PER_CHUNK."]
    return kept, warnings

# ============================================================
# MAIN PIPELINE PER CHUNK
# ============================================================
def process_record(rec: Dict[str, Any], bridge_enabled: bool) -> Dict[str, Any]:
    chunk_id = rec.get("chunk_id")
    chunk_index = rec.get("chunk_index")
    chunk_text = rec.get("chunk_text", "")
    mentions = rec.get("mentions", [])

    doc_id, doc_id_source = build_doc_id(rec)

    if "error" in rec:
        return {
            "doc_id": doc_id,
            "doc_id_source": doc_id_source,
            "pmid": rec.get("pmid"),
            "pmcid": rec.get("pmcid"),
            "chunk_index": chunk_index,
            "chunk_id": chunk_id,
            "atoms": [],
            "warnings": ["Skipped due to upstream error."],
            "bridge": {
                "enabled": bridge_enabled,
                "attempted": False,
                "used": False,
                "mode": None,
                "source_doc_ids": [doc_id],
                "source_chunk_ids": [chunk_id],
                "skipped_reason": "upstream_error",
            },
            "_routing": {"skipped": True},
            "_post": {"dropped_atoms": 0},
        }

    out = extract_atoms_with_routing(chunk_text, mentions)
    atoms = out.get("atoms", [])
    warnings = out.get("warnings", [])
    routing = out.get("_routing", {})

    # 1) filter assumed/no-effect atoms
    atoms, dropped = post_filter_atoms(atoms)

    # 2) multi-target expansion FIRST (so we don't lose target list context)
    atoms, mt_info = expand_multi_target(atoms)

    # 3) clause splitting SECOND, and keep full quote (critical fix)
    atoms, cs_info = clause_split_atoms(atoms)

    # 4) dedupe
    atoms = dedupe_atoms(atoms)

    # 5) cap
    atoms, warnings = cap_atoms(atoms, warnings)

    record_out = {
        "doc_id": doc_id,
        "doc_id_source": doc_id_source,
        "pmid": rec.get("pmid"),
        "pmcid": rec.get("pmcid"),
        "chunk_index": chunk_index,
        "chunk_id": chunk_id,
        "atoms": atoms,
        "warnings": warnings,
        "bridge": {
            "enabled": bridge_enabled,
            "attempted": False,
            "used": False,
            "mode": None,
            "source_doc_ids": [doc_id],
            "source_chunk_ids": [chunk_id],
            "skipped_reason": None if bridge_enabled else "bridge_off",
        },
        "_routing": routing,
        "_post": {
            "dropped_atoms": dropped,
            "multi_target": mt_info,
            "clause_split": cs_info,
        },
    }
    return record_out

# ============================================================
# CLI: print chunk helper
# ============================================================
def print_chunk_from_atoms(atoms_file: Path, chunk_id: int):
    if not atoms_file.exists():
        raise FileNotFoundError(f"Cannot find {atoms_file.resolve()}")
    for ln in atoms_file.read_text(encoding="utf-8", errors="ignore").splitlines():
        rec = json.loads(ln)
        if rec.get("chunk_id") == chunk_id:
            print(json.dumps(rec, indent=2, ensure_ascii=False))
            return
    print(f"chunk_id {chunk_id} not found in {atoms_file}")

# ============================================================
# DRIVER
# ============================================================
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--bridge", choices=["on", "off"], default="off", help="Bridging within-doc only (keep off for mixed chunks).")
    ap.add_argument("--print-chunk", type=int, default=None, help="Print a chunk from atoms.jsonl after generation.")
    args = ap.parse_args()

    bridge_enabled = (args.bridge == "on")

    if not INFILE.exists():
        raise FileNotFoundError(f"Cannot find {INFILE.resolve()}")

    records: List[Dict[str, Any]] = []
    for ln in INFILE.read_text(encoding="utf-8", errors="ignore").splitlines():
        if ln.strip():
            records.append(json.loads(ln))

    total_atoms = 0
    escalations = 0
    dropped_total = 0

    doc_src_counts: Dict[str, int] = {}

    with OUTFILE.open("w", encoding="utf-8") as fout:
        for rec in records:
            outrec = process_record(rec, bridge_enabled=bridge_enabled)

            # bookkeeping
            total_atoms += len(outrec.get("atoms", []))
            if (outrec.get("_routing") or {}).get("escalated"):
                escalations += 1
            dropped_total += int((outrec.get("_post") or {}).get("dropped_atoms", 0))

            src = outrec.get("doc_id_source", "unknown")
            doc_src_counts[src] = doc_src_counts.get(src, 0) + 1

            fout.write(json.dumps(outrec, ensure_ascii=False) + "\n")

            chunk_id = outrec.get("chunk_id")
            doc_id = outrec.get("doc_id")
            idx = outrec.get("chunk_index")
            print(
                f"chunk {chunk_id} doc_id={doc_id}({outrec.get('doc_id_source')}) "
                f"idx={idx} atoms={len(outrec.get('atoms', []))} "
                f"escalated={bool((outrec.get('_routing') or {}).get('escalated'))} "
                f"bridge_enabled={bridge_enabled} bridged={bool((outrec.get('bridge') or {}).get('used'))} "
                f"dropped={int((outrec.get('_post') or {}).get('dropped_atoms', 0))}"
            )

    print(f"Done. total_atoms={total_atoms}, escalations={escalations}, dropped_total={dropped_total}")
    print("doc_id sources: " + ", ".join([f"{k}={v}" for k, v in sorted(doc_src_counts.items())]))
    if not bridge_enabled:
        print("Note: bridging was OFF (recommended for mixed/random chunks).")

    if args.print_chunk is not None:
        print_chunk_from_atoms(OUTFILE, args.print_chunk)

if __name__ == "__main__":
    main()
```

* * *

### Why this is the “right run” now

This v8 script specifically fixes the problem you just hit:

* **Clause splitting no longer shrinks the quote** (so we don’t lose “mTOR, RAPTOR, and RICTOR all …”)
* **Multi-target expansion happens before clause splitting**, so RICTOR will correctly inherit the inhibited readouts

* * *

If you run `--print-chunk 2` and you **still** don’t see `RICTOR + apoptosis/senescence/pyroptosis/matrix catabolism (decrease)`, paste that printed chunk and I’ll adjust the multi-target detector (it’ll be a small regex tweak, not a redesign).

* * *

**You:**

We are on version 11 (v11) not v8.

* * *

**ChatGPT:**

You’re right — my bad. If you’re already at **v11**, we should **patch v11 → v12**, not jump back to v8.

**TAG: PATHAI-0051**

## What I want you to run now (exactly)

### 1) Make a copy of your current v11 script

In your PATHAI folder:

* Copy/rename:  
    `make_atoms_docaware_v11.py` → **`make_atoms_docaware_v12.py`**

### 2) Make **two specific edits** in v12 (these are the fixes we need)

These edits are _surgical_ — you’re not rewriting the pipeline, just preventing the “RICTOR got lost” bug.

#### Edit A — Clause-splitting must **keep the full original quote**

In your **clause-splitting** logic (whatever function name you used in v11, e.g., `clause_split_atoms()`):

* Capture the full original quote once, e.g. `full_quote = atom["evidence"]["supporting_quote"]`
* When you create split atoms (apoptosis, senescence, pyroptosis, etc.), **do not replace** `supporting_quote` with a shortened clause like `"induced autophagy and inhibited apoptosis"`.
* Instead, set every split atom’s `supporting_quote` to **the full original sentence** that still contains:  
    `"Targeting mTOR, RAPTOR, and RICTOR all induced autophagy and inhibited apoptosis, …"`

That single change is what allows multi-target expansion to “see” RICTOR for the inhibited readouts.

#### Edit B — Multi-target expansion must run **before** clause-splitting

In your per-chunk pipeline order in v11 (the section where you do post-filtering / expansions), make it:

1. model extraction
2. post-filter (drop assumed effects)
3. **multi-target expansion** (while the quote still has the target list)
4. **clause/readout splitting**
5. dedupe
6. cap to MAX_ATOMS_PER_CHUNK

If clause-splitting happens first, you end up with shortened quotes that no longer contain the “mTOR, RAPTOR, RICTOR all …” pattern — and you get exactly the missing RICTOR inhibited atoms you saw.

### 3) Run v12 with bridging OFF

```bat
conda activate pathai
cd "C:\Users\Prem Subramaniam\Documents\Pathway AI"
python make_atoms_docaware_v12.py --bridge off
```

## What success looks like (quick sanity checks)

### Console expectation

For **chunk 2**, you should now get **30 atoms** (or at minimum: RICTOR present for apoptosis/senescence/pyroptosis/matrix catabolism).

### Check chunk 2 contains RICTOR + inhibited readouts

If you have a “print chunk” option already in v11/v12, use it.

If not, use a one-liner to count and spot-check:

```bat
python -c "import json; 
r=[json.loads(l) for l in open('atoms.jsonl','r',encoding='utf-8')]; 
c=[x for x in r if x.get('chunk_id')==2][0]; 
print('atoms:',len(c.get('atoms',[])));
hits=[a for a in c.get('atoms',[]) if (a.get('intervention',{}).get('target') or {}).get('name')=='RICTOR' and (a.get('readout',{}).get('name') in ['apoptosis','senescence','pyroptosis','matrix catabolism'])];
print('RICTOR inhibited-readout atoms:',len(hits));
print([ (h['readout']['name'], h['effect']['direction']) for h in hits[:10] ])"
```

You want `RICTOR inhibited-readout atoms:` to be **≥ 4** (ideally 4 per modality if both siRNA and CRISPR are present and properly separated).

* * *

## If you want me to do it “with finality” (full script)

Paste your **current v11 script** (or just the parts that define: the per-chunk pipeline + multi-target expansion + clause splitting), and I’ll return a **complete v12 full script** in one shot, no guessing.

(Without seeing v11, I _can_ tell you exactly what to change, but I can’t responsibly output a “drop-in replacement” that matches your v11 structure and flags.)

* * *

**You:**

I told you must provide the exact full code for v12 for me to run.  No editing by me.

* * *

**ChatGPT:**

Got it. Here is a **single, complete, runnable v12 script** (no manual editing needed) that:

* keeps **bridging OFF by default** (and only ever bridges **within the same doc_id** when enabled)
* fixes your key bug: **clause splitting keeps the full original quote**, so multi-target expansion doesn’t lose “mTOR, RAPTOR, and RICTOR all…”
* expands **“A, B, and C all did X”** into **parallel atoms** (never picks one arbitrarily)
* splits **multi-readout** clauses like “induced autophagy and inhibited apoptosis, …” into one atom per readout with correct direction
* keeps outputs strict + auditable, and prints a clean console summary

**TAG: PATHAI-0052**  
Save as: `make_atoms_docaware_v12.py` (in your Pathway AI folder)

Then run:

```bat
conda activate pathai
cd "C:\Users\Prem Subramaniam\Documents\Pathway AI"
python make_atoms_docaware_v12.py --bridge off
```

Optional sanity check for chunk 2:

```bat
python make_atoms_docaware_v12.py --print-chunk 2
```

* * *

```Python
import os
import json
import re
import argparse
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple
from copy import deepcopy
from openai import OpenAI

# ============================================================
# CONFIG
# ============================================================
DEFAULT_INFILE = "mentions.jsonl"
DEFAULT_OUTFILE = "atoms.jsonl"

MODEL_FAST = "gpt-4o-mini"
MODEL_STRONG = "gpt-4.1"

MAX_ATOMS_PER_CHUNK = 30

TRY_BRIDGE_FORWARD = True
TRY_BRIDGE_BACKWARD = True

# ============================================================
# OPENAI CLIENT
# ============================================================
def _get_api_key() -> str:
    key = os.getenv("OPENAI_API_KEY")
    if not key:
        raise RuntimeError(
            "OPENAI_API_KEY is not set.\n"
            "Miniforge Prompt (temporary):  set OPENAI_API_KEY=YOUR_KEY\n"
            "Persistent (Windows):         setx OPENAI_API_KEY \"YOUR_KEY\"  (then reopen prompt)"
        )
    return key

client = OpenAI(api_key=_get_api_key())

# ============================================================
# STRICT JSON SCHEMA FOR ATOMS (model output)
# ============================================================
ATOM_SCHEMA_WRAPPER: Dict[str, Any] = {
    "name": "MechanisticAtoms",
    "schema": {
        "type": "object",
        "additionalProperties": False,
        "required": ["atoms", "warnings"],
        "properties": {
            "atoms": {
                "type": "array",
                "items": {
                    "type": "object",
                    "additionalProperties": False,
                    "required": [
                        "intervention",
                        "system",
                        "readout",
                        "effect",
                        "strength_cues",
                        "evidence",
                        "confidence",
                    ],
                    "properties": {
                        "intervention": {
                            "type": "object",
                            "additionalProperties": False,
                            "required": ["category", "raw_text", "target", "modality"],
                            "properties": {
                                "category": {
                                    "type": "string",
                                    "enum": [
                                        "GENETIC_KO",
                                        "CRISPR_KO",
                                        "CRISPRi",
                                        "CRISPRa",
                                        "KNOCKDOWN_RNAI",
                                        "SPLICING_MODULATION",
                                        "OVEREXPRESSION",
                                        "RESCUE_ADD_BACK",
                                        "DOMINANT_NEGATIVE",
                                        "MUTANT_VARIANT",
                                        "CHEMICAL_INHIBITOR",
                                        "CHEMICAL_ACTIVATOR",
                                        "CHEMICAL_DEGRADER",
                                        "STIMULUS_TREATMENT",
                                        "NEUTRALIZING_ANTIBODY",
                                        "UNKNOWN",
                                    ],
                                },
                                "raw_text": {"type": "string", "minLength": 1},
                                "target": {
                                    "anyOf": [
                                        {
                                            "type": "object",
                                            "additionalProperties": False,
                                            "required": ["name", "entity_type"],
                                            "properties": {
                                                "name": {"type": "string"},
                                                "entity_type": {
                                                    "type": "string",
                                                    "enum": [
                                                        "gene",
                                                        "protein",
                                                        "chemical",
                                                        "stimulus",
                                                        "antibody",
                                                        "unknown",
                                                    ],
                                                },
                                            },
                                        },
                                        {"type": "null"},
                                    ]
                                },
                                "modality": {
                                    "type": "string",
                                    "enum": [
                                        "LOF",
                                        "GOF",
                                        "INHIBITION",
                                        "ACTIVATION",
                                        "DEGRADATION",
                                        "RESCUE",
                                        "UNKNOWN",
                                    ],
                                },
                            },
                        },
                        "system": {
                            "type": "object",
                            "additionalProperties": False,
                            "required": [
                                "species",
                                "cell_type",
                                "cell_lines",
                                "genotype_context",
                                "disease_context",
                            ],
                            "properties": {
                                "species": {"type": ["string", "null"]},
                                "cell_type": {"type": ["string", "null"]},
                                "cell_lines": {"type": "array", "items": {"type": "string"}},
                                "genotype_context": {"type": ["string", "null"]},
                                "disease_context": {"type": ["string", "null"]},
                            },
                        },
                        "readout": {
                            "type": "object",
                            "additionalProperties": False,
                            "required": ["name", "assay", "figure_refs"],
                            "properties": {
                                "name": {"type": "string"},
                                "assay": {"type": ["string", "null"]},
                                "figure_refs": {"type": "array", "items": {"type": "string"}},
                            },
                        },
                        "effect": {
                            "type": "object",
                            "additionalProperties": False,
                            "required": ["direction", "timepoint", "magnitude", "comparison"],
                            "properties": {
                                "direction": {
                                    "type": "string",
                                    "enum": ["increase", "decrease", "no_change", "mixed", "unknown"],
                                },
                                "timepoint": {"type": ["string", "null"]},
                                "magnitude": {"type": ["string", "null"]},
                                "comparison": {"type": ["string", "null"]},
                            },
                        },
                        "strength_cues": {
                            "type": "object",
                            "additionalProperties": False,
                            "required": ["has_rescue", "has_control", "has_multiple_lines", "other"],
                            "properties": {
                                "has_rescue": {"type": "boolean"},
                                "has_control": {"type": "boolean"},
                                "has_multiple_lines": {"type": "boolean"},
                                "other": {"type": "array", "items": {"type": "string"}},
                            },
                        },
                        "evidence": {
                            "type": "object",
                            "additionalProperties": False,
                            "required": ["supporting_quote", "notes"],
                            "properties": {
                                "supporting_quote": {"type": "string"},
                                "notes": {"type": ["string", "null"]},
                            },
                        },
                        "confidence": {"type": "number", "minimum": 0, "maximum": 1},
                    },
                },
            },
            "warnings": {"type": "array", "items": {"type": "string"}},
        },
    },
}

# ============================================================
# DOC ID
# ============================================================
def build_doc_id(rec: Dict[str, Any]) -> Tuple[str, str]:
    """
    doc_id priority:
      1) PMID:<n>
      2) PMCID:<id>
      3) DOI:<doi>
      4) J:<journal>|V:<vol>|Y:<year>|P:<pages>
      5) FILE:<filename>
      6) CHUNK:<chunk_id>
    """
    pmid = rec.get("pmid")
    pmcid = rec.get("pmcid")
    doi = rec.get("doi")
    journal = rec.get("journal")
    volume = rec.get("volume")
    year = rec.get("year") or rec.get("pub_year")
    pages = rec.get("pages")
    source_file = rec.get("source_file") or rec.get("file") or rec.get("filename")

    if pmid:
        return f"PMID:{str(pmid).strip()}", "pmid"
    if pmcid:
        return f"PMCID:{str(pmcid).strip()}", "pmcid"
    if doi:
        return f"DOI:{str(doi).strip()}", "doi"
    if journal and volume and year and pages:
        jid = f"J:{str(journal).strip()}|V:{str(volume).strip()}|Y:{str(year).strip()}|P:{str(pages).strip()}"
        return jid, "journal_vol_year_pages"
    if source_file:
        return f"FILE:{Path(str(source_file)).name}", "file"
    return f"CHUNK:{rec.get('chunk_id')}", "chunk_fallback"

# ============================================================
# INPUT COMPACTION
# ============================================================
def compact_mentions(mentions: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    out = []
    for i, m in enumerate(mentions, start=1):
        out.append({
            "i": i,
            "category": m.get("category"),
            "raw_text": m.get("raw_text"),
            "target_guess": m.get("target_guess"),
            "method_cues": m.get("method_cues", []),
        })
    return out

# ============================================================
# PROMPT
# ============================================================
SYSTEM_INSTRUCTIONS = (
    "Extract 'mechanistic atoms' from biomedical text.\n\n"
    "Atom definition: an atom MUST include an explicit effect on a readout.\n"
    "Format: [INTERVENTION] causes [EFFECT] in [READOUT] in a [SYSTEM].\n\n"
    "Hard rules:\n"
    "1) Do NOT invent facts.\n"
    "2) Do NOT assume knockdown succeeded unless the text explicitly confirms reduction/knockdown.\n"
    "3) If text says 'A, B, and C all did X' (or 'each/both'), emit separate atoms for A, for B, and for C.\n"
    "4) If a sentence contains multiple readouts (e.g., 'induced autophagy and inhibited apoptosis, senescence...'), emit one atom per readout with correct direction.\n"
    "5) If text only describes delivering siRNA/plasmid/drug but gives no stated change in any readout, output no atoms and add a warning.\n"
    f"6) Keep at most {MAX_ATOMS_PER_CHUNK} atoms.\n"
)

def call_model(model: str, chunk_text: str, mentions: List[Dict[str, Any]]) -> Dict[str, Any]:
    payload = {"chunk_text": chunk_text, "mentions": compact_mentions(mentions)}
    resp = client.responses.create(
        model=model,
        input=[
            {"role": "system", "content": SYSTEM_INSTRUCTIONS},
            {"role": "user", "content": json.dumps(payload, ensure_ascii=False)},
        ],
        text={
            "format": {
                "type": "json_schema",
                "name": ATOM_SCHEMA_WRAPPER["name"],
                "strict": True,
                "schema": ATOM_SCHEMA_WRAPPER["schema"],
            }
        },
    )
    return json.loads(resp.output_text)

def should_escalate(mentions: List[Dict[str, Any]], atoms: List[Dict[str, Any]], warnings: List[str]) -> bool:
    if len(mentions) > 0 and len(atoms) == 0:
        return True
    if atoms:
        avg_conf = sum(float(a.get("confidence", 0) or 0) for a in atoms) / max(1, len(atoms))
        if avg_conf < 0.60:
            return True
    wtxt = " ".join(warnings).lower()
    if ("no explicit" in wtxt or "only describes" in wtxt) and len(mentions) > 0:
        return True
    return False

def extract_atoms_with_routing(chunk_text: str, mentions: List[Dict[str, Any]]) -> Dict[str, Any]:
    routing = {"first_model": MODEL_FAST, "escalated": False, "final_model": MODEL_FAST, "reason": None}
    out_fast = call_model(MODEL_FAST, chunk_text, mentions)
    atoms_fast = out_fast.get("atoms", [])
    warnings_fast = out_fast.get("warnings", [])

    if should_escalate(mentions, atoms_fast, warnings_fast):
        routing["escalated"] = True
        routing["final_model"] = MODEL_STRONG
        routing["reason"] = {"type": "low_confidence_or_empty_or_warning", "details": "heuristics triggered"}
        out_strong = call_model(MODEL_STRONG, chunk_text, mentions)
        out_strong["_routing"] = routing
        return out_strong

    out_fast["_routing"] = routing
    return out_fast

# ============================================================
# POST-FILTER: require explicit effect cue in quote
# ============================================================
EFFECT_CUE = re.compile(
    r"\b("
    r"inhibit|inhibited|inhibition|suppress|suppressed|"
    r"reduce|reduced|reduces|reduction|decrease|decreased|decreases|"
    r"increase|increased|increases|elevate|elevated|"
    r"induce|induced|induces|promote|promoted|enhance|enhanced|"
    r"no effect|did not affect|had no effect|did not change|unchanged|"
    r"rescue|rescued|restore|restored|"
    r"abolish|abolished"
    r")\b",
    re.IGNORECASE,
)

def post_filter_atoms(atoms: List[Dict[str, Any]]) -> Tuple[List[Dict[str, Any]], int]:
    kept = []
    dropped = 0
    for a in atoms:
        sq = ((a.get("evidence") or {}).get("supporting_quote") or "")
        if EFFECT_CUE.search(sq):
            kept.append(a)
        else:
            dropped += 1
    return kept, dropped

# ============================================================
# SETUP-ONLY DETECTION (for bridging trigger only)
# ============================================================
SETUP_READOUT_RE = re.compile(
    r"\b(protein expression|mrna|expression|knockdown|silencing|transfection efficiency|target protein)\b",
    re.IGNORECASE,
)

def looks_setup_only(atoms: List[Dict[str, Any]], warnings: List[str]) -> bool:
    if not atoms:
        return True
    wtxt = " ".join(warnings).lower()
    if "no explicit functional" in wtxt:
        return True
    for a in atoms:
        ro = ((a.get("readout") or {}).get("name") or "")
        if not SETUP_READOUT_RE.search(ro):
            return False
    return True

# ============================================================
# MULTI-TARGET EXPANSION (runs BEFORE clause splitting)
# ============================================================
ALL_EACH_RE = re.compile(r"\b(all|each|both)\b", re.IGNORECASE)

TARGETING_LIST_RE = re.compile(
    r"\b[Tt]argeting\s+([^.;:\n]+?)\s+\b(all|each|both)\b",
    re.IGNORECASE,
)

def _tokenize_targets(s: str) -> List[str]:
    s = s.strip()
    # remove common filler terms
    s = re.sub(r"\b(protein|gene|complex|pathway|signaling|levels?)\b", "", s, flags=re.IGNORECASE)
    # split on commas, and/or, slash
    parts = re.split(r",|\band\b|\bor\b|/|;", s, flags=re.IGNORECASE)
    out = []
    for p in parts:
        t = p.strip()
        t = re.sub(r"[^A-Za-z0-9\-\_]+", "", t)
        if len(t) < 2:
            continue
        if t.lower() in {"targeting", "all", "each", "both", "cells", "cell"}:
            continue
        out.append(t)
    # unique preserve
    seen = set()
    uniq = []
    for x in out:
        k = x.lower()
        if k not in seen:
            seen.add(k)
            uniq.append(x)
    return uniq

def extract_targets_from_quote(quote: str) -> Tuple[List[str], Optional[str]]:
    """
    Returns (targets, raw_text_override).
    raw_text_override is a safe phrase derived from the quote.
    """
    if not ALL_EACH_RE.search(quote):
        return [], None

    m = TARGETING_LIST_RE.search(quote)
    if m:
        candidate = m.group(1)
        targets = _tokenize_targets(candidate)
        if len(targets) >= 2:
            return targets, f"Targeting {candidate.strip()}"

    # fallback: sometimes quote has "mTOR, RAPTOR, and RICTOR all ..."
    m2 = re.search(r"\b([A-Za-z0-9\-\_]+(?:\s*,\s*[A-Za-z0-9\-\_]+)+(?:\s*,?\s*and\s*[A-Za-z0-9\-\_]+)?)\s+\ball\b",
                   quote, flags=re.IGNORECASE)
    if m2:
        targets = _tokenize_targets(m2.group(1))
        if len(targets) >= 2:
            return targets, None

    return [], None

def expand_multi_target(atoms: List[Dict[str, Any]]) -> Tuple[List[Dict[str, Any]], Dict[str, Any]]:
    events = 0
    expanded = 0
    out: List[Dict[str, Any]] = []

    for a in atoms:
        quote = ((a.get("evidence") or {}).get("supporting_quote") or "")
        targets, raw_override = extract_targets_from_quote(quote)
        if not targets:
            out.append(a)
            continue

        events += 1
        for t in targets:
            b = deepcopy(a)

            # set target
            if b.get("intervention", {}).get("target") is None:
                b["intervention"]["target"] = {"name": t, "entity_type": "protein"}
            else:
                b["intervention"]["target"]["name"] = t

            # keep raw_text consistent (only if derived from quote)
            if raw_override:
                b["intervention"]["raw_text"] = raw_override

            # annotate
            notes = (b.get("evidence", {}) or {}).get("notes")
            add = "Expanded per multi-target 'all/each/both' statement."
            b["evidence"]["notes"] = (notes + " " + add).strip() if notes else add

            out.append(b)
            expanded += 1

    return out, {"enabled": True, "events": events, "expanded_atoms": expanded}

# ============================================================
# CLAUSE / MULTI-READOUT SPLITTING (keeps FULL quote)
# ============================================================
# Multiword patterns FIRST
_VERB_PATTERNS = [
    ("had no effect", "no_change"),
    ("no effect", "no_change"),
    ("did not affect", "no_change"),
    ("did not change", "no_change"),
    ("unchanged", "no_change"),
    ("inhibited", "decrease"),
    ("inhibit", "decrease"),
    ("suppressed", "decrease"),
    ("suppress", "decrease"),
    ("reduced", "decrease"),
    ("reduce", "decrease"),
    ("decreased", "decrease"),
    ("decrease", "decrease"),
    ("abolished", "decrease"),
    ("abolish", "decrease"),
    ("induced", "increase"),
    ("induce", "increase"),
    ("increased", "increase"),
    ("increase", "increase"),
    ("promoted", "increase"),
    ("promote", "increase"),
    ("enhanced", "increase"),
    ("enhance", "increase"),
    ("restored", "increase"),
    ("restore", "increase"),
    ("rescued", "increase"),
    ("rescue", "increase"),
]

# Compile regex to find any verb pattern
_VERB_REGEX = re.compile(
    r"\b(" + "|".join(re.escape(v) for v, _ in sorted(_VERB_PATTERNS, key=lambda x: -len(x[0]))) + r")\b",
    re.IGNORECASE,
)

def _verb_to_dir(v: str) -> str:
    vl = v.lower()
    for pat, d in _VERB_PATTERNS:
        if vl == pat:
            return d
    # fallback
    if "no effect" in vl or "did not" in vl or "unchanged" in vl:
        return "no_change"
    return "unknown"

_STOP_CLAUSE_RE = re.compile(
    r"\b(with|whereas|however|but|although|while|when|which|that)\b",
    re.IGNORECASE,
)

def _clean_readout_item(x: str) -> str:
    x = x.strip()
    x = re.sub(r"^[\s,:;]+", "", x)
    x = re.sub(r"^(on|of|to)\s+", "", x, flags=re.IGNORECASE)
    x = re.sub(r"\s+", " ", x).strip()
    # drop trailing junk
    x = re.sub(r"[)\].,;:]+$", "", x).strip()
    return x

def _split_readouts(span: str) -> List[str]:
    # cut off at common clause transitions
    span = _STOP_CLAUSE_RE.split(span)[0]
    span = span.split("(")[0]
    span = span.split(".")[0]
    span = span.strip()

    # normalize connectors
    span = re.sub(r"\s+", " ", span)
    span = re.sub(r"^\s*(and|or)\s+", "", span, flags=re.IGNORECASE)

    # split list
    parts = re.split(r",|\band\b", span, flags=re.IGNORECASE)
    out = []
    for p in parts:
        t = _clean_readout_item(p)
        if not t:
            continue
        # remove accidental leading verb carryover
        t = re.sub(r"^(inhibit(ed)?|suppress(ed)?|reduce(d)?|decrease(d)?|induce(d)?|increase(d)?|promote(d)?|enhance(d)?|restore(d)?|rescue(d)?)\s+",
                   "", t, flags=re.IGNORECASE).strip()
        t = _clean_readout_item(t)
        if t:
            out.append(t)

    # unique preserve
    seen = set()
    uniq = []
    for x in out:
        k = x.lower()
        if k not in seen:
            seen.add(k)
            uniq.append(x)
    return uniq

def clause_split_atoms(atoms: List[Dict[str, Any]]) -> Tuple[List[Dict[str, Any]], Dict[str, Any]]:
    events = 0
    expanded = 0
    out: List[Dict[str, Any]] = []

    for a in atoms:
        full_quote = ((a.get("evidence") or {}).get("supporting_quote") or "")
        if not full_quote:
            out.append(a)
            continue

        matches = list(_VERB_REGEX.finditer(full_quote))
        if not matches:
            out.append(a)
            continue

        # Only split if it looks like multi-readout content
        if ("," not in full_quote) and (" and " not in full_quote.lower()):
            out.append(a)
            continue

        new_atoms: List[Dict[str, Any]] = []

        for i, m in enumerate(matches):
            verb = m.group(1)
            direction = _verb_to_dir(verb)

            start = m.end()
            end = matches[i + 1].start() if i + 1 < len(matches) else len(full_quote)
            span = full_quote[start:end]
            readouts = _split_readouts(span)

            if not readouts:
                continue

            for ro in readouts:
                b = deepcopy(a)

                # CRITICAL FIX: keep FULL quote; do NOT shrink it
                b["evidence"]["supporting_quote"] = full_quote

                # set clean readout name
                b["readout"]["name"] = ro

                # set direction per verb
                b["effect"]["direction"] = direction

                notes = (b.get("evidence", {}) or {}).get("notes")
                add = f"Clause-split (verb '{verb}' -> {direction}, readout '{ro}')."
                b["evidence"]["notes"] = (notes + " " + add).strip() if notes else add

                new_atoms.append(b)

        # If splitting didn't produce a meaningful expansion, keep original
        if len(new_atoms) <= 1:
            out.append(a)
            continue

        events += 1
        expanded += len(new_atoms)
        out.extend(new_atoms)

    return out, {"enabled": True, "events": events, "expanded_atoms": expanded}

# ============================================================
# DEDUPE + CAP
# ============================================================
def atom_key(a: Dict[str, Any]) -> str:
    iv = a.get("intervention", {}) or {}
    tg = (iv.get("target") or {})
    sys = a.get("system", {}) or {}
    ro = a.get("readout", {}) or {}
    ef = a.get("effect", {}) or {}
    ev = a.get("evidence", {}) or {}
    return "|".join([
        (iv.get("category") or "").lower(),
        (iv.get("modality") or "").lower(),
        (tg.get("name") or "").lower(),
        (ro.get("name") or "").lower(),
        (ef.get("direction") or "").lower(),
        (sys.get("species") or "").lower(),
        (sys.get("cell_type") or "").lower(),
        (";".join(sys.get("cell_lines", []) or [])).lower(),
        (sys.get("disease_context") or "").lower(),
        (ev.get("supporting_quote") or "").lower(),
    ])

def dedupe_atoms(atoms: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    seen = set()
    out = []
    for a in atoms:
        k = atom_key(a)
        if k in seen:
            continue
        seen.add(k)
        out.append(a)
    return out

def cap_atoms(atoms: List[Dict[str, Any]], warnings: List[str]) -> Tuple[List[Dict[str, Any]], List[str]]:
    if len(atoms) <= MAX_ATOMS_PER_CHUNK:
        return atoms, warnings
    atoms_sorted = sorted(atoms, key=lambda x: (-(float(x.get("confidence", 0) or 0)), atom_key(x)))
    kept = atoms_sorted[:MAX_ATOMS_PER_CHUNK]
    warnings = list(warnings) + [f"Truncated atoms: {len(atoms)} -> {MAX_ATOMS_PER_CHUNK} due to MAX_ATOMS_PER_CHUNK."]
    return kept, warnings

# ============================================================
# BRIDGING (DOC-AWARE ONLY)
# ============================================================
def merge_text(a: str, b: str) -> str:
    return a.rstrip() + "\n\n" + b.lstrip()

def merge_mentions(a: List[Dict[str, Any]], b: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    return list(a) + list(b)

def choose_best_candidate(cands: List[Tuple[str, Dict[str, Any], List[int]]]) -> Optional[Tuple[str, Dict[str, Any], List[int]]]:
    best = None
    for mode, outd, src_chunks in cands:
        atoms = outd.get("atoms", [])
        if best is None:
            best = (mode, outd, src_chunks)
            continue
        best_atoms = best[1].get("atoms", [])
        if len(atoms) > len(best_atoms):
            best = (mode, outd, src_chunks)
        elif len(atoms) == len(best_atoms) and len(atoms) > 0:
            avg = sum(float(a.get("confidence", 0) or 0) for a in atoms) / len(atoms)
            bavg = sum(float(a.get("confidence", 0) or 0) for a in best_atoms) / len(best_atoms)
            if avg > bavg:
                best = (mode, outd, src_chunks)
    return best

def run_full_post_pipeline(out: Dict[str, Any]) -> Tuple[List[Dict[str, Any]], List[str], Dict[str, Any]]:
    atoms = out.get("atoms", [])
    warnings = out.get("warnings", [])
    atoms, dropped = post_filter_atoms(atoms)

    atoms, mt_info = expand_multi_target(atoms)
    atoms, cs_info = clause_split_atoms(atoms)

    atoms = dedupe_atoms(atoms)
    atoms, warnings = cap_atoms(atoms, warnings)

    post = {"dropped_atoms": dropped, "multi_target": mt_info, "clause_split": cs_info}
    return atoms, warnings, post

# ============================================================
# PROCESS ONE RECORD
# ============================================================
def process_record(
    rec: Dict[str, Any],
    doc_id: str,
    doc_id_source: str,
    bridge_enabled: bool,
    neighbor_prev: Optional[Dict[str, Any]],
    neighbor_next: Optional[Dict[str, Any]],
) -> Dict[str, Any]:
    chunk_id = rec.get("chunk_id")
    chunk_index = rec.get("chunk_index")
    chunk_text = rec.get("chunk_text", "")
    mentions = rec.get("mentions", [])

    if "error" in rec:
        return {
            "doc_id": doc_id,
            "doc_id_source": doc_id_source,
            "pmid": rec.get("pmid"),
            "pmcid": rec.get("pmcid"),
            "chunk_index": chunk_index,
            "chunk_id": chunk_id,
            "atoms": [],
            "warnings": ["Skipped due to upstream error."],
            "bridge": {
                "enabled": bridge_enabled,
                "attempted": False,
                "used": False,
                "mode": None,
                "source_doc_ids": [doc_id],
                "source_chunk_ids": [chunk_id],
                "skipped_reason": "upstream_error",
            },
            "_routing": {"skipped": True},
            "_post": {"dropped_atoms": 0},
        }

    # base extract
    out = extract_atoms_with_routing(chunk_text, mentions)
    routing = out.get("_routing", {})
    atoms, warnings, post = run_full_post_pipeline(out)

    bridge_meta = {
        "enabled": bridge_enabled,
        "attempted": False,
        "used": False,
        "mode": None,
        "source_doc_ids": [doc_id],
        "source_chunk_ids": [chunk_id],
        "skipped_reason": None,
    }

    # bridging trigger (only if enabled)
    if bridge_enabled and len(mentions) > 0 and (len(atoms) == 0 or looks_setup_only(atoms, warnings)):
        bridge_meta["attempted"] = True
        cands: List[Tuple[str, Dict[str, Any], List[int]]] = []

        # forward within doc
        if TRY_BRIDGE_FORWARD and neighbor_next is not None:
            t = merge_text(chunk_text, neighbor_next.get("chunk_text", ""))
            m = merge_mentions(mentions, neighbor_next.get("mentions", []))
            bout = extract_atoms_with_routing(t, m)
            batoms, bwarns, bpost = run_full_post_pipeline(bout)
            bout["atoms"] = batoms
            bout["warnings"] = bwarns
            bout["_post"] = bpost
            cands.append(("forward", bout, [chunk_id, neighbor_next.get("chunk_id")]))

        # backward within doc
        if TRY_BRIDGE_BACKWARD and neighbor_prev is not None:
            t = merge_text(neighbor_prev.get("chunk_text", ""), chunk_text)
            m = merge_mentions(neighbor_prev.get("mentions", []), mentions)
            bout = extract_atoms_with_routing(t, m)
            batoms, bwarns, bpost = run_full_post_pipeline(bout)
            bout["atoms"] = batoms
            bout["warnings"] = bwarns
            bout["_post"] = bpost
            cands.append(("backward", bout, [neighbor_prev.get("chunk_id"), chunk_id]))

        best = choose_best_candidate(cands)
        if best is not None and len(best[1].get("atoms", [])) > 0:
            # accept if it improves atom count OR replaces setup-only
            if (len(best[1].get("atoms", [])) > len(atoms)) or looks_setup_only(atoms, warnings):
                bridge_meta["used"] = True
                bridge_meta["mode"] = best[0]
                bridge_meta["source_chunk_ids"] = best[2]
                out_best = best[1]
                atoms = out_best.get("atoms", [])
                warnings = out_best.get("warnings", [])
                post = out_best.get("_post", post)
                routing = out_best.get("_routing", routing)
        if not bridge_meta["used"]:
            bridge_meta["skipped_reason"] = "no_better_candidate"
    elif not bridge_enabled:
        bridge_meta["skipped_reason"] = "bridge_off"

    return {
        "doc_id": doc_id,
        "doc_id_source": doc_id_source,
        "pmid": rec.get("pmid"),
        "pmcid": rec.get("pmcid"),
        "chunk_index": chunk_index,
        "chunk_id": chunk_id,
        "atoms": atoms,
        "warnings": warnings,
        "bridge": bridge_meta,
        "_routing": routing,
        "_post": post,
    }

# ============================================================
# HELPERS: read/write + doc-aware adjacency
# ============================================================
def read_jsonl(path: Path) -> List[Dict[str, Any]]:
    recs: List[Dict[str, Any]] = []
    for ln in path.read_text(encoding="utf-8", errors="ignore").splitlines():
        if ln.strip():
            recs.append(json.loads(ln))
    return recs

def make_doc_groups(records: List[Dict[str, Any]]) -> Tuple[List[str], List[str], Dict[str, List[int]]]:
    doc_ids: List[str] = []
    doc_srcs: List[str] = []
    groups: Dict[str, List[int]] = {}
    for i, r in enumerate(records):
        doc_id, src = build_doc_id(r)
        doc_ids.append(doc_id)
        doc_srcs.append(src)
        groups.setdefault(doc_id, []).append(i)
    return doc_ids, doc_srcs, groups

def sort_doc_group(records: List[Dict[str, Any]], idxs: List[int]) -> List[int]:
    # Prefer chunk_index if present; else preserve file order
    def key(i: int) -> Tuple[int, int]:
        ci = records[i].get("chunk_index")
        if ci is None:
            return (1, i)
        try:
            return (0, int(ci))
        except Exception:
            return (0, i)
    return sorted(idxs, key=key)

def print_chunk_from_atoms(atoms_file: Path, chunk_id: int):
    for ln in atoms_file.read_text(encoding="utf-8", errors="ignore").splitlines():
        rec = json.loads(ln)
        if rec.get("chunk_id") == chunk_id:
            print(json.dumps(rec, indent=2, ensure_ascii=False))
            return
    print(f"chunk_id {chunk_id} not found in {atoms_file}")

# ============================================================
# MAIN
# ============================================================
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--infile", default=DEFAULT_INFILE)
    ap.add_argument("--outfile", default=DEFAULT_OUTFILE)
    ap.add_argument("--bridge", choices=["on", "off"], default="off",
                    help="Bridging is doc-aware only. Keep OFF for mixed/random chunks across papers.")
    ap.add_argument("--print-chunk", type=int, default=None, help="Print a chunk record from atoms.jsonl after run.")
    args = ap.parse_args()

    infile = Path(args.infile)
    outfile = Path(args.outfile)
    bridge_enabled = (args.bridge == "on")

    if not infile.exists():
        raise FileNotFoundError(f"Cannot find {infile.resolve()}")

    records = read_jsonl(infile)
    doc_ids, doc_srcs, groups = make_doc_groups(records)

    # Precompute doc-aware ordering to define adjacency within doc
    doc_order_map: Dict[str, List[int]] = {doc: sort_doc_group(records, idxs) for doc, idxs in groups.items()}
    pos_in_doc: Dict[int, int] = {}
    for doc, order in doc_order_map.items():
        for p, gi in enumerate(order):
            pos_in_doc[gi] = p

    total_atoms = 0
    escalations = 0
    bridges_attempted = 0
    bridges_used = 0
    dropped_total = 0
    doc_src_counts: Dict[str, int] = {}

    with outfile.open("w", encoding="utf-8") as fout:
        for gi, rec in enumerate(records):
            doc_id = doc_ids[gi]
            doc_src = doc_srcs[gi]
            doc_src_counts[doc_src] = doc_src_counts.get(doc_src, 0) + 1

            # doc-aware neighbors
            order = doc_order_map[doc_id]
            p = pos_in_doc[gi]
            prev_rec = records[order[p - 1]] if (p - 1 >= 0) else None
            next_rec = records[order[p + 1]] if (p + 1 < len(order)) else None

            outrec = process_record(
                rec=rec,
                doc_id=doc_id,
                doc_id_source=doc_src,
                bridge_enabled=bridge_enabled,
                neighbor_prev=prev_rec,
                neighbor_next=next_rec,
            )

            # bookkeeping
            atoms_here = outrec.get("atoms", []) or []
            total_atoms += len(atoms_here)

            if (outrec.get("_routing") or {}).get("escalated"):
                escalations += 1

            dropped_total += int((outrec.get("_post") or {}).get("dropped_atoms", 0))

            b = outrec.get("bridge") or {}
            if b.get("attempted"):
                bridges_attempted += 1
            if b.get("used"):
                bridges_used += 1

            fout.write(json.dumps(outrec, ensure_ascii=False) + "\n")

            print(
                f"chunk {outrec.get('chunk_id')} doc_id={outrec.get('doc_id')}({outrec.get('doc_id_source')}) "
                f"idx={outrec.get('chunk_index')} atoms={len(atoms_here)} "
                f"escalated={bool((outrec.get('_routing') or {}).get('escalated'))} "
                f"bridge_enabled={bridge_enabled} bridged={bool((outrec.get('bridge') or {}).get('used'))} "
                f"dropped={int((outrec.get('_post') or {}).get('dropped_atoms', 0))}"
            )

    print(f"Done. total_atoms={total_atoms}, escalations={escalations}, "
          f"bridges_attempted={bridges_attempted}, bridges_used={bridges_used}, dropped_total={dropped_total}")
    print("doc_id sources: " + ", ".join([f"{k}={v}" for k, v in sorted(doc_src_counts.items())]))
    if not bridge_enabled:
        print("Note: bridging was OFF (recommended for mixed/random chunks).")

    if args.print_chunk is not None:
        print_chunk_from_atoms(outfile, args.print_chunk)

if __name__ == "__main__":
    main()
```

* * *

### What I want you to paste back (so we can confirm it’s fixed)

After running v12 with bridging off, paste **just the chunk 2 atoms summary** (either the console line for chunk 2, or the output of `--print-chunk 2`).

The key thing I’m checking: **do you now get RICTOR atoms for the inhibited readouts (apoptosis/senescence/pyroptosis/matrix catabolism) with direction=decrease**, and do you avoid truncation for this chunk.

* * *

**You:**

chunk 2 doc_id=PMID:39682777(pmid) idx=None atoms=14 escalated=False bridge_enabled=False bridged=False dropped=0  {"doc_id": "PMID:39682777", "doc_id_source": "pmid", "pmid": "39682777", "pmcid": null, "chunk_index": null, "chunk_id": 2, "atoms": [{"intervention": {"category": "CRISPR_KO", "raw_text": "Targeting mTOR, RAPTOR, and RICTOR", "target": {"name": "mTOR", "entity_type": "protein"}, "modality": "GOF"}, "system": {"species": "mammal", "cell_type": "human disk nucleus pulposus cells", "cell_lines": ["human disk nucleus pulposus cells"], "genotype_context": null, "disease_context": "degenerative disk disease"}, "readout": {"name": "autophagy", "assay": null, "figure_refs": []}, "effect": {"direction": "increase", "timepoint": "24h", "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all induced autophagy", "notes": "Expanded per multi-target 'all/each/both' statement."}, "confidence": 0.9}, {"intervention": {"category": "CRISPR_KO", "raw_text": "Targeting mTOR, RAPTOR, and RICTOR", "target": {"name": "RAPTOR", "entity_type": "protein"}, "modality": "GOF"}, "system": {"species": "mammal", "cell_type": "human disk nucleus pulposus cells", "cell_lines": ["human disk nucleus pulposus cells"], "genotype_context": null, "disease_context": "degenerative disk disease"}, "readout": {"name": "autophagy", "assay": null, "figure_refs": []}, "effect": {"direction": "increase", "timepoint": "24h", "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all induced autophagy", "notes": "Expanded per multi-target 'all/each/both' statement."}, "confidence": 0.9}, {"intervention": {"category": "CRISPR_KO", "raw_text": "Targeting mTOR, RAPTOR, and RICTOR", "target": {"name": "RICTOR", "entity_type": "protein"}, "modality": "GOF"}, "system": {"species": "mammal", "cell_type": "human disk nucleus pulposus cells", "cell_lines": ["human disk nucleus pulposus cells"], "genotype_context": null, "disease_context": "degenerative disk disease"}, "readout": {"name": "autophagy", "assay": null, "figure_refs": []}, "effect": {"direction": "increase", "timepoint": "24h", "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all induced autophagy", "notes": "Expanded per multi-target 'all/each/both' statement."}, "confidence": 0.9}, {"intervention": {"category": "CRISPR_KO", "raw_text": "CRISPR–Cas9 plasmid targeting mTOR, RAPTOR, or RICTOR", "target": {"name": "RAPTOR", "entity_type": "protein"}, "modality": "GOF"}, "system": {"species": "mammal", "cell_type": "human disk nucleus pulposus cells", "cell_lines": ["human disk nucleus pulposus cells"], "genotype_context": null, "disease_context": "degenerative disk disease"}, "readout": {"name": "apoptosis", "assay": null, "figure_refs": []}, "effect": {"direction": "decrease", "timepoint": "24h", "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR... inhibited apoptosis", "notes": null}, "confidence": 0.9}, {"intervention": {"category": "CRISPR_KO", "raw_text": "CRISPR–Cas9 plasmid targeting mTOR, RAPTOR, or RICTOR", "target": {"name": "RAPTOR", "entity_type": "protein"}, "modality": "GOF"}, "system": {"species": "mammal", "cell_type": "human disk nucleus pulposus cells", "cell_lines": ["human disk nucleus pulposus cells"], "genotype_context": null, "disease_context": "degenerative disk disease"}, "readout": {"name": "senescence", "assay": null, "figure_refs": []}, "effect": {"direction": "decrease", "timepoint": "24h", "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR... inhibited senescence", "notes": null}, "confidence": 0.9}, {"intervention": {"category": "CRISPR_KO", "raw_text": "CRISPR–Cas9 plasmid targeting mTOR, RAPTOR, or RICTOR", "target": {"name": "RAPTOR", "entity_type": "protein"}, "modality": "GOF"}, "system": {"species": "mammal", "cell_type": "human disk nucleus pulposus cells", "cell_lines": ["human disk nucleus pulposus cells"], "genotype_context": null, "disease_context": "degenerative disk disease"}, "readout": {"name": "pyroptosis", "assay": null, "figure_refs": []}, "effect": {"direction": "decrease", "timepoint": "24h", "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR... inhibited pyroptosis", "notes": null}, "confidence": 0.9}, {"intervention": {"category": "CRISPR_KO", "raw_text": "CRISPR–Cas9 plasmid targeting mTOR, RAPTOR, or RICTOR", "target": {"name": "RAPTOR", "entity_type": "protein"}, "modality": "GOF"}, "system": {"species": "mammal", "cell_type": "human disk nucleus pulposus cells", "cell_lines": ["human disk nucleus pulposus cells"], "genotype_context": null, "disease_context": "degenerative disk disease"}, "readout": {"name": "matrix catabolism", "assay": null, "figure_refs": []}, "effect": {"direction": "decrease", "timepoint": "24h", "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR... inhibited matrix catabolism", "notes": null}, "confidence": 0.9}, {"intervention": {"category": "KNOCKDOWN_RNAI", "raw_text": "Targeting mTOR, RAPTOR, and RICTOR", "target": {"name": "mTOR", "entity_type": "protein"}, "modality": "GOF"}, "system": {"species": "mammal", "cell_type": "human disk nucleus pulposus cells", "cell_lines": ["human disk nucleus pulposus cells"], "genotype_context": null, "disease_context": "degenerative disk disease"}, "readout": {"name": "autophagy", "assay": null, "figure_refs": []}, "effect": {"direction": "increase", "timepoint": "24h", "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all induced autophagy", "notes": "Expanded per multi-target 'all/each/both' statement."}, "confidence": 0.9}, {"intervention": {"category": "KNOCKDOWN_RNAI", "raw_text": "Targeting mTOR, RAPTOR, and RICTOR", "target": {"name": "RAPTOR", "entity_type": "protein"}, "modality": "GOF"}, "system": {"species": "mammal", "cell_type": "human disk nucleus pulposus cells", "cell_lines": ["human disk nucleus pulposus cells"], "genotype_context": null, "disease_context": "degenerative disk disease"}, "readout": {"name": "autophagy", "assay": null, "figure_refs": []}, "effect": {"direction": "increase", "timepoint": "24h", "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all induced autophagy", "notes": "Expanded per multi-target 'all/each/both' statement."}, "confidence": 0.9}, {"intervention": {"category": "KNOCKDOWN_RNAI", "raw_text": "Targeting mTOR, RAPTOR, and RICTOR", "target": {"name": "RICTOR", "entity_type": "protein"}, "modality": "GOF"}, "system": {"species": "mammal", "cell_type": "human disk nucleus pulposus cells", "cell_lines": ["human disk nucleus pulposus cells"], "genotype_context": null, "disease_context": "degenerative disk disease"}, "readout": {"name": "autophagy", "assay": null, "figure_refs": []}, "effect": {"direction": "increase", "timepoint": "24h", "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all induced autophagy", "notes": "Expanded per multi-target 'all/each/both' statement."}, "confidence": 0.9}, {"intervention": {"category": "KNOCKDOWN_RNAI", "raw_text": "siRNA or CRISPR–Cas9 plasmid targeting mTOR, RAPTOR, or RICTOR", "target": {"name": "RAPTOR", "entity_type": "protein"}, "modality": "GOF"}, "system": {"species": "mammal", "cell_type": "human disk nucleus pulposus cells", "cell_lines": ["human disk nucleus pulposus cells"], "genotype_context": null, "disease_context": "degenerative disk disease"}, "readout": {"name": "apoptosis", "assay": null, "figure_refs": []}, "effect": {"direction": "decrease", "timepoint": "24h", "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR... inhibited apoptosis", "notes": null}, "confidence": 0.9}, {"intervention": {"category": "KNOCKDOWN_RNAI", "raw_text": "siRNA or CRISPR–Cas9 plasmid targeting mTOR, RAPTOR, or RICTOR", "target": {"name": "RAPTOR", "entity_type": "protein"}, "modality": "GOF"}, "system": {"species": "mammal", "cell_type": "human disk nucleus pulposus cells", "cell_lines": ["human disk nucleus pulposus cells"], "genotype_context": null, "disease_context": "degenerative disk disease"}, "readout": {"name": "senescence", "assay": null, "figure_refs": []}, "effect": {"direction": "decrease", "timepoint": "24h", "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR... inhibited senescence", "notes": null}, "confidence": 0.9}, {"intervention": {"category": "KNOCKDOWN_RNAI", "raw_text": "siRNA or CRISPR–Cas9 plasmid targeting mTOR, RAPTOR, or RICTOR", "target": {"name": "RAPTOR", "entity_type": "protein"}, "modality": "GOF"}, "system": {"species": "mammal", "cell_type": "human disk nucleus pulposus cells", "cell_lines": ["human disk nucleus pulposus cells"], "genotype_context": null, "disease_context": "degenerative disk disease"}, "readout": {"name": "pyroptosis", "assay": null, "figure_refs": []}, "effect": {"direction": "decrease", "timepoint": "24h", "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR... inhibited pyroptosis", "notes": null}, "confidence": 0.9}, {"intervention": {"category": "KNOCKDOWN_RNAI", "raw_text": "siRNA or CRISPR–Cas9 plasmid targeting mTOR, RAPTOR, or RICTOR", "target": {"name": "RAPTOR", "entity_type": "protein"}, "modality": "GOF"}, "system": {"species": "mammal", "cell_type": "human disk nucleus pulposus cells", "cell_lines": ["human disk nucleus pulposus cells"], "genotype_context": null, "disease_context": "degenerative disk disease"}, "readout": {"name": "matrix catabolism", "assay": null, "figure_refs": []}, "effect": {"direction": "decrease", "timepoint": "24h", "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR... inhibited matrix catabolism", "notes": null}, "confidence": 0.9}], "warnings": [], "bridge": {"enabled": false, "attempted": false, "used": false, "mode": null, "source_doc_ids": ["PMID:39682777"], "source_chunk_ids": [2], "skipped_reason": "bridge_off"}, "_routing": {"first_model": "gpt-4o-mini", "escalated": false, "final_model": "gpt-4o-mini", "reason": null}, "_post": {"dropped_atoms": 0, "multi_target": {"enabled": true, "events": 2, "expanded_atoms": 6}, "clause_split": {"enabled": true, "events": 0, "expanded_atoms": 0}}}

* * *

**ChatGPT:**

Thanks — this is _really_ useful output. v12 did one big thing right (it **didn’t arbitrarily pick one target** for the “all induced autophagy” part), but your chunk 2 shows **three concrete problems** we should fix before you go further:

### What’s still wrong in your chunk 2 output

1. **Multi-target expansion didn’t apply to the “inhibited apoptosis/senescence/pyroptosis/matrix catabolism” atoms**  
    Those atoms have quotes like `Targeting mTOR, RAPTOR, and RICTOR... inhibited apoptosis` but **your “all/each/both” cue got lost**, so v12’s trigger didn’t expand targets there → you ended up with **RAPTOR-only** atoms for those readouts.
2. **Modality is wrong (GOF)**  
    For `CRISPR_KO` and `KNOCKDOWN_RNAI`, modality should not be `GOF`. That’s a model mistake and we should **hard-correct it to LOF** in post-processing.
3. **System fields are a bit messy / hallucination-prone**  
    `species="mammal"` when the text clearly says human; and `cell_lines` contains a cell type. Also timepoints like `24h` are getting attached where they’re not explicitly tied to the specific effect quote — safest is: **only keep a timepoint if it appears in the supporting_quote**.

* * *

## What I want you to run now

Run **v13**, which fixes all three issues above.

**TAG: PATHAI-0053**  
Save as: `make_atoms_docaware_v13.py` (same folder)

Then run:

```bat
conda activate pathai
cd "C:\Users\Prem Subramaniam\Documents\Pathway AI"
python make_atoms_docaware_v13.py --bridge off --print-chunk 2
```

Paste back the printed chunk 2.

* * *

```Python
import os
import json
import re
import argparse
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple
from copy import deepcopy
from openai import OpenAI

# ============================================================
# CONFIG
# ============================================================
DEFAULT_INFILE = "mentions.jsonl"
DEFAULT_OUTFILE = "atoms.jsonl"

MODEL_FAST = "gpt-4o-mini"
MODEL_STRONG = "gpt-4.1"

MAX_ATOMS_PER_CHUNK = 30

TRY_BRIDGE_FORWARD = True
TRY_BRIDGE_BACKWARD = True

# ============================================================
# OPENAI CLIENT
# ============================================================
def _get_api_key() -> str:
    key = os.getenv("OPENAI_API_KEY")
    if not key:
        raise RuntimeError(
            "OPENAI_API_KEY is not set.\n"
            "Miniforge Prompt (temporary):  set OPENAI_API_KEY=YOUR_KEY\n"
            "Persistent (Windows):         setx OPENAI_API_KEY \"YOUR_KEY\"  (then reopen prompt)"
        )
    return key

client = OpenAI(api_key=_get_api_key())

# ============================================================
# STRICT JSON SCHEMA FOR ATOMS (model output)
# ============================================================
ATOM_SCHEMA_WRAPPER: Dict[str, Any] = {
    "name": "MechanisticAtoms",
    "schema": {
        "type": "object",
        "additionalProperties": False,
        "required": ["atoms", "warnings"],
        "properties": {
            "atoms": {
                "type": "array",
                "items": {
                    "type": "object",
                    "additionalProperties": False,
                    "required": [
                        "intervention",
                        "system",
                        "readout",
                        "effect",
                        "strength_cues",
                        "evidence",
                        "confidence",
                    ],
                    "properties": {
                        "intervention": {
                            "type": "object",
                            "additionalProperties": False,
                            "required": ["category", "raw_text", "target", "modality"],
                            "properties": {
                                "category": {
                                    "type": "string",
                                    "enum": [
                                        "GENETIC_KO",
                                        "CRISPR_KO",
                                        "CRISPRi",
                                        "CRISPRa",
                                        "KNOCKDOWN_RNAI",
                                        "SPLICING_MODULATION",
                                        "OVEREXPRESSION",
                                        "RESCUE_ADD_BACK",
                                        "DOMINANT_NEGATIVE",
                                        "MUTANT_VARIANT",
                                        "CHEMICAL_INHIBITOR",
                                        "CHEMICAL_ACTIVATOR",
                                        "CHEMICAL_DEGRADER",
                                        "STIMULUS_TREATMENT",
                                        "NEUTRALIZING_ANTIBODY",
                                        "UNKNOWN",
                                    ],
                                },
                                "raw_text": {"type": "string", "minLength": 1},
                                "target": {
                                    "anyOf": [
                                        {
                                            "type": "object",
                                            "additionalProperties": False,
                                            "required": ["name", "entity_type"],
                                            "properties": {
                                                "name": {"type": "string"},
                                                "entity_type": {
                                                    "type": "string",
                                                    "enum": [
                                                        "gene",
                                                        "protein",
                                                        "chemical",
                                                        "stimulus",
                                                        "antibody",
                                                        "unknown",
                                                    ],
                                                },
                                            },
                                        },
                                        {"type": "null"},
                                    ]
                                },
                                "modality": {
                                    "type": "string",
                                    "enum": [
                                        "LOF",
                                        "GOF",
                                        "INHIBITION",
                                        "ACTIVATION",
                                        "DEGRADATION",
                                        "RESCUE",
                                        "UNKNOWN",
                                    ],
                                },
                            },
                        },
                        "system": {
                            "type": "object",
                            "additionalProperties": False,
                            "required": [
                                "species",
                                "cell_type",
                                "cell_lines",
                                "genotype_context",
                                "disease_context",
                            ],
                            "properties": {
                                "species": {"type": ["string", "null"]},
                                "cell_type": {"type": ["string", "null"]},
                                "cell_lines": {"type": "array", "items": {"type": "string"}},
                                "genotype_context": {"type": ["string", "null"]},
                                "disease_context": {"type": ["string", "null"]},
                            },
                        },
                        "readout": {
                            "type": "object",
                            "additionalProperties": False,
                            "required": ["name", "assay", "figure_refs"],
                            "properties": {
                                "name": {"type": "string"},
                                "assay": {"type": ["string", "null"]},
                                "figure_refs": {"type": "array", "items": {"type": "string"}},
                            },
                        },
                        "effect": {
                            "type": "object",
                            "additionalProperties": False,
                            "required": ["direction", "timepoint", "magnitude", "comparison"],
                            "properties": {
                                "direction": {
                                    "type": "string",
                                    "enum": ["increase", "decrease", "no_change", "mixed", "unknown"],
                                },
                                "timepoint": {"type": ["string", "null"]},
                                "magnitude": {"type": ["string", "null"]},
                                "comparison": {"type": ["string", "null"]},
                            },
                        },
                        "strength_cues": {
                            "type": "object",
                            "additionalProperties": False,
                            "required": ["has_rescue", "has_control", "has_multiple_lines", "other"],
                            "properties": {
                                "has_rescue": {"type": "boolean"},
                                "has_control": {"type": "boolean"},
                                "has_multiple_lines": {"type": "boolean"},
                                "other": {"type": "array", "items": {"type": "string"}},
                            },
                        },
                        "evidence": {
                            "type": "object",
                            "additionalProperties": False,
                            "required": ["supporting_quote", "notes"],
                            "properties": {
                                "supporting_quote": {"type": "string"},
                                "notes": {"type": ["string", "null"]},
                            },
                        },
                        "confidence": {"type": "number", "minimum": 0, "maximum": 1},
                    },
                },
            },
            "warnings": {"type": "array", "items": {"type": "string"}},
        },
    },
}

# ============================================================
# DOC ID
# ============================================================
def build_doc_id(rec: Dict[str, Any]) -> Tuple[str, str]:
    """
    doc_id priority:
      1) PMID:<n>
      2) PMCID:<id>
      3) DOI:<doi>
      4) J:<journal>|V:<vol>|Y:<year>|P:<pages>
      5) FILE:<filename>
      6) CHUNK:<chunk_id>
    """
    pmid = rec.get("pmid")
    pmcid = rec.get("pmcid")
    doi = rec.get("doi")
    journal = rec.get("journal")
    volume = rec.get("volume")
    year = rec.get("year") or rec.get("pub_year")
    pages = rec.get("pages")
    source_file = rec.get("source_file") or rec.get("file") or rec.get("filename")

    if pmid:
        return f"PMID:{str(pmid).strip()}", "pmid"
    if pmcid:
        return f"PMCID:{str(pmcid).strip()}", "pmcid"
    if doi:
        return f"DOI:{str(doi).strip()}", "doi"
    if journal and volume and year and pages:
        jid = f"J:{str(journal).strip()}|V:{str(volume).strip()}|Y:{str(year).strip()}|P:{str(pages).strip()}"
        return jid, "journal_vol_year_pages"
    if source_file:
        return f"FILE:{Path(str(source_file)).name}", "file"
    return f"CHUNK:{rec.get('chunk_id')}", "chunk_fallback"

# ============================================================
# INPUT COMPACTION
# ============================================================
def compact_mentions(mentions: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    out = []
    for i, m in enumerate(mentions, start=1):
        out.append({
            "i": i,
            "category": m.get("category"),
            "raw_text": m.get("raw_text"),
            "target_guess": m.get("target_guess"),
            "method_cues": m.get("method_cues", []),
        })
    return out

# ============================================================
# PROMPT
# ============================================================
SYSTEM_INSTRUCTIONS = (
    "Extract 'mechanistic atoms' from biomedical text.\n\n"
    "Atom definition: an atom MUST include an explicit effect on a readout.\n"
    "Format: [INTERVENTION] causes [EFFECT] in [READOUT] in a [SYSTEM].\n\n"
    "Hard rules:\n"
    "1) Do NOT invent facts.\n"
    "2) Do NOT assume knockdown succeeded unless the text explicitly confirms reduction/knockdown.\n"
    "3) If text says 'A, B, and C all did X' (or 'each/both'), emit separate atoms for A, for B, and for C.\n"
    "4) If a sentence contains multiple readouts (e.g., 'induced autophagy and inhibited apoptosis, senescence...'), emit one atom per readout with correct direction.\n"
    "5) If text only describes delivering siRNA/plasmid/drug but gives no stated change in any readout, output no atoms and add a warning.\n"
    f"6) Keep at most {MAX_ATOMS_PER_CHUNK} atoms.\n"
)

def call_model(model: str, chunk_text: str, mentions: List[Dict[str, Any]]) -> Dict[str, Any]:
    payload = {"chunk_text": chunk_text, "mentions": compact_mentions(mentions)}
    resp = client.responses.create(
        model=model,
        input=[
            {"role": "system", "content": SYSTEM_INSTRUCTIONS},
            {"role": "user", "content": json.dumps(payload, ensure_ascii=False)},
        ],
        text={
            "format": {
                "type": "json_schema",
                "name": ATOM_SCHEMA_WRAPPER["name"],
                "strict": True,
                "schema": ATOM_SCHEMA_WRAPPER["schema"],
            }
        },
    )
    return json.loads(resp.output_text)

def should_escalate(mentions: List[Dict[str, Any]], atoms: List[Dict[str, Any]], warnings: List[str]) -> bool:
    if len(mentions) > 0 and len(atoms) == 0:
        return True
    if atoms:
        avg_conf = sum(float(a.get("confidence", 0) or 0) for a in atoms) / max(1, len(atoms))
        if avg_conf < 0.60:
            return True
    wtxt = " ".join(warnings).lower()
    if ("no explicit" in wtxt or "only describes" in wtxt) and len(mentions) > 0:
        return True
    return False

def extract_atoms_with_routing(chunk_text: str, mentions: List[Dict[str, Any]]) -> Dict[str, Any]:
    routing = {"first_model": MODEL_FAST, "escalated": False, "final_model": MODEL_FAST, "reason": None}
    out_fast = call_model(MODEL_FAST, chunk_text, mentions)
    atoms_fast = out_fast.get("atoms", [])
    warnings_fast = out_fast.get("warnings", [])

    if should_escalate(mentions, atoms_fast, warnings_fast):
        routing["escalated"] = True
        routing["final_model"] = MODEL_STRONG
        routing["reason"] = {"type": "low_confidence_or_empty_or_warning", "details": "heuristics triggered"}
        out_strong = call_model(MODEL_STRONG, chunk_text, mentions)
        out_strong["_routing"] = routing
        return out_strong

    out_fast["_routing"] = routing
    return out_fast

# ============================================================
# POST-FILTER: require explicit effect cue in quote
# ============================================================
EFFECT_CUE = re.compile(
    r"\b("
    r"inhibit|inhibited|inhibition|suppress|suppressed|"
    r"reduce|reduced|reduces|reduction|decrease|decreased|decreases|"
    r"increase|increased|increases|elevate|elevated|"
    r"induce|induced|induces|promote|promoted|enhance|enhanced|"
    r"no effect|did not affect|had no effect|did not change|unchanged|"
    r"rescue|rescued|restore|restored|"
    r"abolish|abolished"
    r")\b",
    re.IGNORECASE,
)

def post_filter_atoms(atoms: List[Dict[str, Any]]) -> Tuple[List[Dict[str, Any]], int]:
    kept = []
    dropped = 0
    for a in atoms:
        sq = ((a.get("evidence") or {}).get("supporting_quote") or "")
        if EFFECT_CUE.search(sq):
            kept.append(a)
        else:
            dropped += 1
    return kept, dropped

# ============================================================
# SETUP-ONLY DETECTION (for bridging trigger only)
# ============================================================
SETUP_READOUT_RE = re.compile(
    r"\b(protein expression|mrna|expression|knockdown|silencing|transfection efficiency|target protein)\b",
    re.IGNORECASE,
)

def looks_setup_only(atoms: List[Dict[str, Any]], warnings: List[str]) -> bool:
    if not atoms:
        return True
    wtxt = " ".join(warnings).lower()
    if "no explicit functional" in wtxt:
        return True
    for a in atoms:
        ro = ((a.get("readout") or {}).get("name") or "")
        if not SETUP_READOUT_RE.search(ro):
            return False
    return True

# ============================================================
# MULTI-TARGET EXPANSION (chunk-aware propagation)
# - If ANY atom in the chunk has "Targeting A, B, and C all/each/both ...",
#   we treat that target-list as an "anchor" and allow expansion for other
#   atoms that reference the same "Targeting A, B, and C ..." even if their
#   quote lost the "all" word (e.g. "... inhibited apoptosis").
# ============================================================
ALL_EACH_RE = re.compile(r"\b(all|each|both)\b", re.IGNORECASE)

# Capture a target list after "Targeting" up to either all/each/both OR an effect verb.
TARGETING_ANY_RE = re.compile(
    r"\b[Tt]argeting\s+(.+?)\s+\b("
    r"all|each|both|"
    r"induce|induced|inhibit|inhibited|suppress|suppressed|"
    r"reduce|reduced|decrease|decreased|increase|increased|"
    r"promote|promoted|enhance|enhanced|"
    r"abolish|abolished|"
    r"had no effect|no effect|did not affect|did not change|unchanged"
    r")\b",
    re.IGNORECASE,
)

def _tokenize_targets(s: str) -> List[str]:
    s = s.strip()
    s = re.sub(r"\b(protein|gene|complex|pathway|signaling|levels?)\b", "", s, flags=re.IGNORECASE)
    parts = re.split(r",|\band\b|\bor\b|/|;", s, flags=re.IGNORECASE)
    out = []
    for p in parts:
        t = p.strip()
        t = re.sub(r"[^A-Za-z0-9\-\_]+", "", t)
        if len(t) < 2:
            continue
        if t.lower() in {"targeting", "all", "each", "both", "cells", "cell"}:
            continue
        out.append(t)
    seen = set()
    uniq = []
    for x in out:
        k = x.lower()
        if k not in seen:
            seen.add(k)
            uniq.append(x)
    return uniq

def _targets_key(targets: List[str]) -> str:
    return "|".join(sorted(t.lower() for t in targets))

def extract_target_list_from_quote(quote: str) -> List[str]:
    m = TARGETING_ANY_RE.search(quote)
    if not m:
        return []
    candidate = m.group(1)
    targets = _tokenize_targets(candidate)
    return targets

def expand_multi_target_chunkaware(atoms: List[Dict[str, Any]]) -> Tuple[List[Dict[str, Any]], Dict[str, Any]]:
    # pass 1: build anchor maps (only when quote includes all/each/both)
    anchor_map: Dict[str, List[str]] = {}
    for a in atoms:
        quote = ((a.get("evidence") or {}).get("supporting_quote") or "")
        if not quote:
            continue
        if not ALL_EACH_RE.search(quote):
            continue
        targets = extract_target_list_from_quote(quote)
        if len(targets) >= 2:
            anchor_map[_targets_key(targets)] = targets

    events_all = 0
    events_propagated = 0
    expanded = 0

    out: List[Dict[str, Any]] = []

    for a in atoms:
        quote = ((a.get("evidence") or {}).get("supporting_quote") or "")
        if not quote:
            out.append(a)
            continue

        targets = extract_target_list_from_quote(quote)
        if len(targets) < 2:
            out.append(a)
            continue

        key = _targets_key(targets)

        use_targets: List[str] = []
        if ALL_EACH_RE.search(quote):
            use_targets = targets
            events_all += 1
        elif key in anchor_map:
            # Propagate the "all/each/both" semantics from an anchor quote in the same chunk
            use_targets = anchor_map[key]
            events_propagated += 1
        else:
            # No anchor present -> do NOT assume list implies "each"; keep as-is
            out.append(a)
            continue

        for t in use_targets:
            b = deepcopy(a)
            if b.get("intervention", {}).get("target") is None:
                b["intervention"]["target"] = {"name": t, "entity_type": "protein"}
            else:
                b["intervention"]["target"]["name"] = t

            notes = (b.get("evidence", {}) or {}).get("notes")
            if ALL_EACH_RE.search(quote):
                add = "Expanded per multi-target 'all/each/both' statement."
            else:
                add = "Expanded per chunk-level multi-target anchor (propagated 'all/each/both' semantics)."
            b["evidence"]["notes"] = (notes + " " + add).strip() if notes else add

            out.append(b)
            expanded += 1

    return out, {
        "enabled": True,
        "anchors": len(anchor_map),
        "events_all": events_all,
        "events_propagated": events_propagated,
        "expanded_atoms": expanded,
    }

# ============================================================
# CLAUSE / MULTI-READOUT SPLITTING (keeps FULL quote)
# ============================================================
_VERB_PATTERNS = [
    ("had no effect", "no_change"),
    ("no effect", "no_change"),
    ("did not affect", "no_change"),
    ("did not change", "no_change"),
    ("unchanged", "no_change"),
    ("inhibited", "decrease"),
    ("inhibit", "decrease"),
    ("suppressed", "decrease"),
    ("suppress", "decrease"),
    ("reduced", "decrease"),
    ("reduce", "decrease"),
    ("decreased", "decrease"),
    ("decrease", "decrease"),
    ("abolished", "decrease"),
    ("abolish", "decrease"),
    ("induced", "increase"),
    ("induce", "increase"),
    ("increased", "increase"),
    ("increase", "increase"),
    ("promoted", "increase"),
    ("promote", "increase"),
    ("enhanced", "increase"),
    ("enhance", "increase"),
    ("restored", "increase"),
    ("restore", "increase"),
    ("rescued", "increase"),
    ("rescue", "increase"),
]

_VERB_REGEX = re.compile(
    r"\b(" + "|".join(re.escape(v) for v, _ in sorted(_VERB_PATTERNS, key=lambda x: -len(x[0]))) + r")\b",
    re.IGNORECASE,
)

def _verb_to_dir(v: str) -> str:
    vl = v.lower()
    for pat, d in _VERB_PATTERNS:
        if vl == pat:
            return d
    if "no effect" in vl or "did not" in vl or "unchanged" in vl:
        return "no_change"
    return "unknown"

_STOP_CLAUSE_RE = re.compile(
    r"\b(with|whereas|however|but|although|while|when|which|that)\b",
    re.IGNORECASE,
)

def _clean_readout_item(x: str) -> str:
    x = x.strip()
    x = re.sub(r"^[\s,:;]+", "", x)
    x = re.sub(r"^(on|of|to)\s+", "", x, flags=re.IGNORECASE)
    x = re.sub(r"\s+", " ", x).strip()
    x = re.sub(r"[)\].,;:]+$", "", x).strip()
    return x

def _split_readouts(span: str) -> List[str]:
    span = _STOP_CLAUSE_RE.split(span)[0]
    span = span.split("(")[0]
    span = span.split(".")[0]
    span = span.strip()
    span = re.sub(r"\s+", " ", span)
    span = re.sub(r"^\s*(and|or)\s+", "", span, flags=re.IGNORECASE)

    parts = re.split(r",|\band\b", span, flags=re.IGNORECASE)
    out = []
    for p in parts:
        t = _clean_readout_item(p)
        if not t:
            continue
        t = re.sub(
            r"^(inhibit(ed)?|suppress(ed)?|reduce(d)?|decrease(d)?|induce(d)?|increase(d)?|promote(d)?|enhance(d)?|restore(d)?|rescue(d)?)\s+",
            "",
            t,
            flags=re.IGNORECASE,
        ).strip()
        t = _clean_readout_item(t)
        if t:
            out.append(t)

    seen = set()
    uniq = []
    for x in out:
        k = x.lower()
        if k not in seen:
            seen.add(k)
            uniq.append(x)
    return uniq

def clause_split_atoms(atoms: List[Dict[str, Any]]) -> Tuple[List[Dict[str, Any]], Dict[str, Any]]:
    events = 0
    expanded = 0
    out: List[Dict[str, Any]] = []

    for a in atoms:
        full_quote = ((a.get("evidence") or {}).get("supporting_quote") or "")
        if not full_quote:
            out.append(a)
            continue

        matches = list(_VERB_REGEX.finditer(full_quote))
        if not matches:
            out.append(a)
            continue

        if ("," not in full_quote) and (" and " not in full_quote.lower()):
            out.append(a)
            continue

        new_atoms: List[Dict[str, Any]] = []

        for i, m in enumerate(matches):
            verb = m.group(1)
            direction = _verb_to_dir(verb)

            start = m.end()
            end = matches[i + 1].start() if i + 1 < len(matches) else len(full_quote)
            span = full_quote[start:end]
            readouts = _split_readouts(span)

            if not readouts:
                continue

            for ro in readouts:
                b = deepcopy(a)
                b["evidence"]["supporting_quote"] = full_quote  # keep FULL quote
                b["readout"]["name"] = ro
                b["effect"]["direction"] = direction

                notes = (b.get("evidence", {}) or {}).get("notes")
                add = f"Clause-split (verb '{verb}' -> {direction}, readout '{ro}')."
                b["evidence"]["notes"] = (notes + " " + add).strip() if notes else add

                new_atoms.append(b)

        if len(new_atoms) <= 1:
            out.append(a)
            continue

        events += 1
        expanded += len(new_atoms)
        out.extend(new_atoms)

    return out, {"enabled": True, "events": events, "expanded_atoms": expanded}

# ============================================================
# DEDUPE + CAP
# ============================================================
def atom_key(a: Dict[str, Any]) -> str:
    iv = a.get("intervention", {}) or {}
    tg = (iv.get("target") or {})
    sys = a.get("system", {}) or {}
    ro = a.get("readout", {}) or {}
    ef = a.get("effect", {}) or {}
    ev = a.get("evidence", {}) or {}
    return "|".join([
        (iv.get("category") or "").lower(),
        (iv.get("modality") or "").lower(),
        (tg.get("name") or "").lower(),
        (ro.get("name") or "").lower(),
        (ef.get("direction") or "").lower(),
        (sys.get("species") or "").lower(),
        (sys.get("cell_type") or "").lower(),
        (";".join(sys.get("cell_lines", []) or [])).lower(),
        (sys.get("disease_context") or "").lower(),
        (ev.get("supporting_quote") or "").lower(),
    ])

def dedupe_atoms(atoms: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    seen = set()
    out = []
    for a in atoms:
        k = atom_key(a)
        if k in seen:
            continue
        seen.add(k)
        out.append(a)
    return out

def cap_atoms(atoms: List[Dict[str, Any]], warnings: List[str]) -> Tuple[List[Dict[str, Any]], List[str]]:
    if len(atoms) <= MAX_ATOMS_PER_CHUNK:
        return atoms, warnings
    atoms_sorted = sorted(atoms, key=lambda x: (-(float(x.get("confidence", 0) or 0)), atom_key(x)))
    kept = atoms_sorted[:MAX_ATOMS_PER_CHUNK]
    warnings = list(warnings) + [f"Truncated atoms: {len(atoms)} -> {MAX_ATOMS_PER_CHUNK} due to MAX_ATOMS_PER_CHUNK."]
    return kept, warnings

# ============================================================
# POST-CORRECTIONS (deterministic cleanup)
# - Fix modality for KO/RNAi to LOF
# - Fix species if cell_type explicitly says "human"
# - Clean cell_lines that are actually cell types
# - Drop timepoint unless it appears in supporting_quote (prevents "24h" leakage)
# ============================================================
def correct_modality(iv_category: str, modality: str) -> str:
    cat = (iv_category or "").strip()

    lof_cats = {"GENETIC_KO", "CRISPR_KO", "CRISPRi", "KNOCKDOWN_RNAI", "SPLICING_MODULATION", "DOMINANT_NEGATIVE"}
    gof_cats = {"OVEREXPRESSION", "CRISPRa"}
    if cat in lof_cats:
        return "LOF"
    if cat in gof_cats:
        return "GOF"
    if cat == "CHEMICAL_INHIBITOR":
        return "INHIBITION"
    if cat == "CHEMICAL_ACTIVATOR":
        return "ACTIVATION"
    if cat == "CHEMICAL_DEGRADER":
        return "DEGRADATION"
    if cat == "RESCUE_ADD_BACK":
        return "RESCUE"
    return modality or "UNKNOWN"

def sanitize_atom(atom: Dict[str, Any]) -> Dict[str, Any]:
    a = deepcopy(atom)

    iv = a.get("intervention", {}) or {}
    sys = a.get("system", {}) or {}
    ef = a.get("effect", {}) or {}
    ev = a.get("evidence", {}) or {}

    # modality correction
    iv_cat = iv.get("category") or "UNKNOWN"
    iv_mod = iv.get("modality") or "UNKNOWN"
    iv["modality"] = correct_modality(iv_cat, iv_mod)
    a["intervention"] = iv

    # species correction if explicitly human in cell_type or cell_lines
    ct = (sys.get("cell_type") or "")
    cls = list(sys.get("cell_lines") or [])
    if sys.get("species") and str(sys.get("species")).strip().lower() in {"mammal", "mammalian"}:
        if "human" in ct.lower() or any("human" in c.lower() for c in cls):
            sys["species"] = "human"

    # clean cell_lines that are actually cell types / duplicates
    clean_cls = []
    for c in cls:
        if not c:
            continue
        if ct and c.strip().lower() == ct.strip().lower():
            continue
        # if it literally looks like a cell type phrase, not a line
        if " cells" in c.lower() and "-" not in c:
            continue
        clean_cls.append(c)
    sys["cell_lines"] = clean_cls

    # if cell_type is empty but a "cells" phrase exists in cell_lines, move it
    if (not sys.get("cell_type")) and clean_cls:
        for c in clean_cls:
            if " cells" in c.lower():
                sys["cell_type"] = c
                sys["cell_lines"] = [x for x in clean_cls if x != c]
                break

    a["system"] = sys

    # timepoint correction: keep only if explicitly in supporting_quote
    tp = ef.get("timepoint")
    quote = (ev.get("supporting_quote") or "")
    if tp and (str(tp).lower() not in quote.lower()):
        ef["timepoint"] = None
    a["effect"] = ef

    return a

# ============================================================
# BRIDGING (DOC-AWARE ONLY)
# ============================================================
def merge_text(a: str, b: str) -> str:
    return a.rstrip() + "\n\n" + b.lstrip()

def merge_mentions(a: List[Dict[str, Any]], b: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    return list(a) + list(b)

def choose_best_candidate(cands: List[Tuple[str, Dict[str, Any], List[int]]]) -> Optional[Tuple[str, Dict[str, Any], List[int]]]:
    best = None
    for mode, outd, src_chunks in cands:
        atoms = outd.get("atoms", [])
        if best is None:
            best = (mode, outd, src_chunks)
            continue
        best_atoms = best[1].get("atoms", [])
        if len(atoms) > len(best_atoms):
            best = (mode, outd, src_chunks)
        elif len(atoms) == len(best_atoms) and len(atoms) > 0:
            avg = sum(float(a.get("confidence", 0) or 0) for a in atoms) / len(atoms)
            bavg = sum(float(a.get("confidence", 0) or 0) for a in best_atoms) / len(best_atoms)
            if avg > bavg:
                best = (mode, outd, src_chunks)
    return best

def run_full_post_pipeline(out: Dict[str, Any]) -> Tuple[List[Dict[str, Any]], List[str], Dict[str, Any]]:
    atoms = out.get("atoms", [])
    warnings = out.get("warnings", [])

    atoms, dropped = post_filter_atoms(atoms)

    # Multi-target expansion first (now chunk-aware and propagated)
    atoms, mt_info = expand_multi_target_chunkaware(atoms)

    # Clause splitting (if needed)
    atoms, cs_info = clause_split_atoms(atoms)

    # Deterministic cleanup
    atoms = [sanitize_atom(a) for a in atoms]

    atoms = dedupe_atoms(atoms)
    atoms, warnings = cap_atoms(atoms, warnings)

    post = {"dropped_atoms": dropped, "multi_target": mt_info, "clause_split": cs_info}
    return atoms, warnings, post

# ============================================================
# PROCESS ONE RECORD
# ============================================================
def process_record(
    rec: Dict[str, Any],
    doc_id: str,
    doc_id_source: str,
    bridge_enabled: bool,
    neighbor_prev: Optional[Dict[str, Any]],
    neighbor_next: Optional[Dict[str, Any]],
) -> Dict[str, Any]:
    chunk_id = rec.get("chunk_id")
    chunk_index = rec.get("chunk_index")
    chunk_text = rec.get("chunk_text", "")
    mentions = rec.get("mentions", [])

    if "error" in rec:
        return {
            "doc_id": doc_id,
            "doc_id_source": doc_id_source,
            "pmid": rec.get("pmid"),
            "pmcid": rec.get("pmcid"),
            "chunk_index": chunk_index,
            "chunk_id": chunk_id,
            "atoms": [],
            "warnings": ["Skipped due to upstream error."],
            "bridge": {
                "enabled": bridge_enabled,
                "attempted": False,
                "used": False,
                "mode": None,
                "source_doc_ids": [doc_id],
                "source_chunk_ids": [chunk_id],
                "skipped_reason": "upstream_error",
            },
            "_routing": {"skipped": True},
            "_post": {"dropped_atoms": 0},
        }

    # base extract
    out = extract_atoms_with_routing(chunk_text, mentions)
    routing = out.get("_routing", {})
    atoms, warnings, post = run_full_post_pipeline(out)

    bridge_meta = {
        "enabled": bridge_enabled,
        "attempted": False,
        "used": False,
        "mode": None,
        "source_doc_ids": [doc_id],
        "source_chunk_ids": [chunk_id],
        "skipped_reason": None,
    }

    # bridging trigger (only if enabled)
    if bridge_enabled and len(mentions) > 0 and (len(atoms) == 0 or looks_setup_only(atoms, warnings)):
        bridge_meta["attempted"] = True
        cands: List[Tuple[str, Dict[str, Any], List[int]]] = []

        # forward within doc
        if TRY_BRIDGE_FORWARD and neighbor_next is not None:
            t = merge_text(chunk_text, neighbor_next.get("chunk_text", ""))
            m = merge_mentions(mentions, neighbor_next.get("mentions", []))
            bout = extract_atoms_with_routing(t, m)
            batoms, bwarns, bpost = run_full_post_pipeline(bout)
            bout["atoms"] = batoms
            bout["warnings"] = bwarns
            bout["_post"] = bpost
            cands.append(("forward", bout, [chunk_id, neighbor_next.get("chunk_id")]))

        # backward within doc
        if TRY_BRIDGE_BACKWARD and neighbor_prev is not None:
            t = merge_text(neighbor_prev.get("chunk_text", ""), chunk_text)
            m = merge_mentions(neighbor_prev.get("mentions", []), mentions)
            bout = extract_atoms_with_routing(t, m)
            batoms, bwarns, bpost = run_full_post_pipeline(bout)
            bout["atoms"] = batoms
            bout["warnings"] = bwarns
            bout["_post"] = bpost
            cands.append(("backward", bout, [neighbor_prev.get("chunk_id"), chunk_id]))

        best = choose_best_candidate(cands)
        if best is not None and len(best[1].get("atoms", [])) > 0:
            if (len(best[1].get("atoms", [])) > len(atoms)) or looks_setup_only(atoms, warnings):
                bridge_meta["used"] = True
                bridge_meta["mode"] = best[0]
                bridge_meta["source_chunk_ids"] = best[2]
                out_best = best[1]
                atoms = out_best.get("atoms", [])
                warnings = out_best.get("warnings", [])
                post = out_best.get("_post", post)
                routing = out_best.get("_routing", routing)
        if not bridge_meta["used"]:
            bridge_meta["skipped_reason"] = "no_better_candidate"
    elif not bridge_enabled:
        bridge_meta["skipped_reason"] = "bridge_off"

    return {
        "doc_id": doc_id,
        "doc_id_source": doc_id_source,
        "pmid": rec.get("pmid"),
        "pmcid": rec.get("pmcid"),
        "chunk_index": chunk_index,
        "chunk_id": chunk_id,
        "atoms": atoms,
        "warnings": warnings,
        "bridge": bridge_meta,
        "_routing": routing,
        "_post": post,
    }

# ============================================================
# HELPERS: read/write + doc-aware adjacency
# ============================================================
def read_jsonl(path: Path) -> List[Dict[str, Any]]:
    recs: List[Dict[str, Any]] = []
    for ln in path.read_text(encoding="utf-8", errors="ignore").splitlines():
        if ln.strip():
            recs.append(json.loads(ln))
    return recs

def make_doc_groups(records: List[Dict[str, Any]]) -> Tuple[List[str], List[str], Dict[str, List[int]]]:
    doc_ids: List[str] = []
    doc_srcs: List[str] = []
    groups: Dict[str, List[int]] = {}
    for i, r in enumerate(records):
        doc_id, src = build_doc_id(r)
        doc_ids.append(doc_id)
        doc_srcs.append(src)
        groups.setdefault(doc_id, []).append(i)
    return doc_ids, doc_srcs, groups

def sort_doc_group(records: List[Dict[str, Any]], idxs: List[int]) -> List[int]:
    def key(i: int) -> Tuple[int, int]:
        ci = records[i].get("chunk_index")
        if ci is None:
            return (1, i)
        try:
            return (0, int(ci))
        except Exception:
            return (0, i)
    return sorted(idxs, key=key)

def print_chunk_from_atoms(atoms_file: Path, chunk_id: int):
    for ln in atoms_file.read_text(encoding="utf-8", errors="ignore").splitlines():
        rec = json.loads(ln)
        if rec.get("chunk_id") == chunk_id:
            print(json.dumps(rec, indent=2, ensure_ascii=False))
            return
    print(f"chunk_id {chunk_id} not found in {atoms_file}")

# ============================================================
# MAIN
# ============================================================
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--infile", default=DEFAULT_INFILE)
    ap.add_argument("--outfile", default=DEFAULT_OUTFILE)
    ap.add_argument("--bridge", choices=["on", "off"], default="off",
                    help="Bridging is doc-aware only. Keep OFF for mixed/random chunks across papers.")
    ap.add_argument("--print-chunk", type=int, default=None, help="Print a chunk record from atoms.jsonl after run.")
    args = ap.parse_args()

    infile = Path(args.infile)
    outfile = Path(args.outfile)
    bridge_enabled = (args.bridge == "on")

    if not infile.exists():
        raise FileNotFoundError(f"Cannot find {infile.resolve()}")

    records = read_jsonl(infile)
    doc_ids, doc_srcs, groups = make_doc_groups(records)

    doc_order_map: Dict[str, List[int]] = {doc: sort_doc_group(records, idxs) for doc, idxs in groups.items()}
    pos_in_doc: Dict[int, int] = {}
    for doc, order in doc_order_map.items():
        for p, gi in enumerate(order):
            pos_in_doc[gi] = p

    total_atoms = 0
    escalations = 0
    bridges_attempted = 0
    bridges_used = 0
    dropped_total = 0
    doc_src_counts: Dict[str, int] = {}

    with outfile.open("w", encoding="utf-8") as fout:
        for gi, rec in enumerate(records):
            doc_id = doc_ids[gi]
            doc_src = doc_srcs[gi]
            doc_src_counts[doc_src] = doc_src_counts.get(doc_src, 0) + 1

            order = doc_order_map[doc_id]
            p = pos_in_doc[gi]
            prev_rec = records[order[p - 1]] if (p - 1 >= 0) else None
            next_rec = records[order[p + 1]] if (p + 1 < len(order)) else None

            outrec = process_record(
                rec=rec,
                doc_id=doc_id,
                doc_id_source=doc_src,
                bridge_enabled=bridge_enabled,
                neighbor_prev=prev_rec,
                neighbor_next=next_rec,
            )

            atoms_here = outrec.get("atoms", []) or []
            total_atoms += len(atoms_here)

            if (outrec.get("_routing") or {}).get("escalated"):
                escalations += 1

            dropped_total += int((outrec.get("_post") or {}).get("dropped_atoms", 0))

            b = outrec.get("bridge") or {}
            if b.get("attempted"):
                bridges_attempted += 1
            if b.get("used"):
                bridges_used += 1

            fout.write(json.dumps(outrec, ensure_ascii=False) + "\n")

            print(
                f"chunk {outrec.get('chunk_id')} doc_id={outrec.get('doc_id')}({outrec.get('doc_id_source')}) "
                f"idx={outrec.get('chunk_index')} atoms={len(atoms_here)} "
                f"escalated={bool((outrec.get('_routing') or {}).get('escalated'))} "
                f"bridge_enabled={bridge_enabled} bridged={bool((outrec.get('bridge') or {}).get('used'))} "
                f"dropped={int((outrec.get('_post') or {}).get('dropped_atoms', 0))}"
            )

    print(f"Done. total_atoms={total_atoms}, escalations={escalations}, "
          f"bridges_attempted={bridges_attempted}, bridges_used={bridges_used}, dropped_total={dropped_total}")
    print("doc_id sources: " + ", ".join([f"{k}={v}" for k, v in sorted(doc_src_counts.items())]))
    if not bridge_enabled:
        print("Note: bridging was OFF (recommended for mixed/random chunks).")

    if args.print_chunk is not None:
        print_chunk_from_atoms(outfile, args.print_chunk)

if __name__ == "__main__":
    main()
```

* * *

### What you should see after running v13 (chunk 2)

* The **apoptosis/senescence/pyroptosis/matrix catabolism** atoms should no longer be RAPTOR-only — you should see **mTOR + RAPTOR + RICTOR** versions (because we propagate the “all” semantics from the anchor quote).
* `CRISPR_KO` and `KNOCKDOWN_RNAI` atoms should have **modality = LOF** (not GOF).
* `timepoint` should likely become **null** unless the actual `supporting_quote` includes it.
* `cell_lines` should **not** contain `"human disk nucleus pulposus cells"` (that belongs in `cell_type`).

Run it and paste the `--print-chunk 2` output — we’ll confirm it’s now logically faithful before moving to graph-building.

* * *

**You:**

chunk 1 is returning 0 atoms.  I will post chunk 2 soon.

* * *

**ChatGPT:**

Got it — and that’s **very likely a real bug in my v13 script**, not “your data”.

### Why chunk 1 can end up with 0 atoms even though the text has an effect

v13 has a **post-filter** (a strict cleanup step) that **drops any atom whose supporting quote doesn’t contain an “effect word”** (like _increased, decreased, inhibited, induced,_ etc.).

Chunk 1’s key effect line is:

> “significant tumor growth **suppression** capability”

…but my effect-word list includes **`suppress` / `suppressed`** (verbs), and I forgot to include **`suppression`** (noun). So if the model quotes **“tumor growth suppression”** (very likely), the filter doesn’t recognize it and drops the atom → **0 atoms**.

Same issue can happen with **“antiproliferative activity”** (also an effect, but not in the list).

* * *

## What I want you to run right now (no manual editing)

This will automatically generate **v14** from your existing v13, with the effect-word filter fixed.

### 1) Save this as: `patch_v13_to_v14.py` (same folder)

```Python
from pathlib import Path

src_path = Path("make_atoms_docaware_v13.py")
dst_path = Path("make_atoms_docaware_v14.py")

if not src_path.exists():
    raise SystemExit("ERROR: make_atoms_docaware_v13.py not found in this folder.")

src = src_path.read_text(encoding="utf-8", errors="ignore")

# Add noun forms / common biology wording that should count as an explicit effect cue
replacements = [
    ("suppress|suppressed|", "suppress|suppressed|suppression|"),
    ("inhibit|inhibited|inhibition|", "inhibit|inhibited|inhibition|inhibitory|"),
]

for old, new in replacements:
    if old not in src:
        raise SystemExit(f"ERROR: Could not find expected text to replace: {old}")
    src = src.replace(old, new)

# Add antiproliferative terms (often used as explicit effect statements)
needle = "r\"\\b(\""
if needle not in src:
    raise SystemExit("ERROR: Could not locate EFFECT_CUE regex block (unexpected file format).")

# Only add if not already present
if "antiproliferative" not in src.lower():
    src = src.replace(
        "abolish|abolished",
        "abolish|abolished|antiproliferative|anti-proliferative|anti proliferative",
        1,
    )

dst_path.write_text(src, encoding="utf-8")
print("Wrote make_atoms_docaware_v14.py (effect-cue filter updated).")
```

### 2) Run it, then run v14

```bat
conda activate pathai
cd "C:\Users\Prem Subramaniam\Documents\Pathway AI"
python patch_v13_to_v14.py
python make_atoms_docaware_v14.py --bridge off --print-chunk 1
```

### What you should expect

Chunk 1 should no longer be 0: you should see **at least 1 atom** for “tumor growth suppression” (and possibly another for “antiproliferative activity” if the model extracts it cleanly).

* * *

When you paste chunk 2, I’ll check two specific things immediately:

* whether the **“all did X”** expansion now applies across the whole multi-readout sentence (not just autophagy),
* and whether **modality stays LOF** for RNAi/CRISPR KO (no GOF leaks).

* * *

**You:**

{"doc_id": "PMID:39682777", "doc_id_source": "pmid", "pmid": "39682777", "pmcid": null, "chunk_index": null, "chunk_id": 2, "atoms": [{"intervention": {"category": "CRISPR_KO", "raw_text": "CRISPR–Cas9 plasmid targeting mTOR, RAPTOR, or RICTOR", "target": {"name": "mTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": null, "cell_type": null, "cell_lines": [], "genotype_context": null, "disease_context": null}, "readout": {"name": "autophagy", "assay": null, "figure_refs": []}, "effect": {"direction": "increase", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all induced autophagy", "notes": "Expanded per multi-target 'all/each/both' statement."}, "confidence": 0.9}, {"intervention": {"category": "CRISPR_KO", "raw_text": "CRISPR–Cas9 plasmid targeting mTOR, RAPTOR, or RICTOR", "target": {"name": "RAPTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": null, "cell_type": null, "cell_lines": [], "genotype_context": null, "disease_context": null}, "readout": {"name": "autophagy", "assay": null, "figure_refs": []}, "effect": {"direction": "increase", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all induced autophagy", "notes": "Expanded per multi-target 'all/each/both' statement."}, "confidence": 0.9}, {"intervention": {"category": "CRISPR_KO", "raw_text": "CRISPR–Cas9 plasmid targeting mTOR, RAPTOR, or RICTOR", "target": {"name": "RICTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": null, "cell_type": null, "cell_lines": [], "genotype_context": null, "disease_context": null}, "readout": {"name": "autophagy", "assay": null, "figure_refs": []}, "effect": {"direction": "increase", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all induced autophagy", "notes": "Expanded per multi-target 'all/each/both' statement."}, "confidence": 0.9}, {"intervention": {"category": "CRISPR_KO", "raw_text": "CRISPR–Cas9 plasmid targeting mTOR, RAPTOR, or RICTOR", "target": {"name": "RAPTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": null, "cell_type": null, "cell_lines": [], "genotype_context": null, "disease_context": null}, "readout": {"name": "apoptosis", "assay": null, "figure_refs": []}, "effect": {"direction": "decrease", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR...inhibited apoptosis", "notes": null}, "confidence": 0.9}, {"intervention": {"category": "CRISPR_KO", "raw_text": "CRISPR–Cas9 plasmid targeting mTOR, RAPTOR, or RICTOR", "target": {"name": "RAPTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": null, "cell_type": null, "cell_lines": [], "genotype_context": null, "disease_context": null}, "readout": {"name": "senescence", "assay": null, "figure_refs": []}, "effect": {"direction": "decrease", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR...inhibited senescence", "notes": null}, "confidence": 0.9}, {"intervention": {"category": "CRISPR_KO", "raw_text": "CRISPR–Cas9 plasmid targeting mTOR, RAPTOR, or RICTOR", "target": {"name": "RAPTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": null, "cell_type": null, "cell_lines": [], "genotype_context": null, "disease_context": null}, "readout": {"name": "pyroptosis", "assay": null, "figure_refs": []}, "effect": {"direction": "decrease", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR...inhibited pyroptosis", "notes": null}, "confidence": 0.9}, {"intervention": {"category": "CRISPR_KO", "raw_text": "CRISPR–Cas9 plasmid targeting mTOR, RAPTOR, or RICTOR", "target": {"name": "RAPTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": null, "cell_type": null, "cell_lines": [], "genotype_context": null, "disease_context": null}, "readout": {"name": "matrix catabolism", "assay": null, "figure_refs": []}, "effect": {"direction": "decrease", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR...inhibited matrix catabolism", "notes": null}, "confidence": 0.9}], "warnings": [], "bridge": {"enabled": false, "attempted": false, "used": false, "mode": null, "source_doc_ids": ["PMID:39682777"], "source_chunk_ids": [2], "skipped_reason": "bridge_off"}, "_routing": {"first_model": "gpt-4o-mini", "escalated": false, "final_model": "gpt-4o-mini", "reason": null}, "_post": {"dropped_atoms": 0, "multi_target": {"enabled": true, "anchors": 1, "events_all": 1, "events_propagated": 0, "expanded_atoms": 3}, "clause_split": {"enabled": true, "events": 0, "expanded_atoms": 0}}}

* * *

**ChatGPT:**



* * *

**You:**

Th

* * *

**ChatGPT:**



* * *

**You:**

The previous prompt is chunk 2 output from running v13 of make_atoms_docaware_v13.py

* * *

**ChatGPT:**

Thanks — this chunk 2 output from **v13** is _exactly_ the kind of “looks OK at first glance but is logically wrong” case we wanted to catch.

### What’s wrong in your v13 chunk 2 output (in plain terms)

You correctly pointed out the biology: **“A, B, and C all did X” means each one individually did X**, not “only RAPTOR did X”.

In your v13 JSON:

* **Autophagy** is expanded correctly to **mTOR / RAPTOR / RICTOR** (good).
* But **apoptosis / senescence / pyroptosis / matrix catabolism** are **NOT** expanded — they appear only with **target = RAPTOR** (bad).
* Your own debug confirms this:  
    `_post.multi_target.events_all = 1` but `events_propagated = 0` → meaning the script detected a multi-target statement, but **didn’t propagate it to the other atoms**.

So we need one concrete fix:

✅ **If any atom’s supporting_quote contains a multi-target list (“mTOR, RAPTOR, RICTOR”) then every atom derived from that same quote must be replicated across all those targets.**  
No “pick one target” ever.

* * *

# Full script to run next

**TAG: PATHAI-0050**  
Save as: **`make_atoms_docaware_v14.py`** (do not edit; just run)

This version does two things:

1. Fixes the “suppression / antiproliferative” effect-cue filtering bug (chunk 1 issue you saw).
2. Fixes **multi-target propagation** so your chunk 2 case always expands systematically.

```Python
import os
import re
import json
import argparse
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple
from copy import deepcopy
from openai import OpenAI

# ============================================================
# CONFIG DEFAULTS
# ============================================================
INFILE = Path("mentions.jsonl")
OUTFILE = Path("atoms.jsonl")

MODEL_FAST_DEFAULT = "gpt-4o-mini"
MODEL_STRONG_DEFAULT = "gpt-4.1"

MAX_ATOMS_PER_CHUNK_DEFAULT = 30
BRIDGE_DEFAULT = "off"  # recommended for mixed/random chunks

# ============================================================
# OPENAI CLIENT
# ============================================================
def _get_api_key() -> str:
    key = os.getenv("OPENAI_API_KEY")
    if not key:
        raise RuntimeError(
            "OPENAI_API_KEY is not set.\n"
            "Miniforge Prompt (temporary):  set OPENAI_API_KEY=YOUR_KEY\n"
            "Persistent (Windows):         setx OPENAI_API_KEY \"YOUR_KEY\"  (then reopen prompt)"
        )
    return key

client = OpenAI(api_key=_get_api_key())

# ============================================================
# STRICT JSON SCHEMA FOR ATOMS (model output)
# ============================================================
ATOM_SCHEMA_WRAPPER: Dict[str, Any] = {
    "name": "MechanisticAtoms",
    "schema": {
        "type": "object",
        "additionalProperties": False,
        "required": ["atoms", "warnings"],
        "properties": {
            "atoms": {
                "type": "array",
                "items": {
                    "type": "object",
                    "additionalProperties": False,
                    "required": [
                        "intervention",
                        "system",
                        "readout",
                        "effect",
                        "strength_cues",
                        "evidence",
                        "confidence",
                    ],
                    "properties": {
                        "intervention": {
                            "type": "object",
                            "additionalProperties": False,
                            "required": ["category", "raw_text", "target", "modality"],
                            "properties": {
                                "category": {
                                    "type": "string",
                                    "enum": [
                                        "GENETIC_KO",
                                        "CRISPR_KO",
                                        "CRISPRi",
                                        "CRISPRa",
                                        "KNOCKDOWN_RNAI",
                                        "SPLICING_MODULATION",
                                        "OVEREXPRESSION",
                                        "RESCUE_ADD_BACK",
                                        "DOMINANT_NEGATIVE",
                                        "MUTANT_VARIANT",
                                        "CHEMICAL_INHIBITOR",
                                        "CHEMICAL_ACTIVATOR",
                                        "CHEMICAL_DEGRADER",
                                        "STIMULUS_TREATMENT",
                                        "NEUTRALIZING_ANTIBODY",
                                        "UNKNOWN",
                                    ],
                                },
                                "raw_text": {"type": "string", "minLength": 1},
                                "target": {
                                    "anyOf": [
                                        {
                                            "type": "object",
                                            "additionalProperties": False,
                                            "required": ["name", "entity_type"],
                                            "properties": {
                                                "name": {"type": "string"},
                                                "entity_type": {
                                                    "type": "string",
                                                    "enum": [
                                                        "gene",
                                                        "protein",
                                                        "chemical",
                                                        "stimulus",
                                                        "antibody",
                                                        "unknown",
                                                    ],
                                                },
                                            },
                                        },
                                        {"type": "null"},
                                    ]
                                },
                                "modality": {
                                    "type": "string",
                                    "enum": [
                                        "LOF",
                                        "GOF",
                                        "INHIBITION",
                                        "ACTIVATION",
                                        "DEGRADATION",
                                        "RESCUE",
                                        "UNKNOWN",
                                    ],
                                },
                            },
                        },
                        "system": {
                            "type": "object",
                            "additionalProperties": False,
                            "required": [
                                "species",
                                "cell_type",
                                "cell_lines",
                                "genotype_context",
                                "disease_context",
                            ],
                            "properties": {
                                "species": {"type": ["string", "null"]},
                                "cell_type": {"type": ["string", "null"]},
                                "cell_lines": {"type": "array", "items": {"type": "string"}},
                                "genotype_context": {"type": ["string", "null"]},
                                "disease_context": {"type": ["string", "null"]},
                            },
                        },
                        "readout": {
                            "type": "object",
                            "additionalProperties": False,
                            "required": ["name", "assay", "figure_refs"],
                            "properties": {
                                "name": {"type": "string"},
                                "assay": {"type": ["string", "null"]},
                                "figure_refs": {"type": "array", "items": {"type": "string"}},
                            },
                        },
                        "effect": {
                            "type": "object",
                            "additionalProperties": False,
                            "required": ["direction", "timepoint", "magnitude", "comparison"],
                            "properties": {
                                "direction": {
                                    "type": "string",
                                    "enum": ["increase", "decrease", "no_change", "mixed", "unknown"],
                                },
                                "timepoint": {"type": ["string", "null"]},
                                "magnitude": {"type": ["string", "null"]},
                                "comparison": {"type": ["string", "null"]},
                            },
                        },
                        "strength_cues": {
                            "type": "object",
                            "additionalProperties": False,
                            "required": ["has_rescue", "has_control", "has_multiple_lines", "other"],
                            "properties": {
                                "has_rescue": {"type": "boolean"},
                                "has_control": {"type": "boolean"},
                                "has_multiple_lines": {"type": "boolean"},
                                "other": {"type": "array", "items": {"type": "string"}},
                            },
                        },
                        "evidence": {
                            "type": "object",
                            "additionalProperties": False,
                            "required": ["supporting_quote", "notes"],
                            "properties": {
                                "supporting_quote": {"type": "string"},
                                "notes": {"type": ["string", "null"]},
                            },
                        },
                        "confidence": {"type": "number", "minimum": 0, "maximum": 1},
                    },
                },
            },
            "warnings": {"type": "array", "items": {"type": "string"}},
        },
    },
}

# ============================================================
# DOC ID SELECTION
# ============================================================
def choose_doc_id(rec: Dict[str, Any]) -> Tuple[str, str]:
    pmid = rec.get("pmid")
    pmcid = rec.get("pmcid")
    doi = rec.get("doi")
    source_file = rec.get("source_file")
    chunk_id = rec.get("chunk_id")

    if pmid:
        return f"PMID:{str(pmid).strip()}", "pmid"
    if pmcid:
        return f"PMCID:{str(pmcid).strip()}", "pmcid"
    if doi:
        return f"DOI:{str(doi).strip()}", "doi"
    if source_file:
        return f"FILE:{Path(str(source_file)).name}", "source_file"
    return f"CHUNK:{chunk_id}", "chunk_fallback"

# ============================================================
# PROMPT
# ============================================================
def build_system_instructions(max_atoms: int) -> str:
    return (
        "Extract 'mechanistic atoms' from biomedical text.\n\n"
        "Definition: an atom MUST include an explicit effect on a readout.\n"
        "Format: [INTERVENTION] causes [EFFECT] in [READOUT] in a [SYSTEM].\n\n"
        "Hard rules:\n"
        "1) Do NOT invent facts.\n"
        "2) Do NOT assume knockdown succeeded unless the text explicitly says reduction/knockdown/confirmed.\n"
        "3) If the text only describes delivering siRNA/plasmid/drug but gives no stated change in any readout, output no atoms and add a warning.\n"
        "4) If a sentence says 'A, B, and C all did X' (or equivalent), you MUST output parallel atoms for A, for B, and for C (do NOT pick one arbitrarily).\n"
        "5) If a sentence lists multiple readouts ('inhibited apoptosis, senescence, ...'), you MAY output one atom per readout if the verb/effect applies.\n"
        f"6) Keep at most {max_atoms} atoms.\n"
    )

# ============================================================
# MODEL CALL + ROUTING
# ============================================================
def compact_mentions(mentions: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    out = []
    for i, m in enumerate(mentions, start=1):
        out.append({
            "i": i,
            "category": m.get("category"),
            "raw_text": m.get("raw_text"),
            "target_guess": m.get("target_guess"),
            "method_cues": m.get("method_cues", []),
        })
    return out

def call_model(model: str, chunk_text: str, mentions: List[Dict[str, Any]], max_atoms: int) -> Dict[str, Any]:
    payload = {
        "chunk_text": chunk_text,
        "mentions": compact_mentions(mentions),
    }
    resp = client.responses.create(
        model=model,
        input=[
            {"role": "system", "content": build_system_instructions(max_atoms)},
            {"role": "user", "content": json.dumps(payload, ensure_ascii=False)},
        ],
        text={
            "format": {
                "type": "json_schema",
                "name": ATOM_SCHEMA_WRAPPER["name"],
                "strict": True,
                "schema": ATOM_SCHEMA_WRAPPER["schema"],
            }
        },
    )
    return json.loads(resp.output_text)

def should_escalate(mentions: List[Dict[str, Any]], atoms: List[Dict[str, Any]], warnings: List[str]) -> bool:
    if len(mentions) > 0 and len(atoms) == 0:
        return True
    if any("validation" in w.lower() for w in warnings):
        return True
    if len(atoms) > 0:
        avg_conf = sum(a.get("confidence", 0) for a in atoms) / max(1, len(atoms))
        if avg_conf < 0.60:
            return True
    return False

def extract_atoms_with_routing(
    chunk_text: str,
    mentions: List[Dict[str, Any]],
    model_fast: str,
    model_strong: str,
    max_atoms: int,
) -> Dict[str, Any]:
    routing = {"first_model": model_fast, "escalated": False, "final_model": model_fast, "reason": None}

    out_fast = call_model(model_fast, chunk_text, mentions, max_atoms)
    atoms_fast = out_fast.get("atoms", [])
    warnings_fast = out_fast.get("warnings", [])

    if should_escalate(mentions, atoms_fast, warnings_fast):
        routing["escalated"] = True
        routing["final_model"] = model_strong
        routing["reason"] = {"type": "low_confidence_or_empty", "details": "heuristics triggered"}

        out_strong = call_model(model_strong, chunk_text, mentions, max_atoms)
        out_strong["_routing"] = routing
        return out_strong

    out_fast["_routing"] = routing
    return out_fast

# ============================================================
# POST-FILTER: explicit effect cues in quote
# ============================================================
EFFECT_CUE = re.compile(
    r"\b("
    r"inhibit|inhibited|inhibition|inhibitory|"
    r"suppress|suppressed|suppression|"
    r"reduce|reduced|reduces|reduction|"
    r"decrease|decreased|decreases|"
    r"increase|increased|increases|"
    r"induce|induced|induces|"
    r"promote|promoted|promotes|"
    r"activate|activated|activates|"
    r"abolish|abolished|"
    r"no effect|did not affect|had no effect|"
    r"rescue|rescued|restore|restored|"
    r"antiproliferative|anti-proliferative|anti proliferative"
    r")\b",
    re.IGNORECASE,
)

def post_filter_atoms(atoms: List[Dict[str, Any]]) -> Tuple[List[Dict[str, Any]], int]:
    kept = []
    dropped = 0
    for a in atoms:
        sq = (a.get("evidence", {}) or {}).get("supporting_quote", "") or ""
        if EFFECT_CUE.search(sq):
            kept.append(a)
        else:
            dropped += 1
    return kept, dropped

# ============================================================
# MULTI-READOUT (CLAUSE) SPLIT (lightweight, safe)
# ============================================================
VERB_TO_DIR = {
    "induce": "increase",
    "induced": "increase",
    "increase": "increase",
    "increased": "increase",
    "promote": "increase",
    "promoted": "increase",
    "activate": "increase",
    "activated": "increase",
    "inhibit": "decrease",
    "inhibited": "decrease",
    "suppress": "decrease",
    "suppressed": "decrease",
    "reduce": "decrease",
    "reduced": "decrease",
    "decrease": "decrease",
    "decreased": "decrease",
}

CLAUSE_REGEX = re.compile(
    r"\b(induced|increased|activated|promoted|inhibited|suppressed|reduced|decreased)\b",
    re.IGNORECASE,
)

def _split_list_items(s: str) -> List[str]:
    # Split on commas and "and"
    s = s.strip().strip(".;")
    s = re.sub(r"\s+", " ", s)
    parts = []
    for p in re.split(r",|\band\b", s, flags=re.IGNORECASE):
        p = p.strip(" .;:()[]{}")
        if p:
            parts.append(p)
    return parts

def clause_split_atoms(atoms: List[Dict[str, Any]]) -> Tuple[List[Dict[str, Any]], Dict[str, Any]]:
    """
    If a quote contains multiple verb+readout segments, ensure we have atoms per readout.
    This is additive (we only add missing ones), then dedupe later.
    """
    added = 0
    events = 0
    expanded: List[Dict[str, Any]] = list(atoms)

    for a in atoms:
        sq = (a.get("evidence", {}) or {}).get("supporting_quote", "") or ""
        verbs = list(CLAUSE_REGEX.finditer(sq))
        if len(verbs) < 2:
            continue

        # Build segments: verb -> text until next verb
        segments = []
        for i, m in enumerate(verbs):
            v = m.group(1)
            start = m.end()
            end = verbs[i + 1].start() if i + 1 < len(verbs) else len(sq)
            seg_text = sq[start:end].strip()
            segments.append((v.lower(), seg_text))

        # Convert segments into (readout, direction) items
        items: List[Tuple[str, str]] = []
        for v, seg in segments:
            direction = VERB_TO_DIR.get(v, "unknown")
            # Often "induced autophagy" (single) and "inhibited apoptosis, senescence, ..."
            readouts = _split_list_items(seg)
            for ro in readouts:
                # clean "..." artifacts
                ro = ro.replace("...", " ").strip()
                if not ro:
                    continue
                items.append((ro, direction))

        if not items:
            continue

        events += 1
        for ro, direction in items:
            na = deepcopy(a)
            na["readout"]["name"] = ro
            na["effect"]["direction"] = direction
            # Make note so you can audit where these came from
            note = (na.get("evidence", {}) or {}).get("notes")
            na["evidence"]["notes"] = (note + " | " if note else "") + "Clause-split from supporting_quote."
            expanded.append(na)
            added += 1

    stats = {"enabled": True, "events": events, "expanded_atoms": added}
    return expanded, stats

# ============================================================
# MULTI-TARGET EXPANSION (critical fix)
# ============================================================
ALL_EACH_REGEX = re.compile(r"\b(all|each|both)\b", re.IGNORECASE)

def _extract_candidate_targets_from_record(
    mentions: List[Dict[str, Any]],
    atoms: List[Dict[str, Any]],
) -> List[str]:
    cands: List[str] = []

    # from mentions
    for m in mentions:
        tg = (m.get("target_guess") or {})
        name = tg.get("name")
        if not name:
            continue
        # split on commas / and / or
        for part in re.split(r",|\band\b|\bor\b|/|;", str(name), flags=re.IGNORECASE):
            part = part.strip()
            if part and len(part) <= 30:
                cands.append(part)

    # from atoms
    for a in atoms:
        t = (a.get("intervention", {}) or {}).get("target") or {}
        nm = t.get("name")
        if nm:
            cands.append(str(nm).strip())

    # unique preserve (case-insensitive)
    seen = set()
    out = []
    for x in cands:
        k = x.lower()
        if k not in seen:
            seen.add(k)
            out.append(x)
    return out

def _quote_mentions_targets(quote: str, targets: List[str]) -> List[str]:
    hits = []
    qlow = quote.lower()
    for t in targets:
        if t.lower() in qlow:
            hits.append(t)
    return hits

def _is_multi_target_quote(quote: str, targets: List[str]) -> Tuple[bool, List[str]]:
    hits = _quote_mentions_targets(quote, targets)
    # Multi-target if it names >=2 candidates (and often has all/each/both, but we allow without it)
    if len(hits) >= 2:
        return True, hits
    return False, hits

def multi_target_expand_atoms(
    atoms: List[Dict[str, Any]],
    mentions: List[Dict[str, Any]],
) -> Tuple[List[Dict[str, Any]], Dict[str, Any]]:
    """
    For any atom whose supporting_quote clearly references multiple targets,
    replicate that atom across all targets mentioned/candidate in that quote.
    """
    cands = _extract_candidate_targets_from_record(mentions, atoms)
    expanded: List[Dict[str, Any]] = []
    events_all = 0
    events_propagated = 0
    anchors = 0

    for a in atoms:
        sq = (a.get("evidence", {}) or {}).get("supporting_quote", "") or ""
        is_mt, hits = _is_multi_target_quote(sq, cands)
        if not is_mt:
            expanded.append(a)
            continue

        anchors += 1
        events_all += 1

        # If the quote is multi-target, we force parallel atoms for each hit target.
        # (This is the bug fix: we propagate for EVERY atom tied to the quote, not only the first.)
        for tname in hits:
            na = deepcopy(a)
            if na.get("intervention", {}).get("target") is None:
                na["intervention"]["target"] = {"name": tname, "entity_type": "protein"}
            else:
                na["intervention"]["target"]["name"] = tname
            note = (na.get("evidence", {}) or {}).get("notes")
            na["evidence"]["notes"] = (note + " | " if note else "") + "Multi-target propagated from quote."
            expanded.append(na)
        events_propagated += 1

    stats = {
        "enabled": True,
        "anchors": anchors,
        "events_all": events_all,
        "events_propagated": events_propagated,
        "expanded_atoms": len(expanded) - len(atoms),
    }
    return expanded, stats

# ============================================================
# DEDUP + TRUNCATE
# ============================================================
def _atom_key(a: Dict[str, Any]) -> Tuple:
    itv = a.get("intervention", {}) or {}
    sys = a.get("system", {}) or {}
    ro = a.get("readout", {}) or {}
    eff = a.get("effect", {}) or {}
    ev = a.get("evidence", {}) or {}
    tgt = itv.get("target") or {}
    return (
        itv.get("category"),
        itv.get("modality"),
        (tgt.get("name") if isinstance(tgt, dict) else None),
        ro.get("name"),
        eff.get("direction"),
        (ev.get("supporting_quote") or "").strip().lower(),
        (sys.get("species"), sys.get("cell_type")),
    )

def dedup_atoms(atoms: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    seen = set()
    out = []
    for a in atoms:
        k = _atom_key(a)
        if k in seen:
            continue
        seen.add(k)
        out.append(a)
    return out

def truncate_atoms(atoms: List[Dict[str, Any]], max_atoms: int) -> Tuple[List[Dict[str, Any]], Optional[str]]:
    if len(atoms) <= max_atoms:
        return atoms, None
    atoms_sorted = sorted(atoms, key=lambda x: float(x.get("confidence", 0)), reverse=True)
    return atoms_sorted[:max_atoms], f"Truncated atoms: {len(atoms)} -> {max_atoms} due to MAX_ATOMS_PER_CHUNK."

# ============================================================
# DRIVER
# ============================================================
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--infile", default=str(INFILE))
    ap.add_argument("--outfile", default=str(OUTFILE))
    ap.add_argument("--model_fast", default=MODEL_FAST_DEFAULT)
    ap.add_argument("--model_strong", default=MODEL_STRONG_DEFAULT)
    ap.add_argument("--max_atoms", type=int, default=MAX_ATOMS_PER_CHUNK_DEFAULT)
    ap.add_argument("--bridge", choices=["on", "off"], default=BRIDGE_DEFAULT)
    args = ap.parse_args()

    infile = Path(args.infile)
    outfile = Path(args.outfile)

    if not infile.exists():
        raise FileNotFoundError(f"Cannot find {infile.resolve()}")

    records: List[Dict[str, Any]] = []
    for ln in infile.read_text(encoding="utf-8", errors="ignore").splitlines():
        if not ln.strip():
            continue
        records.append(json.loads(ln))

    total_atoms = 0
    escalations = 0
    dropped_total = 0
    doc_source_counts: Dict[str, int] = {}

    with outfile.open("w", encoding="utf-8") as fout:
        for rec in records:
            chunk_id = rec.get("chunk_id")
            chunk_text = rec.get("chunk_text", "") or ""
            mentions = rec.get("mentions", []) or []

            doc_id, doc_src = choose_doc_id(rec)
            doc_source_counts[doc_src] = doc_source_counts.get(doc_src, 0) + 1

            out = extract_atoms_with_routing(
                chunk_text=chunk_text,
                mentions=mentions,
                model_fast=args.model_fast,
                model_strong=args.model_strong,
                max_atoms=args.max_atoms,
            )
            routing = out.get("_routing", {})
            atoms = out.get("atoms", []) or []
            warnings = out.get("warnings", []) or []

            # 1) post-filter (explicit effect cue in quote)
            atoms, dropped = post_filter_atoms(atoms)
            dropped_total += dropped

            # 2) clause split (adds missing readouts if quote contains multiple)
            atoms, clause_stats = clause_split_atoms(atoms)

            # 3) multi-target propagation (critical fix)
            atoms, mt_stats = multi_target_expand_atoms(atoms, mentions)

            # 4) dedup + truncate
            atoms = dedup_atoms(atoms)
            trunc_warn = None
            atoms, trunc_warn = truncate_atoms(atoms, args.max_atoms)
            if trunc_warn:
                warnings.append(trunc_warn)

            if routing.get("escalated"):
                escalations += 1

            total_atoms += len(atoms)

            record_out = {
                "doc_id": doc_id,
                "doc_id_source": doc_src,
                "pmid": rec.get("pmid"),
                "pmcid": rec.get("pmcid"),
                "doi": rec.get("doi"),
                "source_file": rec.get("source_file"),
                "chunk_index": rec.get("chunk_index"),
                "chunk_id": chunk_id,
                "atoms": atoms,
                "warnings": warnings,
                "bridge": {
                    "enabled": (args.bridge == "on"),
                    "attempted": False,
                    "used": False,
                    "mode": None,
                    "source_doc_ids": [doc_id],
                    "source_chunk_ids": [chunk_id],
                    "skipped_reason": "bridge_off" if args.bridge == "off" else "not_implemented_in_v14",
                },
                "_routing": routing,
                "_post": {
                    "dropped_atoms": dropped,
                    "clause_split": clause_stats,
                    "multi_target": mt_stats,
                },
            }

            fout.write(json.dumps(record_out, ensure_ascii=False) + "\n")
            print(
                f"chunk {chunk_id} doc_id={doc_id} atoms={len(atoms)} "
                f"escalated={routing.get('escalated', False)} bridge={args.bridge} dropped={dropped}"
            )

    print(f"Done. total_atoms={total_atoms}, escalations={escalations}, dropped_total={dropped_total}")
    print("doc_id sources: " + ", ".join(f"{k}={v}" for k, v in sorted(doc_source_counts.items())))
    if args.bridge == "off":
        print("Note: bridging was OFF (recommended for mixed/random chunks).")

if __name__ == "__main__":
    main()
```

* * *

## Run exactly this

```bat
conda activate pathai
cd "C:\Users\Prem Subramaniam\Documents\Pathway AI"
python make_atoms_docaware_v14.py --bridge off
```

* * *

## What I expect you’ll see for chunk 2 after v14

You should get **parallel atoms for mTOR + RAPTOR + RICTOR** not only for autophagy, but also for:

* apoptosis (decrease)
* senescence (decrease)
* pyroptosis (decrease)
* matrix catabolism (decrease)

So instead of “only RAPTOR inhibits apoptosis…”, you’ll have **mTOR inhibits apoptosis**, **RAPTOR inhibits apoptosis**, **RICTOR inhibits apoptosis**, all tied to the same quote.

* * *

If you paste back the **chunk 2 line from atoms.jsonl after v14**, I’ll sanity-check two things fast:

1. did multi-target propagation apply to _all_ readouts (it should),
2. did we avoid exploding beyond MAX_ATOMS_PER_CHUNK (it should stay reasonable for this chunk).

* * *

**You:**

Here is ouput from chunk 2 from v14.  :: {"doc_id": "PMID:39682777", "doc_id_source": "pmid", "pmid": "39682777", "pmcid": null, "doi": null, "source_file": null, "chunk_index": null, "chunk_id": 2, "atoms": [{"intervention": {"category": "CRISPR_KO", "raw_text": "CRISPR–Cas9 plasmid targeting mTOR", "target": {"name": "mTOR", "entity_type": "protein"}, "modality": "INHIBITION"}, "system": {"species": "human", "cell_type": "nucleus pulposus", "cell_lines": ["degenerative disk cells"], "genotype_context": null, "disease_context": "degenerative disk disease"}, "readout": {"name": "autophagy", "assay": null, "figure_refs": []}, "effect": {"direction": "increase", "timepoint": "168h", "magnitude": "88.1%", "comparison": "CRISPR–Cas9 targeting mTOR"}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all induced autophagy.", "notes": "Multi-target propagated from quote."}, "confidence": 0.9}, {"intervention": {"category": "CRISPR_KO", "raw_text": "CRISPR–Cas9 plasmid targeting mTOR", "target": {"name": "RAPTOR", "entity_type": "protein"}, "modality": "INHIBITION"}, "system": {"species": "human", "cell_type": "nucleus pulposus", "cell_lines": ["degenerative disk cells"], "genotype_context": null, "disease_context": "degenerative disk disease"}, "readout": {"name": "autophagy", "assay": null, "figure_refs": []}, "effect": {"direction": "increase", "timepoint": "168h", "magnitude": "88.1%", "comparison": "CRISPR–Cas9 targeting mTOR"}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all induced autophagy.", "notes": "Multi-target propagated from quote."}, "confidence": 0.9}, {"intervention": {"category": "CRISPR_KO", "raw_text": "CRISPR–Cas9 plasmid targeting mTOR", "target": {"name": "RICTOR", "entity_type": "protein"}, "modality": "INHIBITION"}, "system": {"species": "human", "cell_type": "nucleus pulposus", "cell_lines": ["degenerative disk cells"], "genotype_context": null, "disease_context": "degenerative disk disease"}, "readout": {"name": "autophagy", "assay": null, "figure_refs": []}, "effect": {"direction": "increase", "timepoint": "168h", "magnitude": "88.1%", "comparison": "CRISPR–Cas9 targeting mTOR"}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all induced autophagy.", "notes": "Multi-target propagated from quote."}, "confidence": 0.9}, {"intervention": {"category": "CRISPR_KO", "raw_text": "CRISPR–Cas9 plasmid targeting RAPTOR", "target": {"name": "mTOR", "entity_type": "protein"}, "modality": "INHIBITION"}, "system": {"species": "human", "cell_type": "nucleus pulposus", "cell_lines": ["degenerative disk cells"], "genotype_context": null, "disease_context": "degenerative disk disease"}, "readout": {"name": "apoptosis", "assay": null, "figure_refs": []}, "effect": {"direction": "decrease", "timepoint": "168h", "magnitude": null, "comparison": "CRISPR-KO targeting RAPTOR"}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all inhibited apoptosis.", "notes": "Multi-target propagated from quote."}, "confidence": 0.9}, {"intervention": {"category": "CRISPR_KO", "raw_text": "CRISPR–Cas9 plasmid targeting RAPTOR", "target": {"name": "RAPTOR", "entity_type": "protein"}, "modality": "INHIBITION"}, "system": {"species": "human", "cell_type": "nucleus pulposus", "cell_lines": ["degenerative disk cells"], "genotype_context": null, "disease_context": "degenerative disk disease"}, "readout": {"name": "apoptosis", "assay": null, "figure_refs": []}, "effect": {"direction": "decrease", "timepoint": "168h", "magnitude": null, "comparison": "CRISPR-KO targeting RAPTOR"}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all inhibited apoptosis.", "notes": "Multi-target propagated from quote."}, "confidence": 0.9}, {"intervention": {"category": "CRISPR_KO", "raw_text": "CRISPR–Cas9 plasmid targeting RAPTOR", "target": {"name": "RICTOR", "entity_type": "protein"}, "modality": "INHIBITION"}, "system": {"species": "human", "cell_type": "nucleus pulposus", "cell_lines": ["degenerative disk cells"], "genotype_context": null, "disease_context": "degenerative disk disease"}, "readout": {"name": "apoptosis", "assay": null, "figure_refs": []}, "effect": {"direction": "decrease", "timepoint": "168h", "magnitude": null, "comparison": "CRISPR-KO targeting RAPTOR"}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all inhibited apoptosis.", "notes": "Multi-target propagated from quote."}, "confidence": 0.9}, {"intervention": {"category": "CRISPR_KO", "raw_text": "CRISPR–Cas9 plasmid targeting RICTOR", "target": {"name": "mTOR", "entity_type": "protein"}, "modality": "INHIBITION"}, "system": {"species": "human", "cell_type": "nucleus pulposus", "cell_lines": ["degenerative disk cells"], "genotype_context": null, "disease_context": "degenerative disk disease"}, "readout": {"name": "senescence", "assay": null, "figure_refs": []}, "effect": {"direction": "decrease", "timepoint": "168h", "magnitude": null, "comparison": "CRISPR-KO targeting RICTOR"}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all inhibited senescence.", "notes": "Multi-target propagated from quote."}, "confidence": 0.9}, {"intervention": {"category": "CRISPR_KO", "raw_text": "CRISPR–Cas9 plasmid targeting RICTOR", "target": {"name": "RAPTOR", "entity_type": "protein"}, "modality": "INHIBITION"}, "system": {"species": "human", "cell_type": "nucleus pulposus", "cell_lines": ["degenerative disk cells"], "genotype_context": null, "disease_context": "degenerative disk disease"}, "readout": {"name": "senescence", "assay": null, "figure_refs": []}, "effect": {"direction": "decrease", "timepoint": "168h", "magnitude": null, "comparison": "CRISPR-KO targeting RICTOR"}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all inhibited senescence.", "notes": "Multi-target propagated from quote."}, "confidence": 0.9}, {"intervention": {"category": "CRISPR_KO", "raw_text": "CRISPR–Cas9 plasmid targeting RICTOR", "target": {"name": "RICTOR", "entity_type": "protein"}, "modality": "INHIBITION"}, "system": {"species": "human", "cell_type": "nucleus pulposus", "cell_lines": ["degenerative disk cells"], "genotype_context": null, "disease_context": "degenerative disk disease"}, "readout": {"name": "senescence", "assay": null, "figure_refs": []}, "effect": {"direction": "decrease", "timepoint": "168h", "magnitude": null, "comparison": "CRISPR-KO targeting RICTOR"}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all inhibited senescence.", "notes": "Multi-target propagated from quote."}, "confidence": 0.9}, {"intervention": {"category": "CRISPR_KO", "raw_text": "CRISPR–Cas9 plasmid targeting RAPTOR", "target": {"name": "mTOR", "entity_type": "protein"}, "modality": "INHIBITION"}, "system": {"species": "human", "cell_type": "nucleus pulposus", "cell_lines": ["degenerative disk cells"], "genotype_context": null, "disease_context": "degenerative disk disease"}, "readout": {"name": "pyroptosis", "assay": null, "figure_refs": []}, "effect": {"direction": "decrease", "timepoint": "168h", "magnitude": null, "comparison": "CRISPR-KO targeting RAPTOR"}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all inhibited pyroptosis.", "notes": "Multi-target propagated from quote."}, "confidence": 0.9}, {"intervention": {"category": "CRISPR_KO", "raw_text": "CRISPR–Cas9 plasmid targeting RAPTOR", "target": {"name": "RAPTOR", "entity_type": "protein"}, "modality": "INHIBITION"}, "system": {"species": "human", "cell_type": "nucleus pulposus", "cell_lines": ["degenerative disk cells"], "genotype_context": null, "disease_context": "degenerative disk disease"}, "readout": {"name": "pyroptosis", "assay": null, "figure_refs": []}, "effect": {"direction": "decrease", "timepoint": "168h", "magnitude": null, "comparison": "CRISPR-KO targeting RAPTOR"}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all inhibited pyroptosis.", "notes": "Multi-target propagated from quote."}, "confidence": 0.9}, {"intervention": {"category": "CRISPR_KO", "raw_text": "CRISPR–Cas9 plasmid targeting RAPTOR", "target": {"name": "RICTOR", "entity_type": "protein"}, "modality": "INHIBITION"}, "system": {"species": "human", "cell_type": "nucleus pulposus", "cell_lines": ["degenerative disk cells"], "genotype_context": null, "disease_context": "degenerative disk disease"}, "readout": {"name": "pyroptosis", "assay": null, "figure_refs": []}, "effect": {"direction": "decrease", "timepoint": "168h", "magnitude": null, "comparison": "CRISPR-KO targeting RAPTOR"}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all inhibited pyroptosis.", "notes": "Multi-target propagated from quote."}, "confidence": 0.9}, {"intervention": {"category": "CRISPR_KO", "raw_text": "CRISPR–Cas9 plasmid targeting RICTOR", "target": {"name": "mTOR", "entity_type": "protein"}, "modality": "INHIBITION"}, "system": {"species": "human", "cell_type": "nucleus pulposus", "cell_lines": ["degenerative disk cells"], "genotype_context": null, "disease_context": "degenerative disk disease"}, "readout": {"name": "matrix catabolism", "assay": null, "figure_refs": []}, "effect": {"direction": "decrease", "timepoint": "168h", "magnitude": null, "comparison": "CRISPR-KO targeting RICTOR"}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all inhibited matrix catabolism.", "notes": "Multi-target propagated from quote."}, "confidence": 0.9}, {"intervention": {"category": "CRISPR_KO", "raw_text": "CRISPR–Cas9 plasmid targeting RICTOR", "target": {"name": "RAPTOR", "entity_type": "protein"}, "modality": "INHIBITION"}, "system": {"species": "human", "cell_type": "nucleus pulposus", "cell_lines": ["degenerative disk cells"], "genotype_context": null, "disease_context": "degenerative disk disease"}, "readout": {"name": "matrix catabolism", "assay": null, "figure_refs": []}, "effect": {"direction": "decrease", "timepoint": "168h", "magnitude": null, "comparison": "CRISPR-KO targeting RICTOR"}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all inhibited matrix catabolism.", "notes": "Multi-target propagated from quote."}, "confidence": 0.9}, {"intervention": {"category": "CRISPR_KO", "raw_text": "CRISPR–Cas9 plasmid targeting RICTOR", "target": {"name": "RICTOR", "entity_type": "protein"}, "modality": "INHIBITION"}, "system": {"species": "human", "cell_type": "nucleus pulposus", "cell_lines": ["degenerative disk cells"], "genotype_context": null, "disease_context": "degenerative disk disease"}, "readout": {"name": "matrix catabolism", "assay": null, "figure_refs": []}, "effect": {"direction": "decrease", "timepoint": "168h", "magnitude": null, "comparison": "CRISPR-KO targeting RICTOR"}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all inhibited matrix catabolism.", "notes": "Multi-target propagated from quote."}, "confidence": 0.9}, {"intervention": {"category": "KNOCKDOWN_RNAI", "raw_text": "siRNA or CRISPR–Cas9 plasmid targeting RAPTOR", "target": {"name": "RAPTOR", "entity_type": "protein"}, "modality": "INHIBITION"}, "system": {"species": "human", "cell_type": "nucleus pulposus", "cell_lines": ["degenerative disk cells"], "genotype_context": null, "disease_context": "degenerative disk disease"}, "readout": {"name": "autophagy", "assay": null, "figure_refs": []}, "effect": {"direction": "increase", "timepoint": "168h", "magnitude": "53.8-60.3%", "comparison": "RNAi targeting RAPTOR"}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Both of the approaches specifically suppressed target protein expression; however, the 24-h transfection efficiency differed by 53.8–60.3% for RNAi.", "notes": null}, "confidence": 0.9}, {"intervention": {"category": "KNOCKDOWN_RNAI", "raw_text": "siRNA or CRISPR–Cas9 plasmid targeting RICTOR", "target": {"name": "RICTOR", "entity_type": "protein"}, "modality": "INHIBITION"}, "system": {"species": "human", "cell_type": "nucleus pulposus", "cell_lines": ["degenerative disk cells"], "genotype_context": null, "disease_context": "degenerative disk disease"}, "readout": {"name": "apoptosis", "assay": null, "figure_refs": []}, "effect": {"direction": "decrease", "timepoint": "168h", "magnitude": null, "comparison": "RNAi targeting RICTOR"}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Both of the approaches specifically suppressed target protein expression.", "notes": null}, "confidence": 0.9}, {"intervention": {"category": "KNOCKDOWN_RNAI", "raw_text": "siRNA or CRISPR–Cas9 plasmid targeting mTOR", "target": {"name": "mTOR", "entity_type": "protein"}, "modality": "INHIBITION"}, "system": {"species": "human", "cell_type": "nucleus pulposus", "cell_lines": ["degenerative disk cells"], "genotype_context": null, "disease_context": "degenerative disk disease"}, "readout": {"name": "senescence", "assay": null, "figure_refs": []}, "effect": {"direction": "decrease", "timepoint": "168h", "magnitude": null, "comparison": "RNAi targeting mTOR"}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Both of the approaches specifically suppressed target protein expression.", "notes": null}, "confidence": 0.9}], "warnings": ["No specific readouts were analyzed for the siRNA transfections due to lack of detailed results."], "bridge": {"enabled": false, "attempted": false, "used": false, "mode": null, "source_doc_ids": ["PMID:39682777"], "source_chunk_ids": [2], "skipped_reason": "bridge_off"}, "_routing": {"first_model": "gpt-4o-mini", "escalated": false, "final_model": "gpt-4o-mini", "reason": null}, "_post": {"dropped_atoms": 0, "clause_split": {"enabled": true, "events": 0, "expanded_atoms": 0}, "multi_target": {"enabled": true, "anchors": 5, "events_all": 5, "events_propagated": 5, "expanded_atoms": 10}}}

* * *

**ChatGPT:**

Perfect — **multi-target propagation is now working** (your `_post.multi_target.events_propagated = 5` confirms it). ✅

But your v14 chunk 2 output also reveals the _next_ set of “quiet wrongness” we need to stop:

### What’s still wrong in this v14 chunk 2 output

1. **Hallucinated details**: `timepoint="168h"`, `magnitude="88.1%"`, and the `comparison=...` strings are **not in your supporting_quote**, and very likely not in the chunk text. These must be **null unless explicitly stated**.
2. **Modality mismatch**: for **CRISPR_KO** and **KNOCKDOWN_RNAI**, modality should be **LOF (loss-of-function)**, not `INHIBITION`.
3. **Propagation creates inconsistent raw_text**: e.g. `raw_text="...targeting mTOR"` but `target="RAPTOR"` / `RICTOR`. After propagation, `raw_text` should reflect the **multi-target anchor phrase** (e.g., `"Targeting mTOR, RAPTOR, and RICTOR"`), not one specific target.
4. **RNAi “transfection efficiency / suppressed protein expression” got mis-labeled as autophagy/apoptosis/senescence** in a couple atoms. If the quote is just QC (“suppressed target protein expression”), the readout should be **target protein expression**, not phenotypes.

So: we keep the multi-target logic you now have — and we add a strict “no made-up fields + grounding checks” post-pass.

* * *

# Run this next: v15 (full script, no edits)

**Save as:** `make_atoms_docaware_v15.py`

```Python
import os
import re
import json
import argparse
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple
from copy import deepcopy
from openai import OpenAI

# ============================================================
# CONFIG DEFAULTS
# ============================================================
INFILE = Path("mentions.jsonl")
OUTFILE = Path("atoms.jsonl")

MODEL_FAST_DEFAULT = "gpt-4o-mini"
MODEL_STRONG_DEFAULT = "gpt-4.1"

MAX_ATOMS_PER_CHUNK_DEFAULT = 30
BRIDGE_DEFAULT = "off"

# ============================================================
# OPENAI CLIENT
# ============================================================
def _get_api_key() -> str:
    key = os.getenv("OPENAI_API_KEY")
    if not key:
        raise RuntimeError(
            "OPENAI_API_KEY is not set.\n"
            "Temporary (this shell):  set OPENAI_API_KEY=YOUR_KEY\n"
            "Persistent (Windows):     setx OPENAI_API_KEY \"YOUR_KEY\"  (then reopen prompt)"
        )
    return key

client = OpenAI(api_key=_get_api_key())

# ============================================================
# STRICT JSON SCHEMA FOR ATOMS (model output)
# ============================================================
ATOM_SCHEMA_WRAPPER: Dict[str, Any] = {
    "name": "MechanisticAtoms",
    "schema": {
        "type": "object",
        "additionalProperties": False,
        "required": ["atoms", "warnings"],
        "properties": {
            "atoms": {
                "type": "array",
                "items": {
                    "type": "object",
                    "additionalProperties": False,
                    "required": [
                        "intervention",
                        "system",
                        "readout",
                        "effect",
                        "strength_cues",
                        "evidence",
                        "confidence",
                    ],
                    "properties": {
                        "intervention": {
                            "type": "object",
                            "additionalProperties": False,
                            "required": ["category", "raw_text", "target", "modality"],
                            "properties": {
                                "category": {
                                    "type": "string",
                                    "enum": [
                                        "GENETIC_KO",
                                        "CRISPR_KO",
                                        "CRISPRi",
                                        "CRISPRa",
                                        "KNOCKDOWN_RNAI",
                                        "SPLICING_MODULATION",
                                        "OVEREXPRESSION",
                                        "RESCUE_ADD_BACK",
                                        "DOMINANT_NEGATIVE",
                                        "MUTANT_VARIANT",
                                        "CHEMICAL_INHIBITOR",
                                        "CHEMICAL_ACTIVATOR",
                                        "CHEMICAL_DEGRADER",
                                        "STIMULUS_TREATMENT",
                                        "NEUTRALIZING_ANTIBODY",
                                        "UNKNOWN",
                                    ],
                                },
                                "raw_text": {"type": "string", "minLength": 1},
                                "target": {
                                    "anyOf": [
                                        {
                                            "type": "object",
                                            "additionalProperties": False,
                                            "required": ["name", "entity_type"],
                                            "properties": {
                                                "name": {"type": "string"},
                                                "entity_type": {
                                                    "type": "string",
                                                    "enum": [
                                                        "gene",
                                                        "protein",
                                                        "chemical",
                                                        "stimulus",
                                                        "antibody",
                                                        "unknown",
                                                    ],
                                                },
                                            },
                                        },
                                        {"type": "null"},
                                    ]
                                },
                                "modality": {
                                    "type": "string",
                                    "enum": [
                                        "LOF",
                                        "GOF",
                                        "INHIBITION",
                                        "ACTIVATION",
                                        "DEGRADATION",
                                        "RESCUE",
                                        "UNKNOWN",
                                    ],
                                },
                            },
                        },
                        "system": {
                            "type": "object",
                            "additionalProperties": False,
                            "required": [
                                "species",
                                "cell_type",
                                "cell_lines",
                                "genotype_context",
                                "disease_context",
                            ],
                            "properties": {
                                "species": {"type": ["string", "null"]},
                                "cell_type": {"type": ["string", "null"]},
                                "cell_lines": {"type": "array", "items": {"type": "string"}},
                                "genotype_context": {"type": ["string", "null"]},
                                "disease_context": {"type": ["string", "null"]},
                            },
                        },
                        "readout": {
                            "type": "object",
                            "additionalProperties": False,
                            "required": ["name", "assay", "figure_refs"],
                            "properties": {
                                "name": {"type": "string"},
                                "assay": {"type": ["string", "null"]},
                                "figure_refs": {"type": "array", "items": {"type": "string"}},
                            },
                        },
                        "effect": {
                            "type": "object",
                            "additionalProperties": False,
                            "required": ["direction", "timepoint", "magnitude", "comparison"],
                            "properties": {
                                "direction": {
                                    "type": "string",
                                    "enum": ["increase", "decrease", "no_change", "mixed", "unknown"],
                                },
                                "timepoint": {"type": ["string", "null"]},
                                "magnitude": {"type": ["string", "null"]},
                                "comparison": {"type": ["string", "null"]},
                            },
                        },
                        "strength_cues": {
                            "type": "object",
                            "additionalProperties": False,
                            "required": ["has_rescue", "has_control", "has_multiple_lines", "other"],
                            "properties": {
                                "has_rescue": {"type": "boolean"},
                                "has_control": {"type": "boolean"},
                                "has_multiple_lines": {"type": "boolean"},
                                "other": {"type": "array", "items": {"type": "string"}},
                            },
                        },
                        "evidence": {
                            "type": "object",
                            "additionalProperties": False,
                            "required": ["supporting_quote", "notes"],
                            "properties": {
                                "supporting_quote": {"type": "string"},
                                "notes": {"type": ["string", "null"]},
                            },
                        },
                        "confidence": {"type": "number", "minimum": 0, "maximum": 1},
                    },
                },
            },
            "warnings": {"type": "array", "items": {"type": "string"}},
        },
    },
}

# ============================================================
# DOC ID SELECTION (PMID + optional PMCID; then DOI; then journal biblio; then file; then chunk)
# ============================================================
def _norm(s: Any) -> Optional[str]:
    if s is None:
        return None
    s = str(s).strip()
    return s if s else None

def _safe_journal_token(s: str) -> str:
    # keep letters/numbers/space/.- and collapse whitespace
    s = re.sub(r"\s+", " ", s.strip())
    s = re.sub(r"[^A-Za-z0-9 .\-]", "", s)
    return s[:80]

def choose_doc_id(rec: Dict[str, Any]) -> Tuple[str, str]:
    pmid = _norm(rec.get("pmid"))
    pmcid = _norm(rec.get("pmcid"))
    doi = _norm(rec.get("doi"))
    source_file = _norm(rec.get("source_file"))
    chunk_id = rec.get("chunk_id")

    journal = _norm(rec.get("journal"))
    volume = _norm(rec.get("volume"))
    year = _norm(rec.get("year")) or _norm(rec.get("pub_year"))
    pages = _norm(rec.get("pages"))

    if pmid and pmcid:
        return f"PMID:{pmid}|PMCID:{pmcid}", "pmid_pmcid"
    if pmid:
        return f"PMID:{pmid}", "pmid"
    if pmcid:
        return f"PMCID:{pmcid}", "pmcid"
    if doi:
        return f"DOI:{doi}", "doi"
    if journal and volume and year and pages:
        j = _safe_journal_token(journal)
        return f"JOURNAL:{j}|VOL:{volume}|YEAR:{year}|PP:{pages}", "journal_biblio"
    if source_file:
        return f"FILE:{Path(source_file).name}", "source_file"
    return f"CHUNK:{chunk_id}", "chunk_fallback"

# ============================================================
# PROMPT
# ============================================================
def build_system_instructions(max_atoms: int) -> str:
    return (
        "Extract mechanistic atoms from biomedical text.\n\n"
        "An atom MUST include an explicit effect on a readout.\n"
        "Format: [INTERVENTION] causes [EFFECT] in [READOUT] in a [SYSTEM].\n\n"
        "Hard rules:\n"
        "1) Do NOT invent details.\n"
        "2) Only fill timepoint/magnitude/comparison if explicitly stated in text.\n"
        "3) supporting_quote MUST be copied verbatim from the chunk_text.\n"
        "4) If a sentence says 'A, B, and C all did X' (or equivalent), emit parallel atoms for A, for B, and for C.\n"
        "5) If multiple readouts share the same verb ('inhibited apoptosis, senescence, ...'), you may emit one atom per readout.\n"
        f"6) Keep at most {max_atoms} atoms.\n"
    )

# ============================================================
# MODEL CALL + ROUTING
# ============================================================
def compact_mentions(mentions: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    out = []
    for i, m in enumerate(mentions, start=1):
        out.append({
            "i": i,
            "category": m.get("category"),
            "raw_text": m.get("raw_text"),
            "target_guess": m.get("target_guess"),
            "method_cues": m.get("method_cues", []),
        })
    return out

def call_model(model: str, chunk_text: str, mentions: List[Dict[str, Any]], max_atoms: int) -> Dict[str, Any]:
    payload = {"chunk_text": chunk_text, "mentions": compact_mentions(mentions)}
    resp = client.responses.create(
        model=model,
        input=[
            {"role": "system", "content": build_system_instructions(max_atoms)},
            {"role": "user", "content": json.dumps(payload, ensure_ascii=False)},
        ],
        text={
            "format": {
                "type": "json_schema",
                "name": ATOM_SCHEMA_WRAPPER["name"],
                "strict": True,
                "schema": ATOM_SCHEMA_WRAPPER["schema"],
            }
        },
    )
    return json.loads(resp.output_text)

def should_escalate(mentions: List[Dict[str, Any]], atoms: List[Dict[str, Any]], warnings: List[str]) -> bool:
    if len(mentions) > 0 and len(atoms) == 0:
        return True
    if len(atoms) > 0:
        avg_conf = sum(a.get("confidence", 0) for a in atoms) / max(1, len(atoms))
        if avg_conf < 0.60:
            return True
    return False

def extract_atoms_with_routing(
    chunk_text: str,
    mentions: List[Dict[str, Any]],
    model_fast: str,
    model_strong: str,
    max_atoms: int,
) -> Dict[str, Any]:
    routing = {"first_model": model_fast, "escalated": False, "final_model": model_fast, "reason": None}

    out_fast = call_model(model_fast, chunk_text, mentions, max_atoms)
    atoms_fast = out_fast.get("atoms", [])
    warnings_fast = out_fast.get("warnings", [])

    if should_escalate(mentions, atoms_fast, warnings_fast):
        routing["escalated"] = True
        routing["final_model"] = model_strong
        routing["reason"] = {"type": "low_confidence_or_empty", "details": "heuristics triggered"}

        out_strong = call_model(model_strong, chunk_text, mentions, max_atoms)
        out_strong["_routing"] = routing
        return out_strong

    out_fast["_routing"] = routing
    return out_fast

# ============================================================
# POST-FILTER: must include an effect cue
# ============================================================
EFFECT_CUE = re.compile(
    r"\b("
    r"inhibit|inhibited|inhibition|inhibitory|"
    r"suppress|suppressed|suppression|"
    r"reduce|reduced|reduces|reduction|"
    r"decrease|decreased|decreases|"
    r"increase|increased|increases|"
    r"induce|induced|induces|"
    r"promote|promoted|promotes|"
    r"activate|activated|activates|"
    r"abolish|abolished|"
    r"no effect|did not affect|had no effect|"
    r"rescue|rescued|restore|restored|"
    r"antiproliferative|anti-proliferative|anti proliferative"
    r")\b",
    re.IGNORECASE,
)

def post_filter_atoms(atoms: List[Dict[str, Any]]) -> Tuple[List[Dict[str, Any]], int]:
    kept, dropped = [], 0
    for a in atoms:
        sq = (a.get("evidence", {}) or {}).get("supporting_quote", "") or ""
        if EFFECT_CUE.search(sq):
            kept.append(a)
        else:
            dropped += 1
    return kept, dropped

# ============================================================
# MULTI-TARGET EXPANSION
# ============================================================
def _extract_candidate_targets_from_record(
    mentions: List[Dict[str, Any]],
    atoms: List[Dict[str, Any]],
) -> List[str]:
    cands: List[str] = []

    for m in mentions:
        tg = (m.get("target_guess") or {})
        name = tg.get("name")
        if not name:
            continue
        for part in re.split(r",|\band\b|\bor\b|/|;", str(name), flags=re.IGNORECASE):
            part = part.strip()
            if part and len(part) <= 40:
                cands.append(part)

    for a in atoms:
        t = (a.get("intervention", {}) or {}).get("target") or {}
        nm = t.get("name")
        if nm:
            cands.append(str(nm).strip())

    seen, out = set(), []
    for x in cands:
        k = x.lower()
        if k not in seen:
            seen.add(k)
            out.append(x)
    return out

def _quote_mentions_targets(quote: str, targets: List[str]) -> List[str]:
    hits = []
    qlow = quote.lower()
    for t in targets:
        if t.lower() in qlow:
            hits.append(t)
    return hits

ANCHOR_PHRASE_RE = re.compile(
    r"(Targeting\s+.+?)(?:\s+\b(all|each|both)\b|\s+\b(induced|inhibited|reduced|suppressed|decreased|increased|activated|promoted)\b)",
    re.IGNORECASE,
)

def _extract_anchor_phrase(quote: str) -> Optional[str]:
    m = ANCHOR_PHRASE_RE.search(quote)
    if not m:
        return None
    return m.group(1).strip().rstrip(" .;:")

def multi_target_expand_atoms(
    atoms: List[Dict[str, Any]],
    mentions: List[Dict[str, Any]],
) -> Tuple[List[Dict[str, Any]], Dict[str, Any]]:
    cands = _extract_candidate_targets_from_record(mentions, atoms)
    expanded: List[Dict[str, Any]] = []
    anchors = 0
    events_all = 0
    events_propagated = 0

    for a in atoms:
        sq = (a.get("evidence", {}) or {}).get("supporting_quote", "") or ""
        hits = _quote_mentions_targets(sq, cands)
        if len(hits) < 2:
            expanded.append(a)
            continue

        anchors += 1
        events_all += 1
        anchor_phrase = _extract_anchor_phrase(sq)

        for tname in hits:
            na = deepcopy(a)
            if na.get("intervention", {}).get("target") is None:
                na["intervention"]["target"] = {"name": tname, "entity_type": "protein"}
            else:
                na["intervention"]["target"]["name"] = tname

            # Critical: prevent inconsistent raw_text after propagation
            if anchor_phrase:
                na["intervention"]["raw_text"] = anchor_phrase

            note = (na.get("evidence", {}) or {}).get("notes")
            na["evidence"]["notes"] = (note + " | " if note else "") + "Multi-target propagated from quote."
            expanded.append(na)

        events_propagated += 1

    stats = {
        "enabled": True,
        "anchors": anchors,
        "events_all": events_all,
        "events_propagated": events_propagated,
        "expanded_atoms": len(expanded) - len(atoms),
    }
    return expanded, stats

# ============================================================
# NORMALIZATION / GROUNDING (key v15 fix)
# ============================================================
CATEGORY_TO_MODALITY = {
    "GENETIC_KO": "LOF",
    "CRISPR_KO": "LOF",
    "CRISPRi": "LOF",
    "KNOCKDOWN_RNAI": "LOF",
    "SPLICING_MODULATION": "LOF",
    "CRISPRa": "GOF",
    "OVEREXPRESSION": "GOF",
    "RESCUE_ADD_BACK": "RESCUE",
    "DOMINANT_NEGATIVE": "LOF",
    "MUTANT_VARIANT": "UNKNOWN",
    "CHEMICAL_INHIBITOR": "INHIBITION",
    "CHEMICAL_DEGRADER": "DEGRADATION",
    "CHEMICAL_ACTIVATOR": "ACTIVATION",
    "STIMULUS_TREATMENT": "ACTIVATION",
    "NEUTRALIZING_ANTIBODY": "INHIBITION",
    "UNKNOWN": "UNKNOWN",
}

SENT_SPLIT = re.compile(r"(?<=[.!?])\s+")

def _contains_ci(hay: str, needle: str) -> bool:
    return needle.lower() in hay.lower()

def _null_if_not_grounded(val: Optional[str], chunk_text: str) -> Optional[str]:
    if val is None:
        return None
    v = str(val).strip()
    if not v:
        return None
    return v if _contains_ci(chunk_text, v) else None

def _readout_grounded(readout_name: str, quote: str) -> bool:
    rn = (readout_name or "").strip().lower()
    if not rn:
        return False
    q = quote.lower()
    # token-level grounding (avoids brittle exact match)
    toks = [t for t in re.split(r"[^a-z0-9]+", rn) if len(t) >= 4]
    if not toks:
        return rn in q
    return any(t in q for t in toks)

def _best_sentence_fallback(chunk_text: str, target: Optional[str], readout: str) -> Optional[str]:
    sents = SENT_SPLIT.split(chunk_text.strip())
    if not sents:
        return None
    keys = []
    if target:
        keys.append(target.lower())
    for t in re.split(r"[^a-z0-9]+", (readout or "").lower()):
        if len(t) >= 4:
            keys.append(t)
    keys = list(dict.fromkeys(keys))
    best = None
    best_score = 0
    for s in sents:
        sl = s.lower()
        score = sum(1 for k in keys if k in sl)
        if score > best_score:
            best_score = score
            best = s.strip()
    return best if best_score >= 2 else None

def normalize_and_ground_atoms(
    atoms: List[Dict[str, Any]],
    chunk_text: str,
    warnings: List[str],
) -> List[Dict[str, Any]]:
    out = []
    for a in atoms:
        itv = a.get("intervention", {}) or {}
        eff = a.get("effect", {}) or {}
        ev = a.get("evidence", {}) or {}
        ro = a.get("readout", {}) or {}

        category = itv.get("category", "UNKNOWN")
        expected_mod = CATEGORY_TO_MODALITY.get(category, "UNKNOWN")
        if expected_mod != "UNKNOWN":
            itv["modality"] = expected_mod

        quote = ev.get("supporting_quote") or ""
        if quote and not _contains_ci(chunk_text, quote):
            # replace hallucinated quote with best matching sentence when possible
            tgt_name = None
            tgt = itv.get("target") or {}
            if isinstance(tgt, dict):
                tgt_name = tgt.get("name")
            fallback = _best_sentence_fallback(chunk_text, tgt_name, ro.get("name", ""))
            if fallback:
                ev["supporting_quote"] = fallback
                note = ev.get("notes")
                ev["notes"] = (note + " | " if note else "") + "supporting_quote replaced with closest sentence from chunk_text."
            else:
                warnings.append("supporting_quote was not an exact substring of chunk_text (possible hallucination).")

        # Strict: timepoint/magnitude/comparison must be grounded in chunk_text
        eff["timepoint"] = _null_if_not_grounded(eff.get("timepoint"), chunk_text)
        eff["magnitude"] = _null_if_not_grounded(eff.get("magnitude"), chunk_text)
        eff["comparison"] = _null_if_not_grounded(eff.get("comparison"), chunk_text)

        # Prevent QC sentences from being mislabeled as phenotypes
        qlow = (ev.get("supporting_quote") or "").lower()
        readout_name = ro.get("name") or ""
        if "protein expression" in qlow and not _readout_grounded(readout_name, ev.get("supporting_quote") or ""):
            ro["name"] = "target protein expression"
            eff["direction"] = "decrease"
            eff["timepoint"] = None
            eff["magnitude"] = None
            eff["comparison"] = None
            note = ev.get("notes")
            ev["notes"] = (note + " | " if note else "") + "QC statement: mapped readout to target protein expression."

        # Drop atoms whose readout is not grounded in their own quote (reduces hallucinated mappings)
        if not _readout_grounded(ro.get("name", ""), ev.get("supporting_quote") or ""):
            warnings.append("Dropped an atom because readout did not appear to be supported by its supporting_quote.")
            continue

        a["intervention"] = itv
        a["effect"] = eff
        a["evidence"] = ev
        a["readout"] = ro
        out.append(a)

    return out

# ============================================================
# DEDUP + TRUNCATE
# ============================================================
def _atom_key(a: Dict[str, Any]) -> Tuple:
    itv = a.get("intervention", {}) or {}
    sys = a.get("system", {}) or {}
    ro = a.get("readout", {}) or {}
    eff = a.get("effect", {}) or {}
    ev = a.get("evidence", {}) or {}
    tgt = itv.get("target") or {}
    return (
        itv.get("category"),
        itv.get("modality"),
        (tgt.get("name") if isinstance(tgt, dict) else None),
        ro.get("name"),
        eff.get("direction"),
        (ev.get("supporting_quote") or "").strip().lower(),
        (sys.get("species"), sys.get("cell_type")),
    )

def dedup_atoms(atoms: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    seen = set()
    out = []
    for a in atoms:
        k = _atom_key(a)
        if k in seen:
            continue
        seen.add(k)
        out.append(a)
    return out

def truncate_atoms(atoms: List[Dict[str, Any]], max_atoms: int) -> Tuple[List[Dict[str, Any]], Optional[str]]:
    if len(atoms) <= max_atoms:
        return atoms, None
    atoms_sorted = sorted(atoms, key=lambda x: float(x.get("confidence", 0)), reverse=True)
    return atoms_sorted[:max_atoms], f"Truncated atoms: {len(atoms)} -> {max_atoms} due to MAX_ATOMS_PER_CHUNK."

# ============================================================
# DRIVER
# ============================================================
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--infile", default=str(INFILE))
    ap.add_argument("--outfile", default=str(OUTFILE))
    ap.add_argument("--model_fast", default=MODEL_FAST_DEFAULT)
    ap.add_argument("--model_strong", default=MODEL_STRONG_DEFAULT)
    ap.add_argument("--max_atoms", type=int, default=MAX_ATOMS_PER_CHUNK_DEFAULT)
    ap.add_argument("--bridge", choices=["on", "off"], default=BRIDGE_DEFAULT)
    args = ap.parse_args()

    infile = Path(args.infile)
    outfile = Path(args.outfile)

    if not infile.exists():
        raise FileNotFoundError(f"Cannot find {infile.resolve()}")

    records: List[Dict[str, Any]] = []
    for ln in infile.read_text(encoding="utf-8", errors="ignore").splitlines():
        if not ln.strip():
            continue
        records.append(json.loads(ln))

    total_atoms = 0
    escalations = 0
    dropped_total = 0
    doc_source_counts: Dict[str, int] = {}

    with outfile.open("w", encoding="utf-8") as fout:
        for rec in records:
            chunk_id = rec.get("chunk_id")
            chunk_text = rec.get("chunk_text", "") or ""
            mentions = rec.get("mentions", []) or []

            doc_id, doc_src = choose_doc_id(rec)
            doc_source_counts[doc_src] = doc_source_counts.get(doc_src, 0) + 1

            out = extract_atoms_with_routing(
                chunk_text=chunk_text,
                mentions=mentions,
                model_fast=args.model_fast,
                model_strong=args.model_strong,
                max_atoms=args.max_atoms,
            )
            routing = out.get("_routing", {})
            atoms = out.get("atoms", []) or []
            warnings = out.get("warnings", []) or []

            # 1) must have effect cue
            atoms, dropped = post_filter_atoms(atoms)
            dropped_total += dropped

            # 2) multi-target propagation
            atoms, mt_stats = multi_target_expand_atoms(atoms, mentions)

            # 3) normalize + grounding
            atoms = normalize_and_ground_atoms(atoms, chunk_text, warnings)

            # 4) dedup + truncate
            atoms = dedup_atoms(atoms)
            trunc_warn = None
            atoms, trunc_warn = truncate_atoms(atoms, args.max_atoms)
            if trunc_warn:
                warnings.append(trunc_warn)

            if routing.get("escalated"):
                escalations += 1

            total_atoms += len(atoms)

            record_out = {
                "doc_id": doc_id,
                "doc_id_source": doc_src,
                "pmid": rec.get("pmid"),
                "pmcid": rec.get("pmcid"),
                "doi": rec.get("doi"),
                "source_file": rec.get("source_file"),
                "chunk_index": rec.get("chunk_index"),
                "chunk_id": chunk_id,
                "atoms": atoms,
                "warnings": warnings,
                "bridge": {
                    "enabled": (args.bridge == "on"),
                    "attempted": False,
                    "used": False,
                    "mode": None,
                    "source_doc_ids": [doc_id],
                    "source_chunk_ids": [chunk_id],
                    "skipped_reason": "bridge_off" if args.bridge == "off" else "not_implemented_in_v15",
                },
                "_routing": routing,
                "_post": {
                    "dropped_atoms": dropped,
                    "multi_target": mt_stats,
                },
            }

            fout.write(json.dumps(record_out, ensure_ascii=False) + "\n")
            print(
                f"chunk {chunk_id} doc_id={doc_id} atoms={len(atoms)} "
                f"escalated={routing.get('escalated', False)} bridge={args.bridge} dropped={dropped}"
            )

    print(f"Done. total_atoms={total_atoms}, escalations={escalations}, dropped_total={dropped_total}")
    print("doc_id sources: " + ", ".join(f"{k}={v}" for k, v in sorted(doc_source_counts.items())))
    if args.bridge == "off":
        print("Note: bridging was OFF (recommended for mixed/random chunks).")

if __name__ == "__main__":
    main()
```

* * *

## Run exactly this

```bat
conda activate pathai
cd "C:\Users\Prem Subramaniam\Documents\Pathway AI"
python make_atoms_docaware_v15.py --bridge off
```

* * *

## What you should see improve in chunk 2

* **No more invented** `168h`, `88.1%`, or made-up `comparison` strings → they’ll become **null** unless present in the chunk text.
* **CRISPR_KO / KNOCKDOWN_RNAI modality becomes LOF** automatically.
* **Multi-target propagated atoms will have consistent raw_text** (the “Targeting mTOR, RAPTOR, and RICTOR …” anchor).
* The RNAi QC lines will **not** produce fake apoptosis/senescence/autophagy atoms; if kept at all, they’ll map to **target protein expression**.

Paste back **just chunk 2 from atoms.jsonl after v15** (like you did here), and I’ll sanity-check it quickly against these four points.

* * *

**You:**

I think we are going in circles.  Should we start with new code?

* * *

**ChatGPT:**

Yeah — I agree with you. What’s happening now is **we keep patching downstream symptoms** (hallucinated timepoints, wrong modality, inconsistent raw_text after propagation, QC sentences turning into phenotypes), and each patch creates a new edge case. That _feels_ like progress, but it’s basically a loop.

### The reset that stops the loop

Start fresh with a **simpler contract**:

* **Model outputs “events”** (one per claim), not full atoms.
    * Each event includes:
        * _targets as a list_ (so “A, B, C all did X” is naturally represented)
        * _readouts as a list_ (so “inhibited apoptosis, senescence…” is naturally represented)
        * _one verbatim supporting_quote_ copied from the chunk
* **Python expands events → atoms deterministically**
    * one atom per _(target × readout)_ pair
* **Hard grounding is enforced in code**
    * timepoint/magnitude/comparison/system fields are **nulled unless they literally appear in the supporting_quote**
    * modality is set deterministically from category (CRISPR_KO/RNAi → LOF, etc.)
    * QC lines like “suppressed target protein expression” **cannot become autophagy/apoptosis**

If you’re open to it, this is the cleanest “new code” start.

* * *

## Here is full runnable new code: `make_atoms_docaware_v16.py`

This version **does not depend on your existing mentions.jsonl**. It reads your `pisk_mtor_seed_texts.txt` directly (each chunk starts with `PMID:`), extracts events with strict quoting, expands to atoms, and writes `atoms.jsonl`.

Save this as `make_atoms_docaware_v16.py` in `C:\Users\Prem Subramaniam\Documents\Pathway AI\`.

```Python
import os
import re
import json
import argparse
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple
from copy import deepcopy
from openai import OpenAI

# ==========================
# OpenAI client
# ==========================
def _get_api_key() -> str:
    key = os.getenv("OPENAI_API_KEY")
    if not key:
        raise RuntimeError(
            "OPENAI_API_KEY is not set.\n"
            "Temporary (this shell):  set OPENAI_API_KEY=YOUR_KEY\n"
            "Persistent (Windows):     setx OPENAI_API_KEY \"YOUR_KEY\"  (then reopen prompt)"
        )
    return key

client = OpenAI(api_key=_get_api_key())

# ==========================
# Defaults
# ==========================
MODEL_FAST_DEFAULT = "gpt-4o-mini"
MODEL_STRONG_DEFAULT = "gpt-4.1"
MAX_ATOMS_PER_CHUNK_DEFAULT = 30

# ==========================
# Doc-id logic
# ==========================
def _norm(x: Any) -> Optional[str]:
    if x is None:
        return None
    s = str(x).strip()
    return s if s else None

def _safe_journal_token(s: str) -> str:
    s = re.sub(r"\s+", " ", s.strip())
    s = re.sub(r"[^A-Za-z0-9 .\-]", "", s)
    return s[:80]

def choose_doc_id(meta: Dict[str, Any], chunk_id: int) -> Tuple[str, str]:
    pmid = _norm(meta.get("pmid"))
    pmcid = _norm(meta.get("pmcid"))
    doi = _norm(meta.get("doi"))
    source_file = _norm(meta.get("source_file"))

    journal = _norm(meta.get("journal"))
    volume = _norm(meta.get("volume"))
    year = _norm(meta.get("year")) or _norm(meta.get("pub_year"))
    pages = _norm(meta.get("pages"))

    if pmid and pmcid:
        return f"PMID:{pmid}|PMCID:{pmcid}", "pmid_pmcid"
    if pmid:
        return f"PMID:{pmid}", "pmid"
    if pmcid:
        return f"PMCID:{pmcid}", "pmcid"
    if doi:
        return f"DOI:{doi}", "doi"
    if journal and volume and year and pages:
        j = _safe_journal_token(journal)
        return f"JOURNAL:{j}|VOL:{volume}|YEAR:{year}|PP:{pages}", "journal_biblio"
    if source_file:
        return f"FILE:{Path(source_file).name}", "source_file"
    return f"CHUNK:{chunk_id}", "chunk_fallback"

# ==========================
# Chunk parsing (PMID-based)
# ==========================
PMID_LINE = re.compile(r"^\s*PMID:\s*(\d+)\b(.*)$", re.IGNORECASE)
PMCID_INLINE = re.compile(r"\bPMCID:\s*(PMC\d+)\b", re.IGNORECASE)
DOI_INLINE = re.compile(r"\bdoi:\s*([^\s]+)\b", re.IGNORECASE)

def parse_seed_file(path: Path) -> List[Dict[str, Any]]:
    """
    Reads pisk_mtor_seed_texts.txt-like file where each chunk starts with a line:
      PMID: 12345678 <rest of text...>
    Returns list of records: {chunk_id, meta, chunk_text}
    """
    lines = path.read_text(encoding="utf-8", errors="ignore").splitlines()

    chunks: List[Dict[str, Any]] = []
    cur_meta: Dict[str, Any] = {}
    cur_text_parts: List[str] = []
    cur_started = False

    def flush():
        nonlocal cur_meta, cur_text_parts, cur_started
        if not cur_started:
            return
        text = "\n".join([p for p in cur_text_parts if p is not None]).strip()
        if text:
            chunks.append({
                "meta": deepcopy(cur_meta),
                "chunk_text": text
            })
        cur_meta = {}
        cur_text_parts = []
        cur_started = False

    for ln in lines:
        m = PMID_LINE.match(ln)
        if m:
            # New chunk starts
            flush()
            cur_started = True
            pmid = m.group(1).strip()
            rest = (m.group(2) or "").strip()
            cur_meta["pmid"] = pmid

            # Inline PMCID/DOI on same line if present
            pmcid_m = PMCID_INLINE.search(ln)
            if pmcid_m:
                cur_meta["pmcid"] = pmcid_m.group(1).strip()
            doi_m = DOI_INLINE.search(ln)
            if doi_m:
                cur_meta["doi"] = doi_m.group(1).strip()

            # Keep the "rest" as part of chunk text (without the PMID token)
            if rest:
                cur_text_parts.append(rest)
            continue

        # If we haven't seen a PMID yet, ignore leading junk/blank
        if not cur_started:
            continue

        # Parse metadata lines if they exist (optional)
        pmcid_m = PMCID_INLINE.search(ln)
        if pmcid_m and not cur_meta.get("pmcid"):
            cur_meta["pmcid"] = pmcid_m.group(1).strip()
        doi_m = DOI_INLINE.search(ln)
        if doi_m and not cur_meta.get("doi"):
            cur_meta["doi"] = doi_m.group(1).strip()

        cur_text_parts.append(ln)

    flush()

    # add chunk_id and source_file
    for i, ch in enumerate(chunks, start=1):
        ch["chunk_id"] = i
        ch["meta"]["source_file"] = str(path)
    return chunks

# ==========================
# Event schema (model output)
# ==========================
EVENT_SCHEMA_WRAPPER: Dict[str, Any] = {
    "name": "MechanisticEvents",
    "schema": {
        "type": "object",
        "additionalProperties": False,
        "required": ["events", "warnings"],
        "properties": {
            "events": {
                "type": "array",
                "items": {
                    "type": "object",
                    "additionalProperties": False,
                    "required": [
                        "intervention_category",
                        "intervention_raw",
                        "targets",
                        "readouts",
                        "supporting_quote",
                        "confidence",
                        "system",
                        "notes",
                    ],
                    "properties": {
                        "intervention_category": {
                            "type": "string",
                            "enum": [
                                "GENETIC_KO",
                                "CRISPR_KO",
                                "CRISPRi",
                                "CRISPRa",
                                "KNOCKDOWN_RNAI",
                                "SPLICING_MODULATION",
                                "OVEREXPRESSION",
                                "RESCUE_ADD_BACK",
                                "DOMINANT_NEGATIVE",
                                "MUTANT_VARIANT",
                                "CHEMICAL_INHIBITOR",
                                "CHEMICAL_ACTIVATOR",
                                "CHEMICAL_DEGRADER",
                                "STIMULUS_TREATMENT",
                                "NEUTRALIZING_ANTIBODY",
                                "UNKNOWN",
                            ],
                        },
                        "intervention_raw": {"type": "string", "minLength": 1},
                        "targets": {"type": "array", "items": {"type": "string"}, "minItems": 1},
                        "readouts": {
                            "type": "array",
                            "minItems": 1,
                            "items": {
                                "type": "object",
                                "additionalProperties": False,
                                "required": ["name", "direction", "timepoint", "magnitude", "comparison"],
                                "properties": {
                                    "name": {"type": "string", "minLength": 1},
                                    "direction": {
                                        "type": "string",
                                        "enum": ["increase", "decrease", "no_change", "mixed", "unknown"],
                                    },
                                    "timepoint": {"type": ["string", "null"]},
                                    "magnitude": {"type": ["string", "null"]},
                                    "comparison": {"type": ["string", "null"]},
                                },
                            },
                        },
                        "supporting_quote": {"type": "string", "minLength": 10},
                        "confidence": {"type": "number", "minimum": 0, "maximum": 1},
                        "system": {
                            "type": "object",
                            "additionalProperties": False,
                            "required": ["species", "cell_type", "cell_lines", "disease_context"],
                            "properties": {
                                "species": {"type": ["string", "null"]},
                                "cell_type": {"type": ["string", "null"]},
                                "cell_lines": {"type": "array", "items": {"type": "string"}},
                                "disease_context": {"type": ["string", "null"]},
                            },
                        },
                        "notes": {"type": ["string", "null"]},
                    },
                },
            },
            "warnings": {"type": "array", "items": {"type": "string"}},
        },
    },
}

CATEGORY_TO_MODALITY = {
    "GENETIC_KO": "LOF",
    "CRISPR_KO": "LOF",
    "CRISPRi": "LOF",
    "KNOCKDOWN_RNAI": "LOF",
    "SPLICING_MODULATION": "LOF",
    "CRISPRa": "GOF",
    "OVEREXPRESSION": "GOF",
    "RESCUE_ADD_BACK": "RESCUE",
    "DOMINANT_NEGATIVE": "LOF",
    "MUTANT_VARIANT": "UNKNOWN",
    "CHEMICAL_INHIBITOR": "INHIBITION",
    "CHEMICAL_DEGRADER": "DEGRADATION",
    "CHEMICAL_ACTIVATOR": "ACTIVATION",
    "STIMULUS_TREATMENT": "ACTIVATION",
    "NEUTRALIZING_ANTIBODY": "INHIBITION",
    "UNKNOWN": "UNKNOWN",
}

# ==========================
# Prompt / model call
# ==========================
EFFECT_CUE = re.compile(
    r"\b("
    r"inhibit|inhibited|inhibition|"
    r"suppress|suppressed|suppression|"
    r"reduce|reduced|reduction|"
    r"decrease|decreased|"
    r"increase|increased|"
    r"induce|induced|"
    r"activate|activated|"
    r"no effect|did not affect|had no effect|"
    r"tumor growth suppression|antiproliferative"
    r")\b",
    re.IGNORECASE,
)

def build_system_instructions(max_atoms: int) -> str:
    return (
        "You extract mechanistic EVENTS from biomedical text.\n\n"
        "You must only output events supported by a verbatim quote.\n"
        "supporting_quote MUST be copied exactly from chunk_text.\n\n"
        "Critical constraints:\n"
        "1) Do NOT invent numbers, timepoints, or comparisons.\n"
        "   If timepoint/magnitude/comparison are not literally present in supporting_quote, set them to null.\n"
        "2) If text says 'A, B, and C all did X', set targets=[A,B,C]. This is NOT combination treatment.\n"
        "3) If text says 'inhibited apoptosis, senescence, ...', put one readout entry per item.\n"
        "4) Only include system fields (species/cell_type/cell_lines/disease_context) if explicitly present in supporting_quote; otherwise null/empty.\n"
        f"5) Keep total expanded atoms under {max_atoms} after expansion; prefer higher-confidence events.\n"
        "6) If the sentence is only QC (e.g., 'suppressed target protein expression') treat readout as 'target protein expression', "
        "not downstream phenotypes.\n"
    )

def call_events_model(model: str, chunk_text: str, max_atoms: int) -> Dict[str, Any]:
    resp = client.responses.create(
        model=model,
        input=[
            {"role": "system", "content": build_system_instructions(max_atoms)},
            {"role": "user", "content": json.dumps({"chunk_text": chunk_text}, ensure_ascii=False)},
        ],
        text={
            "format": {
                "type": "json_schema",
                "name": EVENT_SCHEMA_WRAPPER["name"],
                "strict": True,
                "schema": EVENT_SCHEMA_WRAPPER["schema"],
            }
        },
    )
    return json.loads(resp.output_text)

def should_escalate(chunk_text: str, events: List[Dict[str, Any]]) -> bool:
    # If chunk contains effect language but model returned nothing, escalate
    if EFFECT_CUE.search(chunk_text) and len(events) == 0:
        return True
    # If very low confidence overall, escalate
    if events:
        avg = sum(float(e.get("confidence", 0)) for e in events) / max(1, len(events))
        if avg < 0.60:
            return True
    return False

def extract_events_with_routing(chunk_text: str, model_fast: str, model_strong: str, max_atoms: int) -> Dict[str, Any]:
    routing = {"first_model": model_fast, "escalated": False, "final_model": model_fast, "reason": None}

    out_fast = call_events_model(model_fast, chunk_text, max_atoms)
    events_fast = out_fast.get("events", []) or []

    if should_escalate(chunk_text, events_fast):
        routing["escalated"] = True
        routing["final_model"] = model_strong
        routing["reason"] = {"type": "empty_or_low_confidence", "details": "heuristics triggered"}

        out_strong = call_events_model(model_strong, chunk_text, max_atoms)
        out_strong["_routing"] = routing
        return out_strong

    out_fast["_routing"] = routing
    return out_fast

# ==========================
# Grounding / normalization helpers
# ==========================
def _contains_ci(hay: str, needle: str) -> bool:
    return needle.lower() in hay.lower()

def _null_if_not_in_quote(val: Optional[str], quote: str) -> Optional[str]:
    if val is None:
        return None
    v = str(val).strip()
    if not v:
        return None
    return v if _contains_ci(quote, v) else None

def _qc_quote(quote: str) -> bool:
    q = quote.lower()
    return ("protein expression" in q) and any(k in q for k in ["suppressed", "reduced", "decreased", "knockdown", "silenced"])

def normalize_event(event: Dict[str, Any], chunk_text: str, warnings: List[str]) -> Optional[Dict[str, Any]]:
    quote = (event.get("supporting_quote") or "").strip()
    if not quote or not _contains_ci(chunk_text, quote):
        warnings.append("Dropped an event because supporting_quote was not a verbatim substring of chunk_text.")
        return None

    # enforce quote-grounding for timepoint/magnitude/comparison
    for r in event.get("readouts", []) or []:
        r["timepoint"] = _null_if_not_in_quote(r.get("timepoint"), quote)
        r["magnitude"] = _null_if_not_in_quote(r.get("magnitude"), quote)
        r["comparison"] = _null_if_not_in_quote(r.get("comparison"), quote)

    # system fields must be in quote if filled
    sys = event.get("system") or {}
    for k in ["species", "cell_type", "disease_context"]:
        if sys.get(k) and not _contains_ci(quote, str(sys[k])):
            sys[k] = None
    # cell_lines: keep only those literally mentioned in quote
    cleaned_lines = []
    for cl in (sys.get("cell_lines") or []):
        if _contains_ci(quote, cl):
            cleaned_lines.append(cl)
    sys["cell_lines"] = cleaned_lines
    event["system"] = sys

    # QC mapping guardrail
    if _qc_quote(quote):
        for r in event.get("readouts", []) or []:
            r["name"] = "target protein expression"
            if r["direction"] == "unknown":
                r["direction"] = "decrease"

    # sanitize targets list
    targets = [t.strip() for t in (event.get("targets") or []) if str(t).strip()]
    if not targets:
        warnings.append("Dropped an event because targets list was empty after cleaning.")
        return None
    event["targets"] = targets

    # sanitize intervention_raw: must be plausible substring of quote (soft check)
    iraw = (event.get("intervention_raw") or "").strip()
    if iraw and not _contains_ci(quote, iraw):
        # don't drop; just warn and replace with a safer anchor
        warnings.append("intervention_raw was not found in supporting_quote; replacing with safer anchor phrase.")
        event["intervention_raw"] = "Intervention described in supporting_quote"

    return event

# ==========================
# Expand events -> atoms
# ==========================
def expand_events_to_atoms(events: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    atoms: List[Dict[str, Any]] = []

    for e in events:
        cat = e.get("intervention_category", "UNKNOWN")
        modality = CATEGORY_TO_MODALITY.get(cat, "UNKNOWN")
        iraw = e.get("intervention_raw", "")
        sys = e.get("system") or {}
        quote = e.get("supporting_quote") or ""
        notes = e.get("notes")
        conf = float(e.get("confidence", 0.75))

        for tgt in e.get("targets", []):
            # assume protein unless clearly chemical category
            entity_type = "protein"
            if cat in ["CHEMICAL_INHIBITOR", "CHEMICAL_DEGRADER", "CHEMICAL_ACTIVATOR"]:
                entity_type = "protein"

            for rd in e.get("readouts", []) or []:
                atom = {
                    "intervention": {
                        "category": cat,
                        "raw_text": iraw,
                        "target": {"name": tgt, "entity_type": entity_type},
                        "modality": modality,
                    },
                    "system": {
                        "species": sys.get("species"),
                        "cell_type": sys.get("cell_type"),
                        "cell_lines": sys.get("cell_lines") or [],
                        "genotype_context": None,
                        "disease_context": sys.get("disease_context"),
                    },
                    "readout": {"name": rd.get("name"), "assay": None, "figure_refs": []},
                    "effect": {
                        "direction": rd.get("direction", "unknown"),
                        "timepoint": rd.get("timepoint"),
                        "magnitude": rd.get("magnitude"),
                        "comparison": rd.get("comparison"),
                    },
                    "strength_cues": {"has_rescue": False, "has_control": False, "has_multiple_lines": False, "other": []},
                    "evidence": {"supporting_quote": quote, "notes": notes},
                    "confidence": conf,
                }
                atoms.append(atom)

    return atoms

def dedup_atoms(atoms: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    seen = set()
    out = []
    for a in atoms:
        k = (
            a["intervention"]["category"],
            a["intervention"]["modality"],
            a["intervention"]["target"]["name"].lower(),
            a["readout"]["name"].lower(),
            a["effect"]["direction"],
            (a["evidence"]["supporting_quote"] or "").strip().lower(),
        )
        if k in seen:
            continue
        seen.add(k)
        out.append(a)
    return out

def truncate_atoms(atoms: List[Dict[str, Any]], max_atoms: int) -> Tuple[List[Dict[str, Any]], Optional[str]]:
    if len(atoms) <= max_atoms:
        return atoms, None
    atoms_sorted = sorted(atoms, key=lambda x: float(x.get("confidence", 0)), reverse=True)
    return atoms_sorted[:max_atoms], f"Truncated atoms: {len(atoms)} -> {max_atoms}."

# ==========================
# Main
# ==========================
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--infile", default="pisk_mtor_seed_texts.txt")
    ap.add_argument("--outfile", default="atoms.jsonl")
    ap.add_argument("--model_fast", default=MODEL_FAST_DEFAULT)
    ap.add_argument("--model_strong", default=MODEL_STRONG_DEFAULT)
    ap.add_argument("--max_atoms", type=int, default=MAX_ATOMS_PER_CHUNK_DEFAULT)
    args = ap.parse_args()

    infile = Path(args.infile)
    if not infile.exists():
        raise FileNotFoundError(f"Cannot find {infile.resolve()}")

    chunks = parse_seed_file(infile)

    total_atoms = 0
    escalations = 0
    doc_source_counts: Dict[str, int] = {}

    outpath = Path(args.outfile)
    with outpath.open("w", encoding="utf-8") as fout:
        for rec in chunks:
            chunk_id = rec["chunk_id"]
            chunk_text = rec["chunk_text"]
            meta = rec["meta"]

            doc_id, doc_src = choose_doc_id(meta, chunk_id)
            doc_source_counts[doc_src] = doc_source_counts.get(doc_src, 0) + 1

            out = extract_events_with_routing(chunk_text, args.model_fast, args.model_strong, args.max_atoms)
            routing = out.get("_routing", {})
            events = out.get("events", []) or []
            warnings = out.get("warnings", []) or []

            if routing.get("escalated"):
                escalations += 1

            norm_events: List[Dict[str, Any]] = []
            for e in events:
                ne = normalize_event(e, chunk_text, warnings)
                if ne:
                    norm_events.append(ne)

            atoms = expand_events_to_atoms(norm_events)
            atoms = dedup_atoms(atoms)
            atoms, trunc_warn = truncate_atoms(atoms, args.max_atoms)
            if trunc_warn:
                warnings.append(trunc_warn)

            total_atoms += len(atoms)

            record_out = {
                "doc_id": doc_id,
                "doc_id_source": doc_src,
                "pmid": meta.get("pmid"),
                "pmcid": meta.get("pmcid"),
                "doi": meta.get("doi"),
                "source_file": meta.get("source_file"),
                "chunk_index": None,
                "chunk_id": chunk_id,
                "atoms": atoms,
                "warnings": warnings,
                "_routing": routing,
                "_post": {
                    "events_in": len(events),
                    "events_kept": len(norm_events),
                    "atoms_out": len(atoms),
                },
            }

            fout.write(json.dumps(record_out, ensure_ascii=False) + "\n")
            print(
                f"chunk {chunk_id} doc_id={doc_id} events={len(norm_events)} atoms={len(atoms)} "
                f"escalated={routing.get('escalated', False)}"
            )

    print(f"Done. total_atoms={total_atoms}, escalations={escalations}")
    print("doc_id sources: " + ", ".join(f"{k}={v}" for k, v in sorted(doc_source_counts.items())))

if __name__ == "__main__":
    main()
```

* * *

## Run exactly this

```bat
conda activate pathai
cd "C:\Users\Prem Subramaniam\Documents\Pathway AI"
python make_atoms_docaware_v16.py --infile pisk_mtor_seed_texts.txt --outfile atoms_v16.jsonl
```

* * *

## Why this will feel different (not circles)

* The model is **not allowed** to “finish the job” (which is where hallucinations sneak in).
* Multi-target and multi-readout are handled **by structure**, not by patchy propagation logic.
* Anything not literally present in the quote gets **nulled automatically**.

If you paste **just the single JSONL record for chunk 2 from `atoms_v16.jsonl`**, I’ll tell you immediately whether it’s finally behaving like you intended (and if not, we’ll fix the _contract_, not keep patching symptoms).

* * *

**You:**

Anyways for completeness here is chunk 2 from v15.  {"doc_id": "PMID:39682777", "doc_id_source": "pmid", "pmid": "39682777", "pmcid": null, "doi": null, "source_file": null, "chunk_index": null, "chunk_id": 2, "atoms": [{"intervention": {"category": "KNOCKDOWN_RNAI", "raw_text": "Targeting mTOR, RAPTOR, and RICTOR", "target": {"name": "mTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": "human", "cell_type": "disk nucleus pulposus cells", "cell_lines": [], "genotype_context": null, "disease_context": "degenerative disk disease"}, "readout": {"name": "autophagy", "assay": null, "figure_refs": []}, "effect": {"direction": "increase", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all induced autophagy", "notes": "Multi-target propagated from quote."}, "confidence": 1}, {"intervention": {"category": "KNOCKDOWN_RNAI", "raw_text": "Targeting mTOR, RAPTOR, and RICTOR", "target": {"name": "RAPTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": "human", "cell_type": "disk nucleus pulposus cells", "cell_lines": [], "genotype_context": null, "disease_context": "degenerative disk disease"}, "readout": {"name": "autophagy", "assay": null, "figure_refs": []}, "effect": {"direction": "increase", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all induced autophagy", "notes": "Multi-target propagated from quote."}, "confidence": 1}, {"intervention": {"category": "KNOCKDOWN_RNAI", "raw_text": "Targeting mTOR, RAPTOR, and RICTOR", "target": {"name": "RICTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": "human", "cell_type": "disk nucleus pulposus cells", "cell_lines": [], "genotype_context": null, "disease_context": "degenerative disk disease"}, "readout": {"name": "autophagy", "assay": null, "figure_refs": []}, "effect": {"direction": "increase", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all induced autophagy", "notes": "Multi-target propagated from quote."}, "confidence": 1}, {"intervention": {"category": "KNOCKDOWN_RNAI", "raw_text": "Targeting mTOR, RAPTOR, and RICTOR", "target": {"name": "mTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": "human", "cell_type": "disk nucleus pulposus cells", "cell_lines": [], "genotype_context": null, "disease_context": "degenerative disk disease"}, "readout": {"name": "apoptosis", "assay": null, "figure_refs": []}, "effect": {"direction": "decrease", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all induced autophagy and inhibited apoptosis, senescence, pyroptosis, and matrix catabolism, with the most prominent effects observed with RAPTOR CRISPR–Cas9.", "notes": "Multi-target propagated from quote. | supporting_quote replaced with closest sentence from chunk_text."}, "confidence": 1}, {"intervention": {"category": "KNOCKDOWN_RNAI", "raw_text": "Targeting mTOR, RAPTOR, and RICTOR", "target": {"name": "RAPTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": "human", "cell_type": "disk nucleus pulposus cells", "cell_lines": [], "genotype_context": null, "disease_context": "degenerative disk disease"}, "readout": {"name": "apoptosis", "assay": null, "figure_refs": []}, "effect": {"direction": "decrease", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all induced autophagy and inhibited apoptosis, senescence, pyroptosis, and matrix catabolism, with the most prominent effects observed with RAPTOR CRISPR–Cas9.", "notes": "Multi-target propagated from quote. | supporting_quote replaced with closest sentence from chunk_text."}, "confidence": 1}, {"intervention": {"category": "KNOCKDOWN_RNAI", "raw_text": "Targeting mTOR, RAPTOR, and RICTOR", "target": {"name": "RICTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": "human", "cell_type": "disk nucleus pulposus cells", "cell_lines": [], "genotype_context": null, "disease_context": "degenerative disk disease"}, "readout": {"name": "apoptosis", "assay": null, "figure_refs": []}, "effect": {"direction": "decrease", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all induced autophagy and inhibited apoptosis, senescence, pyroptosis, and matrix catabolism, with the most prominent effects observed with RAPTOR CRISPR–Cas9.", "notes": "Multi-target propagated from quote. | supporting_quote replaced with closest sentence from chunk_text."}, "confidence": 1}, {"intervention": {"category": "KNOCKDOWN_RNAI", "raw_text": "Targeting mTOR, RAPTOR, and RICTOR", "target": {"name": "mTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": "human", "cell_type": "disk nucleus pulposus cells", "cell_lines": [], "genotype_context": null, "disease_context": "degenerative disk disease"}, "readout": {"name": "senescence", "assay": null, "figure_refs": []}, "effect": {"direction": "decrease", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all induced autophagy and inhibited apoptosis, senescence, pyroptosis, and matrix catabolism, with the most prominent effects observed with RAPTOR CRISPR–Cas9.", "notes": "Multi-target propagated from quote. | supporting_quote replaced with closest sentence from chunk_text."}, "confidence": 1}, {"intervention": {"category": "KNOCKDOWN_RNAI", "raw_text": "Targeting mTOR, RAPTOR, and RICTOR", "target": {"name": "RAPTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": "human", "cell_type": "disk nucleus pulposus cells", "cell_lines": [], "genotype_context": null, "disease_context": "degenerative disk disease"}, "readout": {"name": "senescence", "assay": null, "figure_refs": []}, "effect": {"direction": "decrease", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all induced autophagy and inhibited apoptosis, senescence, pyroptosis, and matrix catabolism, with the most prominent effects observed with RAPTOR CRISPR–Cas9.", "notes": "Multi-target propagated from quote. | supporting_quote replaced with closest sentence from chunk_text."}, "confidence": 1}, {"intervention": {"category": "KNOCKDOWN_RNAI", "raw_text": "Targeting mTOR, RAPTOR, and RICTOR", "target": {"name": "RICTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": "human", "cell_type": "disk nucleus pulposus cells", "cell_lines": [], "genotype_context": null, "disease_context": "degenerative disk disease"}, "readout": {"name": "senescence", "assay": null, "figure_refs": []}, "effect": {"direction": "decrease", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all induced autophagy and inhibited apoptosis, senescence, pyroptosis, and matrix catabolism, with the most prominent effects observed with RAPTOR CRISPR–Cas9.", "notes": "Multi-target propagated from quote. | supporting_quote replaced with closest sentence from chunk_text."}, "confidence": 1}, {"intervention": {"category": "KNOCKDOWN_RNAI", "raw_text": "Targeting mTOR, RAPTOR, and RICTOR", "target": {"name": "mTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": "human", "cell_type": "disk nucleus pulposus cells", "cell_lines": [], "genotype_context": null, "disease_context": "degenerative disk disease"}, "readout": {"name": "pyroptosis", "assay": null, "figure_refs": []}, "effect": {"direction": "decrease", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all induced autophagy and inhibited apoptosis, senescence, pyroptosis, and matrix catabolism, with the most prominent effects observed with RAPTOR CRISPR–Cas9.", "notes": "Multi-target propagated from quote. | supporting_quote replaced with closest sentence from chunk_text."}, "confidence": 1}, {"intervention": {"category": "KNOCKDOWN_RNAI", "raw_text": "Targeting mTOR, RAPTOR, and RICTOR", "target": {"name": "RAPTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": "human", "cell_type": "disk nucleus pulposus cells", "cell_lines": [], "genotype_context": null, "disease_context": "degenerative disk disease"}, "readout": {"name": "pyroptosis", "assay": null, "figure_refs": []}, "effect": {"direction": "decrease", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all induced autophagy and inhibited apoptosis, senescence, pyroptosis, and matrix catabolism, with the most prominent effects observed with RAPTOR CRISPR–Cas9.", "notes": "Multi-target propagated from quote. | supporting_quote replaced with closest sentence from chunk_text."}, "confidence": 1}, {"intervention": {"category": "KNOCKDOWN_RNAI", "raw_text": "Targeting mTOR, RAPTOR, and RICTOR", "target": {"name": "RICTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": "human", "cell_type": "disk nucleus pulposus cells", "cell_lines": [], "genotype_context": null, "disease_context": "degenerative disk disease"}, "readout": {"name": "pyroptosis", "assay": null, "figure_refs": []}, "effect": {"direction": "decrease", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all induced autophagy and inhibited apoptosis, senescence, pyroptosis, and matrix catabolism, with the most prominent effects observed with RAPTOR CRISPR–Cas9.", "notes": "Multi-target propagated from quote. | supporting_quote replaced with closest sentence from chunk_text."}, "confidence": 1}, {"intervention": {"category": "KNOCKDOWN_RNAI", "raw_text": "Targeting mTOR, RAPTOR, and RICTOR", "target": {"name": "mTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": "human", "cell_type": "disk nucleus pulposus cells", "cell_lines": [], "genotype_context": null, "disease_context": "degenerative disk disease"}, "readout": {"name": "matrix catabolism", "assay": null, "figure_refs": []}, "effect": {"direction": "decrease", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all induced autophagy and inhibited apoptosis, senescence, pyroptosis, and matrix catabolism, with the most prominent effects observed with RAPTOR CRISPR–Cas9.", "notes": "Multi-target propagated from quote. | supporting_quote replaced with closest sentence from chunk_text."}, "confidence": 1}, {"intervention": {"category": "KNOCKDOWN_RNAI", "raw_text": "Targeting mTOR, RAPTOR, and RICTOR", "target": {"name": "RAPTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": "human", "cell_type": "disk nucleus pulposus cells", "cell_lines": [], "genotype_context": null, "disease_context": "degenerative disk disease"}, "readout": {"name": "matrix catabolism", "assay": null, "figure_refs": []}, "effect": {"direction": "decrease", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all induced autophagy and inhibited apoptosis, senescence, pyroptosis, and matrix catabolism, with the most prominent effects observed with RAPTOR CRISPR–Cas9.", "notes": "Multi-target propagated from quote. | supporting_quote replaced with closest sentence from chunk_text."}, "confidence": 1}, {"intervention": {"category": "KNOCKDOWN_RNAI", "raw_text": "Targeting mTOR, RAPTOR, and RICTOR", "target": {"name": "RICTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": "human", "cell_type": "disk nucleus pulposus cells", "cell_lines": [], "genotype_context": null, "disease_context": "degenerative disk disease"}, "readout": {"name": "matrix catabolism", "assay": null, "figure_refs": []}, "effect": {"direction": "decrease", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all induced autophagy and inhibited apoptosis, senescence, pyroptosis, and matrix catabolism, with the most prominent effects observed with RAPTOR CRISPR–Cas9.", "notes": "Multi-target propagated from quote. | supporting_quote replaced with closest sentence from chunk_text."}, "confidence": 1}, {"intervention": {"category": "CRISPR_KO", "raw_text": "Targeting mTOR, RAPTOR, and RICTOR", "target": {"name": "mTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": "human", "cell_type": "disk nucleus pulposus cells", "cell_lines": [], "genotype_context": null, "disease_context": "degenerative disk disease"}, "readout": {"name": "autophagy", "assay": null, "figure_refs": []}, "effect": {"direction": "increase", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all induced autophagy", "notes": "Multi-target propagated from quote."}, "confidence": 1}, {"intervention": {"category": "CRISPR_KO", "raw_text": "Targeting mTOR, RAPTOR, and RICTOR", "target": {"name": "RAPTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": "human", "cell_type": "disk nucleus pulposus cells", "cell_lines": [], "genotype_context": null, "disease_context": "degenerative disk disease"}, "readout": {"name": "autophagy", "assay": null, "figure_refs": []}, "effect": {"direction": "increase", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all induced autophagy", "notes": "Multi-target propagated from quote."}, "confidence": 1}, {"intervention": {"category": "CRISPR_KO", "raw_text": "Targeting mTOR, RAPTOR, and RICTOR", "target": {"name": "RICTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": "human", "cell_type": "disk nucleus pulposus cells", "cell_lines": [], "genotype_context": null, "disease_context": "degenerative disk disease"}, "readout": {"name": "autophagy", "assay": null, "figure_refs": []}, "effect": {"direction": "increase", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all induced autophagy", "notes": "Multi-target propagated from quote."}, "confidence": 1}, {"intervention": {"category": "CRISPR_KO", "raw_text": "Targeting mTOR, RAPTOR, and RICTOR", "target": {"name": "mTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": "human", "cell_type": "disk nucleus pulposus cells", "cell_lines": [], "genotype_context": null, "disease_context": "degenerative disk disease"}, "readout": {"name": "apoptosis", "assay": null, "figure_refs": []}, "effect": {"direction": "decrease", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all induced autophagy and inhibited apoptosis, senescence, pyroptosis, and matrix catabolism, with the most prominent effects observed with RAPTOR CRISPR–Cas9.", "notes": "Multi-target propagated from quote. | supporting_quote replaced with closest sentence from chunk_text."}, "confidence": 1}, {"intervention": {"category": "CRISPR_KO", "raw_text": "Targeting mTOR, RAPTOR, and RICTOR", "target": {"name": "RAPTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": "human", "cell_type": "disk nucleus pulposus cells", "cell_lines": [], "genotype_context": null, "disease_context": "degenerative disk disease"}, "readout": {"name": "apoptosis", "assay": null, "figure_refs": []}, "effect": {"direction": "decrease", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all induced autophagy and inhibited apoptosis, senescence, pyroptosis, and matrix catabolism, with the most prominent effects observed with RAPTOR CRISPR–Cas9.", "notes": "Multi-target propagated from quote. | supporting_quote replaced with closest sentence from chunk_text."}, "confidence": 1}, {"intervention": {"category": "CRISPR_KO", "raw_text": "Targeting mTOR, RAPTOR, and RICTOR", "target": {"name": "RICTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": "human", "cell_type": "disk nucleus pulposus cells", "cell_lines": [], "genotype_context": null, "disease_context": "degenerative disk disease"}, "readout": {"name": "apoptosis", "assay": null, "figure_refs": []}, "effect": {"direction": "decrease", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all induced autophagy and inhibited apoptosis, senescence, pyroptosis, and matrix catabolism, with the most prominent effects observed with RAPTOR CRISPR–Cas9.", "notes": "Multi-target propagated from quote. | supporting_quote replaced with closest sentence from chunk_text."}, "confidence": 1}, {"intervention": {"category": "CRISPR_KO", "raw_text": "Targeting mTOR, RAPTOR, and RICTOR", "target": {"name": "mTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": "human", "cell_type": "disk nucleus pulposus cells", "cell_lines": [], "genotype_context": null, "disease_context": "degenerative disk disease"}, "readout": {"name": "senescence", "assay": null, "figure_refs": []}, "effect": {"direction": "decrease", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all induced autophagy and inhibited apoptosis, senescence, pyroptosis, and matrix catabolism, with the most prominent effects observed with RAPTOR CRISPR–Cas9.", "notes": "Multi-target propagated from quote. | supporting_quote replaced with closest sentence from chunk_text."}, "confidence": 1}, {"intervention": {"category": "CRISPR_KO", "raw_text": "Targeting mTOR, RAPTOR, and RICTOR", "target": {"name": "RAPTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": "human", "cell_type": "disk nucleus pulposus cells", "cell_lines": [], "genotype_context": null, "disease_context": "degenerative disk disease"}, "readout": {"name": "senescence", "assay": null, "figure_refs": []}, "effect": {"direction": "decrease", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all induced autophagy and inhibited apoptosis, senescence, pyroptosis, and matrix catabolism, with the most prominent effects observed with RAPTOR CRISPR–Cas9.", "notes": "Multi-target propagated from quote. | supporting_quote replaced with closest sentence from chunk_text."}, "confidence": 1}, {"intervention": {"category": "CRISPR_KO", "raw_text": "Targeting mTOR, RAPTOR, and RICTOR", "target": {"name": "RICTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": "human", "cell_type": "disk nucleus pulposus cells", "cell_lines": [], "genotype_context": null, "disease_context": "degenerative disk disease"}, "readout": {"name": "senescence", "assay": null, "figure_refs": []}, "effect": {"direction": "decrease", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all induced autophagy and inhibited apoptosis, senescence, pyroptosis, and matrix catabolism, with the most prominent effects observed with RAPTOR CRISPR–Cas9.", "notes": "Multi-target propagated from quote. | supporting_quote replaced with closest sentence from chunk_text."}, "confidence": 1}, {"intervention": {"category": "CRISPR_KO", "raw_text": "Targeting mTOR, RAPTOR, and RICTOR", "target": {"name": "mTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": "human", "cell_type": "disk nucleus pulposus cells", "cell_lines": [], "genotype_context": null, "disease_context": "degenerative disk disease"}, "readout": {"name": "pyroptosis", "assay": null, "figure_refs": []}, "effect": {"direction": "decrease", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all induced autophagy and inhibited apoptosis, senescence, pyroptosis, and matrix catabolism, with the most prominent effects observed with RAPTOR CRISPR–Cas9.", "notes": "Multi-target propagated from quote. | supporting_quote replaced with closest sentence from chunk_text."}, "confidence": 1}, {"intervention": {"category": "CRISPR_KO", "raw_text": "Targeting mTOR, RAPTOR, and RICTOR", "target": {"name": "RAPTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": "human", "cell_type": "disk nucleus pulposus cells", "cell_lines": [], "genotype_context": null, "disease_context": "degenerative disk disease"}, "readout": {"name": "pyroptosis", "assay": null, "figure_refs": []}, "effect": {"direction": "decrease", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all induced autophagy and inhibited apoptosis, senescence, pyroptosis, and matrix catabolism, with the most prominent effects observed with RAPTOR CRISPR–Cas9.", "notes": "Multi-target propagated from quote. | supporting_quote replaced with closest sentence from chunk_text."}, "confidence": 1}, {"intervention": {"category": "CRISPR_KO", "raw_text": "Targeting mTOR, RAPTOR, and RICTOR", "target": {"name": "RICTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": "human", "cell_type": "disk nucleus pulposus cells", "cell_lines": [], "genotype_context": null, "disease_context": "degenerative disk disease"}, "readout": {"name": "pyroptosis", "assay": null, "figure_refs": []}, "effect": {"direction": "decrease", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all induced autophagy and inhibited apoptosis, senescence, pyroptosis, and matrix catabolism, with the most prominent effects observed with RAPTOR CRISPR–Cas9.", "notes": "Multi-target propagated from quote. | supporting_quote replaced with closest sentence from chunk_text."}, "confidence": 1}, {"intervention": {"category": "CRISPR_KO", "raw_text": "Targeting mTOR, RAPTOR, and RICTOR", "target": {"name": "mTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": "human", "cell_type": "disk nucleus pulposus cells", "cell_lines": [], "genotype_context": null, "disease_context": "degenerative disk disease"}, "readout": {"name": "matrix catabolism", "assay": null, "figure_refs": []}, "effect": {"direction": "decrease", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all induced autophagy and inhibited apoptosis, senescence, pyroptosis, and matrix catabolism, with the most prominent effects observed with RAPTOR CRISPR–Cas9.", "notes": "Multi-target propagated from quote. | supporting_quote replaced with closest sentence from chunk_text."}, "confidence": 1}, {"intervention": {"category": "CRISPR_KO", "raw_text": "Targeting mTOR, RAPTOR, and RICTOR", "target": {"name": "RAPTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": "human", "cell_type": "disk nucleus pulposus cells", "cell_lines": [], "genotype_context": null, "disease_context": "degenerative disk disease"}, "readout": {"name": "matrix catabolism", "assay": null, "figure_refs": []}, "effect": {"direction": "decrease", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all induced autophagy and inhibited apoptosis, senescence, pyroptosis, and matrix catabolism, with the most prominent effects observed with RAPTOR CRISPR–Cas9.", "notes": "Multi-target propagated from quote. | supporting_quote replaced with closest sentence from chunk_text."}, "confidence": 1}, {"intervention": {"category": "CRISPR_KO", "raw_text": "Targeting mTOR, RAPTOR, and RICTOR", "target": {"name": "RICTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": "human", "cell_type": "disk nucleus pulposus cells", "cell_lines": [], "genotype_context": null, "disease_context": "degenerative disk disease"}, "readout": {"name": "matrix catabolism", "assay": null, "figure_refs": []}, "effect": {"direction": "decrease", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all induced autophagy and inhibited apoptosis, senescence, pyroptosis, and matrix catabolism, with the most prominent effects observed with RAPTOR CRISPR–Cas9.", "notes": "Multi-target propagated from quote. | supporting_quote replaced with closest sentence from chunk_text."}, "confidence": 1}], "warnings": [], "bridge": {"enabled": false, "attempted": false, "used": false, "mode": null, "source_doc_ids": ["PMID:39682777"], "source_chunk_ids": [2], "skipped_reason": "bridge_off"}, "_routing": {"first_model": "gpt-4o-mini", "escalated": false, "final_model": "gpt-4o-mini", "reason": null}, "_post": {"dropped_atoms": 0, "multi_target": {"enabled": true, "anchors": 30, "events_all": 30, "events_propagated": 30, "expanded_atoms": 60}}}

* * *

**ChatGPT:**

Got it — and **v15 is a really helpful “post-mortem”** because it shows _exactly_ why it keeps looping.

### What v15 is doing right

* It’s correctly doing the **multi-target × multi-readout expansion** (3 targets × 5 readouts → 15 atoms per “event set”).
* It’s not hallucinating timepoints/magnitudes here (those fields are `null`, which is good).

### The big problems in v15 (the loop generators)

1. **Duplicate “event sets” (30 atoms) from the same claim**

* You’re getting the same biological claim expanded twice:
    * once as `KNOCKDOWN_RNAI` (15 atoms)
    * once as `CRISPR_KO` (15 atoms)  
        That’s exactly why chunk 2 balloons to 30.

**Fix principle:** Only emit _one_ intervention category per supporting quote unless the quote explicitly contains _both_ methods.

* * *

2. **Category ↔ quote mismatch**

* Your “RNAi” atoms use this supporting quote:

> “…with the most prominent effects observed with **RAPTOR CRISPR–Cas9**.”

That quote **explicitly mentions CRISPR–Cas9**, so producing it as `KNOCKDOWN_RNAI` is internally inconsistent.

**Fix principle:** Category assignment must be **lexically anchored** (i.e., based on literal tokens in the quote):

* `CRISPR_KO` only if quote contains `CRISPR`/`Cas9`
* `KNOCKDOWN_RNAI` only if quote contains `siRNA`/`RNAi`

* * *

3. **“supporting_quote replaced with closest sentence” is a hard no**  
    You have notes saying:

> “supporting_quote replaced with closest sentence from chunk_text.”

That breaks traceability and is a major source of downstream nonsense.

**Fix principle:** supporting_quote must be **verbatim substring match** of the chunk text, or the event is dropped. No “closest sentence” repair.

* * *

4. **System fields are being filled without being quote-grounded**  
    You’re outputting:

* `species: human`
* `cell_type: disk nucleus pulposus cells`
* `disease_context: degenerative disk disease`

Even when the supporting quote may not contain those strings.

**Fix principle:** If bridge is off (yours is), system fields must be **null/empty unless literally present in the supporting quote**.

* * *

5. **All confidences are `1`**  
    That makes ranking/truncation useless and hides uncertainty.

**Fix principle:** Never force `1`. Keep model confidence but cap (e.g., ≤0.95) and/or down-weight anything that’s propagated/expanded.

* * *

6. Multi-target propagation is happening too late / too many times  
    Your `_post` says:

* `"anchors": 30, "expanded_atoms": 60`

That’s a signature of “propagate on already-expanded atoms” or “propagate repeatedly.”

**Fix principle:** Do propagation **once at the event level**, _then_ expand to atoms.

* * *

## Bottom line

Yes — **starting fresh with a stricter contract is the right move**, because v15’s architecture _encourages_ these exact failure modes (quote repair, category guessing, propagation after expansion).

If you run the “event-first, deterministic expansion” approach I gave you (my v16), chunk 2 should look like this:

* **Either** 15 atoms as `CRISPR_KO` (if the quote mentions CRISPR–Cas9)
* **Or** 15 atoms as `UNKNOWN` (if the quote doesn’t mention a method)
* **Not** 30 atoms split across RNAi + CRISPR unless the quote explicitly says “siRNA or CRISPR–Cas9 …” in the _same sentence_.

If you want to keep your numbering tidy, you can save that exact file as **`make_atoms_docaware_v12.py`** (name doesn’t matter; behavior does), run it, and paste just the **single JSONL line for chunk 2** — I’ll sanity-check it against the invariants above.

* * *

**You:**

pisk_mtor_seed_texts.txtDocumentDo you need the original seed text again to refresh your memory.  It is attached.

* * *

**You:**

We need to create a part 3. Can you give a **BOOTSTRAP MESSAGE (paste into new chat):**

* * *

**ChatGPT:**

Absolutely — here’s a **BOOTSTRAP MESSAGE** you can paste into a new chat to start **Part 3** cleanly.

```
We’re continuing a debugging/upgrade thread for my biomedical “atoms” extraction script.

GOAL
Update the extraction code so it NEVER “arbitrarily picks one target” when a sentence explicitly says:
“A, B, and C all did X”
Instead it must emit parallel atoms systematically for A, B, and C (each alone), with clean, consistent intervention/target pairing.

CONTEXT
- We are on version 11 (v11) lineage (not v8).
- I need you to provide the exact full code for the next version (call it v16 or v12—your choice, but be consistent). I will NOT edit anything manually.
- Please include clear run instructions (exact commands) and any minimal tests/diagnostics I can run.

SEED TEXT FILE
I have the original seed text available as a local file:
  /mnt/data/pisk_mtor_seed_texts.txt
Use it as the ground truth reference text.

CURRENT FAILURE MODE (observed in v13–v15 outputs on PMID:39682777, chunk_id=2)
We keep going in circles because multi-target “all” statements are mishandled.

Example sentence (from chunk 2; representative):
“Targeting mTOR, RAPTOR, and RICTOR all induced autophagy and inhibited apoptosis, senescence, pyroptosis, and matrix catabolism …”

What this MEANS (important):
- It means targeting ANY ONE of the listed targets (mTOR alone OR RAPTOR alone OR RICTOR alone) induced autophagy and inhibited those processes.
- It does NOT imply a combined triple perturbation.

What the code must NOT do (bugs seen in outputs):
1) DO NOT propagate a single intervention raw_text (e.g., “CRISPR targeting mTOR”) onto other targets (RAPTOR/RICTOR). Each target must have its own correctly-matched intervention text or a neutral raw_text that doesn’t claim the wrong target.
2) DO NOT invent timepoints/magnitudes (e.g., “168h”, “88.1%”) unless explicitly stated as readout effect values. Transfection efficiency ≠ effect magnitude on autophagy/apoptosis.
3) DO NOT flip modality (LOF vs GOF) incorrectly. If it’s siRNA/CRISPR KO/targeting for suppression, it should map to LOF (or “INHIBITION” if that’s your internal label—but keep it consistent and correct).
4) DO NOT put “inhibited apoptosis” as the readout name. Readout should be “apoptosis” with effect.direction = decrease.
5) Avoid cross-product explosions and duplicates. Expand multi-target and multi-readout carefully and dedupe deterministically.
6) Chunk 1 is currently returning 0 atoms — we need a lightweight diagnostic for why (filtering? sentence selection? parsing failure?), but the main priority is fixing multi-target “all/each” semantics.

DESIRED OUTPUT BEHAVIOR (high-level)
Given:
- Targets list T = [mTOR, RAPTOR, RICTOR]
- Readouts list R = [autophagy (increase), apoptosis (decrease), senescence (decrease), pyroptosis (decrease), matrix catabolism (decrease)]
Emit atoms for each (t in T, r in R) with:
- target.name = t
- readout.name = r
- effect.direction consistent with “induced/increased” vs “inhibited/decreased”
- evidence.supporting_quote drawn verbatim from the sentence (no fabrication)
- intervention.category and modality consistent with the method actually described in the same scope; if the sentence only says “Targeting …” without specifying method, don’t hallucinate siRNA vs CRISPR—use a neutral category or carry method only if explicitly present nearby.

WHAT I WANT FROM YOU IN THIS NEW CHAT
1) Provide a fresh, complete, ready-to-run code file for the next version (single .py file).
2) Include exact commands to run it on the seed file and reproduce outputs for PMID:39682777 chunk_id=2.
3) Add a small built-in test (or --selftest) that specifically verifies:
   “A, B, and C all induced X” => emits three parallel atoms (A/X, B/X, C/X) with no target/raw_text mismatch.
4) Explain briefly (bullet points) the logic change you made.

I will paste the latest problematic chunk outputs if needed, but start by reading the seed text file and implementing the multi-target “all/each” fix robustly.
```

If you want, I can also tailor that bootstrap message to explicitly include the **exact chunk 2 JSON outputs from v13/v14/v15** you pasted here (so the new chat has concrete “before” artifacts right away) — but the above is already enough to start fresh cleanly.

* * *

**You:**

also tailor that bootstrap message to explicitly include the exact chunk 2 JSON outputs from v13/v14/v15 you pasted here (so the new chat has concrete “before” artifacts right away)

* * *

**ChatGPT:**

Got it — here’s a **BOOTSTRAP MESSAGE** you can paste into a new chat that **includes the exact chunk 2 JSON outputs** you posted for **v13 / v14 / v15** as concrete “before” artifacts.

```
We’re continuing a debugging/upgrade thread for my biomedical “atoms” extraction script.

GOAL
Update the extraction code so it NEVER “arbitrarily picks one target” when a sentence explicitly says:
“A, B, and C all did X”
Instead it must emit parallel atoms systematically for A, B, and C (each alone), with clean, consistent intervention/target pairing.

CONTEXT
- We are on version 11 (v11) lineage (not v8).
- I need you to provide the exact full code for the next version (call it v16 or v12—your choice, but be consistent). I will NOT edit anything manually.
- Please include clear run instructions (exact commands) and any minimal tests/diagnostics I can run.

SEED TEXT FILE
I have the original seed text available as a local file:
  /mnt/data/pisk_mtor_seed_texts.txt
Use it as the ground truth reference text.

KEY SEMANTICS (must be respected)
Example sentence (from chunk 2; representative):
“Targeting mTOR, RAPTOR, and RICTOR all induced autophagy and inhibited apoptosis, senescence, pyroptosis, and matrix catabolism …”

What this MEANS:
- It means targeting ANY ONE of the listed targets (mTOR alone OR RAPTOR alone OR RICTOR alone) induced autophagy and inhibited those processes.
- It does NOT imply a combined triple perturbation.

What the code must NOT do (bugs seen in outputs):
1) DO NOT propagate a single intervention raw_text (e.g., “CRISPR targeting mTOR”) onto other targets (RAPTOR/RICTOR). Each target must have its own correctly-matched intervention text OR a neutral raw_text that does not claim the wrong target.
2) DO NOT invent timepoints/magnitudes (e.g., “168h”, “88.1%”) unless explicitly stated as readout effect values. Transfection efficiency ≠ effect magnitude on autophagy/apoptosis.
3) DO NOT flip modality (LOF vs GOF) incorrectly. If it’s siRNA/CRISPR KO/targeting for suppression, it should map to LOF (or “INHIBITION” if that’s your internal label—but keep it consistent and correct).
4) DO NOT put “inhibited apoptosis” as the readout name. Readout should be “apoptosis” with effect.direction = decrease.
5) Avoid cross-product explosions and duplicates. Expand multi-target and multi-readout carefully and dedupe deterministically.
6) Chunk 1 is currently returning 0 atoms — we need a lightweight diagnostic for why (filtering? sentence selection? parsing failure?), but the main priority is fixing multi-target “all/each” semantics.

DESIRED OUTPUT BEHAVIOR (high-level)
Given:
- Targets list T = [mTOR, RAPTOR, RICTOR]
- Readouts list R = [autophagy (increase), apoptosis (decrease), senescence (decrease), pyroptosis (decrease), matrix catabolism (decrease)]
Emit atoms for each (t in T, r in R) with:
- target.name = t
- readout.name = r
- effect.direction consistent with “induced/increased” vs “inhibited/decreased”
- evidence.supporting_quote drawn verbatim from the sentence (no fabrication)
- intervention.category and modality consistent with the method actually described in the same scope; if the sentence only says “Targeting …” without specifying method, don’t hallucinate siRNA vs CRISPR—use a neutral category or carry method only if explicitly present nearby.

CONCRETE “BEFORE” ARTIFACTS (exact outputs)
Below are the exact JSON outputs for PMID:39682777 chunk_id=2 from v13, v14, and v15.

=== v13 chunk 2 output (exact) ===
{"doc_id": "PMID:39682777", "doc_id_source": "pmid", "pmid": "39682777", "pmcid": null, "chunk_index": null, "chunk_id": 2, "atoms": [{"intervention": {"category": "CRISPR_KO", "raw_text": "CRISPR–Cas9 plasmid targeting mTOR, RAPTOR, or RICTOR", "target": {"name": "mTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": null, "cell_type": null, "cell_lines": [], "genotype_context": null, "disease_context": null}, "readout": {"name": "autophagy", "assay": null, "figure_refs": []}, "effect": {"direction": "increase", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all induced autophagy", "notes": "Expanded per multi-target 'all/each/both' statement."}, "confidence": 0.9}, {"intervention": {"category": "CRISPR_KO", "raw_text": "CRISPR–Cas9 plasmid targeting mTOR, RAPTOR, or RICTOR", "target": {"name": "RAPTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": null, "cell_type": null, "cell_lines": [], "genotype_context": null, "disease_context": null}, "readout": {"name": "autophagy", "assay": null, "figure_refs": []}, "effect": {"direction": "increase", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all induced autophagy", "notes": "Expanded per multi-target 'all/each/both' statement."}, "confidence": 0.9}, {"intervention": {"category": "CRISPR_KO", "raw_text": "CRISPR–Cas9 plasmid targeting mTOR, RAPTOR, or RICTOR", "target": {"name": "RICTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": null, "cell_type": null, "cell_lines": [], "genotype_context": null, "disease_context": null}, "readout": {"name": "autophagy", "assay": null, "figure_refs": []}, "effect": {"direction": "increase", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all induced autophagy", "notes": "Expanded per multi-target 'all/each/both' statement."}, "confidence": 0.9}, {"intervention": {"category": "CRISPR_KO", "raw_text": "CRISPR–Cas9 plasmid targeting mTOR, RAPTOR, or RICTOR", "target": {"name": "RAPTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": null, "cell_type": null, "cell_lines": [], "genotype_context": null, "disease_context": null}, "readout": {"name": "apoptosis", "assay": null, "figure_refs": []}, "effect": {"direction": "decrease", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR...inhibited apoptosis", "notes": null}, "confidence": 0.9}, {"intervention": {"category": "CRISPR_KO", "raw_text": "CRISPR–Cas9 plasmid targeting mTOR, RAPTOR, or RICTOR", "target": {"name": "RAPTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": null, "cell_type": null, "cell_lines": [], "genotype_context": null, "disease_context": null}, "readout": {"name": "senescence", "assay": null, "figure_refs": []}, "effect": {"direction": "decrease", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR...inhibited senescence", "notes": null}, "confidence": 0.9}, {"intervention": {"category": "CRISPR_KO", "raw_text": "CRISPR–Cas9 plasmid targeting mTOR, RAPTOR, or RICTOR", "target": {"name": "RAPTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": null, "cell_type": null, "cell_lines": [], "genotype_context": null, "disease_context": null}, "readout": {"name": "pyroptosis", "assay": null, "figure_refs": []}, "effect": {"direction": "decrease", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR...inhibited pyroptosis", "notes": null}, "confidence": 0.9}, {"intervention": {"category": "CRISPR_KO", "raw_text": "CRISPR–Cas9 plasmid targeting mTOR, RAPTOR, or RICTOR", "target": {"name": "RAPTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": null, "cell_type": null, "cell_lines": [], "genotype_context": null, "disease_context": null}, "readout": {"name": "matrix catabolism", "assay": null, "figure_refs": []}, "effect": {"direction": "decrease", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR...inhibited matrix catabolism", "notes": null}, "confidence": 0.9}], "warnings": [], "bridge": {"enabled": false, "attempted": false, "used": false, "mode": null, "source_doc_ids": ["PMID:39682777"], "source_chunk_ids": [2], "skipped_reason": "bridge_off"}, "_routing": {"first_model": "gpt-4o-mini", "escalated": false, "final_model": "gpt-4o-mini", "reason": null}, "_post": {"dropped_atoms": 0, "multi_target": {"enabled": true, "anchors": 1, "events_all": 1, "events_propagated": 0, "expanded_atoms": 3}, "clause_split": {"enabled": true, "events": 0, "expanded_atoms": 0}}}

=== v14 chunk 2 output (exact) ===
{"doc_id": "PMID:39682777", "doc_id_source": "pmid", "pmid": "39682777", "pmcid": null, "doi": null, "source_file": null, "chunk_index": null, "chunk_id": 2, "atoms": [{"intervention": {"category": "CRISPR_KO", "raw_text": "CRISPR–Cas9 plasmid targeting mTOR", "target": {"name": "mTOR", "entity_type": "protein"}, "modality": "INHIBITION"}, "system": {"species": "human", "cell_type": "nucleus pulposus", "cell_lines": ["degenerative disk cells"], "genotype_context": null, "disease_context": "degenerative disk disease"}, "readout": {"name": "autophagy", "assay": null, "figure_refs": []}, "effect": {"direction": "increase", "timepoint": "168h", "magnitude": "88.1%", "comparison": "CRISPR–Cas9 targeting mTOR"}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all induced autophagy.", "notes": "Multi-target propagated from quote."}, "confidence": 0.9}, {"intervention": {"category": "CRISPR_KO", "raw_text": "CRISPR–Cas9 plasmid targeting mTOR", "target": {"name": "RAPTOR", "entity_type": "protein"}, "modality": "INHIBITION"}, "system": {"species": "human", "cell_type": "nucleus pulposus", "cell_lines": ["degenerative disk cells"], "genotype_context": null, "disease_context": "degenerative disk disease"}, "readout": {"name": "autophagy", "assay": null, "figure_refs": []}, "effect": {"direction": "increase", "timepoint": "168h", "magnitude": "88.1%", "comparison": "CRISPR–Cas9 targeting mTOR"}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all induced autophagy.", "notes": "Multi-target propagated from quote."}, "confidence": 0.9}, {"intervention": {"category": "CRISPR_KO", "raw_text": "CRISPR–Cas9 plasmid targeting mTOR", "target": {"name": "RICTOR", "entity_type": "protein"}, "modality": "INHIBITION"}, "system": {"species": "human", "cell_type": "nucleus pulposus", "cell_lines": ["degenerative disk cells"], "genotype_context": null, "disease_context": "degenerative disk disease"}, "readout": {"name": "autophagy", "assay": null, "figure_refs": []}, "effect": {"direction": "increase", "timepoint": "168h", "magnitude": "88.1%", "comparison": "CRISPR–Cas9 targeting mTOR"}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all induced autophagy.", "notes": "Multi-target propagated from quote."}, "confidence": 0.9}, {"intervention": {"category": "CRISPR_KO", "raw_text": "CRISPR–Cas9 plasmid targeting RAPTOR", "target": {"name": "mTOR", "entity_type": "protein"}, "modality": "INHIBITION"}, "system": {"species": "human", "cell_type": "nucleus pulposus", "cell_lines": ["degenerative disk cells"], "genotype_context": null, "disease_context": "degenerative disk disease"}, "readout": {"name": "apoptosis", "assay": null, "figure_refs": []}, "effect": {"direction": "decrease", "timepoint": "168h", "magnitude": null, "comparison": "CRISPR-KO targeting RAPTOR"}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all inhibited apoptosis.", "notes": "Multi-target propagated from quote."}, "confidence": 0.9}, {"intervention": {"category": "CRISPR_KO", "raw_text": "CRISPR–Cas9 plasmid targeting RAPTOR", "target": {"name": "RAPTOR", "entity_type": "protein"}, "modality": "INHIBITION"}, "system": {"species": "human", "cell_type": "nucleus pulposus", "cell_lines": ["degenerative disk cells"], "genotype_context": null, "disease_context": "degenerative disk disease"}, "readout": {"name": "apoptosis", "assay": null, "figure_refs": []}, "effect": {"direction": "decrease", "timepoint": "168h", "magnitude": null, "comparison": "CRISPR-KO targeting RAPTOR"}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all inhibited apoptosis.", "notes": "Multi-target propagated from quote."}, "confidence": 0.9}, {"intervention": {"category": "CRISPR_KO", "raw_text": "CRISPR–Cas9 plasmid targeting RAPTOR", "target": {"name": "RICTOR", "entity_type": "protein"}, "modality": "INHIBITION"}, "system": {"species": "human", "cell_type": "nucleus pulposus", "cell_lines": ["degenerative disk cells"], "genotype_context": null, "disease_context": "degenerative disk disease"}, "readout": {"name": "apoptosis", "assay": null, "figure_refs": []}, "effect": {"direction": "decrease", "timepoint": "168h", "magnitude": null, "comparison": "CRISPR-KO targeting RAPTOR"}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all inhibited apoptosis.", "notes": "Multi-target propagated from quote."}, "confidence": 0.9}, {"intervention": {"category": "CRISPR_KO", "raw_text": "CRISPR–Cas9 plasmid targeting RICTOR", "target": {"name": "mTOR", "entity_type": "protein"}, "modality": "INHIBITION"}, "system": {"species": "human", "cell_type": "nucleus pulposus", "cell_lines": ["degenerative disk cells"], "genotype_context": null, "disease_context": "degenerative disk disease"}, "readout": {"name": "senescence", "assay": null, "figure_refs": []}, "effect": {"direction": "decrease", "timepoint": "168h", "magnitude": null, "comparison": "CRISPR-KO targeting RICTOR"}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all inhibited senescence.", "notes": "Multi-target propagated from quote."}, "confidence": 0.9}, {"intervention": {"category": "CRISPR_KO", "raw_text": "CRISPR–Cas9 plasmid targeting RICTOR", "target": {"name": "RAPTOR", "entity_type": "protein"}, "modality": "INHIBITION"}, "system": {"species": "human", "cell_type": "nucleus pulposus", "cell_lines": ["degenerative disk cells"], "genotype_context": null, "disease_context": "degenerative disk disease"}, "readout": {"name": "senescence", "assay": null, "figure_refs": []}, "effect": {"direction": "decrease", "timepoint": "168h", "magnitude": null, "comparison": "CRISPR-KO targeting RICTOR"}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all inhibited senescence.", "notes": "Multi-target propagated from quote."}, "confidence": 0.9}, {"intervention": {"category": "CRISPR_KO", "raw_text": "CRISPR–Cas9 plasmid targeting RICTOR", "target": {"name": "RICTOR", "entity_type": "protein"}, "modality": "INHIBITION"}, "system": {"species": "human", "cell_type": "nucleus pulposus", "cell_lines": ["degenerative disk cells"], "genotype_context": null, "disease_context": "degenerative disk disease"}, "readout": {"name": "senescence", "assay": null, "figure_refs": []}, "effect": {"direction": "decrease", "timepoint": "168h", "magnitude": null, "comparison": "CRISPR-KO targeting RICTOR"}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all inhibited senescence.", "notes": "Multi-target propagated from quote."}, "confidence": 0.9}, {"intervention": {"category": "CRISPR_KO", "raw_text": "CRISPR–Cas9 plasmid targeting RAPTOR", "target": {"name": "mTOR", "entity_type": "protein"}, "modality": "INHIBITION"}, "system": {"species": "human", "cell_type": "nucleus pulposus", "cell_lines": ["degenerative disk cells"], "genotype_context": null, "disease_context": "degenerative disk disease"}, "readout": {"name": "pyroptosis", "assay": null, "figure_refs": []}, "effect": {"direction": "decrease", "timepoint": "168h", "magnitude": null, "comparison": "CRISPR-KO targeting RAPTOR"}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all inhibited pyroptosis.", "notes": "Multi-target propagated from quote."}, "confidence": 0.9}, {"intervention": {"category": "CRISPR_KO", "raw_text": "CRISPR–Cas9 plasmid targeting RAPTOR", "target": {"name": "RAPTOR", "entity_type": "protein"}, "modality": "INHIBITION"}, "system": {"species": "human", "cell_type": "nucleus pulposus", "cell_lines": ["degenerative disk cells"], "genotype_context": null, "disease_context": "degenerative disk disease"}, "readout": {"name": "pyroptosis", "assay": null, "figure_refs": []}, "effect": {"direction": "decrease", "timepoint": "168h", "magnitude": null, "comparison": "CRISPR-KO targeting RAPTOR"}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all inhibited pyroptosis.", "notes": "Multi-target propagated from quote."}, "confidence": 0.9}, {"intervention": {"category": "CRISPR_KO", "raw_text": "CRISPR–Cas9 plasmid targeting RAPTOR", "target": {"name": "RICTOR", "entity_type": "protein"}, "modality": "INHIBITION"}, "system": {"species": "human", "cell_type": "nucleus pulposus", "cell_lines": ["degenerative disk cells"], "genotype_context": null, "disease_context": "degenerative disk disease"}, "readout": {"name": "pyroptosis", "assay": null, "figure_refs": []}, "effect": {"direction": "decrease", "timepoint": "168h", "magnitude": null, "comparison": "CRISPR-KO targeting RAPTOR"}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all inhibited pyroptosis.", "notes": "Multi-target propagated from quote."}, "confidence": 0.9}, {"intervention": {"category": "CRISPR_KO", "raw_text": "CRISPR–Cas9 plasmid targeting RICTOR", "target": {"name": "mTOR", "entity_type": "protein"}, "modality": "INHIBITION"}, "system": {"species": "human", "cell_type": "nucleus pulposus", "cell_lines": ["degenerative disk cells"], "genotype_context": null, "disease_context": "degenerative disk disease"}, "readout": {"name": "matrix catabolism", "assay": null, "figure_refs": []}, "effect": {"direction": "decrease", "timepoint": "168h", "magnitude": null, "comparison": "CRISPR-KO targeting RICTOR"}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all inhibited matrix catabolism.", "notes": "Multi-target propagated from quote."}, "confidence": 0.9}, {"intervention": {"category": "CRISPR_KO", "raw_text": "CRISPR–Cas9 plasmid targeting RICTOR", "target": {"name": "RAPTOR", "entity_type": "protein"}, "modality": "INHIBITION"}, "system": {"species": "human", "cell_type": "nucleus pulposus", "cell_lines": ["degenerative disk cells"], "genotype_context": null, "disease_context": "degenerative disk disease"}, "readout": {"name": "matrix catabolism", "assay": null, "figure_refs": []}, "effect": {"direction": "decrease", "timepoint": "168h", "magnitude": null, "comparison": "CRISPR-KO targeting RICTOR"}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all inhibited matrix catabolism.", "notes": "Multi-target propagated from quote."}, "confidence": 0.9}, {"intervention": {"category": "CRISPR_KO", "raw_text": "CRISPR–Cas9 plasmid targeting RICTOR", "target": {"name": "RICTOR", "entity_type": "protein"}, "modality": "INHIBITION"}, "system": {"species": "human", "cell_type": "nucleus pulposus", "cell_lines": ["degenerative disk cells"], "genotype_context": null, "disease_context": "degenerative disk disease"}, "readout": {"name": "matrix catabolism", "assay": null, "figure_refs": []}, "effect": {"direction": "decrease", "timepoint": "168h", "magnitude": null, "comparison": "CRISPR-KO targeting RICTOR"}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all inhibited matrix catabolism.", "notes": "Multi-target propagated from quote."}, "confidence": 0.9}, {"intervention": {"category": "KNOCKDOWN_RNAI", "raw_text": "siRNA or CRISPR–Cas9 plasmid targeting RAPTOR", "target": {"name": "RAPTOR", "entity_type": "protein"}, "modality": "INHIBITION"}, "system": {"species": "human", "cell_type": "nucleus pulposus", "cell_lines": ["degenerative disk cells"], "genotype_context": null, "disease_context": "degenerative disk disease"}, "readout": {"name": "autophagy", "assay": null, "figure_refs": []}, "effect": {"direction": "increase", "timepoint": "168h", "magnitude": "53.8-60.3%", "comparison": "RNAi targeting RAPTOR"}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Both of the approaches specifically suppressed target protein expression; however, the 24-h transfection efficiency differed by 53.8–60.3% for RNAi.", "notes": null}, "confidence": 0.9}, {"intervention": {"category": "KNOCKDOWN_RNAI", "raw_text": "siRNA or CRISPR–Cas9 plasmid targeting RICTOR", "target": {"name": "RICTOR", "entity_type": "protein"}, "modality": "INHIBITION"}, "system": {"species": "human", "cell_type": "nucleus pulposus", "cell_lines": ["degenerative disk cells"], "genotype_context": null, "disease_context": "degenerative disk disease"}, "readout": {"name": "apoptosis", "assay": null, "figure_refs": []}, "effect": {"direction": "decrease", "timepoint": "168h", "magnitude": null, "comparison": "RNAi targeting RICTOR"}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Both of the approaches specifically suppressed target protein expression.", "notes": null}, "confidence": 0.9}, {"intervention": {"category": "KNOCKDOWN_RNAI", "raw_text": "siRNA or CRISPR–Cas9 plasmid targeting mTOR", "target": {"name": "mTOR", "entity_type": "protein"}, "modality": "INHIBITION"}, "system": {"species": "human", "cell_type": "nucleus pulposus", "cell_lines": ["degenerative disk cells"], "genotype_context": null, "disease_context": "degenerative disk disease"}, "readout": {"name": "senescence", "assay": null, "figure_refs": []}, "effect": {"direction": "decrease", "timepoint": "168h", "magnitude": null, "comparison": "RNAi targeting mTOR"}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Both of the approaches specifically suppressed target protein expression.", "notes": null}, "confidence": 0.9}], "warnings": ["No specific readouts were analyzed for the siRNA transfections due to lack of detailed results."], "bridge": {"enabled": false, "attempted": false, "used": false, "mode": null, "source_doc_ids": ["PMID:39682777"], "source_chunk_ids": [2], "skipped_reason": "bridge_off"}, "_routing": {"first_model": "gpt-4o-mini", "escalated": false, "final_model": "gpt-4o-mini", "reason": null}, "_post": {"dropped_atoms": 0, "clause_split": {"enabled": true, "events": 0, "expanded_atoms": 0}, "multi_target": {"enabled": true, "anchors": 5, "events_all": 5, "events_propagated": 5, "expanded_atoms": 10}}}

=== v15 chunk 2 output (exact) ===
{"doc_id": "PMID:39682777", "doc_id_source": "pmid", "pmid": "39682777", "pmcid": null, "doi": null, "source_file": null, "chunk_index": null, "chunk_id": 2, "atoms": [{"intervention": {"category": "KNOCKDOWN_RNAI", "raw_text": "Targeting mTOR, RAPTOR, and RICTOR", "target": {"name": "mTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": "human", "cell_type": "disk nucleus pulposus cells", "cell_lines": [], "genotype_context": null, "disease_context": "degenerative disk disease"}, "readout": {"name": "autophagy", "assay": null, "figure_refs": []}, "effect": {"direction": "increase", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all induced autophagy", "notes": "Multi-target propagated from quote."}, "confidence": 1}, {"intervention": {"category": "KNOCKDOWN_RNAI", "raw_text": "Targeting mTOR, RAPTOR, and RICTOR", "target": {"name": "RAPTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": "human", "cell_type": "disk nucleus pulposus cells", "cell_lines": [], "genotype_context": null, "disease_context": "degenerative disk disease"}, "readout": {"name": "autophagy", "assay": null, "figure_refs": []}, "effect": {"direction": "increase", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all induced autophagy", "notes": "Multi-target propagated from quote."}, "confidence": 1}, {"intervention": {"category": "KNOCKDOWN_RNAI", "raw_text": "Targeting mTOR, RAPTOR, and RICTOR", "target": {"name": "RICTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": "human", "cell_type": "disk nucleus pulposus cells", "cell_lines": [], "genotype_context": null, "disease_context": "degenerative disk disease"}, "readout": {"name": "autophagy", "assay": null, "figure_refs": []}, "effect": {"direction": "increase", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all induced autophagy", "notes": "Multi-target propagated from quote."}, "confidence": 1}, {"intervention": {"category": "KNOCKDOWN_RNAI", "raw_text": "Targeting mTOR, RAPTOR, and RICTOR", "target": {"name": "mTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": "human", "cell_type": "disk nucleus pulposus cells", "cell_lines": [], "genotype_context": null, "disease_context": "degenerative disk disease"}, "readout": {"name": "apoptosis", "assay": null, "figure_refs": []}, "effect": {"direction": "decrease", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all induced autophagy and inhibited apoptosis, senescence, pyroptosis, and matrix catabolism, with the most prominent effects observed with RAPTOR CRISPR–Cas9.", "notes": "Multi-target propagated from quote. | supporting_quote replaced with closest sentence from chunk_text."}, "confidence": 1}, {"intervention": {"category": "KNOCKDOWN_RNAI", "raw_text": "Targeting mTOR, RAPTOR, and RICTOR", "target": {"name": "RAPTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": "human", "cell_type": "disk nucleus pulposus cells", "cell_lines": [], "genotype_context": null, "disease_context": "degenerative disk disease"}, "readout": {"name": "apoptosis", "assay": null, "figure_refs": []}, "effect": {"direction": "decrease", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all induced autophagy and inhibited apoptosis, senescence, pyroptosis, and matrix catabolism, with the most prominent effects observed with RAPTOR CRISPR–Cas9.", "notes": "Multi-target propagated from quote. | supporting_quote replaced with closest sentence from chunk_text."}, "confidence": 1}, {"intervention": {"category": "KNOCKDOWN_RNAI", "raw_text": "Targeting mTOR, RAPTOR, and RICTOR", "target": {"name": "RICTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": "human", "cell_type": "disk nucleus pulposus cells", "cell_lines": [], "genotype_context": null, "disease_context": "degenerative disk disease"}, "readout": {"name": "apoptosis", "assay": null, "figure_refs": []}, "effect": {"direction": "decrease", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all induced autophagy and inhibited apoptosis, senescence, pyroptosis, and matrix catabolism, with the most prominent effects observed with RAPTOR CRISPR–Cas9.", "notes": "Multi-target propagated from quote. | supporting_quote replaced with closest sentence from chunk_text."}, "confidence": 1}, {"intervention": {"category": "KNOCKDOWN_RNAI", "raw_text": "Targeting mTOR, RAPTOR, and RICTOR", "target": {"name": "mTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": "human", "cell_type": "disk nucleus pulposus cells", "cell_lines": [], "genotype_context": null, "disease_context": "degenerative disk disease"}, "readout": {"name": "senescence", "assay": null, "figure_refs": []}, "effect": {"direction": "decrease", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all induced autophagy and inhibited apoptosis, senescence, pyroptosis, and matrix catabolism, with the most prominent effects observed with RAPTOR CRISPR–Cas9.", "notes": "Multi-target propagated from quote. | supporting_quote replaced with closest sentence from chunk_text."}, "confidence": 1}, {"intervention": {"category": "KNOCKDOWN_RNAI", "raw_text": "Targeting mTOR, RAPTOR, and RICTOR", "target": {"name": "RAPTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": "human", "cell_type": "disk nucleus pulposus cells", "cell_lines": [], "genotype_context": null, "disease_context": "degenerative disk disease"}, "readout": {"name": "senescence", "assay": null, "figure_refs": []}, "effect": {"direction": "decrease", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all induced autophagy and inhibited apoptosis, senescence, pyroptosis, and matrix catabolism, with the most prominent effects observed with RAPTOR CRISPR–Cas9.", "notes": "Multi-target propagated from quote. | supporting_quote replaced with closest sentence from chunk_text."}, "confidence": 1}, {"intervention": {"category": "KNOCKDOWN_RNAI", "raw_text": "Targeting mTOR, RAPTOR, and RICTOR", "target": {"name": "RICTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": "human", "cell_type": "disk nucleus pulposus cells", "cell_lines": [], "genotype_context": null, "disease_context": "degenerative disk disease"}, "readout": {"name": "senescence", "assay": null, "figure_refs": []}, "effect": {"direction": "decrease", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all induced autophagy and inhibited apoptosis, senescence, pyroptosis, and matrix catabolism, with the most prominent effects observed with RAPTOR CRISPR–Cas9.", "notes": "Multi-target propagated from quote. | supporting_quote replaced with closest sentence from chunk_text."}, "confidence": 1}, {"intervention": {"category": "KNOCKDOWN_RNAI", "raw_text": "Targeting mTOR, RAPTOR, and RICTOR", "target": {"name": "mTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": "human", "cell_type": "disk nucleus pulposus cells", "cell_lines": [], "genotype_context": null, "disease_context": "degenerative disk disease"}, "readout": {"name": "pyroptosis", "assay": null, "figure_refs": []}, "effect": {"direction": "decrease", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all induced autophagy and inhibited apoptosis, senescence, pyroptosis, and matrix catabolism, with the most prominent effects observed with RAPTOR CRISPR–Cas9.", "notes": "Multi-target propagated from quote. | supporting_quote replaced with closest sentence from chunk_text."}, "confidence": 1}, {"intervention": {"category": "KNOCKDOWN_RNAI", "raw_text": "Targeting mTOR, RAPTOR, and RICTOR", "target": {"name": "RAPTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": "human", "cell_type": "disk nucleus pulposus cells", "cell_lines": [], "genotype_context": null, "disease_context": "degenerative disk disease"}, "readout": {"name": "pyroptosis", "assay": null, "figure_refs": []}, "effect": {"direction": "decrease", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all induced autophagy and inhibited apoptosis, senescence, pyroptosis, and matrix catabolism, with the most prominent effects observed with RAPTOR CRISPR–Cas9.", "notes": "Multi-target propagated from quote. | supporting_quote replaced with closest sentence from chunk_text."}, "confidence": 1}, {"intervention": {"category": "KNOCKDOWN_RNAI", "raw_text": "Targeting mTOR, RAPTOR, and RICTOR", "target": {"name": "RICTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": "human", "cell_type": "disk nucleus pulposus cells", "cell_lines": [], "genotype_context": null, "disease_context": "degenerative disk disease"}, "readout": {"name": "pyroptosis", "assay": null, "figure_refs": []}, "effect": {"direction": "decrease", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all induced autophagy and inhibited apoptosis, senescence, pyroptosis, and matrix catabolism, with the most prominent effects observed with RAPTOR CRISPR–Cas9.", "notes": "Multi-target propagated from quote. | supporting_quote replaced with closest sentence from chunk_text."}, "confidence": 1}, {"intervention": {"category": "KNOCKDOWN_RNAI", "raw_text": "Targeting mTOR, RAPTOR, and RICTOR", "target": {"name": "mTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": "human", "cell_type": "disk nucleus pulposus cells", "cell_lines": [], "genotype_context": null, "disease_context": "degenerative disk disease"}, "readout": {"name": "matrix catabolism", "assay": null, "figure_refs": []}, "effect": {"direction": "decrease", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all induced autophagy and inhibited apoptosis, senescence, pyroptosis, and matrix catabolism, with the most prominent effects observed with RAPTOR CRISPR–Cas9.", "notes": "Multi-target propagated from quote. | supporting_quote replaced with closest sentence from chunk_text."}, "confidence": 1}, {"intervention": {"category": "KNOCKDOWN_RNAI", "raw_text": "Targeting mTOR, RAPTOR, and RICTOR", "target": {"name": "RAPTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": "human", "cell_type": "disk nucleus pulposus cells", "cell_lines": [], "genotype_context": null, "disease_context": "degenerative disk disease"}, "readout": {"name": "matrix catabolism", "assay": null, "figure_refs": []}, "effect": {"direction": "decrease", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all induced autophagy and inhibited apoptosis, senescence, pyroptosis, and matrix catabolism, with the most prominent effects observed with RAPTOR CRISPR–Cas9.", "notes": "Multi-target propagated from quote. | supporting_quote replaced with closest sentence from chunk_text."}, "confidence": 1}, {"intervention": {"category": "KNOCKDOWN_RNAI", "raw_text": "Targeting mTOR, RAPTOR, and RICTOR", "target": {"name": "RICTOR", "entity_type": "protein"}, "modality": "LOF"}, "system": {"species": "human", "cell_type": "disk nucleus pulposus cells", "cell_lines": [], "genotype_context": null, "disease_context": "degenerative disk disease"}, "readout": {"name": "matrix catabolism", "assay": null, "figure_refs": []}, "effect": {"direction": "decrease", "timepoint": null, "magnitude": null, "comparison": null}, "strength_cues": {"has_rescue": false, "has_control": false, "has_multiple_lines": false, "other": []}, "evidence": {"supporting_quote": "Targeting mTOR, RAPTOR, and RICTOR all induced autophagy and inhibited apoptosis, senescence, pyroptosis, and matrix catabolism, with the most prominent effects observed with RAPTOR CRISPR–Cas9.", "notes": "Multi-target propagated from quote. | supporting_quote replaced with closest sentence from chunk_text."}, "confidence": 1}], "warnings": [], "bridge": {"enabled": false, "attempted": false, "used": false, "mode": null, "source_doc_ids": ["PMID:39682777"], "source_chunk_ids": [2], "skipped_reason": "bridge_off"}, "_routing": {"first_model": "gpt-4o-mini", "escalated": false, "final_model": "gpt-4o-mini", "reason": null}, "_post": {"dropped_atoms": 0, "multi_target": {"enabled": true, "anchors": 30, "events_all": 30, "events_propagated": 30, "expanded_atoms": 60}}}

WHAT I WANT FROM YOU IN THIS NEW CHAT
1) Provide a fresh, complete, ready-to-run code file for the next version (single .py file).
2) Include exact commands to run it on the seed file and reproduce outputs for PMID:39682777 chunk_id=2.
3) Add a small built-in test (or --selftest) that specifically verifies:
   “A, B, and C all induced X” => emits three parallel atoms (A/X, B/X, C/X) with no target/raw_text mismatch.
4) Explain briefly (bullet points) the logic change you made.

Start by reading the seed text file and implementing the multi-target “all/each” fix robustly. I will run your code as-is.
```

If you want, I can also produce a second variant of this bootstrap message that’s shorter (same content, but with the v13/v14/v15 JSON placed behind a “collapsed” marker like `<<<BEGIN>>> ... <<<END>>>` so it’s easier to scroll past in the new chat).