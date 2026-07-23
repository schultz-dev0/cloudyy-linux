.pragma library

function cubic(t, p1, p2) {
    const u = 1 - t;
    return 3 * u * u * t * p1 + 3 * u * t * t * p2 + t * t * t;
}

function solveT(x, x1, x2) {
    let t = x;
    for (let i = 0; i < 20; i++) {
        const fx = cubic(t, x1, x2);
        const dx = 3 * (1 - t) * (1 - t) * x1
            + 6 * (1 - t) * t * (x2 - x1)
            + 3 * t * t * (1 - x2);
        if (Math.abs(dx) < 1e-6)
            break;
        t -= (fx - x) / dx;
        if (t < 0) t = 0;
        if (t > 1) t = 1;
    }
    return t;
}

function ease(p, x1, y1, x2, y2) {
    return cubic(solveT(p, x1, x2), y1, y2);
}

function clamp01(v) {
    return Math.max(0, Math.min(1, v));
}

function round3(v) {
    return Math.round(Number(v) * 1000) / 1000;
}

function pointsEqual(a, b) {
    if (!a || !b || a.length !== 4 || b.length !== 4)
        return false;
    for (let i = 0; i < 4; i++) {
        if (Math.abs(Number(a[i]) - Number(b[i])) > 0.0005)
            return false;
    }
    return true;
}
