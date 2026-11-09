#!/usr/bin/env python3
"""Allowlisted source + isolated review bundle. Never scans credential files."""
from pathlib import Path
import hashlib, json, os, subprocess, tempfile
from zipfile import ZipFile, ZipInfo, ZIP_DEFLATED

ROOT = Path(__file__).resolve().parent.parent
TARGET = ROOT.parent / 'EvidenceWorkbenchReview_macOS.zip'
APP = Path('dist/EvidenceWorkbenchReview.app')

def allowed_source(name):
    p = Path(name)
    return (p.parts[0] in {'Sources','Tests','docs','script','.github','benchmarks'} or name in {'Package.swift','README.md','LICENSE','AGENTS.md','CLAUDE.md'}) and not any(part.startswith('.env') or part in {'.codex','ValidationSources','ValidationReport','LocalData','__pycache__'} for part in p.parts)

def plain_file(path):
    return path.is_file() and not any(p.is_symlink() for p in [path, *path.parents] if p != ROOT.parent)

def package():
    app = ROOT / APP
    binary = app / 'Contents/MacOS/EvidenceWorkbenchReview'
    if not plain_file(binary) or app.is_symlink():
        raise ValueError('Build an isolated review bundle first; symlink bundles are refused.')
    names = subprocess.check_output(['git','-C',str(ROOT),'ls-files','-z']).decode().split('\0')
    files = {ROOT/name for name in names if name and allowed_source(name) and plain_file(ROOT/name)}
    for path in app.rglob('*'):
        if path.is_symlink():
            raise ValueError('Symlinks are not permitted inside the review bundle.')
        if plain_file(path): files.add(path)
    fd, temporary = tempfile.mkstemp(prefix='review-package-',suffix='.zip',dir=TARGET.parent);os.close(fd)
    try:
        with ZipFile(temporary,'w',ZIP_DEFLATED) as archive:
            manifest = []
            for path in sorted(files):
                relative = path.relative_to(ROOT);data=path.read_bytes()
                info = ZipInfo.from_file(path, str(Path('EvidenceWorkbenchReview')/relative))
                archive.writestr(info,data,compress_type=ZIP_DEFLATED)
                manifest.append({'path':str(relative),'sha256':hashlib.sha256(data).hexdigest()})
            archive.writestr('EvidenceWorkbenchReview/PACKAGE-MANIFEST.json',json.dumps(manifest,indent=2))
            result=subprocess.run(['git','-C',str(ROOT),'rev-parse','--verify','HEAD'],capture_output=True,text=True)
            revision=result.stdout.strip() if result.returncode==0 else 'unversioned'
            archive.writestr('EvidenceWorkbenchReview/SOURCE-REVISION.txt',revision+'\n')
        with ZipFile(temporary) as archive:
            if archive.testzip() is not None: raise ValueError('Archive integrity failed')
        os.replace(temporary,TARGET)
    finally:
        if Path(temporary).exists():Path(temporary).unlink()
    print('Verified isolated review package:',TARGET.name)

if __name__ == '__main__':package()
