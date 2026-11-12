#!/usr/bin/env python3
"""Prove that a shipped build is the public app, not a developer build.

Public builds perform the automatic first-launch catalog refresh and nothing
more: no on-demand refresh, no live course-description fetching, no reset that
forces a fresh catalog pull, and no data read from outside the signed bundle.

  source     audit Swift sources: developer tools stay behind JMU_DEV_TOOLS/DEBUG
  artifact   audit a release zip (or .app): layout, data, Info.plist, binary
  calibrate  confirm every canary survives in a developer build of the same code
  release    audit a downloaded GitHub release asset set

Exit status is 1 when any check fails; every failure is reported.
"""
import argparse
import os
import pathlib
import plistlib
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import zipfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCES = 'Sources'
APP_NAME = 'JMU Course Planner.app'
EXECUTABLE = 'JMUCoursePlanner'
GUIDE_SOURCE = 'docs/INSTALLATION.txt'
GUIDE_NAME = 'START HERE - Installation Guide.txt'
TITLE = re.compile(r'JMU Course Planner v(?P<version>[0-9A-Za-z.+-]+)')
DATA_FILES = ('catalog_seed.json', 'prereq_coreq_overrides.json', 'degree_requirement_courses.json')
PUBLIC_PROFILE = 'public'
# Exactly what script/build_and_run.sh writes. Extra keys (LSEnvironment,
# NSAppTransportSecurity, ...) could inject configuration into a shipped app.
INFO_KEYS = {
    'CFBundleExecutable', 'CFBundleIdentifier', 'CFBundleName', 'CFBundleShortVersionString',
    'CFBundleVersion', 'JMUPlannerSemanticVersion', 'JMUPlannerBuildProfile', 'CFBundlePackageType',
    'LSMinimumSystemVersion', 'NSPrincipalClass',
}
ARCHS = {0x01000007: 'x86_64', 0x0100000C: 'arm64'}
REQUIRED_ARCHS = {'arm64', 'x86_64'}

# Code that may exist only in developer builds: `#if JMU_DEV_TOOLS`,
# `#if DEBUG`, or `#if DEBUG || JMU_DEV_TOOLS` branches.
DEV_ONLY = {
    'Refresh Requirements control': r'"Refresh Requirements"',
    'on-demand refresh control': r'\b(?:Button|Menu|Toggle|Label|CommandMenu)\(\s*"[^"]*\b(?:Refresh|Reload|Re-?fetch|Fetch|Download|Re-?sync|Update Catalog)',
    'pull-to-refresh': r'\.refreshable\b',
    'catalog PDF download': r'\brefreshCatalogPDF\b|URLSession\.shared\.download\b',
    'live course-description fetch': r'\b(?:liveDescription|persistLiveDescription|forLiveFetched)\b|"Fetched live from ',
    'reset that clears the catalog cache': r'\bresetClearsCatalog\s*=\s*true\b',
    'app-data reset': r'"Reset App Data"|\bresetAppData\b',
    'working-directory data source': r'\bcurrentDirectoryPath\b',
    'launch-time override': r'\bProcessInfo\.processInfo\.(?:environment|arguments)\b|\bCommandLine\.arguments\b',
}

# Strings that appear in the compiled binary only when developer code is
# compiled in. `calibrate` proves each still survives optimization; the
# source audit proves each still exists, behind a developer-only gate.
# Swift stores strings of 15 UTF-8 bytes or fewer inline, so short literals
# such as "Reset App Data" never appear in a binary and cannot be canaries.
CANARIES = {
    'Refresh Requirements menu item': (b'Refresh Requirements', r'"Refresh Requirements"'),
    'live description fetch': (b'Fetched live from ', r'"Fetched live from '),
    'working-directory data fallback': (b'currentDirectoryPath', r'\bcurrentDirectoryPath\b'),
    'app-data reset entry point': (b'resetAppData', r'\bresetAppData\b'),
    'app-data reset confirmation': (b'Reset all app data?', r'"Reset all app data\?"'),
}

# Public code may reference these only from the listed (file, enclosing
# function); their own declarations are exempt.
RESTRICTED = {
    'catalog refresh trigger': (r'refreshCatalog', {('Stores/PlanStore.swift', 'load')}),
    'catalog HTML refresh': (r'refreshCatalogFromHTML', {('Stores/PlanStore.swift', 'refreshCatalog')}),
    'network request': (r'URL(?:Session|Request)', {('Services/CatalogRepository.swift', 'fetchHTML')}),
}
# The one public refresh is the automatic first-launch / stale-cache pull.
AUTOMATIC_REFRESH_GUARD = re.compile(r'^\s*if\b.*\b(?:needsInitialRefresh|hasCurrentCatalogCache)\b')

