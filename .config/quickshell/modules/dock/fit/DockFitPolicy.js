.pragma library

function fitScale(screenWidth, scalableWidth, fixedWidth, edgeMargin) {
    const screen = Number(screenWidth);
    const scalable = Number(scalableWidth);
    if (!Number.isFinite(screen) || screen <= 0
            || !Number.isFinite(scalable) || scalable <= 0)
        return 1;

    const fixedValue = Number(fixedWidth);
    const marginValue = Number(edgeMargin);
    const fixed = Number.isFinite(fixedValue) ? Math.max(0, fixedValue) : 0;
    const margin = Number.isFinite(marginValue) ? Math.max(0, marginValue) : 0;
    return Math.max(0, Math.min(1,
        (screen - margin * 2 - fixed) / scalable));
}
