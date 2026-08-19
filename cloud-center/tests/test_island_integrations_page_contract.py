from __future__ import annotations

from pathlib import Path

import yaml

from lib.ccd import model


ROOT = Path(__file__).resolve().parents[2]
CONFIG = ROOT / "cloud-center/config.yaml"
YAML_PAGE = ROOT / ".config/quickshell/cloud-center/pages/YamlPage.qml"
EDITOR = (
    ROOT
    / ".config/quickshell/cloud-center/components/IslandIntegrationsEditor.qml"
)


def text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def test_shell_yaml_page_owns_the_dynamic_island_editor():
    config = yaml.safe_load(CONFIG.read_text(encoding="utf-8"))
    shell_page = next(page for page in config["pages"] if page["id"] == "quickshell")
    items = [
        item
        for section in shell_page["layout"]
        for item in section.get("items", [])
    ]

    assert sum(item.get("type") == "island_integrations" for item in items) == 1
    assert "island_integrations" not in model.NATIVE_KIND_OVERRIDES.values()
    assert all(page["id"] != "__island_integrations__" for page in model.NATIVE_PAGES)
    built_shell = next(
        page for page in model.load_model(CONFIG)["pages"] if page["id"] == "quickshell"
    )
    assert built_shell["kind"] == "yaml"
    assert any(
        item["type"] == "island_integrations"
        for section in built_shell["sections"]
        for item in section["items"]
    )


def test_yaml_item_loads_the_custom_editor():
    page = text(YAML_PAGE)

    assert 'case "island_integrations": return islandIntegrationsComp;' in page
    assert "IslandIntegrationsEditor { item: modelData }" in page


def test_editor_uses_replaceable_model_and_complete_versioned_documents():
    editor = text(EDITOR)

    assert "ListModel {" in editor
    assert "id: integrationsModel" in editor
    assert "function replaceSettings(settings)" in editor
    assert "integrationsModel.clear();" in editor
    document = editor.split("function currentDocument()", 1)[1].split(
        "function saveCurrentDocument()", 1
    )[0]
    assert "version: 1" in document
    assert "order:" in document
    assert "enabled:" in document
    assert "status" not in document.lower()
    assert "S.Backend.saveIslandIntegrations(root.currentDocument()" in editor


def test_every_row_can_be_disabled_and_each_toggle_saves():
    editor = text(EDITOR)
    toggle = editor.split("function setEnabled(index, enabled)", 1)[1].split(
        "function moveIntegration", 1
    )[0]

    assert 'integrationsModel.setProperty(index, "enabledState", enabled);' in toggle
    assert "root.saveCurrentDocument();" in toggle
    for forbidden in ("enabledCount", "atLeastOne", "last enabled", "count <= 1"):
        assert forbidden not in toggle


def test_drag_is_targetless_and_saves_only_after_completion():
    editor = text(EDITOR)
    drag = editor.split("DragHandler {", 1)[1].split("CloudButton {", 1)[0]

    assert "target: null" in drag
    assert "onActiveChanged:" in drag
    assert "if (!active)" in drag
    assert "moveIntegration" in drag
    assert "saveIslandIntegrations" not in drag


def test_rows_offer_keyboard_up_and_down_ordering():
    editor = text(EDITOR)

    assert "Keys.onUpPressed:" in editor
    assert "Keys.onDownPressed:" in editor
    assert "root.moveIntegration(index, index - 1);" in editor
    assert "root.moveIntegration(index, index + 1);" in editor


def test_failed_saves_reload_authoritative_backend_state():
    editor = text(EDITOR)
    save = editor.split("function saveCurrentDocument()", 1)[1].split(
        "function setEnabled", 1
    )[0]

    assert "S.Backend.saveIslandIntegrations(" in save
    assert "root.replaceSettings(saved);" in save
    assert "S.Backend.getIslandIntegrations(" in save
    assert "root.replaceSettings(authoritative);" in save
    authoritative = save.split(
        "S.Backend.getIslandIntegrations(authoritative =>", 1
    )[1].split("}, loadError =>", 1)[0]
    assert 'root.errorText = "";' in authoritative
    assert "previous" not in save.lower()
    assert "snapshot" not in save.lower()


def test_obsolete_save_failures_return_before_reconciliation_side_effects():
    editor = text(EDITOR)
    save = editor.split("function saveCurrentDocument()", 1)[1].split(
        "function setEnabled", 1
    )[0]
    failure = save.split("}, error => {", 1)[1]
    guard = (
        "if (revision !== root.mutationRevision)\n"
        "                return;"
    )

    assert failure.strip().startswith(guard)
    assert failure.index(guard) < failure.index("root.errorText =")
    assert failure.index(guard) < failure.index("S.Backend.getIslandIntegrations(")
    assert failure.index(guard) < failure.index("root.replaceSettings(authoritative);")


def test_runtime_status_is_non_persistent_and_uses_only_approved_labels():
    editor = text(EDITOR)

    for label in (
        "Detected",
        "Waiting for activity",
        "Shell status unavailable",
    ):
        assert label in editor
    assert "function approvedStatus(status)" in editor
    assert 'statusText: root.approvedStatus(' in editor
