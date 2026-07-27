#!/usr/bin/env python3
"""
Extract structured schema from the AWS Transfer Family API Reference PDF.

Parses every Action and Data Type section using a state machine over the
consistent page structure:

  [SectionName]          ← flush-left heading, first content line
  [description prose]
  Request Syntax         ← marker (operations only)
  { JSON block }
  Request Parameters     ← marker (or "Contents" for data types)
  FieldName              ← flush-left, followed by description lines
  Type: ...
  Valid Values: X | Y
  Required: Yes|No

Outputs tf_api_schema.json with:
  {
    "operations": [{
      "name": str,
      "description": str,
      "request_fields": [{"name", "type", "valid_values", "required", "description"}],
      "response_fields": [...]
    }],
    "data_types": [{
      "name": str,
      "description": str,
      "fields": [{"name", "type", "valid_values", "required", "description"}]
    }]
  }

Default source: ~/Downloads/transferfamily-api.pdf
"""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from typing import Dict, List, Optional, Tuple

try:
    import fitz  # PyMuPDF
except ImportError:
    raise SystemExit("PyMuPDF not installed. Run: pip install pymupdf")


# ---------------------------------------------------------------------------
# Known resource names from the Transfer Family API (Actions + Data Types).
# Used to detect section starts reliably.
# ---------------------------------------------------------------------------

KNOWN_ACTIONS: set[str] = {
    "CreateAccess", "CreateAgreement", "CreateConnector", "CreateProfile",
    "CreateServer", "CreateUser", "CreateWebApp", "CreateWorkflow",
    "DeleteAccess", "DeleteAgreement", "DeleteCertificate", "DeleteConnector",
    "DeleteHostKey", "DeleteProfile", "DeleteServer", "DeleteSshPublicKey",
    "DeleteUser", "DeleteWebApp", "DeleteWebAppCustomization", "DeleteWorkflow",
    "DescribeAccess", "DescribeAgreement", "DescribeCertificate", "DescribeConnector",
    "DescribeExecution", "DescribeHostKey", "DescribeProfile", "DescribeSecurityPolicy",
    "DescribeServer", "DescribeUser", "DescribeWebApp", "DescribeWebAppCustomization",
    "DescribeWorkflow", "ImportCertificate", "ImportHostKey", "ImportSshPublicKey",
    "ListAccesses", "ListAgreements", "ListCertificates", "ListConnectors",
    "ListExecutions", "ListFileTransferResults", "ListHostKeys", "ListProfiles",
    "ListSecurityPolicies", "ListServers", "ListTagsForResource", "ListUsers",
    "ListWebApps", "ListWorkflows", "SendWorkflowStepState", "StartDirectoryListing",
    "StartFileTransfer", "StartRemoteDelete", "StartRemoteMove", "StartServer",
    "StopServer", "TagResource", "TestConnection", "TestIdentityProvider",
    "UntagResource", "UpdateAccess", "UpdateAgreement", "UpdateCertificate",
    "UpdateConnector", "UpdateHostKey", "UpdateProfile", "UpdateServer",
    "UpdateUser", "UpdateWebApp", "UpdateWebAppCustomization",
}

KNOWN_DATA_TYPES: set[str] = {
    "As2AsyncMdnConnectorConfig", "As2ConnectorConfig", "ConnectorEgressConfig",
    "ConnectorFileTransferResult", "ConnectorVpcLatticeEgressConfig",
    "CopyStepDetails", "CustomDirectoriesType", "CustomHttpHeader",
    "CustomStepDetails", "DecryptStepDetails", "DeleteStepDetails",
    "DescribedAccess", "DescribedAgreement", "DescribedCertificate",
    "DescribedConnector", "DescribedConnectorEgressConfig",
    "DescribedConnectorVpcLatticeEgressConfig", "DescribedExecution",
    "DescribedHostKey", "DescribedIdentityCenterConfig", "DescribedProfile",
    "DescribedSecurityPolicy", "DescribedServer", "DescribedUser",
    "DescribedWebApp", "DescribedWebAppCustomization", "DescribedWebAppEndpointDetails",
    "DescribedWebAppIdentityProviderDetails", "DescribedWebAppVpcConfig",
    "DescribedWorkflow", "EfsFileLocation", "EndpointDetails", "ExecutionError",
    "ExecutionResults", "ExecutionStepResult", "FileLocation",
    "HomeDirectoryMapEntry", "IdentityCenterConfig", "IdentityProviderDetails",
    "InputFileLocation", "ListedAccess", "ListedAgreement", "ListedCertificate",
    "ListedConnector", "ListedExecution", "ListedHostKey", "ListedProfile",
    "ListedServer", "ListedUser", "ListedWebApp", "ListedWorkflow",
    "LoggingConfiguration", "PosixProfile", "ProtocolDetails", "S3FileLocation",
    "S3InputFileLocation", "S3StorageOptions", "S3Tag", "ServiceMetadata",
    "SftpConnectorConfig", "SftpConnectorConnectionDetails", "SshPublicKey",
    "Tag", "TagStepDetails", "UpdateConnectorEgressConfig",
    "UpdateConnectorVpcLatticeEgressConfig", "UpdateWebAppEndpointDetails",
    "UpdateWebAppIdentityCenterConfig", "UpdateWebAppIdentityProviderDetails",
    "UpdateWebAppVpcConfig", "UserDetails", "WebAppEndpointDetails",
    "WebAppIdentityProviderDetails", "WebAppUnits", "WebAppVpcConfig",
    "WorkflowDetail", "WorkflowDetails", "WorkflowStep",
}

