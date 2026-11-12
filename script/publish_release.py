#!/usr/bin/env python3
"""Publish only validated versions; safe to retry an identical commit."""
import argparse
import json
import os
import pathlib
import subprocess
import tempfile
from release_policy import git, validate, catalog_revision, CATALOG_SOURCE

PACKAGE_SCRIPT = pathlib.Path(__file__).resolve().parent / 'package_release.sh'
INSTALLATION_GUIDE = PACKAGE_SCRIPT.parent.parent / 'docs' / 'INSTALLATION.txt'
GUIDE_LABEL = 'START HERE - Installation Guide.txt'


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


def guide_asset():
    """Expose the same static guide separately, before the app is downloaded."""
    if not INSTALLATION_GUIDE.is_file():
        raise FileNotFoundError(f'Installation guide missing: {INSTALLATION_GUIDE}')
    return f'{INSTALLATION_GUIDE}#{GUIDE_LABEL}'


def has_guide_asset(release):
    names = {INSTALLATION_GUIDE.name, GUIDE_LABEL, GUIDE_LABEL.replace(' ', '.')}
    return any(a.get('label') in names or a.get('name') in names for a in release.get('assets', []))


def emit_tag(tag):
    """Hand the published tag to the release safeguard job."""
    output = os.environ.get('GITHUB_OUTPUT')
    if output:
        with open(output, 'a', encoding='utf-8') as handle:
            handle.write(f'tag={tag}\n')


def release_kind(base, head, branch):
    """Validate the version transition and return its publication kind."""
    previous = git('show', f'{base}:VERSION')
    version = git('show', f'{head}:VERSION')
    receipt = json.loads(git('show', f'{head}:release-impact.json'))
    revision = catalog_revision(git('show', f'{head}:{CATALOG_SOURCE}'))
    return version, validate(previous, version, receipt, branch, revision)


def existing_tag_refs(tag, sha):
    """Return the tag's remote refs, failing if the tag names another commit."""
    # Resolve annotated or lightweight tags to their commit; never move a tag.
    refs = git('ls-remote', '--tags', 'origin', f'refs/tags/{tag}', f'refs/tags/{tag}^{{}}').splitlines()
    if refs and refs[-1].split()[0] != sha:
        raise ValueError(f'{tag} already belongs to another commit')
    return refs


def find_release(repo, tag):
    # Listing succeeds or fails explicitly; do not interpret permission/network errors as absence.
    releases = json.loads(gh('api', '--paginate', '--slurp', f'repos/{repo}/releases?per_page=100'))
    return next((r for page in releases for r in page if r['tag_name'] == tag), None)


def ensure_app_asset(release, tag, repo):
    """Retry path: add missing app/guide assets without replacing existing ones."""
    label = app_asset_label(tag)
    missing_app = not has_app_asset(release, label)
    missing_guide = not has_guide_asset(release)
    if not missing_app and not missing_guide:
        return
    with tempfile.TemporaryDirectory() as out_dir:
        assets = [guide_asset()] if missing_guide else []
        if missing_app:
            assets.insert(0, f'{package(release_title(tag), out_dir)}#{label}')
        # Without --clobber, an upload racing an existing asset fails instead of overwriting it.
        gh('release', 'upload', tag, *assets, '--repo', repo)


def create_release(tag, sha, kind, repo):
    guide = guide_asset()
    with tempfile.TemporaryDirectory() as out_dir:
        asset = package(release_title(tag), out_dir)
        args = ['release', 'create', tag, f'{asset}#{app_asset_label(tag)}', guide, '--repo', repo, '--target', sha,
                '--title', release_title(tag), '--generate-notes']
        if kind == 'prerelease':
            args.append('--prerelease')
        return gh(*args)


def publish(base, head, branch, repo):
    version, kind = release_kind(base, head, branch)
    if kind == 'none':
        print('Metadata-only patch: no tag or release writes.')
        return
    tag = 'v' + version
    sha = git('rev-parse', head)
    refs = existing_tag_refs(tag, sha)
    existing = find_release(repo, tag)
    if existing:
        if not refs or existing['draft'] or existing['prerelease'] != (kind == 'prerelease'):
            raise ValueError(f'{tag} conflicts with an existing draft or release status')
        ensure_app_asset(existing, tag, repo)
        emit_tag(tag)
        print(existing['html_url'])
        return
    url = create_release(tag, sha, kind, repo)
    emit_tag(tag)
    print(url)

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--base', required=True)
    parser.add_argument('--head', required=True)
    parser.add_argument('--branch', required=True)
    parser.add_argument('--repo', required=True)
    args = parser.parse_args()
    publish(args.base, args.head, args.branch, args.repo)
