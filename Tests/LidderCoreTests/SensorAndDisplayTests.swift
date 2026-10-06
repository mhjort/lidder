import Testing
@testable import LidderCore

@Suite struct ReportDecodingTests {

    @Test func decodesLittleEndianAngle() throws {
        #expect(try LidAngleSensor.decodeAngle([1, 0x7E, 0x00, 0, 0, 0, 0, 0], length: 8) == 126)
        #expect(try LidAngleSensor.decodeAngle([1, 0x2C, 0x01, 0, 0, 0, 0, 0], length: 8) == 300)
        #expect(try LidAngleSensor.decodeAngle([1, 0x00, 0x00], length: 3) == 0)
    }

    @Test func shortReportThrows() {
        #expect(throws: LidAngleSensor.SensorError.shortReport(2)) {
            try LidAngleSensor.decodeAngle([1, 0x7E, 0, 0, 0, 0, 0, 0], length: 2)
        }
    }
}

@Suite struct DisplayTests {

    @Test func gaugeIsAlwaysThirtyCells() {
        for angle in stride(from: -20.0, through: 200, by: 7) {
            #expect(gauge(for: angle).count == 30)
        }
    }

    @Test func gaugeFill() {
        #expect(gauge(for: 0) == String(repeating: "░", count: 30))
        #expect(gauge(for: 90) == String(repeating: "█", count: 15) + String(repeating: "░", count: 15))
        #expect(gauge(for: 180) == String(repeating: "█", count: 30))
    }

    @Test func gaugeClampsOutOfRange() {
        #expect(gauge(for: -10) == gauge(for: 0))
        #expect(gauge(for: 250) == gauge(for: 180))
    }

    @Test(arguments: [
        (0.0, "closed"), (4.9, "closed"),
        (5.0, "slightly open"), (44.9, "slightly open"),
        (45.0, "partially open"), (89.9, "partially open"),
        (90.0, "mostly open"), (119.9, "mostly open"),
        (120.0, "fully open"), (180.0, "fully open"),
    ])
    func labels(angle: Double, label: String) {
        #expect(describe(angle) == label)
    }
}
