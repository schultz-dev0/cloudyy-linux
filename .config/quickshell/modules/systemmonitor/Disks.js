.pragma library

// Disks.js — pure helpers for the System monitor's storage list. No QML
// types so node can test it: `node test_disks.js`.

// Mounts on one filesystem (btrfs @ and @home) report identical numbers;
// show that filesystem once, under its first mountpoint (rule 8).
// ponytail: no device field in cloudyy-system-monitor's JSON, so identical
// used/total stands in for "same filesystem". Ceiling: two different disks
// with identical used and total would merge. Upgrade: emit the backing
// device from the binary and key on that.
function unique(disks) {
    const seen = {};
    const out = [];
    for (let i = 0; i < disks.length; i++) {
        const d = disks[i];
        const key = d.used_gb + "/" + d.total_gb;
        if (seen[key])
            continue;
        seen[key] = true;
        out.push(d);
    }
    return out;
}