DEV_GATE = re.compile(r'(?:DEBUG|JMU_DEV_TOOLS)(?:\s*\|\|\s*(?:DEBUG|JMU_DEV_TOOLS))*')
NEGATED_DEV_GATE = re.compile(r'!\s*(?:DEBUG|JMU_DEV_TOOLS)')
DIRECTIVE = re.compile(r'^\s*#(if|elseif|else|endif)\b\s*(.*?)\s*$')
FUNC = re.compile(r'\bfunc\s+([A-Za-z_][A-Za-z0-9_]*)')


class Failures(list):
    def report(self, heading):
        if self:
            print(f'{heading}: {len(self)} problem(s)', file=sys.stderr)
            for failure in self:
                print(f'  - {failure}', file=sys.stderr)
        return not self


def strip_comments(text):
    """Blank out // and /* */ comments, keeping strings and line numbers."""
    out, i, n = [], 0, len(text)
    in_string = block = False
    while i < n:
        c, pair = text[i], text[i:i + 2]
        if block:
            if pair == '*/':
                block, i = False, i + 2
                continue
            out.append('\n' if c == '\n' else ' ')
        elif in_string:
            out.append(c)
            if c == '\\' and i + 1 < n:
                out.append(text[i + 1])
                i += 1
            elif c == '"' or c == '\n':
                in_string = False
        elif pair == '//':
            while i < n and text[i] != '\n':
                i += 1
            continue
        elif pair == '/*':
            block, i = True, i + 2
            continue
        else:
            in_string = c == '"'
            out.append(c)
        i += 1
    return ''.join(out)


def classify_lines(text):
    """Yield (line_number, line, developer_only) for code lines.

    A line is developer-only when an enclosing active conditional branch is
    compiled only into DEBUG or JMU_DEV_TOOLS builds.
    """
    stack = []  # one bool per open #if: is the current branch developer-only?
    negated = []
    for number, line in enumerate(strip_comments(text).splitlines(), 1):
        match = DIRECTIVE.match(line)
        if match:
            kind, condition = match.groups()
            if kind == 'if':
                stack.append(bool(DEV_GATE.fullmatch(condition)))
                negated.append(bool(NEGATED_DEV_GATE.fullmatch(condition)))
            elif not stack:
                raise ValueError(f'line {number}: #{kind} without #if')
            elif kind == 'elseif':
                stack[-1] = bool(DEV_GATE.fullmatch(condition))
                negated[-1] = False
            elif kind == 'else':
                stack[-1] = negated[-1]
            else:
                stack.pop()
                negated.pop()
            continue
        yield number, line, any(stack)
    if stack:
        raise ValueError('unterminated #if')


def audit_sources(root=ROOT):
    failures = Failures()
    sources = sorted((pathlib.Path(root) / SOURCES).rglob('*.swift'))
    if not sources:
        failures.append(f'no Swift sources under {pathlib.Path(root) / SOURCES}')
    canary_hits = dict.fromkeys(CANARIES, 0)
    for path in sources:
        relative = path.relative_to(pathlib.Path(root) / SOURCES).as_posix()
        target = relative.split('/', 1)[1] if '/' in relative else relative
        try:
            lines = list(classify_lines(path.read_text(encoding='utf-8')))
        except ValueError as error:
            failures.append(f'{relative}: {error}')
            continue
        function = None
        for index, (number, line, developer_only) in enumerate(lines):
            if FUNC.search(line):
                function = FUNC.search(line).group(1)
            where = f'{SOURCES}/{relative}:{number}'
            for label, (_, pattern) in CANARIES.items():
                if developer_only and re.search(pattern, line):
                    canary_hits[label] += 1
            if developer_only:
                continue
            for label, pattern in DEV_ONLY.items():
                if re.search(pattern, line):
                    failures.append(f'{where}: {label} is reachable in public builds; gate it with #if JMU_DEV_TOOLS')
            for label, (name, allowed) in RESTRICTED.items():
                if not re.search(rf'\b{name}\b', line) or re.search(rf'\bfunc\s+{name}\b', line):
                    continue
                if (target, function) not in allowed:
                    failures.append(f'{where}: {label} used outside {sorted(allowed)}; public builds may only refresh automatically')
                elif label == 'catalog refresh trigger':
                    previous = next((l for _, l, _ in reversed(lines[:index]) if l.strip()), '')
                    if not AUTOMATIC_REFRESH_GUARD.match(previous):
                        failures.append(f'{where}: public refresh must sit directly under the needsInitialRefresh/hasCurrentCatalogCache guard')
    for label, hits in canary_hits.items():
        if not hits:
            failures.append(f'canary "{label}" no longer appears in developer-only source; update CANARIES in {pathlib.Path(__file__).name}')
    return failures


