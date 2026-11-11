#!/usr/bin/env python3
"""Publish only validated versions; safe to retry an identical commit."""
import argparse
import json
import subprocess
from release_policy import git, validate, catalog_revision, CATALOG_SOURCE


def gh(*args):
    return subprocess.check_output(['gh', *args], text=True).strip()


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
    if existing:
        if not refs or existing['draft'] or existing['prerelease'] != (kind == 'prerelease'):
            raise ValueError(f'{tag} conflicts with an existing draft or release status')
        print(existing['html_url'])
        return
    args = ['release', 'create', tag, '--repo', repo, '--target', sha,
            '--title', f'JMU Course Planner {tag}', '--generate-notes']
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