# Normalise ligatures that PDFs frequently produce (ﬁ → fi, ﬂ → fl, etc.)
_LIGATURE_MAP = str.maketrans({"ﬁ": "fi", "ﬂ": "fl", "ﬀ": "ff", "ﬃ": "ffi", "ﬄ": "ffl"})

# Section sub-markers inside a resource section
_SECTION_MARKERS = re.compile(
    r"^(Request Syntax|Request Parameters|Response Syntax|"
    r"Response Elements|Errors|Examples|See Also|Contents)$"
)

_HEADER_NOISE = re.compile(r"^(AWS Transfer Family|API Reference)$")

_TYPE_RE = re.compile(r"^Type:\s+(.+)$", re.IGNORECASE)
_VALID_RE = re.compile(r"^Valid Values?:\s+(.+)$", re.IGNORECASE)
_REQUIRED_RE = re.compile(r"^Required:\s+(Yes|No)$", re.IGNORECASE)
_ARRAY_TYPE_RE = re.compile(r"Array of\s+(.+?)\s+objects?", re.IGNORECASE)

# A field heading is a CamelCase word that stands alone on its line
_FIELD_HEADING_RE = re.compile(r"^[A-Z][A-Za-z0-9]+$")

# Words that look like field headings but are inline callout box labels in the PDF
_NON_FIELD_WORDS: set[str] = {
    "Note", "Important", "Tip", "Warning", "Example", "Examples",
    "Contents", "Topics", "Required", "Type", "Pattern",
}

# Lines that are "Type:" continuations on a new annotation line (precede the actual type)
_META_LINE_RE = re.compile(
    r"^(Array Members|Length Constraints|Pattern|HTTP Status Code|"
    r"Minimum|Maximum|Fixed length):", re.IGNORECASE
)


def _clean(line: str) -> str:
    return line.translate(_LIGATURE_MAP).strip()


def _normalise_name(raw: str) -> str:
    """Normalise PDF artefacts in resource/type names."""
    s = raw.translate(_LIGATURE_MAP).strip()
    # Drop trailing page numbers
    s = re.sub(r"\s+\d+\s*$", "", s).strip()
    return s


# ---------------------------------------------------------------------------
# Page extraction
# ---------------------------------------------------------------------------

def _page_lines(page) -> List[str]:
    """Return non-empty, cleaned lines for a PDF page."""
    raw = page.get_text()
    lines = []
    for ln in raw.splitlines():
        ln = _clean(ln)
        if ln and not _HEADER_NOISE.match(ln):
            lines.append(ln)
    return lines


# ---------------------------------------------------------------------------
# Section detection
# ---------------------------------------------------------------------------

def _classify_section_name(name: str) -> Optional[str]:
    """Return 'action', 'data_type', or None."""
    n = _normalise_name(name)
    if n in KNOWN_ACTIONS:
        return "action"
    if n in KNOWN_DATA_TYPES:
        return "data_type"
    return None


def _looks_like_prose(line: str) -> bool:
    """True when a line looks like a description sentence, not a Type:/field line."""
    if not line:
        return False
    if _TYPE_RE.match(line) or _VALID_RE.match(line) or _REQUIRED_RE.match(line):
        return False
    if _META_LINE_RE.match(line):
        return False
    if _SECTION_MARKERS.match(line):
        return False
    if re.match(r"^\d+$", line):          # bare page number
        return False
    # Prose lines are typically longer and contain lowercase words
    return len(line) > 30 or " " in line


