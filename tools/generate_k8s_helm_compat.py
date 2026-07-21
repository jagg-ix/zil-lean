#!/usr/bin/env python3
"""Generate Kubernetes/Helm compatibility ZIL macro layer and runnable example.

This tool emits:
- lib/k8s-helm-compat-macros.zc
- libsets/k8s-helm-compat/k8s-helm-compat-macros.zc
- examples/k8s-helm-compat.zc

It can optionally ingest:
- Helm Chart.yaml
- Helm values.yaml
- CRD YAML files/directories
- Rendered template YAML files/directories
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import textwrap
from pathlib import Path
from typing import Any, Dict, List, Sequence, Tuple

try:
    import yaml
except Exception as exc:  # pragma: no cover
    raise SystemExit("PyYAML is required for this generator: pip3 install pyyaml") from exc


def safe_token(raw: Any) -> str:
    text = str(raw)
    token = re.sub(r"[^A-Za-z0-9_]+", "_", text.strip())
    token = re.sub(r"_+", "_", token).strip("_")
    if not token:
        token = "x"
    if token[0].isdigit():
        token = f"n_{token}"
    return token.lower()


def scalar_to_token(value: Any) -> str:
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return safe_token(value)
    if value is None:
        return "null"
    return safe_token(value)


def load_yaml_or_json(path: Path) -> Any:
    text = path.read_text(encoding="utf-8")
    suffix = path.suffix.lower()
    if suffix == ".json":
        return json.loads(text)
    return yaml.safe_load(text)


def load_yaml_stream(path: Path) -> List[Dict[str, Any]]:
    text = path.read_text(encoding="utf-8")
    docs = []
    for item in yaml.safe_load_all(text):
        if isinstance(item, dict):
            docs.append(item)
    return docs


def collect_yaml_files(paths: Sequence[str]) -> List[Path]:
    out: List[Path] = []
    for raw in paths:
        p = Path(raw).expanduser()
        if not p.exists():
            continue
        if p.is_dir():
            for cand in sorted(p.rglob("*")):
                if cand.suffix.lower() in {".yaml", ".yml", ".json"} and cand.is_file():
                    out.append(cand)
        elif p.suffix.lower() in {".yaml", ".yml", ".json"}:
            out.append(p)
    dedup = []
    seen = set()
    for p in out:
        rp = str(p.resolve())
        if rp not in seen:
            seen.add(rp)
            dedup.append(p)
    return dedup


def flatten_scalars(data: Any, prefix: str = "") -> Dict[str, Any]:
    out: Dict[str, Any] = {}
    if isinstance(data, dict):
        for key, value in data.items():
            key_tok = safe_token(key)
            next_prefix = f"{prefix}_{key_tok}" if prefix else key_tok
            out.update(flatten_scalars(value, next_prefix))
    elif isinstance(data, list):
        for idx, value in enumerate(data):
            next_prefix = f"{prefix}_idx_{idx}"
            out.update(flatten_scalars(value, next_prefix))
    else:
        if prefix:
            out[prefix] = data
    return out


def parse_crds(paths: Sequence[Path]) -> List[Dict[str, str]]:
    crds: List[Dict[str, str]] = []
    for path in paths:
        for doc in load_yaml_stream(path):
            if doc.get("kind") != "CustomResourceDefinition":
                continue
            spec = doc.get("spec", {}) if isinstance(doc.get("spec"), dict) else {}
            names = spec.get("names", {}) if isinstance(spec.get("names"), dict) else {}
            group = spec.get("group", "example.local")
            scope = spec.get("scope", "Namespaced")
            kind_name = names.get("kind", "UnknownKind")
            plural = names.get("plural", safe_token(kind_name) + "s")
            versions = spec.get("versions", [])

            version_names: List[str] = []
            if isinstance(versions, list) and versions:
                for version in versions:
                    if not isinstance(version, dict):
                        continue
                    vname = version.get("name")
                    if vname:
                        version_names.append(str(vname))
            else:
                version = spec.get("version")
                if version:
                    version_names.append(str(version))

            if not version_names:
                version_names = ["v1"]

            for ver in version_names:
                crd_id = safe_token(f"{kind_name}_{group}_{ver}")
                crds.append(
                    {
                        "id": crd_id,
                        "group": safe_token(group),
                        "version": safe_token(ver),
                        "kind": safe_token(kind_name),
                        "plural": safe_token(plural),
                        "scope": safe_token(scope),
                    }
                )
    if not crds:
        crds.append(
            {
                "id": "synccontract_example_v1",
                "group": "sync_example_io",
                "version": "v1",
                "kind": "synccontract",
                "plural": "synccontracts",
                "scope": "namespaced",
            }
        )
    return crds


def parse_template_resources(paths: Sequence[Path], chart_id: str) -> List[Dict[str, str]]:
    resources: List[Dict[str, str]] = []
    for path in paths:
        for doc in load_yaml_stream(path):
            if "kind" not in doc or "apiVersion" not in doc:
                continue
            metadata = doc.get("metadata", {}) if isinstance(doc.get("metadata"), dict) else {}
            res_name = metadata.get("name", "unnamed")
            kind_name = doc.get("kind", "Unknown")
            api_version = doc.get("apiVersion", "v1")
            rid = safe_token(f"{kind_name}_{res_name}")
            resources.append(
                {
                    "id": rid,
                    "chart": chart_id,
                    "api_version": safe_token(api_version),
                    "kind": safe_token(kind_name),
                    "name": safe_token(res_name),
                }
            )
    if not resources:
        resources.append(
            {
                "id": f"{chart_id}_deployment",
                "chart": chart_id,
                "api_version": "apps_v1",
                "kind": "deployment",
                "name": f"{chart_id}_app",
            }
        )
    return resources


def build_macro_library(module_name: str) -> str:
    return textwrap.dedent(
        f"""\
        MODULE {module_name}.

        // Macro layer for Kubernetes CRD + Helm compatibility modeling.

        MACRO KHC_DOC(doc, source, environment):
        EMIT khc:doc:{{{{doc}}}}#kind@entity:k8s_helm_doc.
        EMIT khc:doc:{{{{doc}}}}#source@value:{{{{source}}}}.
        EMIT khc:doc:{{{{doc}}}}#environment@value:{{{{environment}}}}.
        ENDMACRO.

        MACRO KHC_COMPAT_PROFILE(id, strict_mode, drift_window_s):
        EMIT khc:profile:{{{{id}}}}#kind@entity:k8s_helm_profile.
        EMIT khc:profile:{{{{id}}}}#strict_mode@value:{{{{strict_mode}}}}.
        EMIT khc:profile:{{{{id}}}}#drift_window_s@value:{{{{drift_window_s}}}}.
        ENDMACRO.

        MACRO KHC_CHART(id, name, version, app_version):
        EMIT khc:chart:{{{{id}}}}#kind@entity:helm_chart.
        EMIT khc:chart:{{{{id}}}}#chart_name@value:{{{{name}}}}.
        EMIT khc:chart:{{{{id}}}}#chart_version@value:{{{{version}}}}.
        EMIT khc:chart:{{{{id}}}}#app_version@value:{{{{app_version}}}}.
        ENDMACRO.

        MACRO KHC_CHART_VALUE(chart, path, value_type, default_value, required):
        EMIT khc:chart_value:{{{{chart}}}}_{{{{path}}}}#kind@entity:helm_chart_value.
        EMIT khc:chart_value:{{{{chart}}}}_{{{{path}}}}#chart@khc:chart:{{{{chart}}}}.
        EMIT khc:chart_value:{{{{chart}}}}_{{{{path}}}}#path@value:{{{{path}}}}.
        EMIT khc:chart_value:{{{{chart}}}}_{{{{path}}}}#value_type@value:{{{{value_type}}}}.
        EMIT khc:chart_value:{{{{chart}}}}_{{{{path}}}}#default@value:{{{{default_value}}}}.
        EMIT khc:chart_value:{{{{chart}}}}_{{{{path}}}}#required@value:{{{{required}}}}.
        ENDMACRO.

        MACRO KHC_CRD(id, group, version, kind_name, plural, scope):
        EMIT khc:crd:{{{{id}}}}#kind@entity:k8s_crd.
        EMIT khc:crd:{{{{id}}}}#group@value:{{{{group}}}}.
        EMIT khc:crd:{{{{id}}}}#version@value:{{{{version}}}}.
        EMIT khc:crd:{{{{id}}}}#kind_name@value:{{{{kind_name}}}}.
        EMIT khc:crd:{{{{id}}}}#plural@value:{{{{plural}}}}.
        EMIT khc:crd:{{{{id}}}}#scope@value:{{{{scope}}}}.
        ENDMACRO.

        MACRO KHC_TEMPLATE_RESOURCE(id, chart, api_version, kind_name, resource_name):
        EMIT khc:resource:{{{{id}}}}#kind@entity:k8s_template_resource.
        EMIT khc:resource:{{{{id}}}}#chart@khc:chart:{{{{chart}}}}.
        EMIT khc:resource:{{{{id}}}}#api_version@value:{{{{api_version}}}}.
        EMIT khc:resource:{{{{id}}}}#kind_name@value:{{{{kind_name}}}}.
        EMIT khc:resource:{{{{id}}}}#resource_name@value:{{{{resource_name}}}}.
        ENDMACRO.

        MACRO KHC_RELEASE(id, chart, namespace, profile):
        EMIT khc:release:{{{{id}}}}#kind@entity:k8s_release.
        EMIT khc:release:{{{{id}}}}#chart@khc:chart:{{{{chart}}}}.
        EMIT khc:release:{{{{id}}}}#namespace@value:{{{{namespace}}}}.
        EMIT khc:release:{{{{id}}}}#profile@khc:profile:{{{{profile}}}}.
        ENDMACRO.

        MACRO KHC_RELEASE_VALUE(release, path, value):
        EMIT khc:release_value:{{{{release}}}}_{{{{path}}}}#kind@entity:helm_release_value.
        EMIT khc:release_value:{{{{release}}}}_{{{{path}}}}#release@khc:release:{{{{release}}}}.
        EMIT khc:release_value:{{{{release}}}}_{{{{path}}}}#path@value:{{{{path}}}}.
        EMIT khc:release_value:{{{{release}}}}_{{{{path}}}}#value@value:{{{{value}}}}.
        EMIT khc:release:{{{{release}}}}#has_value_path@value:{{{{path}}}}.
        ENDMACRO.

        RULE khc_resource_matches_crd_kind:
        IF ?res#kind@entity:k8s_template_resource AND ?crd#kind@entity:k8s_crd AND ?res#kind_name@?kind AND ?crd#kind_name@?kind
        THEN ?res#compatible_crd@?crd.

        RULE khc_resource_has_compatible_crd:
        IF ?res#compatible_crd@?crd
        THEN ?res#has_compatible_crd@value:true.

        RULE khc_release_manages_resource:
        IF ?release#kind@entity:k8s_release AND ?res#kind@entity:k8s_template_resource AND ?release#chart@?chart AND ?res#chart@?chart
        THEN ?release#manages_resource@?res.

        RULE khc_release_requires_crd:
        IF ?release#kind@entity:k8s_release AND ?release#manages_resource@?res AND ?res#compatible_crd@?crd
        THEN ?release#requires_crd@?crd.

        RULE khc_release_missing_required_value:
        IF ?release#kind@entity:k8s_release AND ?release#chart@?chart AND ?cv#kind@entity:helm_chart_value AND ?cv#chart@?chart AND ?cv#required@value:true AND ?cv#path@?path AND NOT ?release#has_value_path@?path
        THEN ?release#missing_required_value@?path.

        RULE khc_release_has_missing_required:
        IF ?release#missing_required_value@?path
        THEN ?release#has_missing_required@value:true.

        RULE khc_release_config_ready:
        IF ?release#kind@entity:k8s_release AND NOT ?release#has_missing_required@value:true
        THEN ?release#config_ready@value:true.

        RULE khc_release_drift_candidate:
        IF ?release#kind@entity:k8s_release AND ?release#manages_resource@?res AND NOT ?res#has_compatible_crd@value:true
        THEN ?release#drift_candidate@?res.

        QUERY khc_releases:
        FIND ?release ?namespace WHERE ?release#kind@entity:k8s_release AND ?release#namespace@?namespace.

        QUERY khc_resources:
        FIND ?res ?kind WHERE ?res#kind@entity:k8s_template_resource AND ?res#kind_name@?kind.

        QUERY khc_crds:
        FIND ?crd ?kind WHERE ?crd#kind@entity:k8s_crd AND ?crd#kind_name@?kind.

        QUERY khc_missing_required_values:
        FIND ?release ?path WHERE ?release#missing_required_value@?path.

        QUERY khc_drift_candidates:
        FIND ?release ?res WHERE ?release#drift_candidate@?res.

        QUERY khc_release_requirements:
        FIND ?release ?crd WHERE ?release#requires_crd@?crd.
        """
    )


def build_example_model(
    module_name: str,
    chart: Dict[str, str],
    crds: Sequence[Dict[str, str]],
    resources: Sequence[Dict[str, str]],
    values: Sequence[Tuple[str, Any]],
    required_paths: Sequence[str],
    profile_id: str,
    release_id: str,
    namespace: str,
) -> str:
    lines: List[str] = []
    lines.append(f"MODULE {module_name}.")
    lines.append("")
    lines.append("// Run with:")
    lines.append("//   ./tools/generate_k8s_helm_compat.py")
    lines.append("//   ./bin/zil preprocess examples/k8s-helm-compat.zc /tmp/k8s_helm_compat.pre.zc libsets/k8s-helm-compat")
    lines.append("//   ./bin/zil /tmp/k8s_helm_compat.pre.zc")
    lines.append("")
    lines.append("USE KHC_DOC(k8s_helm_generated, generator, dev).")
    lines.append(f"USE KHC_COMPAT_PROFILE({profile_id}, true, 300).")
    lines.append(
        f"USE KHC_CHART({chart['id']}, {chart['name']}, {chart['version']}, {chart['app_version']})."
    )

    for path, raw in values:
        required = "true" if path in required_paths else "false"
        value_token = scalar_to_token(raw)
        value_type = "string"
        if isinstance(raw, bool):
            value_type = "bool"
        elif isinstance(raw, (int, float)):
            value_type = "number"
        lines.append(
            f"USE KHC_CHART_VALUE({chart['id']}, {path}, {value_type}, {value_token}, {required})."
        )

    for crd in crds:
        lines.append(
            "USE KHC_CRD({id}, {group}, {version}, {kind}, {plural}, {scope}).".format(**crd)
        )

    for res in resources:
        lines.append(
            "USE KHC_TEMPLATE_RESOURCE({id}, {chart}, {api_version}, {kind}, {name}).".format(**res)
        )

    lines.append(f"USE KHC_RELEASE({release_id}, {chart['id']}, {namespace}, {profile_id}).")

    for path, raw in values:
        lines.append(f"USE KHC_RELEASE_VALUE({release_id}, {path}, {scalar_to_token(raw)}).")

    lines.append("")
    lines.append("QUERY khc_releases:")
    lines.append("FIND ?release ?namespace WHERE ?release#kind@entity:k8s_release AND ?release#namespace@?namespace.")
    lines.append("")
    lines.append("QUERY khc_missing_required_values:")
    lines.append("FIND ?release ?path WHERE ?release#missing_required_value@?path.")
    lines.append("")
    lines.append("QUERY khc_drift_candidates:")
    lines.append("FIND ?release ?res WHERE ?release#drift_candidate@?res.")
    lines.append("")
    lines.append("QUERY khc_release_requirements:")
    lines.append("FIND ?release ?crd WHERE ?release#requires_crd@?crd.")
    lines.append("")

    return "\n".join(lines)


def pick_required_paths(value_paths: Sequence[str], explicit_required: Sequence[str]) -> List[str]:
    if explicit_required:
        chosen = [safe_token(p) for p in explicit_required]
        chosen_set = set(chosen)
        return [p for p in value_paths if p in chosen_set]
    # deterministic defaults for scaffold use.
    return list(value_paths[:2])


def parse_required_arg(raw: str) -> List[str]:
    if not raw.strip():
        return []
    return [part.strip() for part in raw.split(",") if part.strip()]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--chart", default="", help="Path to Helm Chart.yaml")
    parser.add_argument("--values", default="", help="Path to Helm values.yaml")
    parser.add_argument(
        "--crd",
        action="append",
        default=[],
        help="CRD YAML file or directory (repeatable)",
    )
    parser.add_argument(
        "--template",
        action="append",
        default=[],
        help="Rendered template YAML file or directory (repeatable)",
    )
    parser.add_argument("--release", default="", help="Release identifier token")
    parser.add_argument("--namespace", default="platform", help="Release namespace token")
    parser.add_argument(
        "--required-values",
        default="",
        help="Comma-separated value paths to force as required",
    )
    parser.add_argument(
        "--max-values",
        type=int,
        default=12,
        help="Maximum flattened value paths to include in generated example",
    )
    parser.add_argument(
        "--macro-module",
        default="k8s.helm.compat.lib",
        help="Module name for generated macro library",
    )
    parser.add_argument(
        "--example-module",
        default="k8s.helm.compat.generated",
        help="Module name for generated runnable example",
    )
    parser.add_argument(
        "--out-lib",
        default="lib/k8s-helm-compat-macros.zc",
        help="Macro library output path relative to zil/",
    )
    parser.add_argument(
        "--out-libset",
        default="libsets/k8s-helm-compat/k8s-helm-compat-macros.zc",
        help="Focused libset copy output path relative to zil/",
    )
    parser.add_argument(
        "--out-example",
        default="examples/k8s-helm-compat.zc",
        help="Example model output path relative to zil/",
    )

    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parents[1]

    chart_name = "sample_chart"
    chart_version = "0_1_0"
    app_version = "0_1_0"
    if args.chart:
        chart_data = load_yaml_or_json(Path(args.chart).expanduser())
        if isinstance(chart_data, dict):
            chart_name = safe_token(chart_data.get("name", chart_name))
            chart_version = safe_token(chart_data.get("version", chart_version))
            app_version = safe_token(chart_data.get("appVersion", app_version))

    chart_id = f"chart_{chart_name}"

    values_pairs: List[Tuple[str, Any]] = []
    if args.values:
        values_data = load_yaml_or_json(Path(args.values).expanduser())
        flat_values = flatten_scalars(values_data)
        for path, value in sorted(flat_values.items()):
            values_pairs.append((safe_token(path), value))
    if not values_pairs:
        values_pairs = [
            ("image_repository", "example_repo_sync"),
            ("image_tag", "stable"),
            ("service_port", 8080),
            ("feature_crd_sync_enabled", True),
        ]

    values_pairs = values_pairs[: max(args.max_values, 1)]

    explicit_required = parse_required_arg(args.required_values)
    required_paths = pick_required_paths([p for p, _ in values_pairs], explicit_required)

    crd_files = collect_yaml_files(args.crd)
    crds = parse_crds(crd_files)

    template_files = collect_yaml_files(args.template)
    resources = parse_template_resources(template_files, chart_id)

    release_id = safe_token(args.release) if args.release else f"release_{chart_name}"
    namespace = safe_token(args.namespace)
    profile_id = "profile_default"

    macro_text = build_macro_library(args.macro_module)
    example_text = build_example_model(
        module_name=args.example_module,
        chart={
            "id": chart_id,
            "name": chart_name,
            "version": chart_version,
            "app_version": app_version,
        },
        crds=crds,
        resources=resources,
        values=values_pairs,
        required_paths=required_paths,
        profile_id=profile_id,
        release_id=release_id,
        namespace=namespace,
    )

    out_lib = repo_root / args.out_lib
    out_libset = repo_root / args.out_libset
    out_example = repo_root / args.out_example

    out_lib.parent.mkdir(parents=True, exist_ok=True)
    out_lib.write_text(macro_text, encoding="utf-8")

    out_libset.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(out_lib, out_libset)

    out_example.parent.mkdir(parents=True, exist_ok=True)
    out_example.write_text(example_text, encoding="utf-8")

    print(f"[ok] generated {out_lib.relative_to(repo_root)}")
    print(f"[ok] generated {out_libset.relative_to(repo_root)}")
    print(f"[ok] generated {out_example.relative_to(repo_root)}")

    if args.chart:
        print(f"[info] chart source: {args.chart}")
    if args.values:
        print(f"[info] values source: {args.values}")
    if crd_files:
        print(f"[info] crd inputs: {len(crd_files)}")
    if template_files:
        print(f"[info] template inputs: {len(template_files)}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
