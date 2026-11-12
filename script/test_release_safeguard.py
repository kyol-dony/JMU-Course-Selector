import pathlib
import plistlib
import struct
import tempfile
import unittest
import zipfile

import release_safeguard as safeguard

TAG = 'v0.4.0-alpha.1+catalog.28'
TITLE = f'JMU Course Planner {TAG}'
VERSION = TAG[1:]


def write(path, content):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(content if isinstance(content, bytes) else content.encode())
    return path


def fat_binary(*payload):
    """A minimal universal Mach-O header (arm64 + x86_64) followed by payload."""
    header = struct.pack('>II', 0xCAFEBABE, 2)
    for cputype in (0x0100000C, 0x01000007):
        header += struct.pack('>IIIII', cputype, 0, 0, 0, 0)
    return header + b''.join(payload)


PUBLIC_SOURCES = {
    'JMUCoursePlanner/Views/TopBar.swift': '''
        Menu {
            #if JMU_DEV_TOOLS
            Button("Refresh Requirements") { store.refreshCatalog() }
            Button("Reset App Data") { store.resetAppData() }
            #endif
            Button("Start Over") { store.startFresh() }
        }
        #if JMU_DEV_TOOLS
        .confirmationDialog("Reset all app data?", isPresented: $confirmsReset) {}
        #endif
    ''',
    'JMUCoursePlanner/Stores/PlanStore.swift': '''
        func load() async {
            // A comment mentioning refreshCatalog() and "Refresh Requirements" is ignored.
            if let catalog, needsInitialRefresh(catalog: catalog) || !catalogRepository.hasCurrentCatalogCache() {
                refreshCatalog()
            }
        }
        func refreshCatalog() {
            Task { _ = try await catalogRepository.refreshCatalogFromHTML() }
        }
        #if JMU_DEV_TOOLS
        func describe() -> String { "Fetched live from \\(url)" }
        #endif
    ''',
    'JMUCoursePlanner/Services/CatalogRepository.swift': '''
        func refreshCatalogFromHTML() async throws {}
        #if DEBUG || JMU_DEV_TOOLS
        let fallback = FileManager.default.currentDirectoryPath
        #else
        let fallback: String? = nil
        #endif
        nonisolated private static func fetchHTML(from url: URL) async throws -> String {
            let request = URLRequest(url: url)
            _ = try await URLSession.shared.data(for: request)
        }
    ''',
}


class SourceAuditTests(unittest.TestCase):
    def audit(self, overrides=None):
        with tempfile.TemporaryDirectory() as root:
            for name, text in {**PUBLIC_SOURCES, **(overrides or {})}.items():
                write(pathlib.Path(root) / 'Sources' / name, text)
            return safeguard.audit_sources(root)

    def test_repository_sources_pass(self):
        self.assertEqual(safeguard.audit_sources(), [])

    def test_gated_fixture_passes(self):
        self.assertEqual(self.audit(), [])

    def test_ungated_refresh_menu_item_fails(self):
        failures = self.audit({'JMUCoursePlanner/Views/TopBar.swift': 'Button("Refresh Requirements") { store.refreshCatalog() }'})
        self.assertTrue(any('Refresh Requirements control' in f for f in failures))
        self.assertTrue(any('catalog refresh trigger' in f for f in failures))

    def test_else_branch_of_dev_gate_is_public(self):
        failures = self.audit({'JMUCoursePlanner/Views/Extra.swift': '#if JMU_DEV_TOOLS\n#else\nlet r = Button("Reload Catalog") {}\n#endif'})
        self.assertTrue(any('on-demand refresh control' in f for f in failures))

    def test_negated_gate_else_branch_is_developer_only(self):
        self.assertEqual(self.audit({'JMUCoursePlanner/Views/Extra.swift': '#if !JMU_DEV_TOOLS\n#else\n.refreshable {}\n#endif'}), [])

    def test_unrelated_gate_is_public(self):
        failures = self.audit({'JMUCoursePlanner/Views/Extra.swift': '#if os(macOS)\nlet a = CommandLine.arguments\n#endif'})
        self.assertTrue(any('launch-time override' in f for f in failures))

    def test_new_network_call_fails(self):
        failures = self.audit({'JMUCoursePlanner/Services/Fetch.swift': 'func grab() { URLSession.shared.data(from: url) }'})
        self.assertTrue(any('network request' in f for f in failures))

    def test_unguarded_automatic_refresh_fails(self):
        failures = self.audit({'JMUCoursePlanner/Stores/PlanStore.swift': PUBLIC_SOURCES['JMUCoursePlanner/Stores/PlanStore.swift'].replace(
            'if let catalog, needsInitialRefresh(catalog: catalog) || !catalogRepository.hasCurrentCatalogCache() {', 'do {')})
        self.assertTrue(any('guard' in f for f in failures))

    def test_reset_clearing_catalog_must_be_gated(self):
        failures = self.audit({'JMUCoursePlanner/Services/Reset.swift': 'static let resetClearsCatalog = true'})
        self.assertTrue(any('clears the catalog cache' in f for f in failures))

    def test_app_data_reset_must_be_gated(self):
        failures = self.audit({'JMUCoursePlanner/Views/Reset.swift': 'Button("Reset App Data") { store.resetAppData() }'})
        self.assertEqual(sum('app-data reset' in f for f in failures), 1)

    def test_removed_canary_is_reported(self):
        failures = self.audit({'JMUCoursePlanner/Views/TopBar.swift': 'let x = 1'})
        self.assertTrue(any('canary "Refresh Requirements menu item"' in f for f in failures))

    def test_unbalanced_conditionals_fail(self):
        failures = self.audit({'JMUCoursePlanner/Views/Extra.swift': '#if JMU_DEV_TOOLS\nlet x = 1'})
        self.assertTrue(any('unterminated' in f for f in failures))

    def test_strings_survive_comment_stripping(self):
        self.assertEqual(safeguard.strip_comments('let u = "https://x" // note\n/* a\nb */ let y = 2'),
                         'let u = "https://x" \n  \n   let y = 2')


