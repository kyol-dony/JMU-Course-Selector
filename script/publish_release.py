#!/usr/bin/env python3
"""Publish only validated versions; safe to retry an identical commit."""
import argparse
import json
import pathlib
import subprocess
import tempfile
from release_policy import git, validate, catalog_revision, CATALOG_SOURCE

PACKAGE_SCRIPT = pathlib.Path(__file__).resolve().parent / 'package_release.sh'


def gh(*args):
    return subprocess.check_output(['gh', *args], text=True).strip()


def release_title(tag):
    return f'JMU Course Planner {tag}'


def app_asset_label(tag):
    # Every published release carries the public app zip, named after the release.
    return release_title(tag) + '.zip'


def has_app_asset(release, label):
    # GitHub stores spaces in asset file names as dots; the label keeps them.
    names = {label, label.replace(' ', '.')}
    return any(a.get('label') in names or a.get('name') in names for a in release.get('assets', []))


def package(title, out_dir):
    """Build the public app zip and return its path."""
    output = subprocess.check_output([str(PACKAGE_SCRIPT), title, out_dir], text=True)
    return output.strip().splitlines()[-1]


def publish(base, head, branch, repo):
    previous = git('show', f'{base}:VERSION')
    version = git('show', f'{head}:VERSION')
    receipt = json.loads(git('show', f'{head}:release-impact.json'))
    revision = catalog_revision(git('show', f'{head}:{CATALOG_SOURCE}'))
    kind = validate(previous, version, receipt, branch, revision)
    if kind == 'none':
        print('Metadata-only patch: no tag or release writes.')
        return
    tag = 'v' + version
    sha = git('rev-parse', head)
    # Resolve annotated or lightweight tags to their commit; never move a tag.
    refs = git('ls-remote', '--tags', 'origin', f'refs/tags/{tag}', f'refs/tags/{tag}^{{}}').splitlines()
    if refs:
        resolved = refs[-1].split()[0]
        if resolved != sha:
            raise ValueError(f'{tag} already belongs to another commit')
    # Listing succeeds or fails explicitly; do not interpret permission/network errors as absence.
    releases = json.loads(gh('api', '--paginate', '--slurp', f'repos/{repo}/releases?per_page=100'))
    existing = next((r for page in releases for r in page if r['tag_name'] == tag), None)
    label = app_asset_label(tag)
    if existing:
        if not refs or existing['draft'] or existing['prerelease'] != (kind == 'prerelease'):
            raise ValueError(f'{tag} conflicts with an existing draft or release status')
        if not has_app_asset(existing, label):
            # A retry after a failed upload: add the missing zip, never replace one.
            with tempfile.TemporaryDirectory() as out_dir:
                gh('release', 'upload', tag, f'{package(release_title(tag), out_dir)}#{label}', '--repo', repo)
        print(existing['html_url'])
        return
    with tempfile.TemporaryDirectory() as out_dir:
        asset = package(release_title(tag), out_dir)
        args = ['release', 'create', tag, f'{asset}#{label}', '--repo', repo, '--target', sha,
                '--title', release_title(tag), '--generate-notes']
        if kind == 'prerelease':
            args.append('--prerelease')
        print(gh(*args))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--base', required=True)
    parser.add_argument('--head', required=True)
    parser.add_argument('--branch', required=True)
    parser.add_argument('--repo', required=True)
    args = parser.parse_args()
    publish(args.base, args.head, args.branch, args.repo)
