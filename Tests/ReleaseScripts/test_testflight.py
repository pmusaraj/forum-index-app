import argparse
import importlib.util
import json
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[2] / 'scripts/testflight.py'
spec = importlib.util.spec_from_file_location('testflight', SCRIPT)
testflight = importlib.util.module_from_spec(spec)
spec.loader.exec_module(testflight)


class PrivateUploadTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='forum-index-credentials-test-')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.private = self.root / 'private credentials'
        self.patch = patch.object(testflight, 'PRIVATE_DIR', self.private)
        self.patch.start()
        self.addCleanup(self.patch.stop)
        self.source = self.root / 'source key.p8'
        subprocess.run(['openssl', 'genpkey', '-algorithm', 'EC', '-pkeyopt',
                        'ec_paramgen_curve:P-256', '-out', str(self.source)], check=True,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.args = argparse.Namespace(key_id='TESTKEY123', issuer_id='11111111-2222-3333-4444-555555555555',
                                       key_path=str(self.source))

    def configure(self):
        with patch('builtins.print'):
            testflight.configure(self.args)

    def test_configuration_is_private_and_source_is_unchanged(self):
        original = self.source.read_bytes()
        self.configure()
        config_path = self.private / 'credentials.json'
        config = json.loads(config_path.read_text())
        copied = Path(config['key_path'])
        self.assertEqual(self.private.stat().st_mode & 0o777, 0o700)
        for path in (config_path, copied):
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)
        self.assertEqual(copied.read_bytes(), original)
        self.assertEqual(self.source.read_bytes(), original)
        self.assertNotIn('PRIVATE KEY', config_path.read_text())
        self.assertEqual(testflight.credentials()[1], str(copied))

    def test_rejects_shared_credentials(self):
        self.configure()
        (self.private / 'credentials.json').chmod(0o644)
        with self.assertRaises(ValueError):
            testflight.credentials()

    def test_upload_uses_key_arguments_and_keeps_ids_out_of_export_options(self):
        self.configure()
        archive = self.root / 'archive with spaces.xcarchive'
        archive.mkdir()
        (archive / 'Info.plist').write_bytes(plistlib.dumps({
            'ApplicationProperties': {'CFBundleIdentifier': 'com.musaraj.forumindex'}}))
        for export_only, destination in ((False, 'upload'), (True, 'export')):
            def run(command, **kwargs):
                if command[0] == 'security':
                    return subprocess.CompletedProcess(command, 0, stdout='1) ABC "Apple Distribution: Example (M4XMDAF939)"')
                self.assertEqual(command[0], 'xcodebuild')
                self.assertEqual(command[command.index('-archivePath') + 1], str(archive.resolve()))
                self.assertEqual(command[command.index('-authenticationKeyID') + 1], self.args.key_id)
                options_path = Path(command[command.index('-exportOptionsPlist') + 1])
                options = plistlib.loads(options_path.read_bytes())
                self.assertEqual(options['destination'], destination)
                self.assertNotIn(self.args.key_id, options_path.read_text())
                return subprocess.CompletedProcess(command, 0)
            with patch.object(testflight.subprocess, 'run', side_effect=run), patch('builtins.print'):
                testflight.upload(argparse.Namespace(archive=str(archive), export_options=None, export_only=export_only))
        for log in (self.private / 'logs').iterdir():
            self.assertEqual(log.stat().st_mode & 0o777, 0o600)

    def test_macos_archive_can_be_exported(self):
        self.configure()
        archive = self.root / 'macOS.xcarchive'
        archive.mkdir()
        (archive / 'Info.plist').write_bytes(plistlib.dumps({
            'ApplicationProperties': {'CFBundleIdentifier': 'com.musaraj.forumindex'}}))
        identity = subprocess.CompletedProcess([], 0, stdout='1) ABC "Apple Distribution: Example (M4XMDAF939)"')
        exported = subprocess.CompletedProcess([], 0)
        options_path = self.root / 'manual-export.plist'
        options_path.write_bytes(plistlib.dumps({
            'teamID': 'M4XMDAF939', 'method': 'app-store-connect', 'signingStyle': 'manual',
            'provisioningProfiles': {'com.musaraj.forumindex': 'test-profile'}}))
        def run_command(command, **kwargs):
            if command[0] == 'security':
                return identity
            actual = plistlib.loads(Path(command[command.index('-exportOptionsPlist') + 1]).read_bytes())
            self.assertEqual(actual['signingStyle'], 'manual')
            self.assertEqual(actual['provisioningProfiles'], {'com.musaraj.forumindex': 'test-profile'})
            self.assertEqual(actual['destination'], 'export')
            return exported
        with patch.object(testflight.subprocess, 'run', side_effect=run_command) as run, patch('builtins.print'):
            testflight.upload(argparse.Namespace(archive=str(archive), export_options=str(options_path), export_only=True))
        self.assertEqual(run.call_count, 2)
        self.assertIn(str(archive.resolve()), run.call_args.args[0])

    def test_unrelated_archive_is_rejected_before_export(self):
        self.configure()
        archive = self.root / 'unrelated.xcarchive'
        archive.mkdir()
        (archive / 'Info.plist').write_bytes(plistlib.dumps({
            'ApplicationProperties': {'CFBundleIdentifier': 'com.example.unrelated'}}))
        with patch.object(testflight.subprocess, 'run') as run:
            with self.assertRaisesRegex(ValueError, 'Expected a signed Forum Index'):
                testflight.upload(argparse.Namespace(archive=str(archive), export_options=None, export_only=False))
            run.assert_not_called()

    def test_missing_distribution_identity_stops_before_export(self):
        self.configure()
        archive = self.root / 'archive.xcarchive'
        archive.mkdir()
        (archive / 'Info.plist').write_bytes(plistlib.dumps({
            'ApplicationProperties': {'CFBundleIdentifier': 'com.musaraj.forumindex'}}))
        result = subprocess.CompletedProcess([], 0, stdout='0 valid identities found')
        with patch.object(testflight.subprocess, 'run', return_value=result) as run:
            with self.assertRaisesRegex(ValueError, 'No valid local Apple Distribution'):
                testflight.upload(argparse.Namespace(archive=str(archive), export_options=None, export_only=False))
            self.assertEqual(run.call_count, 1)
            self.assertEqual(run.call_args.args[0][0], 'security')


    def test_old_mac_bundle_id_is_rejected_before_export(self):
        self.configure()
        archive = self.root / 'old-mac.xcarchive'
        archive.mkdir()
        (archive / 'Info.plist').write_bytes(plistlib.dumps({
            'ApplicationProperties': {'CFBundleIdentifier': 'com.musaraj.ForumIndex.macOS'}}))
        with patch.object(testflight.subprocess, 'run') as run:
            with self.assertRaisesRegex(ValueError, 'Expected a signed Forum Index'):
                testflight.upload(argparse.Namespace(archive=str(archive), export_only=False))
            run.assert_not_called()


    def test_custom_mac_options_preserve_signing_and_control_destination(self):
        self.configure()
        archive = self.root / 'mac.xcarchive'
        archive.mkdir()
        (archive / 'Info.plist').write_bytes(plistlib.dumps({
            'ApplicationProperties': {'CFBundleIdentifier': 'com.musaraj.forumindex'}}))
        options = {'teamID': 'M4XMDAF939', 'method': 'app-store-connect',
                   'destination': 'upload', 'signingStyle': 'manual',
                   'signingCertificate': 'app-certificate',
                   'installerSigningCertificate': 'installer-certificate',
                   'provisioningProfiles': {'com.musaraj.forumindex': 'mac-profile'}}
        source = self.root / 'Mac export options.plist'
        source.write_bytes(plistlib.dumps(options))

        def run(command, **kwargs):
            if command[0] == 'security':
                return subprocess.CompletedProcess(command, 0, stdout='1) ABC "Apple Distribution: Example (M4XMDAF939)"')
            actual = plistlib.loads(Path(command[command.index('-exportOptionsPlist') + 1]).read_bytes())
            self.assertEqual(actual, dict(options, destination='export'))
            return subprocess.CompletedProcess(command, 0)

        with patch.object(testflight.subprocess, 'run', side_effect=run), patch('builtins.print'):
            testflight.upload(argparse.Namespace(archive=str(archive), export_only=True,
                                                 export_options=str(source)))
        self.assertEqual(plistlib.loads(source.read_bytes()), options)



if __name__ == '__main__':
    unittest.main()