class ArtifactAuditTests(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.scratch.name) / 'repo'
        for name in safeguard.DATA_FILES:
            write(self.root / 'Data' / name, '{"name": "%s"}' % name)
        write(self.root / safeguard.GUIDE_SOURCE, 'Install me.\n')

    def tearDown(self):
        self.scratch.cleanup()

    def app(self, binary=None, info=None, extra=None):
        app = pathlib.Path(self.scratch.name) / 'stage' / TITLE / safeguard.APP_NAME
        contents = app / 'Contents'
        write(contents / 'MacOS' / safeguard.EXECUTABLE, binary or fat_binary(b'public build'))
        write(contents / '_CodeSignature' / 'CodeResources', 'sig')
        for name in safeguard.DATA_FILES:
            write(contents / 'Resources' / name, (self.root / 'Data' / name).read_bytes())
        plist = {key: 'x' for key in safeguard.INFO_KEYS}
        plist.update(CFBundleExecutable=safeguard.EXECUTABLE, JMUPlannerSemanticVersion=VERSION,
                     JMUPlannerBuildProfile='public')
        plist.update(info or {})
        write(contents / 'Info.plist', plistlib.dumps(plist))
        for name, content in (extra or {}).items():
            write(contents / name, content)
        return app

    def zip(self, app, guide=b'Install me.\n'):
        folder = app.parent
        write(folder / safeguard.GUIDE_NAME, guide)
        archive = pathlib.Path(self.scratch.name) / f'{TITLE}.zip'
        with zipfile.ZipFile(archive, 'w') as bundle:
            for path in sorted(folder.parent.rglob('*')):
                bundle.write(path, path.relative_to(folder.parent).as_posix())
        return archive

    def audit(self, path):
        return safeguard.audit_artifact(path, TITLE, self.root, codesign=False)

    def test_public_zip_passes(self):
        self.assertEqual(self.audit(self.zip(self.app())), [])

    def test_developer_binary_fails(self):
        failures = self.audit(self.app(binary=fat_binary(b'..Refresh Requirements..Fetched live from ..')))
        self.assertEqual(sum('developer-only' in f for f in failures), 2)

    def test_single_architecture_fails(self):
        thin = struct.pack('<II', 0xFEEDFACF, 0x0100000C) + b'public'
        self.assertTrue(any('architectures' in f for f in self.audit(self.app(binary=thin))))

    def test_profile_and_version_must_match(self):
        failures = self.audit(self.app(info={'JMUPlannerBuildProfile': 'developer', 'JMUPlannerSemanticVersion': '0.3.0'}))
        self.assertEqual(sum('Info.plist' in f for f in failures), 2)

    def test_injected_plist_key_fails(self):
        failures = self.audit(self.app(info={'LSEnvironment': {'X': '1'}}))
        self.assertTrue(any('LSEnvironment' in f for f in failures))

    def test_tampered_or_extra_data_fails(self):
        app = self.app(extra={'Resources/catalog_snapshot.json': '{}'})
        write(app / 'Contents' / 'Resources' / 'catalog_seed.json', '{"tampered": true}')
        failures = self.audit(app)
        self.assertTrue(any('catalog_snapshot.json' in f for f in failures))
        self.assertTrue(any('catalog_seed.json differs' in f for f in failures))

    def test_guide_must_match_source(self):
        self.assertTrue(any('differs from docs' in f for f in self.audit(self.zip(self.app(), guide=b'Other'))))

    def test_wrong_archive_layout_fails(self):
        archive = pathlib.Path(self.scratch.name) / 'bad.zip'
        with zipfile.ZipFile(archive, 'w') as bundle:
            bundle.writestr('Other/readme.txt', 'x')
        self.assertTrue(any('top level' in f for f in self.audit(archive)))

    def test_hostile_archive_paths_fail(self):
        archive = pathlib.Path(self.scratch.name) / 'evil.zip'
        with zipfile.ZipFile(archive, 'w') as bundle:
            bundle.writestr('../escape.txt', 'x')
        self.assertTrue(any('unsafe path' in f for f in self.audit(archive)))

    def test_release_asset_set(self):
        assets = pathlib.Path(self.scratch.name) / 'assets'
        zipped = self.zip(self.app())
        write(assets / f'{TITLE}.zip'.replace(' ', '.'), zipped.read_bytes())
        write(assets / 'INSTALLATION.txt', 'Install me.\n')
        self.assertEqual(safeguard.audit_release(TAG, assets, self.root, codesign=False), [])
        write(assets / 'JMU.Course.Planner.dev.zip', zipped.read_bytes())
        self.assertTrue(any('exactly one app archive' in f for f in safeguard.audit_release(TAG, assets, self.root, codesign=False)))

    def test_calibration_requires_every_canary(self):
        binary = write(pathlib.Path(self.scratch.name) / 'dev', b''.join(c for c, _ in safeguard.CANARIES.values()))
        self.assertEqual(safeguard.calibrate(binary), [])
        write(binary, b'Refresh Requirements')
        self.assertEqual(len(safeguard.calibrate(binary)), len(safeguard.CANARIES) - 1)


if __name__ == '__main__':
    unittest.main()
