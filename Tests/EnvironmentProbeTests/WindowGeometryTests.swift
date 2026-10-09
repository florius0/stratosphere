import Foundation
import Testing
@testable import EnvironmentProbe

struct WindowGeometryTests {
    @Test func preservesNegativeDisplayCoordinatesInFailureEvidence() {
        let desired = CGRect(x: -1370, y: -710, width: 560, height: 360)
        let actual = CGRect(x: -1370, y: 90, width: 560, height: 360)
        #expect(!WindowGeometry.matches(actual, desired))
        let evidence = WindowGeometry.values(actual)
        #expect(evidence["x"] == -1370)
        #expect(evidence["y"] == 90)
        #expect(evidence["width"] == 560)
    }
    @Test func retainsExistingStrictTwoPointTolerance() {
        let desired = CGRect(x: -1370, y: 90, width: 560, height: 360)
        #expect(WindowGeometry.matches(desired.offsetBy(dx: 1.99, dy: 0), desired))
        #expect(!WindowGeometry.matches(desired.offsetBy(dx: 2, dy: 0), desired))
        var resized = desired
        resized.size.width += 3
        #expect(!WindowGeometry.matches(resized, desired))
    }
}
