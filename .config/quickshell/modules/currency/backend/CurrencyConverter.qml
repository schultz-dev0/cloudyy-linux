pragma ComponentBehavior: Bound

// modules/currency/backend/CurrencyConverter.qml
import QtQuick

QtObject {
    id: currencyConverter

    // Parse queries like "100 USD to EUR", "50 usd in eur", "25.5 GBP JPY"
    function parseQuery(str) {
        if (!str || str.trim().length === 0)
            return null;

        const m = str.trim().match(/^(\d+(?:\.\d+)?)\s*([a-zA-Z]{3})\s*(?:(?:to|in)\s+)?([a-zA-Z]{3})$/i);
        if (!m)
            return null;

        const from = m[2].toUpperCase();
        const to = m[3].toUpperCase();
        if (from === to)
            return null;

        return {
            amount: parseFloat(m[1]),
            from: from,
            to: to
        };
    }

    function isCurrencyQuery(str) {
        return parseQuery(str) !== null;
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
        const line = `${formatAmount(amount)} ${from} = ${formatAmount(converted)} ${to}`;
        if (!date)
            return line;
        return line;
    }

    function formatSubtitle(amount, from, to, rate, date) {
        const rateText = Number.isFinite(rate)
            ? `1 ${from} = ${formatAmount(rate)} ${to}`
            : "";
        if (date && rateText)
            return `${rateText} · ${date}`;
        return rateText || date || "";
    }
}
