#!/usr/bin/env python3
"""
Index AWS icon package into structured JSON + ZIL fact files.

Outputs:
- examples/generated/aws-icon-catalog.json
- examples/generated/aws-icon-catalog.zc
- examples/generated/aws-service-icon-links.zc

By default, this consumes:
- icon package under ~/Downloads/Icon-package_01302026...
- service list from examples/generated/aws-overview-model-inputs.json
"""

from __future__ import annotations

import argparse
import json
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Sequence, Tuple


def safe_token(raw: str) -> str:
    token = re.sub(r"[^A-Za-z0-9_]+", "_", raw.strip().lower())
    token = re.sub(r"_+", "_", token).strip("_")
    if not token:
        token = "x"
    if token[0].isdigit():
        token = f"n_{token}"
    return token


def normalize_name(raw: str) -> str:
    text = raw
    text = re.sub(r"\.(png|svg)$", "", text, flags=re.I)
    text = re.sub(r"^(Res_|Arch-Category_|Arch_)", "", text)
    text = re.sub(r"_(16|32|48|64)$", "", text)
    text = text.replace("&", " and ")
    text = text.replace("/", " ")
    text = text.replace("-", " ")
    text = re.sub(r"\s+", " ", text).strip()
    return text


def split_tokens(token: str) -> List[str]:
    return [x for x in token.split("_") if x]


@dataclass
class IconAsset:
    relpath: str
    family: str
    bucket: str
    stem_raw: str
    concept_token: str
    format: str
    size: str
    variant: str
    asset_id: str


def infer_family(relpath: str) -> str:
    rp = relpath.lower()
    if "resource-icons_" in rp:
        return "resource"
    if "architecture-service-icons_" in rp:
        return "architecture_service"
    if "architecture-group-icons_" in rp:
        return "architecture_group"
    if "category-icons_" in rp:
        return "category"
    return "other"


def infer_bucket(parts: Sequence[str]) -> str:
    for p in parts:
        if p.startswith("Res_"):
            return safe_token(p[4:])
        if p.startswith("Arch_"):
            return safe_token(p[5:])
        if p.startswith("Arch-Category_"):
            return "category"
    return "misc"


def infer_size(parts: Sequence[str], stem: str) -> str:
    # folder hints first
    for p in parts[::-1]:
        m = re.fullmatch(r"(16|32|48|64)", p)
        if m:
            return f"n_{m.group(1)}"
        m2 = re.search(r"_(16|32|48|64)$", p)
        if m2:
            return f"n_{m2.group(1)}"
    m = re.search(r"_(16|32|48|64)$", stem)
    if m:
        return f"n_{m.group(1)}"
    return "n_48"


def infer_variant(parts: Sequence[str], stem: str) -> str:
    all_text = " ".join(list(parts) + [stem]).lower()
    if "dark" in all_text:
        return "dark"
    if "light" in all_text:
        return "light"
    return "default"


def iter_icon_assets(icon_root: Path) -> List[IconAsset]:
    assets: List[IconAsset] = []
    for path in sorted(icon_root.rglob("*")):
        if not path.is_file():
            continue
        ext = path.suffix.lower()
        if ext not in {".png", ".svg"}:
            continue
        relpath = str(path.relative_to(icon_root))
        parts = list(path.relative_to(icon_root).parts)
        stem_raw = path.stem
        norm = normalize_name(stem_raw)
        concept_token = safe_token(norm)
        family = infer_family(relpath)
        bucket = infer_bucket(parts)
        size = infer_size(parts, stem_raw)
        variant = infer_variant(parts, stem_raw)
        fmt = ext.lstrip(".")
        asset_id = safe_token(f"{family}_{bucket}_{concept_token}_{size}_{variant}_{fmt}")
        assets.append(
            IconAsset(
                relpath=relpath,
                family=family,
                bucket=bucket,
                stem_raw=stem_raw,
                concept_token=concept_token,
                format=fmt,
                size=size,
                variant=variant,
                asset_id=asset_id,
            )
        )
    return assets


def preferred_asset(assets: Sequence[IconAsset]) -> IconAsset:
    # Prefer SVG then common architecture size 48 then 64/32/16.
    size_rank = {"n_48": 0, "n_64": 1, "n_32": 2, "n_16": 3}
    def key(a: IconAsset) -> Tuple[int, int, int]:
        fmt_rank = 0 if a.format == "svg" else 1
        s_rank = size_rank.get(a.size, 9)
        var_rank = 0 if a.variant == "default" else 1
        return (fmt_rank, s_rank, var_rank)
    return sorted(assets, key=key)[0]


