import Foundation
import IOKit
import IOKit.hid

/// Reads the MacBook lid angle from the Apple lid-angle HID sensor.
///
/// Mirrors the approach used by samhenrigold/LidAngleSensor:
/// match the Apple sensor HID device, open it, and read an 8-byte
/// feature report (report ID 1) whose bytes[1..2] are a little-endian
/// uint16 lid angle in degrees.
final class LidAngleSensor {

    enum SensorError: Error, CustomStringConvertible {
        case deviceNotFound
        case openFailed(IOReturn)
        case readFailed(IOReturn)
        case shortReport(Int)

        var description: String {
            switch self {
            case .deviceNotFound:
                return "Lid angle sensor not found. This requires a MacBook with a lid angle sensor (e.g. Apple Silicon, recent models). Tested working on M4; M1/M2 may not be supported."
            case .openFailed(let r):
                return "Failed to open HID device (IOReturn 0x\(String(r, radix: 16)))."
            case .readFailed(let r):
                return "Failed to read feature report (IOReturn 0x\(String(r, radix: 16)))."
            case .shortReport(let n):
                return "Feature report too short (\(n) bytes)."
            }
        }
    }

    // Apple lid angle sensor identifiers.
    private static let vendorID = 0x05AC      // Apple
    private static let productID = 0x8104     // Lid angle sensor
    private static let usagePage = 0x0020     // Sensor
    private static let usage = 0x008A         // Orientation

    private static let reportID: CFIndex = 1
    private static let reportLength = 8
    private static let noOptions = IOOptionBits(kIOHIDOptionsTypeNone)

    private let device: IOHIDDevice
    private var isOpen = false
    private var report = [UInt8](repeating: 0, count: reportLength)

    init() throws {
        guard let device = LidAngleSensor.findDevice() else {
            throw SensorError.deviceNotFound
        }
        self.device = device
    }

    deinit {
        if isOpen {
            IOHIDDeviceClose(device, LidAngleSensor.noOptions)
        }
    }

    func open() throws {
        guard !isOpen else { return }
        let result = IOHIDDeviceOpen(device, LidAngleSensor.noOptions)
        guard result == kIOReturnSuccess else {
            throw SensorError.openFailed(result)
        }
        isOpen = true
    }

    /// Reads the current lid angle in degrees.
    func readAngle() throws -> Double {
        var length = CFIndex(report.count)
        let result = IOHIDDeviceGetReport(
            device,
            kIOHIDReportTypeFeature,
            LidAngleSensor.reportID,
            &report,
            &length
        )
        guard result == kIOReturnSuccess else {
            throw SensorError.readFailed(result)
        }
        guard length >= 3 else {
            throw SensorError.shortReport(length)
        }
        let raw = UInt16(report[2]) << 8 | UInt16(report[1])
        return Double(raw)
    }

    // MARK: - Device discovery

    private static func findDevice() -> IOHIDDevice? {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, noOptions)
        IOHIDManagerOpen(manager, noOptions)
        defer { IOHIDManagerClose(manager, noOptions) }

        // Strategy 1: full match on the standard sensor page.
        let standardMatch: [String: Any] = [
            kIOHIDVendorIDKey as String: vendorID,
            kIOHIDProductIDKey as String: productID,
            kIOHIDDeviceUsagePageKey as String: usagePage,
            kIOHIDDeviceUsageKey as String: usage,
        ]
        if let device = firstUsableDevice(manager: manager, matching: standardMatch) {
            return device
        }

        // Strategy 2: vendor-specific fallback — match by product ID alone.
        let fallbackMatch: [String: Any] = [
            kIOHIDVendorIDKey as String: vendorID,
            kIOHIDProductIDKey as String: productID,
        ]
        return firstUsableDevice(manager: manager, matching: fallbackMatch)
    }

    /// Applies a matching dictionary and returns the first device that
    /// actually responds to the lid-angle feature report.
    private static func firstUsableDevice(manager: IOHIDManager, matching: [String: Any]) -> IOHIDDevice? {
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        guard let set = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else {
            return nil
        }
        for device in set {
            guard IOHIDDeviceOpen(device, noOptions) == kIOReturnSuccess else { continue }
            var buffer = [UInt8](repeating: 0, count: reportLength)
            var length = CFIndex(buffer.count)
            let result = IOHIDDeviceGetReport(
                device,
                kIOHIDReportTypeFeature,
                reportID,
                &buffer,
                &length
            )
            IOHIDDeviceClose(device, noOptions)
            if result == kIOReturnSuccess && length >= 3 {
                return device
            }
        }
        return nil
    }
}
