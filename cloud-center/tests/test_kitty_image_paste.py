"""Verify Kitty pastes PNG file references and leaves ordinary text alone."""
from __future__ import annotations

from pathlib import Path
import runpy
import subprocess
import tempfile
from types import ModuleType, SimpleNamespace
import unittest
from unittest.mock import Mock, patch

ROOT = Path(__file__).resolve().parents[2]
PNG = b'\x89PNG\r\n\x1a\nclipboard image'


class KittyImagePasteTests(unittest.TestCase):
    def setUp(self):
        handler = ModuleType('kittens.tui.handler')
        handler.result_handler = lambda **kwargs: lambda fn: fn
        with patch.dict('sys.modules', {'kittens.tui.handler': handler}):
            self.module = runpy.run_path(str(ROOT / '.config/kitty/cloudyy-paste.py'))
        self.window = Mock()
        self.boss = SimpleNamespace(window_id_map={1: self.window}, paste_from_clipboard=Mock())
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.environment = patch.dict('os.environ', {'XDG_RUNTIME_DIR': self.temp.name})
        self.environment.start()
        self.addCleanup(self.environment.stop)

    def paste(self):
        self.module['handle_result']([], '', 1, self.boss)

    def test_image_pastes_existing_file_without_replacing_clipboard(self):
        with patch('subprocess.run', side_effect=[SimpleNamespace(stdout=b'image/png\n'), SimpleNamespace(stdout=PNG)]) as run:
            self.paste()
        target = Path(self.window.paste_text.call_args.args[0])
        self.assertEqual(target.read_bytes(), PNG)
        self.assertEqual(target.stat().st_mode & 0o777, 0o600)
        self.assertEqual(run.call_count, 2)
        self.assertTrue(all(call.args[0][0] == 'wl-paste' for call in run.call_args_list))
        self.boss.paste_from_clipboard.assert_not_called()

    def test_text_uses_original_paste_action(self):
        with patch('subprocess.run', return_value=SimpleNamespace(stdout=b'text/plain\n')):
            self.paste()
        self.boss.paste_from_clipboard.assert_called_once()
        self.window.paste_text.assert_not_called()

    def test_invalid_image_does_not_paste_path(self):
        with patch('subprocess.run', side_effect=[SimpleNamespace(stdout=b'image/png\n'), SimpleNamespace(stdout=b'not a PNG')]):
            self.paste()
        self.boss.paste_from_clipboard.assert_called_once()
        self.window.paste_text.assert_not_called()

    def test_unavailable_clipboard_falls_back(self):
        with patch('subprocess.run', side_effect=subprocess.TimeoutExpired('wl-paste', 2)):
            self.paste()
        self.boss.paste_from_clipboard.assert_called_once()
