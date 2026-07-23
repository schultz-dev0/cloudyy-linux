.pragma library

function build(clients) {
    const list = Array.isArray(clients) ? clients.slice() : [];
    const byAddress = {};
    const byWorkspace = {};
    const addresses = [];
    for (const window of list) {
        const address = `${window?.address ?? ""}`;
        if (address.length > 0) {
            byAddress[address] = window;
            addresses.push(address);
        }
        const workspaceId = Math.trunc(Number(window?.workspace?.id));
        if (Number.isFinite(workspaceId) && workspaceId > 0) {
            if (!byWorkspace[workspaceId])
                byWorkspace[workspaceId] = [];
            byWorkspace[workspaceId].push(window);
        }
    }
    return {
        windowList: list,
        windowByAddress: byAddress,
        windowsByWorkspace: byWorkspace,
        addresses: addresses
    };
}

function resolveCached(cache, key, resolver) {
    const normalizedKey = `${key ?? ""}`;
    if (Object.prototype.hasOwnProperty.call(cache, normalizedKey))
        return cache[normalizedKey];
    const value = resolver();
    cache[normalizedKey] = value;
    return value;
}
