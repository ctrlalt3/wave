#!/usr/bin/env python3
"""Generate the checked-in Xcode project with Python's standard library."""
from pathlib import Path
import hashlib
import json
import plistlib
import re
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
manifest = (ROOT / 'project.yml').read_text()
version = re.search(r"MARKETING_VERSION: '([^']+)'", manifest).group(1)
build = re.search(r"CURRENT_PROJECT_VERSION: '([^']+)'", manifest).group(1)
orientations = ['UIInterfaceOrientationPortrait', 'UIInterfaceOrientationPortraitUpsideDown', 'UIInterfaceOrientationLandscapeLeft', 'UIInterfaceOrientationLandscapeRight']
info = {
    'CFBundleDevelopmentRegion': 'es', 'CFBundleDisplayName': 'Wave',
    'CFBundleExecutable': '$(EXECUTABLE_NAME)', 'CFBundleIdentifier': '$(PRODUCT_BUNDLE_IDENTIFIER)',
    'CFBundleInfoDictionaryVersion': '6.0', 'CFBundleName': '$(PRODUCT_NAME)',
    'CFBundlePackageType': 'APPL', 'CFBundleShortVersionString': version, 'CFBundleVersion': build,
    'LSRequiresIPhoneOS': True, 'UILaunchScreen': {}, 'UIBackgroundModes': ['audio'],
    'UIApplicationSceneManifest': {'UIApplicationSupportsMultipleScenes': True},
    'UISupportedInterfaceOrientations': orientations, 'UISupportedInterfaceOrientations~ipad': orientations,
    'NSAppleMusicUsageDescription': 'Wave necesita acceso para mostrar y reproducir las canciones, álbumes y playlists de tu biblioteca de Música.'
}
(ROOT / 'Info.plist').write_bytes(plistlib.dumps(info, sort_keys=False))
objects = {}
def ident(name):
    return hashlib.sha256(('wave-ios:' + name).encode()).hexdigest()[:24].upper()
def add(identifier, isa, **fields):
    key = ident(identifier)
    objects[key] = {'isa': isa, **fields}
    return key

def configurations(name, settings):
    values = []
    for mode in ['Debug', 'Release']:
        config = dict(settings)
        config['SWIFT_OPTIMIZATION_LEVEL'] = '-Onone' if mode == 'Debug' else '-O'
        if mode == 'Debug':
            config['SWIFT_ACTIVE_COMPILATION_CONDITIONS'] = 'DEBUG'
            config['ENABLE_TESTABILITY'] = 'YES'
        values.append(add(f'{name}:{mode}', 'XCBuildConfiguration', buildSettings=config, name=mode))
    return add(f'{name}:configuration-list', 'XCConfigurationList', buildConfigurations=values, defaultConfigurationIsVisible=0, defaultConfigurationName='Release')

main = ident('main-group')
products = ident('products-group')
project = ident('project')
app = ident('Wave-target')
tests = ident('WaveTests-target')
app_product = add('app-product', 'PBXFileReference', explicitFileType='wrapper.application', includeInIndex=0, path='Wave.app', sourceTree='BUILT_PRODUCTS_DIR')
test_product = add('test-product', 'PBXFileReference', explicitFileType='wrapper.cfbundle', includeInIndex=0, path='WaveTests.xctest', sourceTree='BUILT_PRODUCTS_DIR')
source_groups = []
phases = {}
for name in ['Wave', 'WaveTests']:
    refs = []
    builds = []
    for file in sorted((ROOT / name).glob('*.swift')):
        ref = add(f'file:{name}/{file.name}', 'PBXFileReference', lastKnownFileType='sourcecode.swift', path=file.name, sourceTree='<group>')
        refs.append(ref)
        builds.append(add(f'build:{name}/{file.name}', 'PBXBuildFile', fileRef=ref))
    source_groups.append(add(f'group:{name}', 'PBXGroup', children=refs, path=name, sourceTree='<group>'))
    phases[name] = [add(f'{name}:sources', 'PBXSourcesBuildPhase', buildActionMask=2147483647, files=builds, runOnlyForDeploymentPostprocessing=0),
                    add(f'{name}:frameworks', 'PBXFrameworksBuildPhase', buildActionMask=2147483647, files=[], runOnlyForDeploymentPostprocessing=0),
                    add(f'{name}:resources', 'PBXResourcesBuildPhase', buildActionMask=2147483647, files=[], runOnlyForDeploymentPostprocessing=0)]
