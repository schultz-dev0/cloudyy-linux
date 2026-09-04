"""Curated-theme QML contract and isolated runtime tests."""

from __future__ import annotations

import json
import os
from pathlib import Path
import re
import select
import shutil
import subprocess
import tempfile
import time
import unittest


ROOT = Path(__file__).resolve().parents[2]
THEME_QML = ROOT / ".config/quickshell/Theme.qml"
QML_ROOTS = (ROOT / ".config/quickshell",)

SEMANTIC_ROLES = {
    "background", "surface", "surfaceRaised", "surfaceOverlay", "text",
    "textMuted", "accent", "accentMuted", "accentAlt", "accentText",
    "border", "selection", "success", "warning", "error", "info", "shadow",
}

CODE_OWNED_HELPERS = {
    "_minLightness", "glass", "glassPanelBorder", "glassShell", "hairline",
    "isLightTheme", "islandAccent", "islandBorder", "islandCarouselHeight",
    "islandCarouselWidth", "islandCloseDuration", "islandExpandDuration",
    "islandExpandedMaxHeight", "islandFocus", "islandHover", "islandOnAccent",
    "islandOnSurface", "islandOnSurfaceVariant", "islandOpacityDuration",
    "islandOpenDuration", "islandOpenLowerRadius", "islandPressed",
    "islandPreviewContentWidth", "islandPreviewInset", "islandPreviewRadius",
    "islandRestHeight", "islandRestLowerRadius", "islandRestWidth",
    "islandShellHMargin", "islandShellHeight", "islandShellWidth",
    "islandShoulderRadius", "islandSurface", "islandTimerRestWidth", "resin",
    "resinBorder", "resinFillAlpha", "resinGloss", "resinGlow",
}

REMOVED_MATERIAL_ROLES = {
    "error_container", "inverse_on_surface", "inverse_primary", "inverse_surface",
    "on_background", "on_error", "on_error_container", "on_primary",
    "on_primary_container", "on_primary_fixed", "on_primary_fixed_variant",
    "on_secondary", "on_secondary_container", "on_secondary_fixed",
    "on_secondary_fixed_variant", "on_surface", "on_surface_variant",
    "on_tertiary", "on_tertiary_container", "on_tertiary_fixed",
    "on_tertiary_fixed_variant", "outline", "outline_variant", "primary",
    "primary_container", "primary_fixed", "primary_fixed_dim", "scrim",
    "secondary", "secondary_container", "secondary_fixed", "secondary_fixed_dim",
    "source_color", "surface_bright", "surface_container",
    "surface_container_high", "surface_container_highest", "surface_container_low",
    "surface_container_lowest", "surface_dim", "surface_tint", "surface_variant",
    "tertiary", "tertiary_container", "tertiary_fixed", "tertiary_fixed_dim",
    "accentSoft", "textPrimary",
}


def _qml_without_comments(path: Path) -> str:
    source = path.read_text()
    source = re.sub(r"/\*.*?\*/", "", source, flags=re.DOTALL)
    return re.sub(r"//.*", "", source)


def _theme_document(
    mode: str, accent: str, accent_text: str, shadow: str = "#2E3440"
) -> dict[str, object]:
    colors = {
        "background": "#2E3440",
        "surface": "#3B4252",
        "surfaceRaised": "#434C5E",
        "surfaceOverlay": "#4C566A",
        "text": "#ECEFF4",
        "textMuted": "#E5E9F0",
        "accent": accent,
        "accentMuted": "#5E81AC",
        "accentAlt": "#8FBCBB",
        "onAccent": accent_text,
        "border": "#4C566A",
        "selection": "#434C5E",
        "success": "#A3BE8C",
        "warning": "#EBCB8B",
        "error": "#BF616A",
        "info": "#81A1C1",
        "shadow": shadow,
    }
    return {"name": "Test", "slug": "test", "mode": mode, "colors": colors}


