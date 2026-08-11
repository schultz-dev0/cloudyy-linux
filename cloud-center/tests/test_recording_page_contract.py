from pathlib import Path
import unittest

from lib.ccd import model, protocol


REPO_ROOT = Path(__file__).resolve().parents[2]
SHELL = REPO_ROOT / ".config/quickshell/cloud-center/shell.qml"
BACKEND = REPO_ROOT / ".config/quickshell/cloud-center/services/Backend.qml"
PAGE = REPO_ROOT / ".config/quickshell/cloud-center/pages/RecordingEditor.qml"
LAUNCHER = REPO_ROOT / "cloud-center/cloud-center"
COMPONENTS_DIR = REPO_ROOT / ".config/quickshell/cloud-center/components"
STATE_JS = COMPONENTS_DIR / "RecordingState.js"
AUDIO_PICKER = COMPONENTS_DIR / "RecordingAudioPicker.qml"
GALLERY_GRID = COMPONENTS_DIR / "RecordingGalleryGrid.qml"


class RecordingPageContractTests(unittest.TestCase):
    def test_model_registers_recording_page(self):
        model.load_model()
        ids = [p["id"] for p in model.load_model()["pages"]]
        self.assertIn("__recording__", ids)

    def test_model_routes_recording_to_native_page(self):
        self.assertEqual(model.NATIVE_KIND_OVERRIDES.get("__recording__"), "recording")
        by_id = {p["id"]: p for p in model.load_model()["pages"]}
        recording = by_id["__recording__"]
        self.assertEqual(recording["kind"], "recording")
        self.assertEqual(recording["title"], "Recording")
        self.assertEqual(recording["icon"], "\U000f0100")
        categories = {c["title"]: c["pages"] for c in model.load_model()["categories"]}
        system = categories["System"]
        self.assertIn("__recording__", system)
        self.assertLess(system.index("__audio__"), system.index("__recording__"))
        self.assertLess(system.index("__recording__"), system.index("__region__"))

    def test_shell_and_backend_wire_recording(self):
        shell = SHELL.read_text(encoding="utf-8")
        backend = BACKEND.read_text(encoding="utf-8")
        self.assertIn('page.kind === "recording"', shell)
        self.assertIn("RecordingEditor", shell)
        self.assertIn("recordingSnapshotEvent", backend)
        self.assertIn("recordingActionDoneEvent", backend)
        self.assertIn('case "recording_snapshot"', backend)
        self.assertIn('case "recording_action_done"', backend)

    def test_launcher_aliases_recording(self):
        source = LAUNCHER.read_text(encoding="utf-8")
        for alias in ('[recording]="__recording__"', '[record]="__recording__"'):
            self.assertIn(alias, source)
        self.assertIn("[screenshots]=\"__recording__\"", source)

    def test_protocol_methods_registered(self):
        # Importing lib.ccd.recording registers its methods (as a module-level
        # side effect) against the shared protocol.METHODS table.
        import lib.ccd.recording  # noqa: F401

        expected = {
            "get_recording_snapshot",
            "start_recording_watch",
            "stop_recording_watch",
            "run_recording_action",
        }
        self.assertTrue(expected <= protocol.METHODS.keys())

    def test_page_files_exist(self):
        for path in (PAGE, STATE_JS, AUDIO_PICKER, GALLERY_GRID):
            self.assertTrue(path.is_file(), path)

    def test_page_wires_recording_components(self):
        source = PAGE.read_text(encoding="utf-8")
        self.assertIn("RecordingState.js", source)
        self.assertIn("RecordingAudioPicker", source)
        self.assertIn("RecordingGalleryGrid", source)
        self.assertIn("Flickable", source)
        self.assertIn("SectionCard", source)
        self.assertIn("get_recording_snapshot", source)
        self.assertIn("start_recording_watch", source)
        self.assertIn("stop_recording_watch", source)
        self.assertIn("run_recording_action", source)
        self.assertIn("onRecordingSnapshotEvent", source)
        self.assertIn("onRecordingActionDoneEvent", source)

    def test_page_has_expected_ui_strings(self):
        source = PAGE.read_text(encoding="utf-8")
        for label in (
            "Controls", "Paths", "Audio Inputs", "Encode", "Behavior", "Gallery",
            "Screenshot", "Save Screenshot", "Start Recording", "Stop Recording",
            "Screenshots Directory", "Recordings Directory",
            "Frame Rate", "File Type", "Codec", "Filename Pattern",
            "Island Preview Duration (ms)", "Auto-Copy After Capture", "Edit Command",
        ):
            self.assertIn(label, source, label)

    def test_audio_picker_has_mic_and_desktop_ui_strings(self):
        source = AUDIO_PICKER.read_text(encoding="utf-8")
        for label in ("Microphone", "Desktop Audio", "rec_audio_mic", "rec_audio_desktop",
                      "rec_mic_device", "rec_desktop_device"):
            self.assertIn(label, source, label)

    def test_gallery_grid_supports_expected_actions(self):
        source = GALLERY_GRID.read_text(encoding="utf-8")
        for action in ('"open"', '"copy"', '"edit"', '"reveal"', '"delete"'):
            self.assertIn(action, source, action)
        self.assertIn("ensureThumbNeeded", source)
        self.assertIn("DragHandler", source)
        self.assertIn("Drag.mimeData", source)

    def test_recording_state_js_has_snapshot_helpers(self):
        source = STATE_JS.read_text(encoding="utf-8")
        self.assertIn("function emptySnapshot", source)
        self.assertIn("function clone", source)


if __name__ == "__main__":
    unittest.main()
