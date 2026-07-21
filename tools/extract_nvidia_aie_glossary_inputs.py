#!/usr/bin/env python3
"""
Extract structured glossary inputs from NVIDIA AI Enterprise glossary page.

Primary source:
  https://docs.nvidia.com/ai-enterprise/release-7/latest/troubleshooting/glossary.html

Outputs:
- JSON catalog with sections + terms + metadata
- ZIL fact seed file for glossary modeling and queries
"""

from __future__ import annotations

import argparse
import datetime as dt
import html
import json
import re
import subprocess
import urllib.request
from pathlib import Path
from typing import Dict, List, Sequence

DEFAULT_URL = (
    "https://docs.nvidia.com/ai-enterprise/release-7/latest/troubleshooting/glossary.html"
)

META_RE = re.compile(r'<meta\s+name="([^"]+)"\s+content="([^"]*)"\s*/?>', re.IGNORECASE)
SECTION_RE = re.compile(
    r'<section\s+id="([^"]+)">\s*<h2>(.+?)<a\s+class="headerlink"',
    re.IGNORECASE | re.DOTALL,
)
TERM_RE = re.compile(
    r'<dt\s+id="term-([^"]+)">(.+?)<a\s+class="headerlink"[^>]*>.*?</a></dt>\s*'
    r'<dd><p>(.+?)</p>',
    re.IGNORECASE | re.DOTALL,
)
TITLE_RE = re.compile(r"<title>(.*?)</title>", re.IGNORECASE | re.DOTALL)


def safe_token(raw: str) -> str:
    tok = re.sub(r"[^A-Za-z0-9_]+", "_", raw.strip().lower())
    tok = re.sub(r"_+", "_", tok).strip("_")
    if not tok:
        tok = "x"
    if tok[0].isdigit():
        tok = f"n_{tok}"
    return tok


def strip_tags(value: str) -> str:
    # Remove HTML tags and normalize whitespace.
    no_tags = re.sub(r"<[^>]+>", "", value)
    return " ".join(html.unescape(no_tags).split())


def short_token_text(text: str, words: int = 24) -> str:
    parts = text.split()
    return safe_token(" ".join(parts[:words]))


