import QtQuick
import QtTest
import "../../../../.config/quickshell/cloud-center/components/BezierMath.js" as BezierMath

TestCase {
    name: "BezierMath"

    function test_linear_ease() {
        fuzzyCompare(BezierMath.ease(0.5, 0, 0, 1, 1), 0.5, 0.01);
        compare(BezierMath.clamp01(1.5), 1);
        compare(BezierMath.round3(0.1234), 0.123);
    }

    function test_points_equal() {
        compare(BezierMath.pointsEqual([0.1, 0.2, 0.3, 0.4], [0.1, 0.2, 0.3, 0.4]), true);
        compare(BezierMath.pointsEqual([0.1, 0.2, 0.3, 0.4], [0.1, 0.2, 0.3, 0.5]), false);
    }
}
