pragma ComponentBehavior: Bound

// modules/calculator/backend/Calculator.qml
import QtQuick

QtObject {
    id: calculator

    // ── Public Properties ─────────────────────────────────────────────────
    property string lastError: ""
    property bool hasError: lastError.length > 0

    // ── Mathematical Expression Evaluator ─────────────────────────────────
    // Safely evaluates mathematical expressions with proper precedence.
    // Supports: +, -, *, /, %, ^, parentheses, spaces
    function evaluate(expression) {
        lastError = "";
        
        if (!expression || expression.trim().length === 0) {
            lastError = "Empty expression";
            return null;
        }

        try {
            const result = evaluateExpression(expression.trim());
            return result;
        } catch (e) {
            lastError = String(e);
            return null;
        }
    }

    // ── Tokenizer ─────────────────────────────────────────────────────────
    function tokenize(expr) {
        const tokens = [];
        let i = 0;

        while (i < expr.length) {
            const char = expr[i];

            if (/\s/.test(char)) {
                i++;
                continue;
            }

            if (/[0-9.]/.test(char)) {
                let raw = "";
                let dotCount = 0;
                while (i < expr.length && /[0-9.]/.test(expr[i])) {
                    if (expr[i] === ".") {
                        dotCount++;
                        if (dotCount > 1)
                            throw new Error("Invalid number: " + raw + expr[i]);
                    }
                    raw += expr[i];
                    i++;
                }
                if (raw === "." || raw.endsWith("."))
                    throw new Error("Invalid number: " + raw);
                tokens.push({ type: "number", value: parseFloat(raw) });
            } else if (/[+\-*\/%^]/.test(char)) {
                tokens.push({ type: "operator", value: char });
                i++;
            } else if (char === "(" || char === ")") {
                tokens.push({ type: char === "(" ? "lparen" : "rparen", value: char });
                i++;
            } else {
                throw new Error("Invalid character: " + char);
            }
        }

        return tokens;
    }

    // ── Expression Parser with Precedence ─────────────────────────────────
    function evaluateExpression(expr) {
        const tokens = tokenize(expr);
        if (tokens.length === 0)
            throw new Error("Empty expression");

        let pos = 0;

        function peek() { return pos < tokens.length ? tokens[pos] : null; }
        function consume() { return tokens[pos++]; }

        // Precedence (low to high):
        //   + -   (additive)
        //   * / % (multiplicative)
        //   unary - +
        //   ^     (power, right-associative)
        //   primary

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
            const base = parsePrimary();
            if (peek() && peek().type === "operator" && peek().value === "^") {
                consume();
                const exp = parseUnary(); // right-associative: recurse via parseUnary
                return Math.pow(base, exp);
            }
            return base;
        }

        function parsePrimary() {
            const token = peek();
            if (!token)
                throw new Error("Unexpected end of expression");
            if (token.type === "number") {
                consume();
                return token.value;
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

    // ── Format Result ─────────────────────────────────────────────────────
    function formatResult(value) {
        if (value === null || value === undefined || !Number.isFinite(value))
            return "";
        const rounded = Math.round(value * 1e8) / 1e8;
        return rounded.toString();
    }

    // ── Detect whether a string looks like a math expression ──────────────
    // Requires: only numeric characters and operators (no letters), and at
    // least one binary operator between two digit sequences.
    function isMathExpression(str) {
        if (!str || str.trim().length === 0)
            return false;
        const s = str.trim();
        // Reject anything containing a letter — not a math expression
        if (/[a-zA-Z]/.test(s))
            return false;
        // Must contain only digits, operators, parens, spaces, and decimal points
        if (!/^[\d\s+\-*\/%^().]+$/.test(s))
            return false;
        // Must contain at least one operator that follows a digit or closing paren
        return /[\d)]\s*[+\-*\/%^]/.test(s) || /[+\-*\/%^]\s*[\d(]/.test(s) && /\d/.test(s);
    }
}