def fetch_html(url: str, timeout: int) -> str:
    req = urllib.request.Request(
        url,
        headers={
            "User-Agent": "Mozilla/5.0 (compatible; zil-glossary-extractor/1.0)",
            "Accept": "text/html,application/xhtml+xml",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            content_type = resp.headers.get("Content-Type", "")
            if "text/html" not in content_type and "application/xhtml" not in content_type:
                raise SystemExit(f"unexpected content type: {content_type}")
            raw = resp.read()
        return raw.decode("utf-8", errors="replace")
    except Exception:
        # Fallback for environments where Python SSL trust store is not configured.
        proc = subprocess.run(
            ["curl", "-sS", url],
            capture_output=True,
            text=True,
            check=True,
        )
        page = proc.stdout
        if "<html" not in page.lower():
            raise SystemExit("failed to fetch HTML page via urllib and curl fallback")
        return page


def load_html(url: str, html_file: Path | None, timeout: int) -> str:
    if html_file is not None:
        if not html_file.exists():
            raise SystemExit(f"html file not found: {html_file}")
        return html_file.read_text(encoding="utf-8")
    return fetch_html(url, timeout=timeout)


def parse_title(page: str) -> str:
    m = TITLE_RE.search(page)
    if not m:
        return ""
    return strip_tags(m.group(1))


def parse_meta(page: str) -> Dict[str, str]:
    out: Dict[str, str] = {}
    for k, v in META_RE.findall(page):
        out[k.strip()] = html.unescape(v.strip())
    return out


def parse_sections(page: str) -> List[Dict[str, str]]:
    sections: List[Dict[str, str]] = []
    for sid, raw_name in SECTION_RE.findall(page):
        name = strip_tags(raw_name)
        sections.append(
            {
                "id": sid,
                "name": name,
                "id_token": safe_token(sid),
                "name_token": safe_token(name),
            }
        )
    # The first glossary list is under <section id="glossary"> with h1, not h2.
    if not any(s["id"] == "glossary" for s in sections):
        sections.insert(
            0,
            {
                "id": "glossary",
                "name": "Glossary",
                "id_token": "glossary",
                "name_token": "glossary",
            },
        )
    return sections


def find_section_ranges(page: str, sections: Sequence[Dict[str, str]]) -> List[tuple[str, int, int]]:
    ranges: List[tuple[str, int, int]] = []
    starts: List[tuple[str, int]] = []
    for s in sections:
        marker = f'<section id="{s["id"]}">'  # exact anchor
        idx = page.find(marker)
        if idx >= 0:
            starts.append((s["id"], idx))
    starts.sort(key=lambda x: x[1])
    for i, (sid, start) in enumerate(starts):
        end = starts[i + 1][1] if i + 1 < len(starts) else len(page)
        ranges.append((sid, start, end))
    if not ranges:
        ranges.append(("glossary", 0, len(page)))
    return ranges


def section_for_pos(pos: int, ranges: Sequence[tuple[str, int, int]]) -> str:
    for sid, start, end in ranges:
        if start <= pos < end:
            return sid
    return "glossary"


def parse_terms(page: str, sections: Sequence[Dict[str, str]]) -> List[Dict[str, str]]:
    ranges = find_section_ranges(page, sections)
    terms: List[Dict[str, str]] = []
    seen = set()

    for m in TERM_RE.finditer(page):
        raw_id = m.group(1)
        raw_term = strip_tags(m.group(2))
        raw_def = strip_tags(m.group(3))
        term_key = safe_token(raw_term)
        if term_key in seen:
            continue
        seen.add(term_key)
        sid = section_for_pos(m.start(), ranges)
        terms.append(
            {
                "id": raw_id,
                "term": raw_term,
                "definition": raw_def,
                "section_id": sid,
                "term_token": term_key,
                "definition_token": short_token_text(raw_def, words=28),
            }
        )

    return terms


def section_counts(terms: Sequence[Dict[str, str]]) -> Dict[str, int]:
    counts: Dict[str, int] = {}
    for t in terms:
        sid = t["section_id"]
        counts[sid] = counts.get(sid, 0) + 1
    return counts


def build_zc(module_name: str, source_url: str, sections: Sequence[Dict[str, str]], terms: Sequence[Dict[str, str]], fetched_at: str) -> str:
    lines: List[str] = [
        f"MODULE {module_name}.",
        "",
        "// Generated from NVIDIA AI Enterprise glossary page.",
        "source:nvidia_aie_glossary#kind@entity:document.",
        "source:nvidia_aie_glossary#provider@provider:nvidia.",
        f"source:nvidia_aie_glossary#url@value:{safe_token(source_url)}.",
        f"source:nvidia_aie_glossary#fetched_at@value:{safe_token(fetched_at)}.",
        "provider:nvidia#kind@entity:provider.",
        "provider:nvidia#source@value:nvidia.",
        "",
    ]

    for s in sections:
        sid = s["id_token"]
        lines.append(f"nvaie:section:{sid}#kind@entity:nvidia_glossary_section.")
        lines.append(f"nvaie:section:{sid}#name@value:{s['name_token']}.")
    lines.append("")

    for t in terms:
        tid = t["term_token"]
        sid = safe_token(t["section_id"])
        lines.append(f"nvaie:term:{tid}#kind@entity:nvidia_glossary_term.")
        lines.append(f"nvaie:term:{tid}#term@value:{tid}.")
        lines.append(f"nvaie:term:{tid}#section@nvaie:section:{sid}.")
        lines.append(f"nvaie:term:{tid}#definition@value:{t['definition_token']}.")
    lines.append("")

    lines += [
        "QUERY nvidia_glossary_sections:",
        "FIND ?s ?name WHERE ?s#kind@entity:nvidia_glossary_section AND ?s#name@?name.",
        "",
        "QUERY nvidia_glossary_terms:",
        "FIND ?t ?term ?sec WHERE ?t#kind@entity:nvidia_glossary_term AND ?t#term@?term AND ?t#section@?sec.",
        "",
        "QUERY nvidia_glossary_terms_by_section:",
        "FIND ?sec ?term WHERE ?termEntity#kind@entity:nvidia_glossary_term AND ?termEntity#section@?sec AND ?termEntity#term@?term.",
        "",
    ]

    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--url", default=DEFAULT_URL)
    parser.add_argument("--html-file", default="")
    parser.add_argument("--timeout-sec", type=int, default=20)
    parser.add_argument(
        "--out-json",
        default="examples/generated/nvidia-aie-glossary-inputs.json",
    )
    parser.add_argument(
        "--out-zc",
        default="examples/generated/nvidia-aie-glossary-inputs.zc",
    )
    parser.add_argument("--module", default="nvidia.aie.glossary.extracted")
    parser.add_argument("--strict-min-terms", type=int, default=40)
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parents[1]
    html_file = Path(args.html_file).expanduser() if args.html_file else None

    page = load_html(args.url, html_file=html_file, timeout=args.timeout_sec)
    title = parse_title(page)
    meta = parse_meta(page)
    sections = parse_sections(page)
    terms = parse_terms(page, sections)

    if len(terms) < max(1, args.strict_min_terms):
        raise SystemExit(
            f"too few terms extracted ({len(terms)}), expected at least {args.strict_min_terms}"
        )

    fetched_at = dt.datetime.now(dt.timezone.utc).isoformat()
    sec_count = section_counts(terms)

    data = {
        "source_url": args.url,
        "source_html_file": str(html_file) if html_file else "",
        "fetched_at": fetched_at,
        "title": title,
        "meta": {
            "docbuild:last-update": meta.get("docbuild:last-update", ""),
            "docs_products": meta.get("docs_products", ""),
            "docs_version": meta.get("docs_version", ""),
            "docs_books": meta.get("docs_books", ""),
        },
        "stats": {
            "sections_found": len(sections),
            "terms_found": len(terms),
        },
        "sections": [
            {
                **s,
                "terms": sec_count.get(s["id"], 0),
            }
            for s in sections
        ],
        "terms": terms,
    }

    out_json = (repo_root / args.out_json).resolve()
    out_zc = (repo_root / args.out_zc).resolve()
    out_json.parent.mkdir(parents=True, exist_ok=True)
    out_zc.parent.mkdir(parents=True, exist_ok=True)

    out_json.write_text(json.dumps(data, indent=2), encoding="utf-8")
    out_zc.write_text(
        build_zc(
            module_name=args.module,
            source_url=args.url,
            sections=sections,
            terms=terms,
            fetched_at=fetched_at,
        ),
        encoding="utf-8",
    )

    print(f"[ok] source: {args.url}")
    if html_file:
        print(f"[ok] html:   {html_file}")
    print(f"[ok] json:   {out_json}")
    print(f"[ok] zc:     {out_zc}")
    print(f"[ok] stats: sections={len(sections)} terms={len(terms)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