def _first_content_line(lines: List[str], allowed_kinds: set) -> Optional[str]:
    """Return the first line that is a confirmed section heading.

    allowed_kinds restricts which kinds of sections may start on this page:
      {"action"}     — before the Data Types boundary (Actions portion of PDF)
      {"data_type"}  — after the Data Types boundary

    This prevents field names that share a name with a known resource (e.g.
    IdentityProviderDetails appearing as a field inside DescribedServer) from
    triggering a false section start, because on DescribedServer's continuation
    pages we are past the Actions boundary but IdentityProviderDetails's own
    section hasn't been reached yet in alphabetical order.
    """
    for i, ln in enumerate(lines[:4]):
        if _SECTION_MARKERS.match(ln):
            return None
        kind = _classify_section_name(ln)
        if kind and kind in allowed_kinds:
            # Confirm by checking next non-empty line is prose, not a Type: annotation
            for j in range(i + 1, min(i + 4, len(lines))):
                nxt = lines[j].strip()
                if not nxt:
                    continue
                if _looks_like_prose(nxt):
                    return ln   # confirmed section start
                else:
                    return None  # next line is a Type:/marker/field — this is a field
            return ln  # nothing after it — treat as section start conservatively
    return None


# ---------------------------------------------------------------------------
# Field block parser
# ---------------------------------------------------------------------------

FieldRecord = Dict  # name, type, valid_values, required, description


def _parse_field_block(lines: List[str], section_name: str = "") -> List[FieldRecord]:
    """
    Parse a sequence of lines that contain parameter/field descriptions.
    Returns a list of field dicts.

    section_name is used to filter out self-referential running-footer lines
    (e.g. "DescribedServer" appearing at the bottom of its own pages).
    """
    fields: List[FieldRecord] = []
    current: Optional[FieldRecord] = None
    desc_lines: List[str] = []

    def _flush():
        nonlocal current, desc_lines
        if current is None:
            return
        current["description"] = " ".join(desc_lines).strip()
        fields.append(current)
        current = None
        desc_lines = []

    for ln in lines:
        # Stop at next sub-section marker
        if _SECTION_MARKERS.match(ln):
            _flush()
            break

        # Skip bare page numbers
        if re.match(r"^\d+$", ln):
            continue

        if _FIELD_HEADING_RE.match(ln):
            # Skip callout box labels (Note, Important, etc.)
            if ln in _NON_FIELD_WORDS:
                continue
            # Skip self-referential section name appearing as running footer
            if ln == section_name:
                continue
            _flush()
            current = {
                "name": ln,
                "type": "",
                "valid_values": [],
                "required": "no",
                "description": "",
            }
            desc_lines = []
            continue

        if current is None:
            continue

        m = _TYPE_RE.match(ln)
        if m:
            current["type"] = m.group(1).strip()
            continue

        m = _VALID_RE.match(ln)
        if m:
            raw_vals = m.group(1)
            # Valid values may span multiple lines; merge with previous
            current["valid_values"] = [
                v.strip() for v in re.split(r"\s*\|\s*", raw_vals) if v.strip()
            ]
            continue

        m = _REQUIRED_RE.match(ln)
        if m:
            current["required"] = m.group(1).lower()
            continue

        # Skip metadata annotation lines (length constraints, patterns, etc.)
        if _META_LINE_RE.match(ln):
            continue

        desc_lines.append(ln)

    _flush()
    return fields


# ---------------------------------------------------------------------------
# JSON block extractor (for Request Syntax)
# ---------------------------------------------------------------------------

def _extract_json_block(lines: List[str]) -> str:
    """Return the raw JSON block as a single string (best-effort)."""
    in_block = False
    depth = 0
    collected: List[str] = []
    for ln in lines:
        if not in_block:
            if ln.startswith("{"):
                in_block = True
            else:
                continue
        if in_block:
            collected.append(ln)
            depth += ln.count("{") + ln.count("[")
            depth -= ln.count("}") + ln.count("]")
            if depth <= 0:
                break
    return "\n".join(collected)


# ---------------------------------------------------------------------------
# Section accumulator
# ---------------------------------------------------------------------------

class _Section:
    def __init__(self, name: str, kind: str):
        self.name = name
        self.kind = kind          # "action" or "data_type"
        self.lines: List[str] = []


def _page_footer_name(page_lines: List[str]) -> str:
    """Return the running-footer section name from the last few lines of a page.

    The PDF places a running footer at the bottom of each page:
      <SectionName or SubsectionMarker>
      <PageNumber>

    For the FIRST page of a section, the footer is the section name itself.
    For continuation pages, the footer is a sub-section marker (Contents,
    Request Parameters, Response Elements, …).

    Returns the footer name (the non-numeric line just before the bare number),
    or "" if not found.
    """
    # Walk backwards to find a lone page number, then return what precedes it
    for i in range(len(page_lines) - 1, max(len(page_lines) - 6, -1), -1):
        if re.match(r"^\d+$", page_lines[i]):
            # The line before this number is the running footer
            if i > 0:
                return page_lines[i - 1].strip()
    return ""


