.pragma library

function text(value) {
    if (value === undefined || value === null)
        return "";
    return `${value}`.trim();
}

function lower(value) {
    return text(value).toLowerCase();
}

function cleanDesktopId(value) {
    return lower(value).replace(/\.desktop$/, "");
}

function desktopIdFromPath(value) {
    const path = text(value);
    if (!path)
        return "";
    const parts = path.split("/");
    return text(parts[parts.length - 1]).replace(/\.desktop$/i, "");
}

function desktopId(desktop, window) {
    if (window?.forceProcessIdentity && lower(window?.processAppKey))
        return lower(window.processAppKey);
    const resolvedDesktop = desktop?.resolved !== false;
    if (resolvedDesktop) {
        const resolvedId = cleanDesktopId(desktop?.id) || lower(desktop?.wmclass);
        if (resolvedId)
            return resolvedId;
    }
    return lower(window?.processAppKey)
        || cleanDesktopId(desktop?.id)
        || lower(desktop?.wmclass)
        || lower(window?.class || window?.initialClass)
        || "unknown";
}

function isCursor(desktop, window) {
    const values = [
        desktop?.id,
        desktop?.name,
        desktop?.wmclass,
        window?.processAppKey,
        window?.class,
        window?.initialClass
    ].map(lower);
    return values.some(value => value === "cursor"
        || value === "co.anysphere.cursor"
        || value.endsWith("/cursor"));
}

function roleForWindow(window, desktop) {
    const title = lower(window?.title);
    const initialTitle = lower(window?.initialTitle);
    if (isCursor(desktop, window)
            && (title === "agents" || title === "cursor agents"
                || initialTitle === "agents" || initialTitle === "cursor agents"))
        return "agents";
    return "main";
}

function baseLabel(desktop, window) {
    return text(desktop?.name)
        || text(window?.class || window?.initialClass)
        || "Unknown";
}

function identityForWindow(window, desktop) {
    const role = roleForWindow(window, desktop);
    const label = baseLabel(desktop, window);
    return {
        version: 2,
        appId: desktopId(desktop, window),
        class: text(window?.class || desktop?.wmclass || window?.initialClass),
        initialClass: text(window?.initialClass),
        role: role,
        label: role === "agents" ? `${label} Agents` : label,
        exec: text(desktop?.exec),
        desktopPath: text(desktop?.desktopPath),
        icon: text(desktop?.icon),
        launchTarget: null
    };
}

function primaryIdentityForApp(app) {
    return {
        version: 2,
        appId: desktopId(app, null),
        class: text(app?.wmclass || app?.class),
        initialClass: "",
        role: "main",
        label: text(app?.name) || text(app?.wmclass || app?.class),
        exec: text(app?.exec),
        desktopPath: text(app?.desktopPath),
        icon: text(app?.icon),
        launchTarget: null
    };
}

function canonicalKey(identity) {
    return (lower(identity?.appId) || lower(identity?.class) || "unknown")
        + "::" + (lower(identity?.role) || "main");
}

function sameIdentity(left, right) {
    return canonicalKey(left) === canonicalKey(right);
}

function displayLabel(identity) {
    return text(identity?.label) || text(identity?.class) || "Unknown";
}

function decodeFileUri(uri) {
    try {
        return decodeURIComponent(text(uri).replace(/^file:\/\//, ""));
    } catch (error) {
        return "";
    }
}

function workspaceTargetForWindow(window, recentUris) {
    const title = lower(window?.title);
    for (const uri of recentUris || []) {
        const decoded = decodeFileUri(uri);
        const parts = decoded.split("/").filter(part => part.length > 0);
        const base = lower(parts.length > 0 ? parts[parts.length - 1] : "");
        if (base && title.includes(base))
            return { kind: "folderUri", value: text(uri) };
    }
    return null;
}

function filterWindowsForIdentity(identity, windows, desktop) {
    const matches = [];
    for (const window of windows || []) {
        if (sameIdentity(identity, identityForWindow(window, desktop)))
            matches.push(window);
    }
    matches.sort((left, right) => (left?.focusHistoryID ?? 999999)
        - (right?.focusHistoryID ?? 999999));
    return matches;
}

function validLaunchTarget(target) {
    if (!target || typeof target !== "object")
        return null;
    const kind = text(target.kind);
    const value = text(target.value);
    if (!kind || !value)
        return null;
    return { kind: kind, value: value };
}

function normalizePin(entry, desktop, window, recentUris) {
    const source = entry || {};
    let identity;
    if (Number(source.version) === 2 && text(source.appId)) {
        identity = {
            version: 2,
            appId: lower(source.appId),
            class: text(source.class || desktop?.wmclass),
            initialClass: text(source.initialClass),
            role: lower(source.role) || "main",
            label: text(source.label),
            exec: text(source.exec),
            desktopPath: text(source.desktopPath),
            icon: text(source.icon),
            launchTarget: validLaunchTarget(source.launchTarget)
        };
    } else if (window) {
        identity = identityForWindow(window, desktop);
    } else {
        const app = desktop || {
            id: source.appId || source.class,
            name: source.label || source.class,
            wmclass: source.class,
            exec: source.exec,
            desktopPath: source.desktopPath,
            icon: source.icon
        };
        identity = primaryIdentityForApp(app);
    }

    identity.version = 2;
    identity.role = lower(identity.role) || "main";
    identity.label = text(identity.label)
        || (identity.role === "agents" ? `${baseLabel(desktop, window)} Agents`
            : baseLabel(desktop, window));
    identity.exec = text(source.exec) || text(identity.exec) || text(desktop?.exec);
    identity.desktopPath = text(source.desktopPath) || text(identity.desktopPath)
        || text(desktop?.desktopPath);
    identity.icon = text(source.icon) || text(identity.icon) || text(desktop?.icon);
    identity.launchTarget = validLaunchTarget(source.launchTarget)
        || validLaunchTarget(identity.launchTarget)
        || (window ? workspaceTargetForWindow(window, recentUris) : null);
    return identity;
}

function pinKey(entry) {
    return canonicalKey(entry);
}

function launchArguments(identity, target) {
    const result = [];
    const key = canonicalKey(identity);
    if (key === "cursor::main")
        result.push("--classic");
    else if (key === "cursor::agents")
        result.push("--glass");
    const validTarget = validLaunchTarget(target);
    if (validTarget) {
        const value = validTarget.kind === "folderUri"
            && validTarget.value.startsWith("file://")
            ? decodeFileUri(validTarget.value)
            : validTarget.value;
        if (value)
            result.push(value);
    }
    return result;
}

function activationDecision(requestedIdentity, windows, desktop, recentUris) {
    const matches = filterWindowsForIdentity(requestedIdentity, windows, desktop);
    if (matches.length > 0)
        return { action: "focus", window: matches[0] };

    let target = validLaunchTarget(requestedIdentity?.launchTarget);
    if (!target && canonicalKey(requestedIdentity) === "cursor::main") {
        const first = text((recentUris || [])[0]);
        if (first)
            target = { kind: "folderUri", value: first };
    }
    return {
        action: "launch",
        launchTarget: target,
        desktopPath: text(requestedIdentity?.desktopPath || desktop?.desktopPath),
        exec: canonicalKey(requestedIdentity).startsWith("cursor::")
            ? "/usr/share/cursor/cursor"
            : text(requestedIdentity?.exec || desktop?.exec)
    };
}
