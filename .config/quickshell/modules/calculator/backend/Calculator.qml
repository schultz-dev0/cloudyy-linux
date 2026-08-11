pragma ComponentBehavior: Bound

// modules/calculator/backend/Calculator.qml
import QtQuick
import "CalculatorMath.js" as CalculatorMath

QtObject {
    id: calculator

    property string lastError: ""
    property bool hasError: lastError.length > 0

    function evaluate(expression) {
        lastError = "";
        if (!expression || expression.trim().length === 0) {
            lastError = "Empty expression";
            return null;
        }
        try {
            return CalculatorMath.evaluate(expression.trim());
        } catch (e) {
            lastError = String(e);
            return null;
        }
    }

    function formatResult(value) {
        return CalculatorMath.formatResult(value);
    }

    function isMathExpression(str) {
        return CalculatorMath.isMathExpression(str);
    }
}
