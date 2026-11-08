#!/usr/bin/env python3
"""Package the app and source without local credentials, user data or build caches."""
import json
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED

root = Path(__file__).resolve().parent.parent
target = root.parent / "EvidenceWorkbench_macOS.zip"
excluded = {".git", ".build", "LocalData", "__pycache__", "EvidenceWorkbenchQA.app"}
def permitted(path):
    relative = path.relative_to(root)
    return not any(part in excluded or part == ".env" or part.startswith(".env.") for part in relative.parts) and path.name != ".DS_Store" and not path.is_symlink()

with ZipFile(target, "w", compression=ZIP_DEFLATED, compresslevel=6) as archive:
    for path in sorted(root.rglob("*")):
        if permitted(path) and path.is_file():
            archive.write(path, Path("EvidenceWorkbench") / path.relative_to(root))

# Check the real configured value in memory only; never print it or include the file.
secret = None
keyfile = root / ".env.local"
if keyfile.exists():
    for line in keyfile.read_text().splitlines():
        if line.startswith("OPENAI_API_KEY="):
            value = line.split("=", 1)[1].strip()
            try: secret = json.loads(value).encode()
            except ValueError: secret = value.strip("\"'").encode()
with ZipFile(target) as archive:
    assert archive.testzip() is None
    assert "EvidenceWorkbench/dist/EvidenceWorkbench.app/Contents/MacOS/EvidenceWorkbench" in archive.namelist()
    if secret:
        for name in archive.namelist():
            if secret in archive.read(name):
                target.unlink()
                raise RuntimeError("Credential detected in package; archive removed.")
print("Verified app/source archive; credentials and local review data excluded.")