def _accumulate_sections(doc) -> List[_Section]:
    """Walk all pages and group lines into named sections.

    A new section is started only when a known section name appears in BOTH:
      1. The first content line of the page, AND
      2. The running footer (the line before the page number at the bottom).

    This precisely identifies first pages of sections while ignoring
    continuation pages where field names happen to be known resource names.
    """
    sections: List[_Section] = []
    current: Optional[_Section] = None
    # Determine allowed kinds by tracking which part of the PDF we're in.
    in_data_types = False

    for page in doc:
        page_lines = _page_lines(page)
        if not page_lines:
            continue

        # Detect entry into the "Data Types" portion of the document
        filtered_first = [ln for ln in page_lines[:3]]
        if filtered_first and filtered_first[0] == "Data Types":
            in_data_types = True

        allowed = {"data_type"} if in_data_types else {"action"}
        heading = _first_content_line(page_lines, allowed)

        if heading:
            # Confirm this is truly the section's first page by checking the footer
            footer = _page_footer_name(page_lines)
            footer_norm = _normalise_name(footer)
            if footer_norm == heading:
                kind = _classify_section_name(heading)
                if kind and kind in allowed:
                    current = _Section(heading, kind)
                    sections.append(current)
                    start = page_lines.index(heading) + 1
                    current.lines.extend(page_lines[start:])
                    continue

        if current is not None:
            current.lines.extend(page_lines)

    return sections


# ---------------------------------------------------------------------------
# Section parser
# ---------------------------------------------------------------------------

def _parse_action(section: _Section) -> Dict:
    lines = section.lines
    # Split by sub-markers into named zones
    zones: Dict[str, List[str]] = {}
    current_zone = "description"
    zones[current_zone] = []
    for ln in lines:
        if _SECTION_MARKERS.match(ln):
            current_zone = ln
            zones.setdefault(current_zone, [])
        else:
            zones[current_zone].append(ln)

    description = " ".join(zones.get("description", [])).strip()
    request_fields = _parse_field_block(zones.get("Request Parameters", []), section.name)
    response_fields = _parse_field_block(zones.get("Response Elements", []), section.name)

    return {
        "name": section.name,
        "description": description,
        "request_fields": request_fields,
        "response_fields": response_fields,
    }


def _parse_data_type(section: _Section) -> Dict:
    lines = section.lines
    zones: Dict[str, List[str]] = {}
    current_zone = "description"
    zones[current_zone] = []
    for ln in lines:
        if _SECTION_MARKERS.match(ln):
            current_zone = ln
            zones.setdefault(current_zone, [])
        else:
            zones[current_zone].append(ln)

    description = " ".join(zones.get("description", [])).strip()
    fields = _parse_field_block(zones.get("Contents", []), section.name)

    return {
        "name": section.name,
        "description": description,
        "fields": fields,
    }


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--pdf",
        default="transferfamily-api.pdf",
        help="Path to the Transfer Family API Reference PDF",
    )
    parser.add_argument(
        "--out",
        default="examples/generated/tf_api_schema.json",
        help="Output JSON path (relative to repo root)",
    )
    args = parser.parse_args()

    pdf_path = Path(args.pdf).expanduser().resolve()
    if not pdf_path.exists():
        raise SystemExit(f"PDF not found: {pdf_path}")

    repo_root = Path(__file__).resolve().parents[1]
    out_path = (repo_root / args.out).resolve()
    out_path.parent.mkdir(parents=True, exist_ok=True)

    print(f"[tf-extract] opening {pdf_path} ({pdf_path.stat().st_size // 1024} KB)")
    doc = fitz.open(str(pdf_path))
    print(f"[tf-extract] {len(doc)} pages — accumulating sections …")

    sections = _accumulate_sections(doc)
    print(f"[tf-extract] found {len(sections)} sections")

    actions = []
    data_types = []
    for sec in sections:
        if sec.kind == "action":
            actions.append(_parse_action(sec))
        else:
            data_types.append(_parse_data_type(sec))

    schema = {
        "source_pdf": str(pdf_path),
        "stats": {
            "actions": len(actions),
            "data_types": len(data_types),
            "total_request_fields": sum(len(a["request_fields"]) for a in actions),
            "total_response_fields": sum(len(a["response_fields"]) for a in actions),
            "total_data_type_fields": sum(len(d["fields"]) for d in data_types),
        },
        "operations": actions,
        "data_types": data_types,
    }

    out_path.write_text(json.dumps(schema, indent=2), encoding="utf-8")
    print(f"[tf-extract] actions={len(actions)}  data_types={len(data_types)}")
    print(f"[tf-extract] → {out_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