def fat_archs(binary):
    data = binary.read_bytes()[:4096]
    if len(data) < 8:
        return set()
    magic, count = struct.unpack('>II', data[:8])
    if magic == 0xCAFEBABE:
        return {ARCHS.get(struct.unpack('>I', data[8 + 20 * i:12 + 20 * i])[0], 'unknown') for i in range(count)}
    if magic == 0xCAFEBABF:
        return {ARCHS.get(struct.unpack('>I', data[8 + 32 * i:12 + 32 * i])[0], 'unknown') for i in range(count)}
    thin = struct.unpack('<I', data[:4])[0]
    if thin in (0xFEEDFACE, 0xFEEDFACF):
        return {ARCHS.get(struct.unpack('<I', data[4:8])[0], 'unknown')}
    return set()


def audit_binary(binary, require_universal=True):
    failures = Failures()
    data = binary.read_bytes()
    for label, (canary, _) in CANARIES.items():
        if canary in data:
            failures.append(f'binary contains developer-only {label} ({canary.decode()!r})')
    archs = fat_archs(binary)
    if require_universal and archs != REQUIRED_ARCHS:
        failures.append(f'binary architectures {sorted(archs) or "unrecognized"} != {sorted(REQUIRED_ARCHS)}')
    return failures


def audit_app(app, version, root=ROOT, codesign=None):
    failures = Failures()
    app, root = pathlib.Path(app), pathlib.Path(root)
    contents = app / 'Contents'
    expected = {'Info.plist', f'MacOS/{EXECUTABLE}', '_CodeSignature/CodeResources'}
    expected |= {f'Resources/{name}' for name in DATA_FILES}
    found = set()
    for path in app.rglob('*'):
        if path.is_symlink():
            failures.append(f'unexpected symlink in bundle: {path.relative_to(app)}')
        elif path.is_file():
            found.add(path.relative_to(contents).as_posix() if contents in path.parents else f'../{path.relative_to(app)}')
    for extra in sorted(found - expected):
        failures.append(f'unexpected file in bundle: Contents/{extra}')
    for missing in sorted(expected - found):
        failures.append(f'missing bundle file: Contents/{missing}')
    for name in DATA_FILES:
        shipped, source = contents / 'Resources' / name, root / 'Data' / name
        if shipped.is_file() and source.is_file() and shipped.read_bytes() != source.read_bytes():
            failures.append(f'Resources/{name} differs from Data/{name} at the shipped commit')
    try:
        info = plistlib.loads((contents / 'Info.plist').read_bytes())
    except (OSError, plistlib.InvalidFileException) as error:
        failures.append(f'Info.plist unreadable: {error}')
        info = {}
    if info:
        for key in sorted(set(info) - INFO_KEYS):
            failures.append(f'unexpected Info.plist key: {key}')
        checks = {
            'CFBundleExecutable': EXECUTABLE,
            'JMUPlannerSemanticVersion': version,
            'JMUPlannerBuildProfile': PUBLIC_PROFILE,
        }
        for key, value in checks.items():
            if info.get(key) != value:
                failures.append(f'Info.plist {key} is {info.get(key)!r}, expected {value!r}')
    binary = contents / 'MacOS' / EXECUTABLE
    if binary.is_file():
        failures += audit_binary(binary)
    if codesign is None:
        codesign = shutil.which('codesign') is not None
    if codesign:
        result = subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], capture_output=True, text=True)
        if result.returncode:
            failures.append(f'codesign verification failed: {result.stderr.strip()}')
    return failures


def extract(archive, destination):
    """Extract a release zip without following hostile paths."""
    with zipfile.ZipFile(archive) as bundle:
        for member in bundle.infolist():
            parts = pathlib.PurePosixPath(member.filename).parts
            if member.filename.startswith('/') or '..' in parts:
                raise ValueError(f'unsafe path in archive: {member.filename}')
            if (member.external_attr >> 16) & 0o170000 == 0o120000:
                raise ValueError(f'symlink in archive: {member.filename}')
    if shutil.which('ditto'):
        subprocess.run(['ditto', '-x', '-k', str(archive), str(destination)], check=True)
    else:
        with zipfile.ZipFile(archive) as bundle:
            bundle.extractall(destination)
            for member in bundle.infolist():
                mode = (member.external_attr >> 16) & 0o777
                if mode:
                    os.chmod(pathlib.Path(destination) / member.filename, mode)