def score_service_to_concept(service_id: str, concept_token: str) -> float:
    s_tokens = split_tokens(service_id)
    c_tokens = split_tokens(concept_token)
    if not s_tokens or not c_tokens:
        return 0.0
    if service_id == concept_token:
        return 1.0
    s_set = set(s_tokens)
    c_set = set(c_tokens)
    inter = len(s_set & c_set)
    if inter == 0:
        # fallback substring match for compact forms like cloudtrail/cloudwatch
        if service_id in concept_token or concept_token in service_id:
            return 0.52
        return 0.0
    overlap = inter / max(2, min(len(s_set), len(c_set)))
    prefix_bonus = 0.0
    if concept_token.startswith(service_id) or service_id.startswith(concept_token):
        prefix_bonus += 0.2
    if "amazon" in s_set and "amazon" in c_set:
        prefix_bonus += 0.05
    if "aws" in s_set and "aws" in c_set:
        prefix_bonus += 0.05
    return min(1.0, overlap + prefix_bonus)


def build_service_links(
    service_ids: Sequence[str],
    concept_tokens: Sequence[str],
    min_score: float,
) -> List[Dict[str, object]]:
    links: List[Dict[str, object]] = []
    for sid in service_ids:
        best_token = None
        best_score = 0.0
        for ct in concept_tokens:
            score = score_service_to_concept(sid, ct)
            if score > best_score:
                best_score = score
                best_token = ct
        if best_token and best_score >= min_score:
            links.append(
                {
                    "service_id": sid,
                    "icon_concept_token": best_token,
                    "confidence": int(round(best_score * 100)),
                }
            )
    return links


def write_catalog_zc(
    out_zc: Path,
    icon_root: Path,
    concept_assets: Dict[str, List[IconAsset]],
) -> None:
    lines: List[str] = []
    lines.append("MODULE aws.icon.catalog.generated.")
    lines.append("")
    lines.append("source:aws_icon_package#kind@entity:document.")
    lines.append(f"source:aws_icon_package#root_token@value:{safe_token(str(icon_root))}.")
    lines.append("")

    for concept_token in sorted(concept_assets.keys()):
        assets = concept_assets[concept_token]
        family = assets[0].family
        bucket = assets[0].bucket
        concept_id = safe_token(f"{family}_{bucket}_{concept_token}")
        pref = preferred_asset(assets)
        pref_asset_id = pref.asset_id
        lines.append(f"aws:icon_concept:{concept_id}#kind@entity:aws_icon_concept.")
        lines.append(f"aws:icon_concept:{concept_id}#family@value:{family}.")
        lines.append(f"aws:icon_concept:{concept_id}#bucket@value:{bucket}.")
        lines.append(f"aws:icon_concept:{concept_id}#token@value:{concept_token}.")
        lines.append(f"aws:icon_concept:{concept_id}#preferred_asset@aws:icon_asset:{pref_asset_id}.")
        for asset in assets:
            reltok = safe_token(asset.relpath)
            lines.append(f"aws:icon_asset:{asset.asset_id}#kind@entity:aws_icon_asset.")
            lines.append(
                f"aws:icon_asset:{asset.asset_id}#concept@aws:icon_concept:{concept_id}."
            )
            lines.append(f"aws:icon_asset:{asset.asset_id}#format@value:{asset.format}.")
            lines.append(f"aws:icon_asset:{asset.asset_id}#size@value:{asset.size}.")
            lines.append(f"aws:icon_asset:{asset.asset_id}#variant@value:{asset.variant}.")
            lines.append(f"aws:icon_asset:{asset.asset_id}#relpath_token@value:{reltok}.")
        lines.append("")

    lines.extend(
        [
            "QUERY aws_icon_concepts:",
            "FIND ?icon ?family WHERE ?icon#kind@entity:aws_icon_concept AND ?icon#family@?family.",
            "",
            "QUERY aws_icon_assets:",
            "FIND ?asset ?fmt WHERE ?asset#kind@entity:aws_icon_asset AND ?asset#format@?fmt.",
            "",
        ]
    )
    out_zc.parent.mkdir(parents=True, exist_ok=True)
    out_zc.write_text("\n".join(lines), encoding="utf-8")


