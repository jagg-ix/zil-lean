#!/usr/bin/env python3
"""
Generate a ZIL extension scaffold from arXiv:2505.17335v2
("Secure Parsing and Serializing with Separation Logic Applied to CBOR, CDDL, and COSE").

Outputs:
- JSON extraction summary (claims, contributions, metadata)
- Runnable ZIL model that uses everparse interop macros + paper coverage facts/queries

Default source PDF:
  ~/Downloads/2505.17335v2.pdf
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
from pathlib import Path
from typing import Any, Dict, List, Sequence


CONTRIB_RE = re.compile(
    r"Our\s+(first|second|third|fourth)\s+contribution\s*\(§\s*([0-9.]+)\)\s*is\s*(.+?)\.",
    re.IGNORECASE,
)

CLAIM_DEFS: Sequence[Dict[str, Any]] = (
    {
        "id": "pulseparse_verified_library",
        "summary": "pulseparse_verified_parser_serializer_library",
        "probes": ["pulseparse", "verified library for secure parsing and serialization"],
        "mode": "all",
    },
    {
        "id": "recursive_constant_stack_space",
        "summary": "recursive_formats_constant_stack_space_validation",
        "probes": ["recursive formats", "constant stack space"],
        "mode": "all",
    },
    {
        "id": "evercbor_deterministic_non_malleable",
        "summary": "evercbor_deterministic_fragment_non_malleable",
        "probes": ["evercbor", "deterministic encoding", "non-malleable"],
        "mode": "all",
    },
    {
        "id": "evercddl_well_formedness_sound",
        "summary": "evercddl_well_formedness_elaboration_sound",
        "probes": ["evercddl", "well-formedness", "proven sound"],
        "mode": "all",
    },
    {
        "id": "cose_verified_signing",
        "summary": "verified_cose_signing_implementation",
        "probes": ["cose", "verified library", "signature"],
        "mode": "all",
    },
    {
        "id": "dpe_generated_verified_code",
        "summary": "dpe_generated_verified_parsers_serializers",
        "probes": ["dpe", "generate verified code"],
        "mode": "all",
    },
    {
        "id": "memory_safety_guarantee",
        "summary": "memory_safety_guarantee",
        "probes": ["memory safe", "memory safety"],
        "mode": "any",
    },
    {
        "id": "arithmetic_safety_guarantee",
        "summary": "arithmetic_safety_guarantee",
        "probes": ["arithmetically safe", "arithmetic safety"],
        "mode": "any",
    },
    {
        "id": "functional_correctness_guarantee",
        "summary": "functional_correctness_guarantee",
        "probes": ["functionally correct", "functional correctness"],
        "mode": "any",
    },
    {
        "id": "non_malleability_guarantee",
        "summary": "non_malleability_guarantee",
        "probes": ["non-malleable", "non-malleability"],
        "mode": "any",
    },
    {
        "id": "non_ambiguity_guarantee",
        "summary": "non_ambiguity_guarantee",
        "probes": ["non-ambiguous", "unambiguous"],
        "mode": "any",
    },
    {
        "id": "c_and_rust_extraction",
        "summary": "karamel_extraction_to_c_and_safe_rust",
        "probes": ["karamel", "standalone library in c", "safe rust"],
        "mode": "all",
    },
    {
        "id": "performance_evaluation",
        "summary": "performance_comparison_with_common_cbor_libraries",
        "probes": ["evaluate evercbor", "competitive in speed", "memory consumption"],
        "mode": "all",
    },
    {
        "id": "adversarial_input_focus",
        "summary": "security_focus_under_adversarial_inputs",
        "probes": ["adversarial inputs", "security"],
        "mode": "all",
    },
    {
        "id": "double_fetch_freedom",
        "summary": "double_fetch_freedom_explicit_claim",
        "probes": ["double-fetch"],
        "mode": "any",
    },
)

KEYWORDS = (
    "pulseparse",
    "everparse",
    "evercbor",
    "evercddl",
    "cbor",
    "cddl",
    "cose",
    "dpe",
    "memory safety",
    "arithmetic safety",
    "functional correctness",
    "non-malleable",
    "non-ambiguous",
    "constant stack space",
    "adversarial inputs",
    "karamel",
)


def safe_token(raw: str) -> str:
    token = re.sub(r"[^A-Za-z0-9_]+", "_", raw.strip().lower())
    token = re.sub(r"_+", "_", token).strip("_")
    if not token:
        token = "x"
    if token[0].isdigit():
        token = f"n_{token}"
    return token


def num_token(n: int) -> str:
    return f"n_{n}"


def normalize_ws(text: str) -> str:
    return " ".join(text.replace("\f", " ").split())


def sentence_split(text: str) -> List[str]:
    sentences = []
    for part in re.split(r"(?<=[.!?])\s+", normalize_ws(text)):
        s = part.strip()
        if len(s) < 30:
            continue
        if len(s) > 420:
            continue
        sentences.append(s)
    return sentences


def run_pdftotext(pdf_path: Path) -> str:
    if not pdf_path.exists():
        raise SystemExit(f"PDF not found: {pdf_path}")
    try:
        proc = subprocess.run(
            ["pdftotext", str(pdf_path), "-"],
            capture_output=True,
            text=True,
            check=True,
        )
    except FileNotFoundError as exc:
        raise SystemExit("pdftotext not found. Install poppler (pdftotext).") from exc
    except subprocess.CalledProcessError as exc:
        raise SystemExit(f"pdftotext failed: {exc.stderr.strip() or exc}") from exc
    return proc.stdout


def run_pdfinfo(pdf_path: Path) -> Dict[str, str]:
    try:
        proc = subprocess.run(
            ["pdfinfo", str(pdf_path)],
            capture_output=True,
            text=True,
            check=True,
        )
    except Exception:
        return {}
    info: Dict[str, str] = {}
    for line in proc.stdout.splitlines():
        if ":" not in line:
            continue
        k, v = line.split(":", 1)
        info[k.strip()] = v.strip()
    return info


def extract_contributions(text: str) -> List[Dict[str, str]]:
    out: List[Dict[str, str]] = []
    for m in CONTRIB_RE.finditer(normalize_ws(text)):
        ordinal = m.group(1).lower()
        section = m.group(2)
        statement = m.group(3).strip()
        out.append(
            {
                "ordinal": ordinal,
                "section": section,
                "statement": statement,
                "statement_token": safe_token(statement)[:120],
            }
        )
    return out


def find_excerpt(sentences: Sequence[str], probes: Sequence[str]) -> str:
    low_probes = [p.lower() for p in probes]
    for sentence in sentences:
        low = sentence.lower()
        if any(p in low for p in low_probes):
            return sentence
    return ""


def match_claim(text: str, claim: Dict[str, Any], sentences: Sequence[str]) -> Dict[str, Any]:
    low = text.lower()
    probes = [p.lower() for p in claim["probes"]]
    hits = [p for p in probes if p in low]
    mode = claim.get("mode", "any")
    detected = bool(hits) if mode == "any" else len(hits) == len(probes)
    return {
        "id": claim["id"],
        "summary": claim["summary"],
        "mode": mode,
        "probes": list(claim["probes"]),
        "matched_probes": hits,
        "detected": detected,
        "excerpt": find_excerpt(sentences, probes),
    }


def extract_claims(text: str) -> List[Dict[str, Any]]:
    sentences = sentence_split(text)
    return [match_claim(text, claim, sentences) for claim in CLAIM_DEFS]


def keyword_counts(text: str) -> Dict[str, int]:
    low = text.lower()
    return {safe_token(k): low.count(k.lower()) for k in KEYWORDS}


def build_zc(module_name: str, source_pdf: Path, claims: Sequence[Dict[str, Any]], contributions: Sequence[Dict[str, str]]) -> str:
    paper_id = "paper:2505_17335v2"
    run_id = "run_p2505_17335v2_ci_001"

    lines: List[str] = [
        f"MODULE {module_name}.",
        "",
        "// Generated automatically from arXiv:2505.17335v2.",
        "// Coverage model for PulseParse / EverCBOR / EverCDDL / COSE / DPE claims.",
        "// Run with:",
        "//   ./bin/zil preprocess examples/generated/everparse-2505-17335-extension.zc /tmp/everparse_2505_17335.pre.zc libsets/everparse-interop",
        "//   ./bin/zil /tmp/everparse_2505_17335.pre.zc",
        "",
        f"{paper_id}#kind@entity:research_paper.",
        f"{paper_id}#title@value:secure_parsing_serializing_separation_logic_cbor_cddl_cose.",
        f"{paper_id}#arxiv@value:n_2505_17335_v2.",
        f"{paper_id}#source_pdf@value:{safe_token(source_pdf.name)}.",
        "",
        "USE EP_SPEC(p2505_17335_suite, secure_parsing_serializing_sl, paper_contract, arxiv_2505_17335v2).",
        "USE EP_PROFILE(c_rust_verified, c_rust, everparse_karamel, no_ub).",
        f"USE EP_RUN({run_id}, p2505_17335_suite, c_rust_verified, succeeded).",
        "",
        f"USE EP_ARTIFACT({run_id}, a_fstar, fstar_specs, pulseparse_fstar_specs).",
        f"USE EP_ARTIFACT({run_id}, a_pulse, pulse_impl, pulseparse_impl).",
        f"USE EP_ARTIFACT({run_id}, a_c_lib, c_library, evercbor_c_library).",
        f"USE EP_ARTIFACT({run_id}, a_rust_lib, rust_library, evercbor_safe_rust_library).",
        f"USE EP_ARTIFACT({run_id}, a_codegen, code_generator, evercddl_codegen).",
        "",
        f"USE EP_TEST_SUITE({run_id}, batch, true, true, true, n_3).",
        "",
    ]

    # Keep generic EP guarantees explicit, detected from paper text where possible.
    guarantee_map = {
        "memory_safety": "memory_safety_guarantee",
        "arithmetic_safety": "arithmetic_safety_guarantee",
        "double_fetch_freedom": "double_fetch_freedom",
    }
    claim_by_id = {c["id"]: c for c in claims}
    for gid, cid in guarantee_map.items():
        verdict = "proved" if claim_by_id.get(cid, {}).get("detected") else "pending"
        lines.append(f"USE EP_GUARANTEE({run_id}, g_{safe_token(gid)}, {safe_token(gid)}, {verdict}).")

    lines += [
        "",
        f"USE EP_EVIDENCE({run_id}, e_primary, everparse_2505_17335v2_contract, paper_pdf, arxiv_2505_17335v2).",
        "",
    ]

    for c in contributions:
        cid = safe_token(c["ordinal"])
        lines.append(f"paper:contrib:{cid}#kind@entity:paper_contribution.")
        lines.append(f"paper:contrib:{cid}#paper@{paper_id}.")
        lines.append(f"paper:contrib:{cid}#section@value:{safe_token(c['section'])}.")
        lines.append(f"paper:contrib:{cid}#statement@value:{c['statement_token']}.")
    lines.append("")

    covered_ids: List[str] = []
    gap_ids: List[str] = []
    for claim in claims:
        cid = safe_token(claim["id"])
        detected = bool(claim["detected"])
        status = "covered" if detected else "gap"
        if detected:
            covered_ids.append(cid)
        else:
            gap_ids.append(cid)
        lines.append(f"paper:claim:{cid}#kind@entity:paper_claim.")
        lines.append(f"paper:claim:{cid}#paper@{paper_id}.")
        lines.append(f"paper:claim:{cid}#summary@value:{safe_token(claim['summary'])}.")
        lines.append(f"paper:claim:{cid}#detected@value:{str(detected).lower()}.")
        lines.append(f"paper:claim:{cid}#status@value:{status}.")
    lines.append("")

    lines.append(f"{paper_id}#claims_total@value:{num_token(len(claims))}.")
    lines.append(f"{paper_id}#claims_covered@value:{num_token(len(covered_ids))}.")
    lines.append(f"{paper_id}#claims_gap@value:{num_token(len(gap_ids))}.")
    lines.append("")

    if claims:
        all_covered = " AND ".join(
            f"paper:claim:{safe_token(c['id'])}#status@value:covered" for c in claims
        )
        lines.append("RULE paper_full_coverage:")
        lines.append(f"IF {all_covered}")
        lines.append(f"THEN {paper_id}#coverage@value:full.")
        lines.append("")

    lines += [
        "QUERY paper_claim_status:",
        "FIND ?claim ?status WHERE ?claim#kind@entity:paper_claim AND ?claim#status@?status.",
        "",
        "QUERY paper_claim_gaps:",
        "FIND ?claim WHERE ?claim#kind@entity:paper_claim AND ?claim#status@value:gap.",
        "",
        "QUERY paper_full_coverage:",
        f"FIND ?coverage WHERE {paper_id}#coverage@?coverage.",
        "",
        "QUERY ep_contract_gaps:",
        "FIND ?run ?gap WHERE ?run#contract_gap@?gap.",
        "",
        "QUERY ep_contract_verified_runs:",
        "FIND ?run WHERE ?run#contract_verified@value:true.",
        "",
    ]

    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pdf", default="~/Downloads/2505.17335v2.pdf")
    parser.add_argument(
        "--out-json",
        default="examples/generated/everparse-2505-17335-model-inputs.json",
    )
    parser.add_argument(
        "--out-zc",
        default="examples/generated/everparse-2505-17335-extension.zc",
    )
    parser.add_argument("--module", default="everparse.paper.p2505_17335.extension")
    parser.add_argument(
        "--strict",
        action="store_true",
        help="Fail if less than four explicit contribution statements are extracted.",
    )
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parents[1]
    pdf_path = Path(args.pdf).expanduser().resolve()

    raw_text = run_pdftotext(pdf_path)
    text = normalize_ws(raw_text)
    contributions = extract_contributions(raw_text)
    claims = extract_claims(text)

    if args.strict and len(contributions) < 4:
        raise SystemExit(
            f"strict mode failed: expected >=4 contribution statements, found {len(contributions)}"
        )

    data = {
        "source_pdf": str(pdf_path),
        "pdf_info": run_pdfinfo(pdf_path),
        "stats": {
            "chars": len(raw_text),
            "sentences": len(sentence_split(raw_text)),
            "contributions_found": len(contributions),
            "claims_total": len(claims),
            "claims_covered": sum(1 for c in claims if c["detected"]),
            "claims_gap": sum(1 for c in claims if not c["detected"]),
        },
        "keyword_counts": keyword_counts(raw_text),
        "contributions": contributions,
        "claims": claims,
    }

    out_json = (repo_root / args.out_json).resolve()
    out_zc = (repo_root / args.out_zc).resolve()
    out_json.parent.mkdir(parents=True, exist_ok=True)
    out_zc.parent.mkdir(parents=True, exist_ok=True)

    out_json.write_text(json.dumps(data, indent=2), encoding="utf-8")
    out_zc.write_text(
        build_zc(args.module, pdf_path, claims, contributions),
        encoding="utf-8",
    )

    covered = data["stats"]["claims_covered"]
    total = data["stats"]["claims_total"]
    print(f"[ok] source: {pdf_path}")
    print(f"[ok] json:   {out_json}")
    print(f"[ok] zc:     {out_zc}")
    print(f"[ok] contributions={len(contributions)} claims={covered}/{total} covered")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
