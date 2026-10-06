#!/usr/bin/env python3
"""Package complete iOS sources, widgets and signing configuration for Xcode."""
import argparse
import hashlib
import os
from pathlib import Path
import re
import subprocess
import sys
import zipfile

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--output', type=Path)
args = parser.parse_args()
subprocess.run([sys.executable, str(root / 'scripts/generate-project.py')], check=True)
version = re.search(r"MARKETING_VERSION: '([^']+)'", (root / 'project.yml').read_text()).group(1)
release = args.output or root.parent / 'static/ios-releases' / version
release.mkdir(parents=True, exist_ok=True)
output = release / f'Wave-iOS-{version}.zip'
temp = output.with_suffix('.tmp.zip')
prefix = f'Wave-iOS-{version}/'
with zipfile.ZipFile(temp, 'w', zipfile.ZIP_DEFLATED) as archive:
    for directory in ['Wave', 'Shared', 'WaveWidgets', 'WaveTests', 'Wave.xcodeproj', 'scripts']:
        for file in sorted((root / directory).rglob('*')):
            if file.is_file() and '__pycache__' not in file.parts and not file.name.startswith('.'):
                archive.write(file, prefix + file.relative_to(root).as_posix())
    for filename in ['Info.plist', 'README.md', 'project.yml']:
        archive.write(root / filename, prefix + filename)
with zipfile.ZipFile(temp) as archive:
    assert archive.testzip() is None
    for required in ['Wave/AdaptiveLayout.swift', 'Wave/WaveDockView.swift', 'Wave/WidgetPlayback.swift',
                     'Shared/WaveWidgetState.swift', 'Shared/WavePlaybackIntent.swift', 'Shared/WaveWidgetBrowser.swift',
                     'Wave/WidgetLibraryIntegration.swift', 'Wave/WaveDockLibraryView.swift',
                     'WaveWidgets/WaveWidgetBrowserViews.swift',
                     'WaveWidgets/WaveWidgets.swift', 'WaveWidgets/Info.plist',
                     'Wave/Wave.entitlements', 'WaveWidgets/WaveWidgets.entitlements', 'Wave.xcodeproj/project.pbxproj']:
        assert prefix + required in archive.namelist(), required
os.replace(temp, output)
checksum = hashlib.sha256(output.read_bytes()).hexdigest()
release.joinpath('SHA256SUMS.txt').write_text(checksum + '  ' + output.name + '\n')
local = root / 'releases' / output.name
local.parent.mkdir(exist_ok=True)
if local.resolve() != output.resolve():
    staging = local.with_suffix('.tmp.zip')
    staging.unlink(missing_ok=True)
    os.link(output, staging)
    os.replace(staging, local)
print(f'Paquete preparado: {output} ({output.stat().st_size} bytes)')
print(f'SHA-256: {checksum}')
