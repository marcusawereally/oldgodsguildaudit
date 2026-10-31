"""Validate addon packaging paths without executing addon code."""
from pathlib import Path
import re

root = Path(__file__).resolve().parent
tocs = list(root.glob("OldGods*/*.toc")) + list(root.glob("forever/OldGods*/*.toc"))
assert tocs, "No addon TOC found"
for toc in tocs:
    content = toc.read_text(encoding="utf-8-sig")
    assert re.search(r"^## Version: \d+\.\d+\.\d+\.\d+\s*$", content, re.M), f"Missing version: {toc}"
    for line in content.splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            assert re.fullmatch(r"[A-Za-z][A-Za-z0-9_-]*\.lua", line), f"Invalid TOC path: {line}"
            assert (toc.parent / line).is_file(), f"Missing addon file: {toc.parent / line}"
    manifest = toc.parent / "Assets/manifest.txt"
    if manifest.exists():
        for asset in manifest.read_text().splitlines():
            assert re.fullmatch(r"Icons/[a-z][a-z0-9-]*\.(svg|tga)", asset), f"Invalid asset: {asset}"
            assert (manifest.parent / asset).is_file(), f"Missing asset: {asset}"
print(f"PASS: {len(tocs)} addon TOCs and their declared files")
