import QtQuick
import QtTest
import "../../../.config/quickshell/modules/currency/backend/CurrencyParse.js" as Currency

TestCase {
    name: "CurrencyParse"

    function test_codesOptionalTo() {
        const a = Currency.parseQuery("1440 USD GBP");
        compare(a.amount, 1440);
        compare(a.from, "USD");
        compare(a.to, "GBP");

        const b = Currency.parseQuery("100 usd to eur");
        compare(b.from, "USD");
        compare(b.to, "EUR");
    }

    function test_symbols() {
        const a = Currency.parseQuery("$100 to EUR");
        compare(a.amount, 100);
        compare(a.from, "USD");
        compare(a.to, "EUR");

        const b = Currency.parseQuery("€50 in gbp");
        compare(b.amount, 50);
        compare(b.from, "EUR");
        compare(b.to, "GBP");

        const c = Currency.parseQuery("100$ to eur");
        compare(c.amount, 100);
        compare(c.from, "USD");
        compare(c.to, "EUR");
    }

    function test_commonNames() {
        const a = Currency.parseQuery("100 dollars to euros");
        compare(a.amount, 100);
        compare(a.from, "USD");
        compare(a.to, "EUR");

        const b = Currency.parseQuery("50 pounds in usd");
        compare(b.from, "GBP");
        compare(b.to, "USD");
    }

    function test_rejectsQuidAndSameCurrency() {
        compare(Currency.parseQuery("100 quid to usd"), null);
        compare(Currency.parseQuery("10 USD USD"), null);
        compare(Currency.parseQuery("hello"), null);
    }
}
