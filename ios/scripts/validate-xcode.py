#!/usr/bin/env python3
"""Build app + widgets and execute XCTest before allowing a verified release."""
import datetime
import json
from pathlib import Path
import platform
import re
import shutil
import subprocess
import sys
import tempfile
from xcode_validation import ROOT, RECEIPT, source_digest

if platform.system() != 'Darwin' or shutil.which('xcodebuild') is None:
    sys.exit('Necesitas un Mac con Xcode completo. Un análisis de sintaxis en Linux no valida la compilación de iOS.')
RECEIPT.parent.mkdir(parents=True, exist_ok=True)
RECEIPT.unlink(missing_ok=True)
subprocess.run([sys.executable, str(ROOT / 'scripts/generate-project.py')], check=True)
subprocess.run([sys.executable, str(ROOT / 'scripts/test-project.py')], check=True)
subprocess.run([sys.executable, str(ROOT / 'scripts/test-xcode-gate.py')], check=True)
original_digest = source_digest()
xcode = subprocess.check_output(['xcodebuild', '-version'], text=True).strip()
devices = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'devices', 'available', '--json'], text=True))['devices']
def runtime_version(name):
    match = re.search(r'iOS-(\d+)(?:-(\d+))?', name)
    return tuple(int(value or 0) for value in match.groups()) if match else (0, 0)
chosen = None
for runtime in sorted(devices, key=runtime_version, reverse=True):
    if runtime_version(runtime) < (17, 0):
        continue
    chosen = next((device for device in devices[runtime] if device.get('isAvailable') and device['name'].startswith('iPhone')), None)
    if chosen:
        break
if chosen is None:
    sys.exit('Instala un simulador iPhone con iOS 17 o posterior desde Xcode → Settings → Platforms.')
log = RECEIPT.parent / 'xcode-build.log'
with tempfile.TemporaryDirectory(prefix='wave-xcode-validation-') as derived:
    common = ['xcodebuild', '-project', str(ROOT / 'Wave.xcodeproj'), '-scheme', 'Wave',
              '-configuration', 'Debug', '-destination', 'id=' + chosen['udid'], '-derivedDataPath', derived,
              'CODE_SIGNING_ALLOWED=NO', 'CODE_SIGNING_REQUIRED=NO']
    with log.open('w') as output:
        for action in ['build-for-testing', 'test-without-building']:
            output.write('\nACTION: ' + action + '\n'); output.flush()
            process = subprocess.Popen(common + [action], cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
            for line in process.stdout:
                output.write(line)
                if 'error:' in line or '** ' in line or 'Test Suite' in line or 'failed' in line.lower():
                    print(line, end='', flush=True)
            result = process.wait()
            if result:
                sys.exit(f'Validación fallida ({action}). No se permite publicar. Consulta {log}')
if original_digest != source_digest():
    sys.exit('Las fuentes cambiaron durante la validación. No se permite publicar hasta repetirla.')
value = {'source_sha256': original_digest, 'build': 'passed', 'tests': 'passed',
         'xcode_version': xcode, 'simulator': chosen['name'],
         'completed_at': datetime.datetime.now(datetime.timezone.utc).isoformat()}
RECEIPT.write_text(json.dumps(value, indent=2) + '\n')
print('Compilación de Wave + WaveWidgets y XCTest completados. Ahora puedes ejecutar package-release.py.')
