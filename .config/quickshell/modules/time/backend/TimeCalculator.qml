pragma ComponentBehavior: Bound

// modules/time/backend/TimeCalculator.qml
import QtQuick

QtObject {
    id: timeCalculator

    property string lastError: ""
    property bool hasError: lastError.length > 0

    readonly property var _unitSeconds: ({
        "h": 3600, "hr": 3600, "hrs": 3600, "hour": 3600, "hours": 3600,
        "m": 60, "min": 60, "mins": 60, "minute": 60, "minutes": 60,
        "s": 1, "sec": 1, "secs": 1, "second": 1, "seconds": 1
    })

    readonly property var _unitPattern: /(\d+(?:\.\d+)?)\s*(hours?|hrs?|h|minutes?|mins?|min|m|seconds?|secs?|sec|s)/gi

    function _unitMultiplier(unit) {
        return _unitSeconds[String(unit).toLowerCase()] ?? null;
    }

    function _detectUnit(term) {
        const m = String(term).match(/(\d+(?:\.\d+)?)\s*(hours?|hrs?|h|minutes?|mins?|min|m|seconds?|secs?|sec|s)/i);
        if (!m)
            return null;
        return _unitMultiplier(m[2]);
    }

    function _parseColonTerm(term) {
        const m = String(term).trim().match(/^(\d+):(\d{1,2})(?::(\d{1,2}))?$/);
        if (!m)
            return null;

        const a = parseInt(m[1], 10);
        const b = parseInt(m[2], 10);
        if (!Number.isFinite(a) || !Number.isFinite(b) || b >= 60)
            return null;

        if (m[3] !== undefined) {
            const c = parseInt(m[3], 10);
            if (!Number.isFinite(c) || c >= 60)
                return null;
            return a * 3600 + b * 60 + c;
        }

        return a * 60 + b;
    }

    function _parseUnitTerm(term) {
        const s = String(term).trim();
        if (!s)
            return null;

        const re = new RegExp(_unitPattern.source, "gi");
        let total = 0;
        let matched = 0;
        let lastIndex = 0;
        let m;

        while ((m = re.exec(s)) !== null) {
            const gap = s.substring(lastIndex, m.index);
            if (!/^\s*$/.test(gap))
                return null;
            const mult = _unitMultiplier(m[2]);
            if (!mult)
                return null;
            total += parseFloat(m[1]) * mult;
            matched++;
            lastIndex = re.lastIndex;
        }

        if (matched === 0)
            return null;
        if (s.substring(lastIndex).trim() !== "")
            return null;
        return total;
    }

    function _parseTerm(term, defaultUnit) {
        const s = String(term).trim();
        if (!s)
            return null;

        const colon = _parseColonTerm(s);
        if (colon !== null)
            return colon;

        const units = _parseUnitTerm(s);
        if (units !== null)
            return units;

        const bare = s.match(/^(\d+(?:\.\d+)?)$/);
        if (bare && defaultUnit)
            return parseFloat(bare[1]) * defaultUnit;

        return null;
    }

    function _splitExpression(expr) {
        return String(expr).trim().split(/\s*([+\-])\s*/).filter(p => p.length > 0);
    }

    function _looksLikeTime(expr) {
        const s = String(expr).trim();
        if (!/[+\-]/.test(s))
            return false;
        return /\d{1,2}:\d{1,2}(?::\d{1,2})?/.test(s)
            || /\d+(?:\.\d+)?\s*(?:hours?|hrs?|h|minutes?|mins?|min|m|seconds?|secs?|sec|s)\b/i.test(s);
    }

    function evaluate(expression) {
        lastError = "";
        if (!expression || String(expression).trim().length === 0) {
            lastError = "Empty expression";
            return null;
        }

        const parts = _splitExpression(expression);
        if (parts.length < 3 || parts.length % 2 === 0) {
            lastError = "Invalid time expression";
            return null;
        }

        let defaultUnit = null;
        for (let i = 0; i < parts.length; i += 2) {
            const u = _detectUnit(parts[i]);
            if (u) {
                defaultUnit = u;
                break;
            }
        }

        let total = _parseTerm(parts[0], defaultUnit);
        if (total === null) {
            lastError = "Invalid time term: " + parts[0];
            return null;
        }

        for (let i = 1; i < parts.length; i += 2) {
            const op = parts[i];
            const term = _parseTerm(parts[i + 1], defaultUnit);
            if (term === null) {
                lastError = "Invalid time term: " + parts[i + 1];
                return null;
            }
            total = op === "+" ? total + term : total - term;
        }

        return total;
    }

    function isTimeExpression(str) {
        if (!str || String(str).trim().length === 0)
            return false;
        if (!_looksLikeTime(str))
            return false;
        return evaluate(str) !== null;
    }

    function _pad2(n) {
        return n < 10 ? "0" + n : String(n);
    }

    function formatResult(totalSeconds) {
        if (totalSeconds === null || totalSeconds === undefined || !Number.isFinite(totalSeconds))
            return "";

        const negative = totalSeconds < 0;
        let secs = Math.round(Math.abs(totalSeconds));
        const h = Math.floor(secs / 3600);
        secs %= 3600;
        const m = Math.floor(secs / 60);
        const s = secs % 60;

        const parts = [];
        if (h > 0)
            parts.push(h + "h");
        if (m > 0)
            parts.push(m + "m");
        if (s > 0 || parts.length === 0)
            parts.push(s + "s");

        const text = parts.join(" ");
        return negative ? "-" + text : text;
    }

    function formatSubtitle(totalSeconds) {
        if (totalSeconds === null || totalSeconds === undefined || !Number.isFinite(totalSeconds))
            return "";

        const negative = totalSeconds < 0;
        let secs = Math.round(Math.abs(totalSeconds));
        const h = Math.floor(secs / 3600);
        secs %= 3600;
        const m = Math.floor(secs / 60);
        const s = secs % 60;

        let clock;
        if (h > 0)
            clock = h + ":" + _pad2(m) + ":" + _pad2(s);
        else
            clock = m + ":" + _pad2(s);

        const totalMin = Math.round(Math.abs(totalSeconds) / 60);
        const detail = totalMin > 0 ? totalMin + " min total" : Math.abs(totalSeconds) + " sec total";
        return (negative ? "-" : "") + clock + " · " + detail;
    }
}
