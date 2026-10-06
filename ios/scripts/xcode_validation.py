"""Bind Xcode validation to the exact source and project files being packaged."""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RECEIPT = ROOT / 'validation' / 'xcode-validation.json'

def source_digest(root=ROOT):
    files = []
    for directory in ['Wave', 'Shared', 'WaveWidgets', 'WaveTests', 'Wave.xcodeproj', 'scripts']:
        files.extend(p for p in (root / directory).rglob('*') if p.is_file() and '__pycache__' not in p.parts)
    files.extend(root / name for name in ['Info.plist', 'project.yml'])
    digest = hashlib.sha256()
    for file in sorted(files, key=lambda p: p.relative_to(root).as_posix()):
        digest.update(file.relative_to(root).as_posix().encode())
        digest.update(b'\0')
        digest.update(file.read_bytes())
        digest.update(b'\0')
    return digest.hexdigest()

def require_verified_build(root=ROOT):
    receipt = root / 'validation' / 'xcode-validation.json'
    if not receipt.is_file():
        raise RuntimeError('Publicación bloqueada: falta una compilación real con Xcode. Ejecuta python3 scripts/validate-xcode.py en un Mac.')
    value = json.loads(receipt.read_text())
    if value.get('source_sha256') != source_digest(root):
        raise RuntimeError('Publicación bloqueada: las fuentes han cambiado desde la compilación. Ejecuta de nuevo validate-xcode.py.')
    if value.get('build') != 'passed' or value.get('tests') != 'passed' or not value.get('xcode_version'):
        raise RuntimeError('Publicación bloqueada: la compilación y los XCTest deben completar correctamente.')
    return value