info_ref = add('info-ref', 'PBXFileReference', lastKnownFileType='text.plist.xml', path='Info.plist', sourceTree='<group>')
add('products-group', 'PBXGroup', children=[app_product, test_product], name='Products', sourceTree='<group>')
add('main-group', 'PBXGroup', children=source_groups + [info_ref, products], sourceTree='<group>')
base = {'SDKROOT': 'iphoneos', 'IPHONEOS_DEPLOYMENT_TARGET': '17.0', 'SWIFT_VERSION': '5.0',
        'TARGETED_DEVICE_FAMILY': '1,2', 'CLANG_ENABLE_MODULES': 'YES', 'CODE_SIGN_STYLE': 'Automatic',
        'MARKETING_VERSION': version, 'CURRENT_PROJECT_VERSION': build, 'PRODUCT_NAME': '$(TARGET_NAME)'}
app_settings = {**base, 'PRODUCT_BUNDLE_IDENTIFIER': 'app.wave.music.ios', 'INFOPLIST_FILE': 'Info.plist',
                'GENERATE_INFOPLIST_FILE': 'NO', 'LD_RUNPATH_SEARCH_PATHS': ['$(inherited)', '@executable_path/Frameworks']}
test_settings = {**base, 'PRODUCT_BUNDLE_IDENTIFIER': 'app.wave.music.ios.tests', 'GENERATE_INFOPLIST_FILE': 'YES',
                 'TEST_HOST': '$(BUILT_PRODUCTS_DIR)/Wave.app/Wave',
                 'BUNDLE_LOADER': '$(TEST_HOST)', 'LD_RUNPATH_SEARCH_PATHS': ['$(inherited)', '@executable_path/Frameworks', '@loader_path/Frameworks']}
proxy = add('test-proxy', 'PBXContainerItemProxy', containerPortal=project, proxyType=1, remoteGlobalIDString=app, remoteInfo='Wave')
dependency = add('test-dependency', 'PBXTargetDependency', target=app, targetProxy=proxy)
add('Wave-target', 'PBXNativeTarget', buildConfigurationList=configurations('Wave', app_settings), buildPhases=phases['Wave'], buildRules=[], dependencies=[], name='Wave', productName='Wave', productReference=app_product, productType='com.apple.product-type.application')
add('WaveTests-target', 'PBXNativeTarget', buildConfigurationList=configurations('WaveTests', test_settings), buildPhases=phases['WaveTests'], buildRules=[], dependencies=[dependency], name='WaveTests', productName='WaveTests', productReference=test_product, productType='com.apple.product-type.bundle.unit-test')
add('project', 'PBXProject', attributes={'BuildIndependentTargetsInParallel': 'YES', 'LastUpgradeCheck': '1600', 'TargetAttributes': {app: {'CreatedOnToolsVersion': '16.0'}, tests: {'CreatedOnToolsVersion': '16.0', 'TestTargetID': app}}}, buildConfigurationList=configurations('project', {'CLANG_ENABLE_MODULES': 'YES'}), compatibilityVersion='Xcode 14.0', developmentRegion='es', hasScannedForEncodings=0, knownRegions=['es', 'en', 'Base'], mainGroup=main, productRefGroup=products, projectDirPath='', projectRoot='', targets=[app, tests])

