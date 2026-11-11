import unittest
from unittest.mock import patch
from release_policy import parse, transition, validate, publish_kind, check_message, catalog_revision, DEV
from publish_release import publish


class PolicyTests(unittest.TestCase):
    def test_semver(self):
        for version in ('1.0.0', '0.2.0-alpha.1', '1.0.0+build.01'):
            parse(version)
        for version in ('v1.0.0', '01.0.0', '1.0.0-alpha.01', '1.0.0-', '1.0.0\n', '1.0.0+á'):
            with self.assertRaises(ValueError):
                parse(version)

    def test_patch_never_publishes_on_dev(self):
        for patch in (0, 1, 9, 99):
            old = f'0.2.{patch}-alpha.1'
            new = transition(old, DEV, 'patch')
            self.assertEqual(new, f'0.2.{patch + 1}-alpha.1')
            self.assertEqual(publish_kind(old, new, DEV), 'none')

    def test_minor_and_breaking_pre_stable(self):
        for impact in ('minor', 'major'):
            new = transition('0.2.9-alpha.1', DEV, impact)
            self.assertEqual(new, '0.3.0-alpha.1')
            self.assertEqual(publish_kind('0.2.9-alpha.1', new, DEV), 'prerelease')

    def test_initial_stable(self):
        for impact in ('patch', 'minor', 'major'):
            self.assertEqual(transition('0.1.0-alpha.1', 'main', impact), '1.0.0')

    def test_stable_bumps(self):
        for impact, version in [('patch', '1.2.4'), ('minor', '1.3.0'), ('major', '2.0.0')]:
            self.assertEqual(transition('1.2.3', 'main', impact), version)

    def test_future_promotion(self):
        self.assertEqual(transition('1.2.3', DEV, 'minor'), '1.3.0-alpha.1')
        self.assertEqual(transition('1.3.0-alpha.1', 'main', 'minor'), '1.3.0')

    def test_receipt(self):
        receipt = dict(base='0.1.0-alpha.1', impact='patch', target=DEV, reason='Restore documented parser behavior')
        self.assertEqual(validate(receipt['base'], '0.1.1-alpha.1', receipt, DEV), 'none')
        for field, value in [('base', '0.0.0'), ('reason', ''), ('target', 'main'), ('impact', 'unknown')]:
            with self.assertRaises(ValueError):
                validate('0.1.0-alpha.1', '0.1.1-alpha.1', dict(receipt, **{field: value}), DEV)

    def test_messages(self):
        for message in ('fix(parser): restore catalog rules', 'feat!: replace saved schema\n\nBREAKING CHANGE: migration required', 'chore: update docs'):
            check_message(message)
        with self.assertRaises(ValueError):
            check_message('Updated stuff')

    def test_catalog_identity(self):
        self.assertEqual(catalog_revision('    private static let cacheSchemaVersion = 28\n'), 28)
        self.assertEqual(transition('0.2.0-alpha.1+catalog.27', DEV, 'patch', 28), '0.2.1-alpha.1+catalog.28')
        self.assertEqual(transition('0.2.1-alpha.1+catalog.28', DEV, 'minor', 29), '0.3.0-alpha.1+catalog.29')
        self.assertEqual(transition('0.2.0-alpha.1+catalog.28', 'main', 'minor', 28), '1.0.0+catalog.28')
        self.assertEqual(transition('1.0.0+catalog.28', 'main', 'patch', 29), '1.0.1+catalog.29')
        self.assertEqual(publish_kind('0.2.0-alpha.1+catalog.27', '0.2.1-alpha.1+catalog.28', DEV), 'none')
        receipt = dict(base='0.2.0-alpha.1+catalog.27', target=DEV, impact='patch', reason='Restore catalog parsing rules')
        with self.assertRaises(ValueError):
            validate(receipt['base'], '0.2.1-alpha.1+catalog.27', receipt, DEV, 28)

    def test_missing_catalog_source(self):
        with self.assertRaises(ValueError):
            catalog_revision('no catalog constant')

    @patch('publish_release.package')
    @patch('publish_release.gh')
    @patch('publish_release.git')
    def test_patch_has_zero_github_calls(self, git, gh, package):
        git.side_effect = ['0.1.0-alpha.1+catalog.27', '0.1.1-alpha.1+catalog.28', '{"base":"0.1.0-alpha.1+catalog.27","impact":"patch","target":"schedule-board-interaction","reason":"Restore parser behavior"}', 'private static let cacheSchemaVersion = 28']
        publish('base', 'head', DEV, 'owner/repo')
        gh.assert_not_called()
        package.assert_not_called()

    @patch('publish_release.package', return_value='/out/JMU Course Planner v0.2.0-alpha.1+catalog.28.zip')
    @patch('publish_release.gh')
    @patch('publish_release.git')
    def test_minor_publishes_at_sha(self, git, gh, package):
        git.side_effect = ['0.1.0-alpha.1+catalog.27', '0.2.0-alpha.1+catalog.28', '{"base":"0.1.0-alpha.1+catalog.27","impact":"minor","target":"schedule-board-interaction","reason":"Support new catalog family"}', 'private static let cacheSchemaVersion = 28', 'abc123', '']
        gh.side_effect = ['[[]]', 'release-url']
        publish('base', 'head', DEV, 'owner/repo')
        command = gh.call_args.args
        self.assertEqual(command[:3], ('release', 'create', 'v0.2.0-alpha.1+catalog.28'))
        self.assertIn('--prerelease', command)
        self.assertEqual(command[command.index('--target') + 1], 'abc123')
        self.assertEqual(package.call_args.args[0], 'JMU Course Planner v0.2.0-alpha.1+catalog.28')
        self.assertEqual(command[3], '/out/JMU Course Planner v0.2.0-alpha.1+catalog.28.zip#JMU Course Planner v0.2.0-alpha.1+catalog.28.zip')
        self.assertEqual(command[command.index('--title') + 1], 'JMU Course Planner v0.2.0-alpha.1+catalog.28')

    @patch('publish_release.gh')
    @patch('publish_release.git')
    def test_existing_tag_must_match(self, git, gh):
        git.side_effect = ['0.1.0-alpha.1+catalog.27', '0.2.0-alpha.1+catalog.28', '{"base":"0.1.0-alpha.1+catalog.27","impact":"minor","target":"schedule-board-interaction","reason":"Support new catalog family"}', 'private static let cacheSchemaVersion = 28', 'abc123', 'different refs/tags/v0.2.0-alpha.1+catalog.28']
        with self.assertRaises(ValueError):
            publish('base', 'head', DEV, 'owner/repo')
        gh.assert_not_called()

    @patch('publish_release.package')
    @patch('publish_release.gh')
    @patch('publish_release.git')
    def test_retry_reuses_existing_release(self, git, gh, package):
        git.side_effect = ['0.1.0-alpha.1+catalog.27', '0.2.0-alpha.1+catalog.28', '{"base":"0.1.0-alpha.1+catalog.27","impact":"minor","target":"schedule-board-interaction","reason":"Support new catalog family"}', 'private static let cacheSchemaVersion = 28', 'abc123', 'abc123 refs/tags/v0.2.0-alpha.1+catalog.28']
        gh.return_value = '[[{"tag_name":"v0.2.0-alpha.1+catalog.28","draft":false,"prerelease":true,"html_url":"existing-url","assets":[{"name":"JMU.Course.Planner.v0.2.0-alpha.1+catalog.28.zip","label":""}]}]]'
        publish('base', 'head', DEV, 'owner/repo')
        self.assertEqual(gh.call_count, 1)
        package.assert_not_called()

    @patch('publish_release.package', return_value='/out/app.zip')
    @patch('publish_release.gh')
    @patch('publish_release.git')
    def test_retry_uploads_missing_app_zip_without_replacing(self, git, gh, package):
        git.side_effect = ['0.1.0-alpha.1+catalog.27', '0.2.0-alpha.1+catalog.28', '{"base":"0.1.0-alpha.1+catalog.27","impact":"minor","target":"schedule-board-interaction","reason":"Support new catalog family"}', 'private static let cacheSchemaVersion = 28', 'abc123', 'abc123 refs/tags/v0.2.0-alpha.1+catalog.28']
        gh.side_effect = ['[[{"tag_name":"v0.2.0-alpha.1+catalog.28","draft":false,"prerelease":true,"html_url":"existing-url","assets":[]}]]', '']
        publish('base', 'head', DEV, 'owner/repo')
        upload = gh.call_args.args
        self.assertEqual(upload[:3], ('release', 'upload', 'v0.2.0-alpha.1+catalog.28'))
        self.assertEqual(upload[3], '/out/app.zip#JMU Course Planner v0.2.0-alpha.1+catalog.28.zip')
        self.assertNotIn('--clobber', upload)

if __name__ == '__main__':
    unittest.main()
