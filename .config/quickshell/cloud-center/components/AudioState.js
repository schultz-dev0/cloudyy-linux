.pragma library

function clone(value) {
    return JSON.parse(JSON.stringify(value));
}

function stableSelection(items, current, idField) {
    const list = items || [];
    if (list.some(item => String(item[idField]) === String(current)))
        return String(current);
    const fallback = list.find(item => item.is_default) || list[0];
    return fallback ? String(fallback[idField]) : "";
}

function displayValue(pending, key, fallback) {
    const item = (pending || {})[key];
    return item === undefined ? fallback : item.value;
}

function setPending(pending, key, generation, value) {
    const next = clone(pending || {});
    next[key] = { generation: generation, value: value };
    return next;
}

function clearCompleted(pending, key, generation) {
    const next = clone(pending || {});
    if (next[key] !== undefined && Number(next[key].generation) <= Number(generation))
        delete next[key];
    return next;
}

function shouldPromptService(snapshot) {
    const automation = (snapshot || {}).automation || {};
    const service = (snapshot || {}).service || {};
    const wanted = automation.bluetooth_auto_switch !== false || automation.enabled === true;
    return wanted && !(service.enabled === true && service.active === true)
        && Number(automation.service_prompt_version || 0) < 1;
}