def serialize(value, depth=0):
    indent = '\t' * depth
    if isinstance(value, dict):
        return '{\n' + ''.join(f'{indent}\t{json.dumps(str(key))} = {serialize(item, depth + 1)};\n' for key, item in value.items()) + indent + '}'
    if isinstance(value, list):
        return '(\n' + ''.join(f'{indent}\t{serialize(item, depth + 1)},\n' for item in value) + indent + ')'
    if isinstance(value, int):
        return str(value)
    return json.dumps(value, ensure_ascii=True)

bundle = ROOT / 'Wave.xcodeproj'
bundle.mkdir(exist_ok=True)
(bundle / 'project.pbxproj').write_text('// !$*UTF8*$!\n' + serialize({'archiveVersion': 1, 'classes': {}, 'objectVersion': 56, 'objects': objects, 'rootObject': project}) + '\n')
shared = bundle / 'xcshareddata/xcschemes'
shared.mkdir(parents=True, exist_ok=True)
scheme = ET.Element('Scheme', LastUpgradeVersion='1600', version='1.3')
def reference(parent, target, product, name):
    ET.SubElement(parent, 'BuildableReference', BuildableIdentifier='primary', BlueprintIdentifier=target, BuildableName=product, BlueprintName=name, ReferencedContainer='container:Wave.xcodeproj')
action = ET.SubElement(scheme, 'BuildAction', parallelizeBuildables='YES', buildImplicitDependencies='YES')
entries = ET.SubElement(action, 'BuildActionEntries')
entry = ET.SubElement(entries, 'BuildActionEntry', buildForTesting='YES', buildForRunning='YES', buildForProfiling='YES', buildForArchiving='YES', buildForAnalyzing='YES')
reference(entry, app, 'Wave.app', 'Wave')
action = ET.SubElement(scheme, 'TestAction', buildConfiguration='Debug', selectedDebuggerIdentifier='Xcode.DebuggerFoundation.Debugger.LLDB', selectedLauncherIdentifier='Xcode.IDEFoundation.Launcher.LLDB', shouldUseLaunchSchemeArgsEnv='YES')
entry = ET.SubElement(ET.SubElement(action, 'Testables'), 'TestableReference', skipped='NO')
reference(entry, tests, 'WaveTests.xctest', 'WaveTests')
action = ET.SubElement(scheme, 'LaunchAction', buildConfiguration='Debug', selectedDebuggerIdentifier='Xcode.DebuggerFoundation.Debugger.LLDB', selectedLauncherIdentifier='Xcode.IDEFoundation.Launcher.LLDB', launchStyle='0', useCustomWorkingDirectory='NO', ignoresPersistentStateOnLaunch='NO', debugDocumentVersioning='YES', debugServiceExtension='internal', allowLocationSimulation='YES')
reference(ET.SubElement(action, 'BuildableProductRunnable', runnableDebuggingMode='0'), app, 'Wave.app', 'Wave')
action = ET.SubElement(scheme, 'ProfileAction', buildConfiguration='Release', shouldUseLaunchSchemeArgsEnv='YES', savedToolIdentifier='', useCustomWorkingDirectory='NO', debugDocumentVersioning='YES')
reference(ET.SubElement(action, 'BuildableProductRunnable', runnableDebuggingMode='0'), app, 'Wave.app', 'Wave')
ET.SubElement(scheme, 'AnalyzeAction', buildConfiguration='Debug')
ET.SubElement(scheme, 'ArchiveAction', buildConfiguration='Release', revealArchiveInOrganizer='YES')
ET.indent(scheme)
(shared / 'Wave.xcscheme').write_bytes(ET.tostring(scheme, encoding='utf-8', xml_declaration=True))
workspace = bundle / 'project.xcworkspace'
workspace.mkdir(exist_ok=True)
(workspace / 'contents.xcworkspacedata').write_text('<?xml version="1.0" encoding="UTF-8"?><Workspace version="1.0"><FileRef location="self:"></FileRef></Workspace>\n')
print(f'Proyecto preparado: {bundle} · {version} ({build})')
