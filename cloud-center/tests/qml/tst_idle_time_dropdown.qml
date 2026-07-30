import QtQuick
import QtTest

TestCase {
    name: "IdleTimeDropdown"
    when: windowShown

    readonly property url componentRoot: Qt.resolvedUrl(
        "../../../../.config/quickshell/cloud-center/components/")

    function createRow(actions) {
        const component = Qt.createComponent(componentRoot + "RowEditableNumberSelect.qml");
        verify(component.status === Component.Ready, component.errorString());
        if (component.status !== Component.Ready)
            return null;
        const row = component.createObject(this, {
            width: 700,
            item: {
                id: "lock_timeout",
                icon: "",
                title: "Lock after",
                description: "Minutes before locking",
                value: 15,
                preset_min: 15,
                preset_max: 120,
                preset_step: 15,
            },
            request: (method, params) => actions.push({ method: method, params: params }),
        });
        verify(row !== null, component.errorString());
        return row;
    }

    function findEditableCombo(item) {
        if (item && item.options !== undefined && item.filterQuery !== undefined
                && typeof item.open === "function")
            return item;
        if (!item || !item.children)
            return null;
        for (const child of item.children) {
            const found = findEditableCombo(child);
            if (found)
                return found;
        }
        return null;
    }

    function findTextInput(item) {
        if (item && item.cursorPosition !== undefined && typeof item.selectAll === "function")
            return item;
        if (!item || !item.children)
            return null;
        for (const child of item.children) {
            const found = findTextInput(child);
            if (found)
                return found;
        }
        return null;
    }

    function replaceEditorText(editor, text) {
        editor.forceActiveFocus();
        editor.selectAll();
        if (text === "")
            keyClick(Qt.Key_Backspace);
        else {
            for (let index = 0; index < text.length; index++)
                keyClick(text.charAt(index).toUpperCase().charCodeAt(0));
        }
        wait(1);
    }

    function test_preset_values_are_derived_from_item_bounds() {
        const row = createRow([]);
        if (!row) return;
        compare(row.presetValues(), [15, 30, 45, 60, 75, 90, 105, 120]);
        row.destroy();
    }

    function test_selecting_preset_commits_numeric_value_immediately() {
        const actions = [];
        const row = createRow(actions);
        if (!row) return;
        row.selectPreset(30);
        compare(actions.length, 1);
        compare(actions[0].method, "run_action");
        compare(actions[0].params.item, "lock_timeout");
        compare(actions[0].params.value, 30);
        compare(row.lastSavedDisplayValue, "30");
        wait(1);
        compare(actions.length, 1);
        row.destroy();
    }

    function test_accepting_custom_whole_minutes_commits_numeric_value() {
        const actions = [];
        const row = createRow(actions);
        if (!row) return;
        verify(row.commitText("17"));
        compare(actions.length, 1);
        compare(actions[0].params.value, 17);
        compare(row.lastSavedDisplayValue, "17");
        row.destroy();
    }

    function test_focus_loss_uses_the_same_text_commit() {
        const actions = [];
        const row = createRow(actions);
        if (!row) return;
        row.commitOnFocusLoss("22");
        compare(actions.length, 1);
        compare(actions[0].params.value, 22);
        compare(row.lastSavedDisplayValue, "22");
        row.destroy();
    }

    function test_real_editor_return_commits_the_edited_value_once() {
        const actions = [];
        const row = createRow(actions);
        if (!row) return;
        const editor = findTextInput(row);
        verify(editor !== null);
        if (!editor) return;
        replaceEditorText(editor, "17");
        keyClick(Qt.Key_Return);
        wait(1);
        compare(actions.length, 1);
        compare(actions[0].params.value, 17);
        row.destroy();
    }

    function test_real_editor_focus_transition_commits_the_edited_value_once() {
        const actions = [];
        const row = createRow(actions);
        if (!row) return;
        const editor = findTextInput(row);
        verify(editor !== null);
        if (!editor) return;
        replaceEditorText(editor, "22");
        keyClick(Qt.Key_Escape);
        row.forceActiveFocus();
        wait(1);
        compare(actions.length, 1);
        compare(actions[0].params.value, 22);
        row.destroy();
    }

    function test_empty_real_editor_return_restores_without_request() {
        const actions = [];
        const row = createRow(actions);
        if (!row) return;
        const editor = findTextInput(row);
        verify(editor !== null);
        if (!editor) return;
        replaceEditorText(editor, "");
        keyClick(Qt.Key_Return);
        wait(1);
        compare(actions.length, 0);
        compare(row.displayValue, "15");
        compare(editor.text, "15");
        row.destroy();
    }

    function test_non_numeric_real_editor_blur_restores_without_request() {
        const actions = [];
        const row = createRow(actions);
        if (!row) return;
        const editor = findTextInput(row);
        verify(editor !== null);
        if (!editor) return;
        replaceEditorText(editor, "abc");
        keyClick(Qt.Key_Escape);
        row.forceActiveFocus();
        wait(1);
        compare(actions.length, 0);
        compare(row.displayValue, "15");
        compare(editor.text, "15");
        row.destroy();
    }

    function test_leading_zero_real_editor_return_normalizes_positive_minutes() {
        const actions = [];
        const row = createRow(actions);
        if (!row) return;
        const editor = findTextInput(row);
        verify(editor !== null);
        if (!editor) return;
        replaceEditorText(editor, "0017");
        keyClick(Qt.Key_Return);
        wait(1);
        compare(actions.length, 1);
        compare(actions[0].params.value, 17);
        compare(row.displayValue, "17");
        compare(editor.text, "17");
        row.destroy();
    }

    function test_invalid_text_runs_no_action_and_restores_saved_value() {
        const actions = [];
        const row = createRow(actions);
        if (!row) return;
        row.selectPreset(30);
        compare(actions.length, 1);
        verify(!row.commitText("17.5"));
        wait(1);
        compare(actions.length, 1);
        compare(row.lastSavedDisplayValue, "30");
        compare(row.displayValue, "30");
        verify(isNaN(row.parseMinutes("0")));
        verify(isNaN(row.parseMinutes("-1")));
        verify(isNaN(row.parseMinutes("")));
        verify(isNaN(row.parseMinutes("abc")));
        row.destroy();
    }
}
