"""Check generated target membership, signing and widget embedding on any OS."""
import contextlib
import io
import plistlib
import runpy
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

class ProjectTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with contextlib.redirect_stdout(io.StringIO()):
            cls.model = runpy.run_path(str(ROOT / 'scripts/generate-project.py'))
        cls.objects = cls.model['objects']

    def target(self, name):
        return self.objects[self.model['ident'](name + '-target')]

    def settings(self, name):
        config = self.objects[self.target(name)['buildConfigurationList']]
        return [self.objects[key]['buildSettings'] for key in config['buildConfigurations']]

    def sources(self, name):
        phase = next(self.objects[p] for p in self.target(name)['buildPhases'] if self.objects[p]['isa'] == 'PBXSourcesBuildPhase')
        return [self.objects[self.objects[b]['fileRef']]['path'] for b in phase['files']]

    def test_shared_models_and_intents_compile_into_both_targets(self):
        for name in ['Wave', 'WaveWidgets']:
            sources = self.sources(name)
            self.assertIn('WavePlaybackIntent.swift', sources)
            self.assertIn('WaveWidgetState.swift', sources)
            self.assertEqual(len(sources), len(set(sources)))

    def test_extension_does_not_compile_application_player(self):
        self.assertNotIn('WavePlayer.swift', self.sources('WaveWidgets'))
        self.assertNotIn('WaveApp.swift', self.sources('WaveWidgets'))
        self.assertIn('WaveWidgets.swift', self.sources('WaveWidgets'))
        self.assertNotIn('WaveWidgets.swift', self.sources('Wave'))

    def test_intents_use_app_process_implementation_only_in_application(self):
        for settings in self.settings('Wave'):
            self.assertIn('WAVE_APP', settings['SWIFT_ACTIVE_COMPILATION_CONDITIONS'])
        for settings in self.settings('WaveWidgets'):
            self.assertNotIn('WAVE_APP', settings.get('SWIFT_ACTIVE_COMPILATION_CONDITIONS', ''))
            self.assertEqual(settings['APPLICATION_EXTENSION_API_ONLY'], 'YES')

    def test_extension_is_embedded_and_built_with_app(self):
        app = self.target('Wave')
        copies = [self.objects[p] for p in app['buildPhases'] if self.objects[p]['isa'] == 'PBXCopyFilesBuildPhase']
        self.assertEqual(len(copies), 1)
        self.assertEqual(copies[0]['dstSubfolderSpec'], 13)
        embedded = self.objects[self.objects[copies[0]['files'][0]]['fileRef']]
        self.assertEqual(embedded['path'], 'WaveWidgets.appex')
        self.assertTrue(any(self.objects[d]['target'] == self.model['widgets'] for d in app['dependencies']))

    def test_same_app_group_for_application_and_extension(self):
        for name in ['Wave', 'WaveWidgets']:
            for settings in self.settings(name):
                with (ROOT / settings['CODE_SIGN_ENTITLEMENTS']).open('rb') as stream:
                    entitlements = plistlib.load(stream)
                self.assertEqual(entitlements['com.apple.security.application-groups'], ['group.app.wave.music'])

    def test_bundle_identifiers_preserve_upgrade_and_unique_extension(self):
        self.assertEqual(self.settings('Wave')[0]['PRODUCT_BUNDLE_IDENTIFIER'], 'app.wave.music.ios')
        self.assertEqual(self.settings('WaveWidgets')[0]['PRODUCT_BUNDLE_IDENTIFIER'], 'app.wave.music.ios.widgets')

    def test_matching_versions_in_all_targets_and_plists(self):
        for name in ['Wave', 'WaveWidgets', 'WaveTests']:
            for settings in self.settings(name):
                self.assertEqual(settings['MARKETING_VERSION'], self.model['version'])
                self.assertEqual(settings['CURRENT_PROJECT_VERSION'], self.model['build'])
        for filename in ['Info.plist', 'WaveWidgets/Info.plist']:
            with (ROOT / filename).open('rb') as stream:
                info = plistlib.load(stream)
            self.assertEqual(info['CFBundleShortVersionString'], self.model['version'])
            self.assertEqual(info['CFBundleVersion'], self.model['build'])

    def test_widget_extension_point_and_deep_links(self):
        with (ROOT / 'Info.plist').open('rb') as stream:
            info = plistlib.load(stream)
        self.assertEqual(info['CFBundleURLTypes'][0]['CFBundleURLSchemes'], ['wave'])
        self.assertIn('UIInterfaceOrientationLandscapeLeft', info['UISupportedInterfaceOrientations'])
        self.assertIn('UIInterfaceOrientationLandscapeRight', info['UISupportedInterfaceOrientations'])
        with (ROOT / 'WaveWidgets/Info.plist').open('rb') as stream:
            widget = plistlib.load(stream)
        self.assertEqual(widget['NSExtension']['NSExtensionPointIdentifier'], 'com.apple.widgetkit-extension')

    def test_generation_is_reproducible(self):
        file = ROOT / 'Wave.xcodeproj/project.pbxproj'
        before = file.read_bytes()
        with contextlib.redirect_stdout(io.StringIO()):
            runpy.run_path(str(ROOT / 'scripts/generate-project.py'))
        self.assertEqual(file.read_bytes(), before)

if __name__ == '__main__':
    unittest.main()