def write_links_zc(
    out_zc: Path,
    links: Sequence[Dict[str, object]],
    concept_assets: Dict[str, List[IconAsset]],
) -> None:
    lines: List[str] = []
    lines.append("MODULE aws.icon.service.links.generated.")
    lines.append("")
    for link in links:
        sid = str(link["service_id"])
        ctoken = str(link["icon_concept_token"])
        confidence = int(link["confidence"])
        assets = concept_assets[ctoken]
        concept_id = safe_token(f"{assets[0].family}_{assets[0].bucket}_{ctoken}")
        lines.append(f"aws:service:{sid}#icon_concept@aws:icon_concept:{concept_id}.")
        lines.append(f"aws:service:{sid}#icon_link_confidence@value:n_{confidence}.")
    lines.extend(
        [
            "",
            "QUERY aws_service_icon_links:",
            "FIND ?svc ?icon WHERE ?svc#icon_concept@?icon.",
            "",
        ]
    )
    out_zc.parent.mkdir(parents=True, exist_ok=True)
    out_zc.write_text("\n".join(lines), encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--icon-root",
        default="~/Downloads/Icon-package_01302026.31b40d126ed27079b708594940ad577a86150582",
    )
    parser.add_argument(
        "--services-json",
        default="examples/generated/aws-overview-model-inputs.json",
    )
    parser.add_argument(
        "--out-json",
        default="examples/generated/aws-icon-catalog.json",
    )
    parser.add_argument(
        "--out-zc",
        default="examples/generated/aws-icon-catalog.zc",
    )
    parser.add_argument(
        "--out-links-zc",
        default="examples/generated/aws-service-icon-links.zc",
    )
    parser.add_argument("--min-confidence", type=float, default=0.55)
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parents[1]
    icon_root = Path(args.icon_root).expanduser().resolve()
    services_path = (repo_root / args.services_json).resolve()
    out_json = (repo_root / args.out_json).resolve()
    out_zc = (repo_root / args.out_zc).resolve()
    out_links_zc = (repo_root / args.out_links_zc).resolve()

    if not icon_root.exists():
        raise SystemExit(f"icon root not found: {icon_root}")
    if not services_path.exists():
        raise SystemExit(f"services json not found: {services_path}")

    assets = iter_icon_assets(icon_root)
    concept_assets: Dict[str, List[IconAsset]] = {}
    for a in assets:
        concept_assets.setdefault(a.concept_token, []).append(a)

    services_data = json.loads(services_path.read_text(encoding="utf-8"))
    service_ids = [item["id"] for item in services_data.get("services", []) if "id" in item]

    links = build_service_links(
        service_ids=service_ids,
        concept_tokens=sorted(concept_assets.keys()),
        min_score=max(0.0, min(1.0, args.min_confidence)),
    )

    catalog = {
        "icon_root": str(icon_root),
        "counts": {
            "assets": len(assets),
            "concepts": len(concept_assets),
            "service_links": len(links),
        },
        "families": sorted(set(a.family for a in assets)),
        "concepts": [
            {
                "token": ctoken,
                "family": cassets[0].family,
                "bucket": cassets[0].bucket,
                "asset_count": len(cassets),
                "preferred_asset": preferred_asset(cassets).relpath,
                "assets": [
                    {
                        "relpath": a.relpath,
                        "format": a.format,
                        "size": a.size,
                        "variant": a.variant,
                    }
                    for a in cassets
                ],
            }
            for ctoken, cassets in sorted(concept_assets.items())
        ],
        "service_links": links,
    }

    out_json.parent.mkdir(parents=True, exist_ok=True)
    out_json.write_text(json.dumps(catalog, indent=2), encoding="utf-8")
    write_catalog_zc(out_zc, icon_root, concept_assets)
    write_links_zc(out_links_zc, links, concept_assets)

    print(f"[ok] icon root: {icon_root}")
    print(f"[ok] json:      {out_json}")
    print(f"[ok] catalog zc:{out_zc}")
    print(f"[ok] links zc:  {out_links_zc}")
    print(
        "[ok] stats: assets={a} concepts={c} links={l}".format(
            a=len(assets), c=len(concept_assets), l=len(links)
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

