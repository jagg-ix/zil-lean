#!/usr/bin/env python3
"""
export-sftp-users-to-zil.py — Export AWS Transfer Family SFTP users directly into ZIL facts.

Includes ZIL output mode, per-user detail queries (SSH key count, home directory type), sa-east-1 support.

Usage:
    python3 export-sftp-users-to-zil.py [--region REGION] [--server SERVER_ID [SERVER_ID ...]]
                                         [--profile AWS_PROFILE] [--output OUTPUT.zc]
                                         [--module MODULE_NAME]

Pass --server to choose servers; per-region defaults can be added to
DEFAULT_SERVERS (empty by default).

Output: ZIL model file using TF_USER macros from tf-macros.zc.
"""

import argparse
import boto3
import json
import logging
import re
import sys
from datetime import datetime

logger = logging.getLogger(__name__)
logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")


# ---------------------------------------------------------------------------
# Token normalization
# ---------------------------------------------------------------------------

def _token(raw: str) -> str:
    t = raw.strip().lower()
    t = re.sub(r"[^a-z0-9_]", "_", t)
    t = re.sub(r"_+", "_", t)
    return t.strip("_") or "unknown"


def _server_token(server_id: str) -> str:
    return _token(server_id)


# ---------------------------------------------------------------------------
# AWS Transfer Family queries
# ---------------------------------------------------------------------------

def list_users(transfer_client, server_id: str) -> list[dict]:
    users = []
    paginator = transfer_client.get_paginator("list_users")
    for page in paginator.paginate(ServerId=server_id):
        users.extend(page.get("Users", []))
    return users


def describe_user(transfer_client, server_id: str, username: str) -> dict:
    try:
        resp = transfer_client.describe_user(ServerId=server_id, UserName=username)
        return resp.get("User", {})
    except Exception as e:
        logger.warning(f"describe_user failed for {username} on {server_id}: {e}")
        return {}


# ---------------------------------------------------------------------------
# ZIL emitter
# ---------------------------------------------------------------------------

class ZilEmitter:
    def __init__(self, out):
        self._out = out

    def line(self, s=""):
        self._out.write(s + "\n")

    def comment(self, s):
        self.line(f"// {s}")

    def fact(self, subject, relation, obj):
        self.line(f"{subject}#{relation}@{obj}.")

    def macro(self, name, *args):
        self.line(f"USE {name}({', '.join(str(a) for a in args)}).")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

DEFAULT_SERVERS = {}


def export_server(transfer_client, server_id: str, env_hint: str,
                  region: str, emitter: ZilEmitter, detail: bool = True):
    srv_tok = _server_token(server_id)

    emitter.comment(f"--- {server_id} ({env_hint}, {region}) ---")
    users = list_users(transfer_client, server_id)
    logger.info(f"{server_id}: found {len(users)} users")

    for user_stub in users:
        username = user_stub["UserName"]
        home_dir = user_stub.get("HomeDirectory", "")
        role_arn = user_stub.get("Role", "")

        user_tok = _token(username)
        role_label = _token(role_arn.split("/")[-1]) if role_arn else "unknown"

        # Determine home directory type from stub
        home_type = "path"

        if detail:
            full = describe_user(transfer_client, server_id, username)
            home_type_raw = full.get("HomeDirectoryType", "PATH")
            home_type = "path" if home_type_raw == "PATH" else "logical"
            ssh_keys = full.get("SshPublicKeys", [])
            key_count = len(ssh_keys)
            home_dir = full.get("HomeDirectory", home_dir)
        else:
            key_count = user_stub.get("SshPublicKeyCount", 0)

        emitter.macro("TF_USER", user_tok, srv_tok, home_type, f'"{role_label}"')
        entity = f"tf:user:{srv_tok}:{user_tok}"
        if home_dir:
            emitter.fact(entity, "home_directory", f'value:"{home_dir}"')
        emitter.fact(entity, "ssh_key_count", f"value:{key_count}")
        if username != user_tok:
            emitter.fact(entity, "actual_username", f'value:"{username}"')
        emitter.line()


def main():
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--region", default="sa-east-1")
    p.add_argument("--server", nargs="+",
                   help="Server ID(s) to export. Defaults to DEFAULT_SERVERS entries for --region.")
    p.add_argument("--profile", default=None,
                   help="AWS profile name (default: ambient credential chain)")
    p.add_argument("--output", default="/tmp/sftp-users-export.zc",
                   help="Output ZIL file path")
    p.add_argument("--module", default="sftp.users.export",
                   help="ZIL module name")
    p.add_argument("--no-detail", action="store_true",
                   help="Skip describe_user calls (faster, less accurate)")
    opts = p.parse_args()

    # Resolve server list
    if opts.server:
        servers = [(sid, "unknown") for sid in opts.server]
    else:
        servers = DEFAULT_SERVERS.get(opts.region)
        if not servers:
            print(f"No default servers for region {opts.region}. Pass --server explicitly.", file=sys.stderr)
            sys.exit(1)

    # AWS session
    try:
        session = boto3.Session(profile_name=opts.profile)
        transfer_client = session.client("transfer", region_name=opts.region)
    except Exception as e:
        print(f"Failed to create AWS session: {e}", file=sys.stderr)
        sys.exit(1)

    with open(opts.output, "w") as f:
        e = ZilEmitter(f)
        e.line(f"MODULE {opts.module}.")
        e.line()
        e.comment(f"Generated by export-sftp-users-to-zil.py")
        e.comment(f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M')}")
        e.comment(f"Region: {opts.region}  Profile: {opts.profile}")
        e.line()

        for server_id, env_hint in servers:
            try:
                export_server(transfer_client, server_id, env_hint,
                              opts.region, e, detail=not opts.no_detail)
            except Exception as ex:
                logger.error(f"Failed to export {server_id}: {ex}")

    print(f"Wrote {opts.output}")
    print(f"Run with --no-detail to skip describe_user calls if you hit rate limits.")


if __name__ == "__main__":
    main()
