import QtQuick
import ".."

RowBase {
    id: numberSelectRow

    property string lastSavedDisplayValue: String(item.value ?? "")
    property alias displayValue: combo.value
    required property var request

    function presetValues() {
        const minimum = Number(item.preset_min);
        const maximum = Number(item.preset_max);
        const step = Number(item.preset_step);
        const values = [];
        if (!isFinite(minimum) || !isFinite(maximum) || !isFinite(step) || step <= 0)
            return values;
        for (let value = minimum; value <= maximum; value += step)
            values.push(value);
        return values;
    }

    function parseMinutes(text) {
        const trimmed = String(text ?? "").trim();
        if (!/^[0-9]+$/.test(trimmed))
            return NaN;
        const value = Number(trimmed);
        return isFinite(value) && value > 0 && Math.floor(value) === value ? value : NaN;
    }

    function save(value) {
        const numericValue = Number(value);
        lastSavedDisplayValue = String(numericValue);
        combo.value = lastSavedDisplayValue;
        combo.filterQuery = "";
        request("run_action", { item: item.id, value: numericValue });
    }

    function setDisplayValue(value) {
        combo.value = String(value);
        combo.filterQuery = "";
    }

    function selectPreset(value) {
        save(value);
    }

    function commitText(text) {
        const minutes = parseMinutes(text);
        if (isNaN(minutes)) {
            setDisplayValue(lastSavedDisplayValue);
            return false;
        }
        save(minutes);
        return true;
    }

    function commitOnFocusLoss(text) {
        return commitText(text);
    }

    EditableCombo {
        id: combo
        width: 160
        options: numberSelectRow.presetValues()
        value: numberSelectRow.lastSavedDisplayValue
        popupHint: "Type any whole number"
        backgroundColor: Theme.surface_container
        hoverColor: Theme.surface_container_high
        borderColor: Theme.outline_variant
        textColor: Theme.textPrimary
        mutedColor: Theme.textMuted
        accentColor: Theme.primary

        onOptionSelected: value => numberSelectRow.selectPreset(value)
        onTextAccepted: text => numberSelectRow.commitText(text)
        onEditorBlurred: text => numberSelectRow.commitOnFocusLoss(text)
    }
}
