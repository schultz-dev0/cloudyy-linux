import QtQuick
import QtTest

TestCase {
    name: "MonitorComponents"
    when: windowShown

    readonly property url componentRoot: Qt.resolvedUrl(
        "../../../../.config/quickshell/cloud-center/components/")

    function createRequired(fileName) {
        const component = Qt.createComponent(componentRoot + fileName);
        verify(component.status === Component.Ready, component.errorString());
        if (component.status !== Component.Ready)
            return null;
        const object = component.createObject(this, { width: 700, height: 220 });
        verify(object !== null, component.errorString());
        return object;
    }

    function findText(item, value) {
        if (item && item.text !== undefined && item.text === value)
            return item;
        if (!item || !item.children)
            return null;
        for (const child of item.children) {
            const found = findText(child, value);
            if (found)
                return found;
        }
        return null;
    }

    function test_row_text_uses_native_vertical_hinting() {
        const component = Qt.createComponent(componentRoot + "RowBase.qml");
        verify(component.status === Component.Ready, component.errorString());
        if (component.status !== Component.Ready)
            return;
        const row = component.createObject(this, {
            width: 700,
            item: {
                icon: "",
                title: "Position",
                description: "Top-left logical pixels",
            },
        });
        verify(row !== null, component.errorString());
        if (!row)
            return;

        const title = findText(row, "Position");
        const description = findText(row, "Top-left logical pixels");
        verify(title !== null);
        verify(description !== null);
        compare(title.renderType, Text.NativeRendering);
        compare(description.renderType, Text.NativeRendering);
        compare(title.font.hintingPreference, Font.PreferVerticalHinting);
        compare(description.font.hintingPreference, Font.PreferVerticalHinting);
        compare(title.font.pixelSize, 14);
        compare(title.font.weight, Font.Medium);
        compare(description.font.pixelSize, 12);
        row.destroy();
    }

    function test_sidebar_item_text_matches_readable_typography() {
        const component = Qt.createComponent(componentRoot + "SidebarItem.qml");
        verify(component.status === Component.Ready, component.errorString());
        if (component.status !== Component.Ready)
            return;
        const item = component.createObject(this, {
            width: 220,
            pageId: "monitors",
            title: "Monitors",
            glyph: "",
        });
        verify(item !== null, component.errorString());
        if (!item)
            return;

        const label = findText(item, "Monitors");
        verify(label !== null);
        compare(label.renderType, Text.NativeRendering);
        compare(label.font.hintingPreference, Font.PreferVerticalHinting);
        compare(label.font.pixelSize, 14);
        compare(label.font.weight, Font.Medium);
        item.destroy();
    }

    function test_section_heading_matches_readable_typography() {
        const component = Qt.createComponent(componentRoot + "SectionCard.qml");
        verify(component.status === Component.Ready, component.errorString());
        if (component.status !== Component.Ready)
            return;
        const card = component.createObject(this, {
            width: 700,
            section: { title: "Workspaces" },
        });
        verify(card !== null, component.errorString());
        if (!card)
            return;

        const heading = findText(card, "WORKSPACES");
        verify(heading !== null);
        compare(heading.renderType, Text.NativeRendering);
        compare(heading.font.hintingPreference, Font.PreferVerticalHinting);
        compare(heading.font.pixelSize, 11);
        compare(heading.font.weight, Font.Medium);
        card.destroy();
    }

    function test_canvas_uses_staged_mode_scale_and_rotation() {
        const canvas = createRequired("MonitorLayoutCanvas.qml");
        if (!canvas)
            return;
        verify(typeof canvas.logicalSize === "function");
        const size = canvas.logicalSize({
            mode: "2560x1440@120.00Hz",
            width: 1920,
            height: 1080,
            scale: 2.0,
            transform: 3,
        });
        compare(size.width, 720);
        compare(size.height, 1280);
        canvas.destroy();
    }

    function test_canvas_snap_aligns_rotated_draft_edges() {
        const canvas = createRequired("MonitorLayoutCanvas.qml");
        if (!canvas)
            return;
        canvas.monitors = [
            { name: "DP-1", mode: "1920x1080@60Hz", width: 1920, height: 1080,
              scale: 1, transform: 0, x: 0, y: 0, enabled: true },
            { name: "DP-2", mode: "2560x1440@120Hz", width: 2560, height: 1440,
              scale: 1, transform: 3, x: 2000, y: 0, enabled: true },
        ];
        const snapped = canvas.snapPosition("DP-2", 1905, 8);
        compare(snapped.x, 1920);
        compare(snapped.y, 0);
        canvas.destroy();
    }

    function test_editable_combo_filters_and_keeps_custom_text() {
        const combo = createRequired("EditableCombo.qml");
        if (!combo)
            return;
        combo.options = ["3440x1440@180.00Hz", "3440x1440@60.00Hz", "1920x1080@60.00Hz"];
        compare(combo.filteredOptions("180"), ["3440x1440@180.00Hz"]);
        combo.value = "3440x1440@180.00Hz";
        combo.open();
        compare(combo.filterQuery, "");
        compare(combo.visibleOptions, combo.options);
        combo.value = "custom-mode";
        compare(combo.value, "custom-mode");
        combo.destroy();
    }
}
