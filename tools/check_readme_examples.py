#!/usr/bin/env python3
"""Check that the commands in the README quick start print what the README shows.

    python3 -I tools/check_readme_examples.py [--show]

Only the section from "## Quick start" to the next "## " heading is read:
  * a ```bash block that is immediately followed by a ```text block is run from the repository root; it must exit with status 0 and its
    standard output must equal the text block;
  * every ```zc block must be contiguous text of a file under examples/, so a quoted model cannot go stale.
Other blocks (the build, commands with no output to compare) are not run here; `make examples` covers the model's commands.
--show prints what each command printed instead of comparing, for writing the README (put an empty ```text block after a command to have it run).
"""
import pathlib, re, subprocess, sys

root = pathlib.Path(__file__).resolve().parent.parent
show = "--show" in sys.argv
readme = (root / "README.md").read_text()

start = readme.find("## Quick start")
if start == -1:
    sys.exit("FAIL  README.md has no '## Quick start' section")
end = readme.find("\n## ", start + 1)
section = readme[start:end if end != -1 else len(readme)]
blocks = [(m.group(1), m.group(2).rstrip("\n")) for m in re.finditer(r"^```(\w*)\n(.*?)^```", section, re.M | re.S)]
models = [p.read_text() for p in (root / "examples").rglob("*.zc")]

failures = 0
def fail(message):
    global failures
    failures += 1
    print("FAIL  " + message, file=sys.stderr)

for position, (language, body) in enumerate(blocks):
    if language == "zc":
        if any(body in text for text in models):
            print(f"PASS  the zc block {position + 1} is text of a file under examples/")
        else:
            fail(f"the zc block {position + 1} is in no file under examples/:\n{body[:200]}")
    elif language == "bash":
        following = blocks[position + 1] if position + 1 < len(blocks) else None
        if not (following and following[0] == "text"):
            continue
        run = subprocess.run(["bash", "-c", "set -euo pipefail\n" + body], cwd=root, capture_output=True, text=True)
        label = body.splitlines()[0][:70]
        if run.returncode != 0:
            fail(f"command failed ({run.returncode}): {label}\n{run.stderr[-600:]}")
            continue
        got = run.stdout.rstrip("\n")
        if show:
            print(f"--- {label}\n{got}")
        elif got == following[1]:
            print(f"PASS  {label}")
        else:
            fail(f"output differs: {label}\n--- README\n{following[1]}\n--- actual\n{got}")

if failures:
    print(f"README quick start: {failures} check(s) failed", file=sys.stderr)
    sys.exit(1)
if not show:
    print("README quick start: all checks pass")
