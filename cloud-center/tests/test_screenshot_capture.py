"""Exercise screenshot clipboard bytes and editing without touching the desktop."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]


class ScreenshotCaptureTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.env = dict(os.environ, PATH=f'{self.root}:{os.environ["PATH"]}', TEST_ROOT=str(self.root))
        source = (ROOT / 'bin/cloudyy-screenshot-capture').read_text()
        source = source.replace('/tmp/cloudyy-screenshot.path', str(self.root / 'latest'))
        source = source.replace('/tmp/screenshot-popup-', str(self.root / 'screenshot-popup-'))
        source = source.replace('-o /tmp ', f'-o {self.root} ')
        self.script = self.root / 'capture'
        self.script.write_text(source)
        self.stub('hyprcap', '''if [[ ${CANCEL:-0} == 1 ]]; then exit 1; fi
while (($#)); do
case "$1" in -o) dir=$2; shift;; -f) name=$2; shift;; esac
shift
done
printf '\\211PNG\\r\\n\\032\\noriginal' > "$dir/$name"
''')
        self.stub('wl-copy', 'printf "%s\\n" "$@" > "$TEST_ROOT/mime"\ncat > "$TEST_ROOT/clipboard"')
        self.stub('qs', 'exit 0')
        self.stub('notify-send', 'exit 0')
        self.stub('python3', 'printf "%s/saved\\n" "$TEST_ROOT"')
        self.stub('cloudyy-recording-args', 'printf -- "-w -o %s/saved -f %s" "$TEST_ROOT" "$4"')
        self.stub('satty', '''[[ $5 == --copy-command && $6 == 'wl-copy --type image/png' ]] || exit 2
[[ $7 == --action-on-enter && $8 == save-to-clipboard ]] || exit 2
[[ $9 == --save-after-copy && ${10} == --early-exit ]] || exit 2
printf "edited PNG" > "$4"
wl-copy --type image/png <"$4"''')

    def stub(self, name, body):
        path = self.root / name
        path.write_text('#!/usr/bin/env bash\n' + body + '\n')
        path.chmod(0o755)

    def run_capture(self, flag, **env):
        return subprocess.run(['bash', str(self.script), flag], env=dict(self.env, **env), capture_output=True)

    def assert_image_clipboard(self):
        image = Path((self.root / 'latest').read_text())
        self.assertEqual((self.root / 'clipboard').read_bytes(), image.read_bytes())
        self.assertEqual((self.root / 'mime').read_text(), '--type\nimage/png\n')

    def test_region_copies_image_bytes(self):
        self.assertEqual(self.run_capture('--screenshot').returncode, 0)
        self.assert_image_clipboard()

    def test_saved_capture_copies_image_without_auto_copy_setting(self):
        self.assertEqual(self.run_capture('--screenshot-save').returncode, 0)
        self.assert_image_clipboard()

    def test_edit_uses_latest_capture_and_copies_edited_bytes(self):
        self.run_capture('--screenshot')
        self.assertEqual(self.run_capture('--edit').returncode, 0)
        self.assert_image_clipboard()
        self.assertEqual((self.root / 'clipboard').read_bytes(), b'edited PNG')

    def test_cancel_preserves_clipboard_and_latest(self):
        self.run_capture('--screenshot')
        original = (self.root / 'latest').read_bytes()
        self.run_capture('--screenshot', CANCEL='1')
        self.assertEqual((self.root / 'latest').read_bytes(), original)
        self.assert_image_clipboard()

    def test_edit_missing_capture_fails_without_copying(self):
        self.assertEqual(self.run_capture('--edit').returncode, 1)
        self.assertFalse((self.root / 'clipboard').exists())