class CuratedThemeQmlContractTests(unittest.TestCase):
    def test_qml_consumers_use_only_semantic_roles_and_code_owned_helpers(self):
        references: dict[str, list[str]] = {}
        allowed = SEMANTIC_ROLES | CODE_OWNED_HELPERS
        for root in QML_ROOTS:
            for path in root.rglob("*.qml"):
                if path.resolve() == THEME_QML.resolve():
                    continue
                for name in re.findall(r"\bTheme\.([A-Za-z_][A-Za-z0-9_]*)", _qml_without_comments(path)):
                    references.setdefault(name, []).append(str(path.relative_to(ROOT)))

        self.assertTrue(references, "expected Cloudyy QML consumers to reference Theme")
        unexpected = {name: paths for name, paths in references.items() if name not in allowed}
        self.assertEqual(unexpected, {})
        self.assertTrue(SEMANTIC_ROLES & references.keys())
        self.assertEqual(REMOVED_MATERIAL_ROLES & references.keys(), set())

    def test_singleton_declares_exact_semantic_surface_without_compatibility_aliases(self):
        source = THEME_QML.read_text()
        mutable_colors = set(re.findall(
            r"^\s{4}property color ([A-Za-z_][A-Za-z0-9_]*):", source, re.MULTILINE
        ))
        self.assertEqual(mutable_colors, SEMANTIC_ROLES)
        self.assertEqual(REMOVED_MATERIAL_ROLES & set(re.findall(
            r"^\s+(?:readonly )?property \w+ ([A-Za-z_][A-Za-z0-9_]*):",
            source,
            re.MULTILINE,
        )), set())
        self.assertNotIn("matugen", source.lower())
        self.assertIn('target: "theme"', source)
        self.assertRegex(source, r"function reload\(\)")

    def test_all_qml_is_detached_from_matugen(self):
        offenders = []
        for root in QML_ROOTS:
            for path in root.rglob("*.qml"):
                if "matugen" in path.read_text().lower():
                    offenders.append(str(path.relative_to(ROOT)))
        self.assertEqual(offenders, [])

    def test_themeable_status_color_uses_semantic_error_role(self):
        bar = (ROOT / ".config/quickshell/Bar.qml").read_text()
        self.assertNotIn('bat.percent < 15 ? "#ffdddd"', bar)
        self.assertIn("bat.percent < 15 ? Theme.error", bar)

    def test_reviewed_error_surfaces_keep_content_distinct_from_background(self):
        cloud_button = (
            ROOT / ".config/quickshell/cloud-center/components/CloudButton.qml"
        ).read_text()
        self.assertIn(
            "return Theme.glass(Theme.error, hover.hovered ? 0.20 : 0.12);",
            cloud_button,
        )

        expected = {
            ".config/quickshell/cloud-center/components/AudioPriorityEditor.qml": (
                "color: root.serviceActive ? Theme.accentMuted : Theme.glass(Theme.error, 0.12)",
                "color: root.serviceActive ? Theme.text : Theme.error",
            ),
            ".config/quickshell/cloud-center/pages/RecordingEditor.qml": (
                "color: recordingPage.hasError ? Theme.glass(Theme.error, 0.12) : Theme.accentMuted",
                "color: recordingPage.hasError ? Theme.error : Theme.text",
            ),
            ".config/quickshell/cloud-center/pages/MonitorsEditor.qml": (
                "color: dpmsHover.hovered ? Theme.error : Theme.glass(Theme.error, 0.12)",
                "color: dpmsHover.hovered ? Theme.accentText : Theme.error",
                "color: Theme.glass(Theme.error, 0.12)",
                'text: "Remove virtual output " + monPage.selectedName; color: Theme.error',
            ),
        }
        for relative, snippets in expected.items():
            source = (ROOT / relative).read_text()
            for snippet in snippets:
                with self.subTest(path=relative, snippet=snippet):
                    self.assertIn(snippet, source)

    def test_media_fallback_gradient_preserves_two_authored_identities(self):
        media_card = (
            ROOT / ".config/quickshell/modules/controlcenter/MediaCard.qml"
        ).read_text()
        gradient = media_card.split("gradient: Gradient {", 1)[1].split("}", 3)
        gradient_source = "}".join(gradient[:3])
        self.assertIn("color: Theme.accentMuted", gradient_source)
        self.assertIn("color: Theme.accentAlt", gradient_source)

    def test_canonical_singleton_links_are_preserved_and_fallback_is_removed(self):
        links = {
            ROOT / ".config/quickshell/cloud-center/Theme.qml": "../Theme.qml",
            ROOT / ".config/quickshell/lock/Theme.qml": "../Theme.qml",
        }
        for path, target in links.items():
            with self.subTest(path=path):
                self.assertTrue(path.is_symlink())
                self.assertEqual(os.readlink(path), target)
                self.assertEqual(path.resolve(), THEME_QML.resolve())
        self.assertFalse((ROOT / "install/assets/default-theme/quickshell/Theme.qml").exists())

    @unittest.skipUnless(shutil.which("qs"), "Quickshell is unavailable")
    def test_singleton_loads_atomically_and_watches_active_theme_file(self):
        with tempfile.TemporaryDirectory(prefix="cloudyy-theme-qml-") as temp:
            temp_root = Path(temp)
            config = temp_root / "quickshell-theme-contract"
            state = temp_root / "state"
            runtime = temp_root / "runtime"
            theme_file = state / "cloudyy/current/theme/theme.json"
            config.mkdir()
            runtime.mkdir(mode=0o700)
            theme_file.parent.mkdir(parents=True)
            shutil.copy2(THEME_QML, config / "Theme.qml")
            theme_file.write_text(json.dumps(_theme_document("dark", "#010203", "#112233")))
            (config / "shell.qml").write_text(
                """import QtQuick
import Quickshell
import \".\"

ShellRoot {
    id: root
    property bool ready: false
    property int ticks: 0

    Timer {
        interval: 40
        running: true
        repeat: true
        onTriggered: {
            root.ticks++;
            const accent = String(Theme.accent).toLowerCase();
            const accentText = String(Theme.accentText).toLowerCase();
            const shadowChannelsMatch = Math.round(Theme.shadow.r * 255) === 0x10
                && Math.round(Theme.shadow.g * 255) === 0x20
                && Math.round(Theme.shadow.b * 255) === 0x30
                && Math.round(Theme.shadow.a * 255) === 0x80;
            if (!root.ready && Theme.mode === \"dark\" && accent === \"#010203\"
                    && accentText === \"#112233\") {
                root.ready = true;
                console.info(\"CLOUDYY_THEME_QML_READY\");
            } else if (root.ready && Theme.mode === \"light\" && accent === \"#abcdef\"
                    && accentText === \"#fedcba\" && shadowChannelsMatch) {
                console.info(\"CLOUDYY_THEME_QML_PASS\");
                Qt.callLater(Qt.quit);
            } else if (root.ready && Theme.mode === \"light\" && accent === \"#abcdef\"
                    && accentText === \"#fedcba\" && !shadowChannelsMatch) {
                console.error(\"CLOUDYY_THEME_QML_CHANNELS \" + String(Theme.shadow));
                Qt.callLater(Qt.quit);
            } else if (root.ready && (Theme.mode !== \"dark\" || accent !== \"#010203\"
                    || accentText !== \"#112233\")) {
                console.error(\"CLOUDYY_THEME_QML_PARTIAL \" + Theme.mode + \" \" + accent
                    + \" \" + accentText);
                Qt.callLater(Qt.quit);
            } else if (root.ticks > 250) {
                console.error(\"CLOUDYY_THEME_QML_TIMEOUT \" + Theme.mode + \" \" + accent);
                Qt.callLater(Qt.quit);
            }
        }
    }
}
"""
            )

            env = {
                **os.environ,
                "HOME": str(temp_root / "home"),
                "XDG_STATE_HOME": str(state),
                "XDG_RUNTIME_DIR": str(runtime),
                "QT_QPA_PLATFORM": "offscreen",
                "NO_COLOR": "1",
            }
            process = subprocess.Popen(
                ["qs", "--no-color", "-p", str(config / "shell.qml")],
                cwd=ROOT,
                env=env,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
            )
            output: list[str] = []
            try:
                deadline = time.monotonic() + 10
                ready = False
                while time.monotonic() < deadline and process.poll() is None:
                    readable, _, _ = select.select([process.stdout], [], [], 0.2)
                    if not readable:
                        continue
                    line = process.stdout.readline()
                    output.append(line)
                    if "CLOUDYY_THEME_QML_READY" in line:
                        ready = True
                        break
                self.assertTrue(ready, "".join(output))

                theme_file.write_text(json.dumps({
                    "name": "Partial", "slug": "partial", "mode": "light",
                    "colors": {"accent": "#abcdef"},
                }))
                time.sleep(0.4)
                theme_file.write_text(json.dumps(_theme_document(
                    "light", "#abcdef", "#fedcba", "#10203080"
                )))
                remainder, _ = process.communicate(timeout=12)
                output.append(remainder)
            finally:
                if process.poll() is None:
                    process.terminate()
                    try:
                        remainder, _ = process.communicate(timeout=3)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        remainder, _ = process.communicate(timeout=3)
                    output.append(remainder)

            combined = "".join(output)
            self.assertEqual(process.returncode, 0, combined)
            self.assertNotIn("CLOUDYY_THEME_QML_PARTIAL", combined)
            self.assertNotIn("CLOUDYY_THEME_QML_CHANNELS", combined)
            self.assertNotIn("CLOUDYY_THEME_QML_TIMEOUT", combined)
            self.assertIn("CLOUDYY_THEME_QML_PASS", combined)


if __name__ == "__main__":
    unittest.main()
