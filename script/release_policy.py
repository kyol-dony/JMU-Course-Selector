#!/usr/bin/env python3
"""Project release policy. Versions are prepared once per integration PR."""
import argparse
import json
import pathlib
import re
import subprocess

DEV = "schedule-board-interaction"
SEMVER = re.compile(r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?(?:\+([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?")
COMMIT = re.compile(r"(?:feat|fix|perf|refactor|docs|test|build|ci|chore|revert)(?:\([A-Za-z0-9_./-]+\))?!?: .+")


def parse(value):
    m = SEMVER.fullmatch(value)
    if not m or any(p.isdigit() and len(p) > 1 and p[0] == '0' for p in (m[4] or '').split('.')):
        raise ValueError(f"Invalid SemVer: {value}")
    return tuple(map(int, m.group(1, 2, 3))) + (m[4], m[5])


def catalog_revision(source):
    matches = re.findall(r'^\s*(?:private\s+)?static let cacheSchemaVersion\s*=\s*([0-9]+)\s*$', source, re.MULTILINE)
    if len(matches) != 1:
        raise ValueError('Expected exactly one literal cacheSchemaVersion in CatalogRepository.swift')
    return int(matches[0])


CATALOG_SOURCE = 'Sources/JMUCoursePlanner/Services/CatalogRepository.swift'


def transition(previous, branch, impact, catalog=None):
    metadata = parse(previous)[4]
    if metadata and not re.fullmatch(r'catalog\.(0|[1-9][0-9]*)', metadata):
        raise ValueError('Canonical build metadata must be catalog.REVISION')
    result = core_transition(previous.split('+')[0], branch, impact)
    suffix = f'catalog.{catalog}' if catalog is not None else metadata
    return result + ('+' + suffix if suffix else '')


def core_transition(previous, branch, impact):
    major, minor, patch, stage, metadata = parse(previous)
    if impact not in ('patch', 'minor', 'major'):
        raise ValueError('Impact must be patch, minor, or major')
    if metadata:
        raise ValueError('Canonical VERSION cannot contain build metadata')
    if branch not in (DEV, 'main'):
        raise ValueError('Only integration branches allocate versions')
    if branch == 'main' and major == 0:
        return '1.0.0'
    if branch == DEV:
        if stage and stage not in ('alpha.1', 'beta.1', 'rc.1'):
            raise ValueError('Stage changes require explicit release preparation')
        # After stable promotion, dev branches must first sync stable main.
        if impact == 'major' and major > 0:
            major, minor, patch = major + 1, 0, 0
        elif impact in ('minor', 'major'):
            minor, patch = minor + 1, 0
        else:
            patch += 1
        return f'{major}.{minor}.{patch}-{stage or "alpha.1"}'
    if stage:
        # Promotion uses the already selected future stable target.
        return f'{major}.{minor}.{patch}'
    if impact == 'major':
        major, minor, patch = major + 1, 0, 0
    elif impact == 'minor':
        minor, patch = minor + 1, 0
    else:
        patch += 1
    return f'{major}.{minor}.{patch}'


def publish_kind(previous, current, branch):
    old, new = parse(previous), parse(current)
    if branch == 'main' and new[0] >= 1 and not new[3]:
        return 'stable'
    if branch == DEV and (new[0], new[1]) > (old[0], old[1]):
        return 'prerelease'
    return 'none'


def git(*args):
    return subprocess.check_output(['git', *args], text=True).strip()


def validate(previous, current, receipt, branch, catalog=None):
    if receipt.get('base') != previous:
        raise ValueError('Stale release receipt: sync destination and prepare again')
    if len(receipt.get('reason', '').strip()) < 12:
        raise ValueError('Record a meaningful impact rationale (at least 12 characters)')
    if receipt.get('target') != branch:
        raise ValueError('Release receipt target differs from integration branch')
    expected = transition(previous, branch, receipt.get('impact'), catalog)
    if current != expected:
        raise ValueError(f'Expected VERSION {expected}, got {current}')
    return publish_kind(previous, current, branch)


def check_message(message):
    first = message.splitlines()[0] if message.splitlines() else ''
    if not COMMIT.fullmatch(first):
        raise ValueError('Use Conventional Commits: type(scope)!: description')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    prep = sub.add_parser('prepare')
    prep.add_argument('--base-ref', required=True)
    prep.add_argument('--target', required=True, choices=[DEV, 'main'])
    prep.add_argument('--impact', required=True, choices=['patch', 'minor', 'major'])
    prep.add_argument('--reason', required=True)
    check = sub.add_parser('check')
    check.add_argument('--base-ref', required=True)
    check.add_argument('--head-ref', default='HEAD')
    check.add_argument('--target', required=True, choices=[DEV, 'main'])
    msg = sub.add_parser('check-message')
    msg.add_argument('file')
    args = parser.parse_args()
    if args.command == 'check-message':
        check_message(pathlib.Path(args.file).read_text())
        return
    previous = git('show', f'{args.base_ref}:VERSION')
    if args.command == 'prepare':
        receipt = dict(base=previous, target=args.target, impact=args.impact, reason=args.reason)
        catalog = catalog_revision(pathlib.Path(CATALOG_SOURCE).read_text())
        current = transition(previous, args.target, args.impact, catalog)
        validate(previous, current, receipt, args.target, catalog)
        pathlib.Path('VERSION').write_text(current + '\n')
        pathlib.Path('release-impact.json').write_text(json.dumps(receipt, indent=2) + '\n')
    else:
        current = git('show', f'{args.head_ref}:VERSION')
        receipt = json.loads(git('show', f'{args.head_ref}:release-impact.json'))
        catalog = catalog_revision(git('show', f'{args.head_ref}:{CATALOG_SOURCE}'))
        # Ignore historical commits already on destination and native merge subjects.
        bootstraps = git('log', '--diff-filter=A', '--format=%H', args.head_ref, '--', 'VERSION').splitlines()
        for sha in git('rev-list', '--no-merges', f'{args.base_ref}..{args.head_ref}').splitlines():
            if any(subprocess.run(['git', 'merge-base', '--is-ancestor', sha, baseline], capture_output=True).returncode == 0 for baseline in bootstraps):
                continue
            check_message(git('show', '-s', '--format=%B', sha))
    print(json.dumps(dict(version=current, kind=validate(previous, current, receipt, args.target, catalog))))


if __name__ == '__main__':
    try:
        main()
    except (ValueError, KeyError) as error:
        raise SystemExit(str(error))