def audit_artifact(path, title, root=ROOT, codesign=None):
    failures = Failures()
    match = TITLE.fullmatch(title)
    if not match:
        return Failures([f'not a release title: {title!r}'])
    version, path, root = match['version'], pathlib.Path(path), pathlib.Path(root)
    if path.suffix == '.app':
        return audit_app(path, version, root, codesign)
    with tempfile.TemporaryDirectory() as scratch:
        try:
            extract(path, scratch)
        except (ValueError, zipfile.BadZipFile, subprocess.CalledProcessError) as error:
            return Failures([f'{path.name}: {error}'])
        top = sorted(p.name for p in pathlib.Path(scratch).iterdir())
        if top != [title]:
            return Failures([f'archive top level is {top}, expected [{title!r}]'])
        folder = pathlib.Path(scratch) / title
        entries = sorted(p.name for p in folder.iterdir())
        if entries != sorted([APP_NAME, GUIDE_NAME]):
            failures.append(f'release folder holds {entries}, expected {sorted([APP_NAME, GUIDE_NAME])}')
        guide = folder / GUIDE_NAME
        if guide.is_file() and guide.read_bytes() != (root / GUIDE_SOURCE).read_bytes():
            failures.append(f'{GUIDE_NAME} differs from {GUIDE_SOURCE}')
        app = folder / APP_NAME
        if app.is_dir() and not app.is_symlink():
            failures += audit_app(app, version, root, codesign)
        else:
            failures.append(f'{APP_NAME} is missing or not an app bundle directory')
    return failures


def calibrate(binary):
    """A developer build of the same code must contain every canary."""
    data = pathlib.Path(binary).read_bytes()
    return Failures(
        f'canary "{label}" ({canary.decode()!r}) is missing from the developer build; '
        f'the binary scan can no longer detect it, so update CANARIES'
        for label, (canary, _) in CANARIES.items() if canary not in data
    )


def audit_release(tag, assets, root=ROOT, codesign=None):
    """Audit the asset set downloaded from a GitHub release."""
    assets, root = pathlib.Path(assets), pathlib.Path(root)
    title = f'JMU Course Planner {tag}'
    files = sorted(p for p in assets.iterdir() if p.is_file())
    zips = [p for p in files if p.suffix == '.zip']
    failures = Failures()
    # GitHub stores spaces in asset file names as dots.
    expected_zip = {f'{title}.zip', f'{title}.zip'.replace(' ', '.')}
    if len(zips) != 1 or zips[0].name not in expected_zip:
        return Failures([f'expected exactly one app archive named {title}.zip, found {[p.name for p in zips]}'])
    for extra in files:
        if extra not in zips and extra.name != pathlib.Path(GUIDE_SOURCE).name:
            failures.append(f'unexpected release asset: {extra.name}')
    guide = assets / pathlib.Path(GUIDE_SOURCE).name
    if not guide.is_file():
        failures.append('release is missing the installation guide asset')
    elif guide.read_bytes() != (root / GUIDE_SOURCE).read_bytes():
        failures.append(f'installation guide asset differs from {GUIDE_SOURCE}')
    failures += audit_artifact(zips[0], title, root, codesign)
    return failures


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest='command', required=True)
    source = commands.add_parser('source')
    source.add_argument('--root', default=ROOT)
    artifact = commands.add_parser('artifact')
    artifact.add_argument('path')
    artifact.add_argument('--title', required=True)
    artifact.add_argument('--root', default=ROOT)
    calibration = commands.add_parser('calibrate')
    calibration.add_argument('binary')
    release = commands.add_parser('release')
    release.add_argument('--tag', required=True)
    release.add_argument('--assets', required=True)
    release.add_argument('--root', default=ROOT)
    args = parser.parse_args(argv)

    if args.command == 'source':
        ok = audit_sources(args.root).report('Source safeguard')
    elif args.command == 'artifact':
        ok = audit_artifact(args.path, args.title, args.root).report('Artifact safeguard')
    elif args.command == 'calibrate':
        ok = calibrate(args.binary).report('Safeguard calibration')
    else:
        ok = audit_release(args.tag, args.assets, args.root).report('Release safeguard')
    print(f'{args.command}: {"passed" if ok else "FAILED"}', file=sys.stderr)
    return 0 if ok else 1


if __name__ == '__main__':
    sys.exit(main())
