.pragma library

// CurrencyParse.js — spotlight currency query parsing (codes, symbols, names)

const SYMBOL_TO_CODE = {
    "$": "USD",
    "€": "EUR",
    "£": "GBP",
    "¥": "JPY"
};

const NAME_TO_CODE = {
    "dollar": "USD",
    "dollars": "USD",
    "euro": "EUR",
    "euros": "EUR",
    "pound": "GBP",
    "pounds": "GBP",
    "yen": "JPY",
    "yuan": "CNY",
    "franc": "CHF",
    "francs": "CHF",
    "rupee": "INR",
    "rupees": "INR",
    "won": "KRW"
};

function _resolveToken(raw) {
    if (!raw)
        return null;
    const t = String(raw).trim();
    if (!t)
        return null;
    if (SYMBOL_TO_CODE[t])
        return SYMBOL_TO_CODE[t];
    const lower = t.toLowerCase();
    if (NAME_TO_CODE[lower])
        return NAME_TO_CODE[lower];
    if (/^[a-zA-Z]{3}$/.test(t))
        return t.toUpperCase();
    return null;
}

function _pair(amount, fromRaw, toRaw) {
    const from = _resolveToken(fromRaw);
    const to = _resolveToken(toRaw);
    if (!from || !to || from === to)
        return null;
    if (!Number.isFinite(amount))
        return null;
    return { amount: amount, from: from, to: to };
}

function parseQuery(str) {
    if (!str || String(str).trim().length === 0)
        return null;

    const s = String(str).trim();

    // $100 to EUR  |  €50 in gbp  |  £20 USD
    let m = s.match(/^([€$£¥])\s*(\d+(?:\.\d+)?)\s*(?:(?:to|in)\s+)?(.+)$/i);
    if (m)
        return _pair(parseFloat(m[2]), m[1], m[3]);

    // 100$ to eur
    m = s.match(/^(\d+(?:\.\d+)?)\s*([€$£¥])\s*(?:(?:to|in)\s+)?(.+)$/i);
    if (m)
        return _pair(parseFloat(m[1]), m[2], m[3]);

    // 100 USD GBP  |  100 usd to eur  |  100 dollars to euros
    m = s.match(/^(\d+(?:\.\d+)?)\s+([a-zA-Z]+)\s*(?:(?:to|in)\s+)?([a-zA-Z]+)$/i);
    if (m)
        return _pair(parseFloat(m[1]), m[2], m[3]);

    return null;
}

function isCurrencyQuery(str) {
    return parseQuery(str) !== null;
}
