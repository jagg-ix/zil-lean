#!/usr/bin/env python3
"""
Extract structured AWS modeling inputs from aws-overview.pdf.

Outputs:
- JSON catalog with services, regions, topical controls, and summary counts
- ZIL fact seed file usable for follow-up AWS compatibility modeling

Default source:
  ~/Downloads/aws-overview.pdf
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
from pathlib import Path
from typing import Dict, Iterable, List, Sequence, Tuple


SERVICE_LINE_RE = re.compile(r"^(Amazon|AWS)\s+[A-Za-z0-9][A-Za-z0-9&/,'().:+ -]{1,90}$")
REGION_RE = re.compile(r"\b(?:us|eu|ap|sa|ca|af|me|il|mx|cn|us-gov)-[a-z0-9-]+-\d\b")

SERVICE_STOP = {
    "aws whitepaper",
    "aws services",
    "accessing aws services",
    "overview of amazon web services",
    "benefits of aws security",
    "introduction to aws",
    "global infrastructure",
    "security and compliance",
    "security",
    "compliance",
    "aws services by category",
    "aws whitepapers & guides",
}

CONTROL_KEYWORDS: Dict[str, Tuple[str, ...]] = {
    "identity": ("iam", "least privilege", "mfa", "multi-factor", "federat"),
    "encryption": ("encrypt", "kms", "key management", "tls", "ssl"),
    "logging": ("cloudtrail", "cloudwatch", "log", "audit", "monitor"),
    "network": ("vpc", "security group", "subnet", "route table", "private link"),
    "resilience": ("backup", "disaster recovery", "availability", "fault", "multi-az"),
    "governance": ("compliance", "policy", "control tower", "governance", "guardrail"),
    "cost": ("cost", "budget", "optimization", "savings", "pricing"),
}

CONTROL_SENTENCE_HINTS = (
    "must",
    "should",
    "required",
    "ensure",
    "recommend",
    "best practice",
    "security",
    "compliance",
    "resilien",
    "availability",
    "encryption",
    "monitor",
    "audit",
    "logging",
    "network",
    "backup",
)


def safe_token(raw: str) -> str:
    token = re.sub(r"[^A-Za-z0-9_]+", "_", raw.strip().lower())
    token = re.sub(r"_+", "_", token).strip("_")
    if not token:
        token = "x"
    if token[0].isdigit():
        token = f"n_{token}"
    return token


def is_toc_noise_line(line: str) -> bool:
    if re.search(r"\.{3,}", line):
        return True
    if re.match(r"^[ivxlcdm]+\s*$", line.lower()):
        return True
    if re.match(r"^\d+\s+[A-Z][A-Za-z]", line):
        return True
    return False


def run_pdftotext(pdf_path: Path) -> str:
    if not pdf_path.exists():
        raise SystemExit(f"PDF not found: {pdf_path}")
    cmd = ["pdftotext", str(pdf_path), "-"]
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, check=True)
    except FileNotFoundError as exc:
        raise SystemExit("pdftotext not found. Install poppler (pdftotext).") from exc
    except subprocess.CalledProcessError as exc:
        raise SystemExit(f"pdftotext failed: {exc.stderr.strip() or exc}") from exc
    return proc.stdout


def normalize_lines(text: str) -> List[str]:
    cleaned = text.replace("\f", "\n")
    lines = []
    for raw in cleaned.splitlines():
        line = re.sub(r"\s+", " ", raw).strip()
        if not line:
            continue
        lines.append(line)
    return lines


def clean_toc_line(line: str) -> str:
    # Remove table-of-contents leader dots + page numbers.
    line = re.sub(r"\.{2,}\s*\d+\s*$", "", line).strip()
    line = re.sub(r"\s+\d+\s*$", "", line).strip()
    line = line.lstrip("•- ").strip()
    line = re.sub(r"\s+", " ", line)
    line = line.rstrip(".,;: ").strip()
    return line


def is_likely_service(line: str) -> bool:
    if not SERVICE_LINE_RE.match(line):
        return False
    low = line.lower()
    if len(line) > 72:
        return False
    if low in SERVICE_STOP:
        return False
    # Skip long legal/heading lines.
    if "copyright" in low or "trademark" in low:
        return False
    if re.match(r"^amazon ec2 .*\binstances?\b", low):
        return False
    # Skip descriptive sentences that start with Amazon/AWS but are not service names.
    if any(
        marker in low
        for marker in (
            " is ",
            " are ",
            " enables ",
            " helps ",
            " allows ",
            " provides ",
            " makes ",
            " integrates ",
            " manages ",
            " supports ",
            " simplifies ",
        )
    ):
        return False
    return True


def extract_services(lines: Sequence[str], max_services: int) -> List[str]:
    seen = set()
    services = []
    for line in lines:
        candidate = clean_toc_line(line)
        if not is_likely_service(candidate):
            continue
        key = candidate.lower()
        if key in seen:
            continue
        seen.add(key)
        services.append(candidate)
        if len(services) >= max_services:
            break
    return services


def sentence_split(text: str) -> List[str]:
    raw = re.split(r"(?<=[.!?])\s+", re.sub(r"\s+", " ", text))
    out = []
    for s in raw:
        s = s.strip()
        if len(s) < 40:
            continue
        if len(s) > 320:
            continue
        if re.search(r"\.{3,}", s):
            continue
        if re.match(r"^\d+\s+[A-Z][A-Za-z]", s):
            continue
        out.append(s)
    return out


def classify_control(sentence: str) -> str:
    low = sentence.lower()
    best = "general"
    best_score = 0
    for category, words in CONTROL_KEYWORDS.items():
        score = 0
        for w in words:
            if w in low:
                score += 1
        if score > best_score:
            best = category
            best_score = score
    return best


def extract_controls(text: str, max_controls: int) -> List[Dict[str, str]]:
    controls = []
    seen = set()
    for sentence in sentence_split(text):
        low = sentence.lower()
        if not any(h in low for h in CONTROL_SENTENCE_HINTS):
            continue
        if sentence in seen:
            continue
        # Skip near-header lines masquerading as sentences.
        if SERVICE_LINE_RE.match(sentence):
            continue
        if "overview of amazon web services aws whitepaper" in low:
            continue
        if re.search(r"\b\d+\s+overview of amazon web services\b", low):
            continue
        seen.add(sentence)
        controls.append(
            {
                "id": f"ctrl_{safe_token(sentence)[:40]}",
                "category": classify_control(sentence),
                "excerpt": sentence,
            }
        )
        if len(controls) >= max_controls:
            break
    return controls


def keyword_counts(text: str) -> Dict[str, int]:
    low = text.lower()
    counts: Dict[str, int] = {}
    for category, words in CONTROL_KEYWORDS.items():
        total = 0
        for w in words:
            total += low.count(w)
        counts[category] = total
    return counts


def extract_named_regions(lines: Sequence[str], text: str) -> List[str]:
    found = set()
    allowed_majors = {
        "us east",
        "us west",
        "europe",
        "asia pacific",
        "asia paciﬁc",
        "south america",
        "canada",
        "govcloud",
        "middle east",
        "africa",
        "china",
        "israel",
        "mexico",
    }
    major_display = {
        "us east": "US East",
        "us west": "US West",
        "europe": "Europe",
        "asia pacific": "Asia Pacific",
        "asia paciﬁc": "Asia Pacific",
        "south america": "South America",
        "canada": "Canada",
        "govcloud": "GovCloud",
        "middle east": "Middle East",
        "africa": "Africa",
        "china": "China",
        "israel": "Israel",
        "mexico": "Mexico",
    }
    # Pattern like: AWS US East (Northern Virginia)
    for m in re.finditer(r"\bAWS\s+([A-Za-z]+(?:\s+[A-Za-z]+){0,2})\s+\(([^)]+)\)", text):
        major = re.sub(r"\s+", " ", m.group(1)).strip().lower()
        loc = re.sub(r"\s+", " ", m.group(2)).strip()
        if major in allowed_majors:
            found.add(f"{major_display.get(major, major.title())} ({loc})")
    # Pick up unprefixed region-name lists in lines that mention "following AWS Regions".
    hotspot = [i for i, line in enumerate(lines) if "following AWS Regions" in line]
    city_names = (
        "Northern Virginia",
        "Ohio",
        "Oregon",
        "Northern California",
        "Montreal",
        "Sao Paulo",
        "São Paulo",
        "Ireland",
        "Frankfurt",
        "London",
        "Paris",
        "Stockholm",
        "Singapore",
        "Tokyo",
        "Sydney",
        "Seoul",
        "Mumbai",
        "Milan",
        "Cape Town",
    )
    for idx in hotspot:
        window = " ".join(lines[idx : idx + 4])
        for name in city_names:
            if re.search(rf"\b{re.escape(name)}\b", window):
                found.add(name)
    # Drop plain city aliases when already present as a parenthesized region location.
    paren_locs = set()
    for item in found:
        m = re.search(r"\(([^)]+)\)\s*$", item)
        if m:
            paren_locs.add(m.group(1).strip())
    found = {item for item in found if "(" in item or item not in paren_locs}
    return sorted(found)


def build_zc_seed(
    module_name: str,
    services: Sequence[str],
    regions: Sequence[str],
    controls: Sequence[Dict[str, str]],
) -> str:
    lines = [
        f"MODULE {module_name}.",
        "",
        "// Generated from aws-overview.pdf extraction.",
        "source:aws_overview_pdf#kind@entity:document.",
        "source:aws_overview_pdf#provider@provider:aws.",
        "provider:aws#kind@entity:provider.",
        "provider:aws#source@value:amazon_web_services.",
        "",
    ]
    for name in services:
        sid = safe_token(name)
        lines.append(f"aws:service:{sid}#kind@entity:aws_service.")
        lines.append(f"aws:service:{sid}#provider@provider:aws.")
        lines.append(f"aws:service:{sid}#name@value:{safe_token(name)}.")
    lines.append("")
    for region in regions:
        rid = safe_token(region)
        lines.append(f"aws:region:{rid}#kind@entity:aws_region.")
        lines.append(f"aws:region:{rid}#name@value:{rid}.")
    lines.append("")
    for control in controls:
        cid = safe_token(control["id"])
        lines.append(f"aws:control:{cid}#kind@entity:aws_control.")
        lines.append(f"aws:control:{cid}#category@value:{safe_token(control['category'])}.")
        lines.append("aws:control:{cid}#source@source:aws_overview_pdf.".format(cid=cid))
    lines += [
        "",
        "QUERY aws_services:",
        "FIND ?s WHERE ?s#kind@entity:aws_service.",
        "",
        "QUERY aws_regions:",
        "FIND ?r WHERE ?r#kind@entity:aws_region.",
        "",
        "QUERY aws_controls:",
        "FIND ?c ?cat WHERE ?c#kind@entity:aws_control AND ?c#category@?cat.",
        "",
    ]
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pdf", default="~/Downloads/aws-overview.pdf")
    parser.add_argument(
        "--out-json",
        default="examples/generated/aws-overview-model-inputs.json",
    )
    parser.add_argument(
        "--out-zc",
        default="examples/generated/aws-overview-model-inputs.zc",
    )
    parser.add_argument("--module", default="aws.overview.extracted")
    parser.add_argument("--max-services", type=int, default=500)
    parser.add_argument("--max-controls", type=int, default=120)
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parents[1]
    pdf_path = Path(args.pdf).expanduser()
    text = run_pdftotext(pdf_path)
    lines = normalize_lines(text)
    body_text = " ".join(line for line in lines if not is_toc_noise_line(line))

    services = extract_services(lines, max_services=max(1, args.max_services))
    code_regions = sorted(set(m.group(0) for m in REGION_RE.finditer(text)))
    named_regions = extract_named_regions(lines, text)
    regions = sorted(set(code_regions + named_regions))
    controls = extract_controls(body_text, max_controls=max(1, args.max_controls))

    data = {
        "source_pdf": str(pdf_path),
        "stats": {
            "chars": len(text),
            "lines": len(lines),
            "services_found": len(services),
            "regions_found": len(regions),
            "controls_found": len(controls),
        },
        "regions": regions,
        "services": [{"id": safe_token(s), "name": s} for s in services],
        "controls": controls,
        "keyword_counts": keyword_counts(text),
        "next_modeling_hints": {
            "provider": "aws",
            "required_config_paths": [
                "account_id",
                "region",
                "vpc_id",
                "subnet_ids",
                "kms_key_id",
                "cloudtrail_enabled",
                "logging_sink",
            ],
            "drift_signals": [
                "missing_required_config",
                "region_mismatch",
                "unencrypted_storage",
                "audit_logging_disabled",
            ],
        },
    }

    out_json = (repo_root / args.out_json).resolve()
    out_zc = (repo_root / args.out_zc).resolve()
    out_json.parent.mkdir(parents=True, exist_ok=True)
    out_zc.parent.mkdir(parents=True, exist_ok=True)

    out_json.write_text(json.dumps(data, indent=2), encoding="utf-8")
    out_zc.write_text(
        build_zc_seed(args.module, services, regions, controls),
        encoding="utf-8",
    )

    print(f"[ok] source: {pdf_path}")
    print(f"[ok] json:   {out_json}")
    print(f"[ok] zc:     {out_zc}")
    print(
        "[ok] stats: services={s} regions={r} controls={c}".format(
            s=len(services), r=len(regions), c=len(controls)
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
