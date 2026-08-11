import QtQuick
import QtTest
import "../../../.config/quickshell/modules/calculator/backend/CalculatorMath.js" as Calc

TestCase {
    name: "CalculatorMath"

    function test_basicStillWorks() {
        compare(Calc.evaluate("2+3*4"), 14);
        compare(Calc.evaluate("(1+2)^2"), 9);
    }

    function test_functionsAndConstants() {
        compare(Calc.evaluate("sqrt(9)"), 3);
        compare(Calc.evaluate("abs(-4)"), 4);
        fuzzyCompare(Calc.evaluate("2*pi"), 2 * Math.PI, 1e-9);
        fuzzyCompare(Calc.evaluate("ln(e)"), 1, 1e-9);
        compare(Calc.evaluate("log(100)"), 2);
    }

    function test_friendlierSyntax() {
        compare(Calc.evaluate("2(3+4)"), 14);
        compare(Calc.evaluate("2×3"), 6);
        compare(Calc.evaluate("8÷2"), 4);
        compare(Calc.evaluate("50%"), 0.5);
        compare(Calc.evaluate("200*10%"), 20);
        fuzzyCompare(Calc.evaluate("2pi"), 2 * Math.PI, 1e-9);
        compare(Calc.evaluate("2sqrt(9)"), 6);
    }

    function test_isMathExpressionAllowlist() {
        verify(Calc.isMathExpression("sqrt(9)+1"));
        verify(Calc.isMathExpression("2pi"));
        verify(Calc.isMathExpression("50%"));
        verify(!Calc.isMathExpression("100 USD GBP"));
        verify(!Calc.isMathExpression("hello world"));
    }
}
