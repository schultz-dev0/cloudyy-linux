pragma ComponentBehavior: Bound

// modules/currency/backend/CurrencyConverter.qml
import QtQuick
import "CurrencyParse.js" as CurrencyParse

QtObject {
    id: currencyConverter

    // from|to → { rate, date, fetchedAt }
    property var rateCache: ({})

    function parseQuery(str) {
        return CurrencyParse.parseQuery(str);
    }

    function isCurrencyQuery(str) {
        return CurrencyParse.isCurrencyQuery(str);
    }

    function cacheKey(from, to) {
        return from + "|" + to;
    }

    function getCachedRate(from, to) {
        const key = cacheKey(from, to);
        const hit = rateCache[key];
        if (!hit || !Number.isFinite(hit.rate))
            return null;
        return hit;
    }

    function rememberRate(from, to, rate, date) {
        if (!Number.isFinite(rate))
            return;
        const next = Object.assign({}, rateCache);
        next[cacheKey(from, to)] = {
            rate: rate,
            date: date || "",
            fetchedAt: Date.now()
        };
        rateCache = next;
    }

    function convertCached(amount, from, to) {
        const hit = getCachedRate(from, to);
        if (!hit)
            return null;
        return {
            amount: amount,
            from: from,
            to: to,
            converted: amount * hit.rate,
            rate: hit.rate,
            date: hit.date || "",
            cached: true
        };
    }

    function formatAmount(value) {
        if (!Number.isFinite(value))
            return "";
        const abs = Math.abs(value);
        if (abs >= 1e6 || (abs > 0 && abs < 0.01))
            return value.toPrecision(6).replace(/\.?0+$/, "");
        return (Math.round(value * 1e4) / 1e4).toString();
    }

    function formatResult(amount, from, to, converted, date) {
        return `${formatAmount(amount)} ${from} = ${formatAmount(converted)} ${to}`;
    }

    function formatSubtitle(amount, from, to, rate, date, extra) {
        const rateText = Number.isFinite(rate)
            ? `1 ${from} = ${formatAmount(rate)} ${to}`
            : "";
        const bits = [];
        if (rateText)
            bits.push(rateText);
        if (date)
            bits.push(date);
        if (extra)
            bits.push(extra);
        return bits.join(" · ");
    }
}
