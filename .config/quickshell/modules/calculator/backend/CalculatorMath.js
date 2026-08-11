.pragma library

// CalculatorMath.js — spotlight math evaluator (ops, functions, friendly syntax)

const FUNCTIONS = {
    "sqrt": Math.sqrt,
    "abs": Math.abs,
    "sin": Math.sin,
    "cos": Math.cos,
    "tan": Math.tan,
    "log": function (x) { return Math.log10(x); },
    "ln": Math.log,
    "floor": Math.floor,
    "ceil": Math.ceil,
    "round": Math.round
};

const CONSTANTS = {
    "pi": Math.PI,
    "e": Math.E
};

function evaluate(expression) {
    if (!expression || String(expression).trim().length === 0)
        throw new Error("Empty expression");
    return evaluateExpression(String(expression).trim());
}

function formatResult(value) {
    if (value === null || value === undefined || !Number.isFinite(value))
        return "";
    const rounded = Math.round(value * 1e8) / 1e8;
    return rounded.toString();
}

function isMathExpression(str) {
    if (!str || String(str).trim().length === 0)
        return false;
    const s = String(str).trim();
    if (isCurrencyLooking(s))
        return false;
    try {
        tokenize(s);
        return /[\d)pi e!]/.test(s.toLowerCase()) && (
            /[\d)]\s*[+\-*\/%^×÷·]/.test(s)
            || /[+\-*\/%^×÷·]\s*[\d(]/.test(s)
            || /(?:sqrt|abs|sin|cos|tan|log|ln|floor|ceil|round)\s*\(/i.test(s)
            || /(?:pi|e)\b/i.test(s)
            || /%/.test(s)
            || /!/.test(s)
            || /\d\s*\(/.test(s)
            || /\)\s*\d/.test(s)
            || /\)\s*\(/.test(s)
            || /\d(?:pi|e)\b/i.test(s)
            || /(?:pi|e)\s*\(/i.test(s)
        );
    } catch (e) {
        return false;
    }
}

function isCurrencyLooking(s) {
    if (/[€$£¥]/.test(s))
        return true;
    if (/\b(?:to|in)\b/i.test(s) && /[a-zA-Z]{3}/.test(s))
        return true;
    if (/^\d+(?:\.\d+)?\s+[a-zA-Z]{3}\s+[a-zA-Z]{3}$/i.test(s))
        return true;
    if (/\b(?:dollars?|euros?|pounds?|yen|yuan|francs?|rupees?|won)\b/i.test(s))
        return true;
    return false;
}

function tokenize(expr) {
    const tokens = [];
    let i = 0;
    const s = expr;

    function prevType() {
        return tokens.length ? tokens[tokens.length - 1].type : null;
    }

    function maybeImplicitMultiply() {
        const prev = prevType();
        if (prev === "number" || prev === "rparen" || prev === "constant" || prev === "percent" || prev === "factorial")
            tokens.push({ type: "operator", value: "*" });
    }

    while (i < s.length) {
        const char = s[i];

        if (/\s/.test(char)) {
            i++;
            continue;
        }

        if (char === "×" || char === "·") {
            tokens.push({ type: "operator", value: "*" });
            i++;
            continue;
        }
        if (char === "÷") {
            tokens.push({ type: "operator", value: "/" });
            i++;
            continue;
        }

        if (/[0-9.]/.test(char)) {
            maybeImplicitMultiply();
            let raw = "";
            let dotCount = 0;
            while (i < s.length && /[0-9.]/.test(s[i])) {
                if (s[i] === ".") {
                    dotCount++;
                    if (dotCount > 1)
                        throw new Error("Invalid number: " + raw + s[i]);
                }
                raw += s[i];
                i++;
            }
            if (raw === "." || raw.endsWith("."))
                throw new Error("Invalid number: " + raw);
            tokens.push({ type: "number", value: parseFloat(raw) });
            continue;
        }

        if (/[a-zA-Z]/.test(char)) {
            let name = "";
            while (i < s.length && /[a-zA-Z]/.test(s[i])) {
                name += s[i];
                i++;
            }
            const lower = name.toLowerCase();
            if (FUNCTIONS[lower]) {
                maybeImplicitMultiply();
                tokens.push({ type: "function", value: lower });
            } else if (CONSTANTS[lower] !== undefined) {
                maybeImplicitMultiply();
                tokens.push({ type: "constant", value: CONSTANTS[lower] });
            } else {
                throw new Error("Unknown identifier: " + name);
            }
            continue;
        }

        if (char === "%") {
            tokens.push({ type: "percent", value: "%" });
            i++;
            continue;
        }

        if (char === "!") {
            tokens.push({ type: "factorial", value: "!" });
            i++;
            continue;
        }

        if (/[+\-*/^]/.test(char)) {
            tokens.push({ type: "operator", value: char });
            i++;
            continue;
        }

        if (char === "(") {
            maybeImplicitMultiply();
            tokens.push({ type: "lparen", value: "(" });
            i++;
            continue;
        }
        if (char === ")") {
            tokens.push({ type: "rparen", value: ")" });
            i++;
            continue;
        }

        throw new Error("Invalid character: " + char);
    }

    return tokens;
}

function factorial(n) {
    if (!Number.isFinite(n) || n < 0 || Math.floor(n) !== n)
        throw new Error("Factorial requires non-negative integer");
    if (n > 170)
        throw new Error("Factorial too large");
    let r = 1;
    for (let i = 2; i <= n; i++)
        r *= i;
    return r;
}

function evaluateExpression(expr) {
    const tokens = tokenize(expr);
    if (tokens.length === 0)
        throw new Error("Empty expression");

    let pos = 0;

    function peek() { return pos < tokens.length ? tokens[pos] : null; }
    function consume() { return tokens[pos++]; }

    function parseExpression() {
        let result = parseAdditive();
        if (pos < tokens.length)
            throw new Error("Unexpected token: " + peek().value);
        return result;
    }

    function parseAdditive() {
        let result = parseMultiplicative();
        while (peek() && peek().type === "operator"
               && (peek().value === "+" || peek().value === "-")) {
            const op = consume().value;
            const right = parseMultiplicative();
            result = op === "+" ? result + right : result - right;
        }
        return result;
    }

    function parseMultiplicative() {
        let result = parseUnary();
        while (peek() && peek().type === "operator"
               && (peek().value === "*" || peek().value === "/" || peek().value === "%")) {
            const op = consume().value;
            const right = parseUnary();
            if (op === "/") {
                if (right === 0) throw new Error("Division by zero");
                result = result / right;
            } else if (op === "%") {
                if (right === 0) throw new Error("Modulo by zero");
                result = result % right;
            } else {
                result = result * right;
            }
        }
        return result;
    }

    function parseUnary() {
        const token = peek();
        if (token && token.type === "operator"
            && (token.value === "-" || token.value === "+")) {
            const op = consume().value;
            return op === "-" ? -parsePower() : parsePower();
        }
        return parsePower();
    }

    function parsePower() {
        const base = parsePostfix();
        if (peek() && peek().type === "operator" && peek().value === "^") {
            consume();
            const exp = parseUnary();
            return Math.pow(base, exp);
        }
        return base;
    }

    function parsePostfix() {
        let result = parsePrimary();
        while (peek() && (peek().type === "percent" || peek().type === "factorial")) {
            const t = consume();
            if (t.type === "percent")
                result = result / 100;
            else
                result = factorial(result);
        }
        return result;
    }

    function parsePrimary() {
        const token = peek();
        if (!token)
            throw new Error("Unexpected end of expression");

        if (token.type === "number" || token.type === "constant") {
            consume();
            return token.value;
        }

        if (token.type === "function") {
            const name = consume().value;
            if (!peek() || peek().type !== "lparen")
                throw new Error("Expected '(' after " + name);
            consume();
            const arg = parseAdditive();
            if (!peek() || peek().type !== "rparen")
                throw new Error("Missing closing parenthesis");
            consume();
            const fn = FUNCTIONS[name];
            const out = fn(arg);
            if (!Number.isFinite(out))
                throw new Error("Invalid result from " + name);
            return out;
        }

        if (token.type === "lparen") {
            consume();
            const result = parseAdditive();
            if (!peek() || peek().type !== "rparen")
                throw new Error("Missing closing parenthesis");
            consume();
            return result;
        }

        throw new Error("Unexpected token: " + token.value);
    }

    return parseExpression();
}
