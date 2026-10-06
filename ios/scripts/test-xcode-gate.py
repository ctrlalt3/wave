"""The release gate must reject missing, stale and unsuccessful Xcode checks."""
import json
from pathlib import Path
import tempfile
import unittest
from xcode_validation import require_verified_build, source_digest

class GateTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / 'Wave').mkdir()
        (self.root / 'Wave/Test.swift').write_text('let value = 1\n')
        (self.root / 'Info.plist').write_text('test-info')
        (self.root / 'project.yml').write_text('test-project')
        (self.root / 'validation').mkdir()
    def record(self, **updates):
        value = {'source_sha256': source_digest(self.root), 'build': 'passed', 'tests': 'passed', 'xcode_version': 'Xcode fixture for gate test'}
        value.update(updates)
        (self.root / 'validation/xcode-validation.json').write_text(json.dumps(value))
    def test_missing_validation_blocks_publication(self):
        with self.assertRaisesRegex(RuntimeError, 'falta una compilación'):
            require_verified_build(self.root)
    def test_modified_source_invalidates_previous_validation(self):
        self.record()
        (self.root / 'Wave/Test.swift').write_text('let value = 2\n')
        with self.assertRaisesRegex(RuntimeError, 'fuentes han cambiado'):
            require_verified_build(self.root)
    def test_failed_build_or_tests_cannot_authorize_release(self):
        for field in ['build', 'tests']:
            self.record(**{field: 'failed'})
            with self.assertRaisesRegex(RuntimeError, 'completar correctamente'):
                require_verified_build(self.root)
    def test_matching_successful_validation_is_accepted(self):
        self.record()
        self.assertEqual(require_verified_build(self.root)['source_sha256'], source_digest(self.root))

if __name__ == '__main__':
    unittest.main()
