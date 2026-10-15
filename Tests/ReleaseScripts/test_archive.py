import os
from pathlib import Path
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[2] / 'scripts/archive.sh'


class ArchiveTests(unittest.TestCase):
    def test_platforms_and_unsigned_archives(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            fake = root / 'xcodebuild'
            fake.write_text('#!/bin/sh\nprintf "%s\\n" "$@" > "$ARCHIVE_TEST_ARGS"\n')
            fake.chmod(0o755)
            output = root / 'arguments'
            env = dict(os.environ, PATH=f'{root}:{os.environ["PATH"]}',
                       ARCHIVE_TEST_ARGS=str(output))
            for platform, scheme, destination in (
                ('ios', 'ForumIndex-iOS', 'generic/platform=iOS'),
                ('macos', 'ForumIndex-macOS', 'generic/platform=macOS'),
            ):
                for unsigned in (False, True):
                    with self.subTest(platform=platform, unsigned=unsigned):
                        command = [str(SCRIPT), platform]
                        if unsigned:
                            command.append('--unsigned')
                        command.append('-allowProvisioningUpdates')
                        subprocess.run(command, env=env, check=True, capture_output=True)
                        args = output.read_text().splitlines()
                        self.assertEqual(args[args.index('-scheme') + 1], scheme)
                        self.assertEqual(args[args.index('-destination') + 1], destination)
                        self.assertEqual(args[args.index('-configuration') + 1], 'Release')
                        self.assertIn('CODE_SIGNING_ALLOWED=' + ('NO' if unsigned else 'YES'), args)
                        self.assertIn('-allowProvisioningUpdates', args)
                        self.assertEqual(args[-1], 'archive')
            output.unlink()
            result = subprocess.run([str(SCRIPT), 'invalid'], env=env, capture_output=True)
            self.assertEqual(result.returncode, 2)
            self.assertFalse(output.exists())
