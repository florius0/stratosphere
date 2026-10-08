import AppKit
import DisplayProbeBridge

struct DisplayObservation: Equatable {
    var id: CGDirectDisplayID
    var uuid: String
    var bounds: CGRect
    var pixels: CGSize
    var logical: CGSize
    var refresh: Double
    var mirrored: Bool
    var main: Bool
    var vendor: UInt32
    var product: UInt32
    var serial: UInt32
    var json: [String: Any] {
        ["id": id, "uuid": uuid, "bounds": ["x": bounds.minX, "y": bounds.minY, "width": bounds.width, "height": bounds.height],
         "pixels": ["width": pixels.width, "height": pixels.height], "logical": ["width": logical.width, "height": logical.height],
         "refresh_hz": refresh, "mirrored": mirrored, "main": main, "vendor": vendor, "product": product, "serial": serial]
    }
}
@MainActor final class DisplayQualification {
    private(set) var baseline: [DisplayObservation]
    private var owned: [STVirtualDisplay] = []
    private(set) var evidence: [[String: Any]] = []
    init() throws {
        baseline = try Self.observe(kind: .setup)
        guard !baseline.isEmpty, baseline.contains(where: \.main), baseline.allSatisfy({ !$0.mirrored }) else {
            throw ProbeFailure("Probe requires an existing nonmirrored base desktop.")
        }
    }
    static func observe(kind: FailureKind = .assertion) throws -> [DisplayObservation] {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success else { throw ProbeFailure("Cannot read display topology", kind: kind) }
        var identifiers = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &identifiers, &count) == .success else { throw ProbeFailure("Cannot read display topology", kind: kind) }
        return try identifiers.prefix(Int(count)).sorted().map { id in
            guard let mode = CGDisplayCopyDisplayMode(id), let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue(), let text = CFUUIDCreateString(nil, uuid) else { throw ProbeFailure("Display mode/UUID unavailable for \(id)", kind: kind) }
            return DisplayObservation(id: id, uuid: text as String, bounds: CGDisplayBounds(id), pixels: CGSize(width: mode.pixelWidth, height: mode.pixelHeight), logical: CGSize(width: mode.width, height: mode.height), refresh: mode.refreshRate,
                                      mirrored: CGDisplayIsInMirrorSet(id) != 0, main: CGDisplayIsMain(id) != 0,
                                      vendor: CGDisplayVendorNumber(id), product: CGDisplayModelNumber(id), serial: CGDisplaySerialNumber(id))
        }
    }
    private func create(width: UInt32, height: UInt32, hiDPI: Bool, serial: UInt32) throws -> STVirtualDisplay {
        let display: STVirtualDisplay
        do { display = try STVirtualDisplay.create(withWidth: width, height: height, hiDPI: hiDPI, serial: serial) }
        catch { throw ProbeFailure("Virtual-display capability unavailable: \(error)", kind: .setup) }
        owned.append(display)
        try SystemObservation.wait("virtual display \(display.displayID) to become active") {
            try Self.observe(kind: .setup).contains(where: { $0.id == display.displayID && CGDisplayIsActive($0.id) != 0 })
        }
        return display
    }
    private func configure(_ origins: [CGDirectDisplayID: CGPoint]) throws {
        var configuration: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&configuration) == .success, let configuration else { throw ProbeFailure("Display configuration unavailable") }
        var completed = false
        defer { if !completed { CGCancelDisplayConfiguration(configuration) } }
        for (id, point) in origins {
            guard CGConfigureDisplayMirrorOfDisplay(configuration, id, kCGNullDirectDisplay) == .success,
                  CGConfigureDisplayOrigin(configuration, id, Int32(point.x), Int32(point.y)) == .success else { throw ProbeFailure("Cannot configure extended display origins", kind: .assertion) }
        }
        guard CGCompleteDisplayConfiguration(configuration, .forSession) == .success else { throw ProbeFailure("Display configuration rejected", kind: .assertion) }
        completed = true
        try SystemObservation.wait("observed display arrangement", kind: .assertion) {
            let topology = try Self.observe()
            return origins.allSatisfy { id, point in topology.contains { $0.id == id && $0.bounds.origin == point && !$0.mirrored } }
        }
    }
    func qualify(placeWindows: (CGDirectDisplayID, CGDirectDisplayID) throws -> Void) throws {
        evidence.append(["phase": "baseline", "displays": baseline.map(\.json)])
        let a = try create(width: 1440, height: 900, hiDPI: false, serial: 791101)
        let b = try create(width: 2560, height: 1600, hiDPI: true, serial: 791102)
        let initial = try Self.observe()
        guard initial.count == baseline.count + 2, baseline.allSatisfy({ original in initial.contains(where: { $0.id == original.id }) }),
              let oa = initial.first(where: { $0.id == a.displayID }), let ob = initial.first(where: { $0.id == b.displayID }),
              oa.logical == CGSize(width: 1440, height: 900), oa.pixels == oa.logical,
              ob.logical == CGSize(width: 1280, height: 800), ob.pixels == CGSize(width: 2560, height: 1600) else {
            throw ProbeFailure("Virtual displays did not expose the required native modes/densities or retain base monitors", kind: .assertion)
        }
        var origins = Dictionary(uniqueKeysWithValues: baseline.map { ($0.id, $0.bounds.origin) })
        origins[a.displayID] = CGPoint(x: (baseline.map { $0.bounds.minX }.min() ?? 0) - oa.bounds.width, y: 0)
        origins[b.displayID] = CGPoint(x: 0, y: (baseline.map { $0.bounds.minY }.min() ?? 0) - ob.bounds.height)
        try configure(origins)
        evidence.append(["phase": "left-and-above", "displays": try Self.observe().map(\.json)])
        try placeWindows(a.displayID, b.displayID)
        let shift = CGPoint(x: -origins[a.displayID]!.x, y: 0)
        try configure(origins.mapValues { CGPoint(x: $0.x + shift.x, y: $0.y + shift.y) })
        guard CGMainDisplayID() == a.displayID else { throw ProbeFailure("Native main-display change was not observed", kind: .assertion) }
        evidence.append(["phase": "main-changed", "displays": try Self.observe().map(\.json)])
        // Restore base as main before releasing the other display.
        try configure(origins)
        let previousID = b.displayID, previousUUID = ob.uuid
        b.release()
        try SystemObservation.wait("virtual display removal", kind: .assertion) { try !Self.observe().contains(where: { $0.id == previousID }) }
        evidence.append(["phase": "removed", "displays": try Self.observe().map(\.json)])
        let readded = try create(width: 2560, height: 1600, hiDPI: true, serial: 791102)
        let reconnect = try Self.observe().first(where: { $0.id == readded.displayID })
        guard reconnect?.uuid == previousUUID, reconnect?.serial == ob.serial, reconnect?.vendor == ob.vendor, reconnect?.product == ob.product else {
            throw ProbeFailure("Virtual display reconnect did not preserve observed durable identity", kind: .assertion)
        }
        origins.removeValue(forKey: previousID)
        origins[readded.displayID] = CGPoint(x: 0, y: (baseline.map { $0.bounds.minY }.min() ?? 0) - ob.bounds.height)
        try configure(origins)
        evidence.append(["phase": "reconnected", "displays": try Self.observe().map(\.json)])
        try placeWindows(a.displayID, readded.displayID)
    }
    func cleanup() throws {
        for display in owned { display.release() }
        owned.removeAll()
        try SystemObservation.wait("owned displays to disappear", kind: .cleanup) {
            Set(try Self.observe(kind: .cleanup).map(\.id)) == Set(baseline.map(\.id))
        }
        try configure(Dictionary(uniqueKeysWithValues: baseline.map { ($0.id, $0.bounds.origin) }))
        let final = try Self.observe(kind: .cleanup)
        guard final == baseline else { throw ProbeFailure("Display cleanup did not restore baseline modes, origins, identity, and main display", kind: .cleanup) }
        evidence.append(["phase": "restored", "displays": final.map(\.json)])
    }
}
