import AppKit
import DisplayProbeBridge

struct DisplayObservation: Equatable, Codable {
  var id: CGDirectDisplayID
  var uuid: String
  var bounds: CGRect
  var pixels: CGSize
  var logical: CGSize
  var refresh: Double
  var active: Bool
  var mirrored: Bool
  var main: Bool
  var vendor: UInt32
  var product: UInt32
  var serial: UInt32
  var json: [String: Any] {
    [
      "id": id, "uuid": uuid,
      "bounds": [
        "x": bounds.minX, "y": bounds.minY, "width": bounds.width, "height": bounds.height,
      ],
      "pixels": ["width": pixels.width, "height": pixels.height],
      "logical": ["width": logical.width, "height": logical.height],
      "refresh_hz": refresh, "active": active, "mirrored": mirrored, "main": main, "vendor": vendor,
      "product": product, "serial": serial,
    ]
  }
}
@MainActor final class DisplayQualification {
  private let profile: Profile
  private(set) var baseline: [DisplayObservation]
  private var owned: [STVirtualDisplay] = []
  private(set) var evidence: [[String: Any]] = []
  init(profile: Profile) throws {
    self.profile = profile
    baseline = try DisplayReadout.read(profile: profile, kind: .setup)
    guard !baseline.isEmpty, baseline.contains(where: \.main), baseline.allSatisfy({ !$0.mirrored })
    else {
      throw ProbeFailure("Probe requires an existing nonmirrored base desktop.")
    }
  }
  private func observe(kind: FailureKind = .assertion) throws -> [DisplayObservation] {
    // The creating process cannot read modes after its baseline query on
    // observed macOS 26.5. A fresh process observes actual native modes.
    try DisplayReadout.read(profile: profile, kind: kind)
  }
  private func create(width: UInt32, height: UInt32, hiDPI: Bool, serial: UInt32) throws
    -> STVirtualDisplay
  {
    let display: STVirtualDisplay
    do {
      display = try STVirtualDisplay.create(
        withWidth: width, height: height, hiDPI: hiDPI, serial: serial)
    } catch { throw ProbeFailure("Virtual-display capability unavailable: \(error)", kind: .setup) }
    owned.append(display)
    try SystemObservation.wait("virtual display \(display.displayID) to become active") {
      try DisplayReadout.read(profile: profile, kind: .setup).contains(where: {
        $0.id == display.displayID && $0.active
      })
    }
    return display
  }
  private func configure(_ origins: [CGDirectDisplayID: CGPoint], kind: FailureKind = .assertion)
    throws
  {
    do { try DisplayConfigurationHelper.apply(origins, profile: profile, kind: kind) } catch {
      var row: [String: Any] = [
        "phase": "display-configuration-failed", "error": String(describing: error),
      ]
      if let failure = error as? DisplayConfigurationFailure {
        row["stage"] = failure.reply.stage
        if let target = failure.reply.target { row["target_display"] = target }
        if let code = failure.reply.cgError { row["cg_error"] = code }
      }
      evidence.append(row)
      throw error
    }
    try SystemObservation.wait("observed display arrangement", kind: kind) {
      let topology = try self.observe(kind: kind)
      return origins.allSatisfy { id, point in
        topology.contains { $0.id == id && $0.bounds.origin == point && !$0.mirrored }
      }
    }
  }
  func qualify(placeWindows: (DisplayObservation, DisplayObservation) throws -> Void) throws {
    evidence.append(["phase": "baseline", "displays": baseline.map(\.json)])
    let a = try create(width: 1440, height: 900, hiDPI: false, serial: 791101)
    let b = try create(width: 2560, height: 1600, hiDPI: true, serial: 791102)
    let initial = try self.observe()
    guard initial.count == baseline.count + 2,
      baseline.allSatisfy({ original in initial.contains(where: { $0.id == original.id }) }),
      let oa = initial.first(where: { $0.id == a.displayID }),
      let ob = initial.first(where: { $0.id == b.displayID }),
      oa.logical == CGSize(width: 1440, height: 900), oa.pixels == oa.logical,
      ob.logical == CGSize(width: 1280, height: 800), ob.pixels == CGSize(width: 2560, height: 1600)
    else {
      throw ProbeFailure(
        "Virtual displays did not expose the required native modes/densities or retain base monitors",
        kind: .assertion)
    }
    var origins = Dictionary(uniqueKeysWithValues: baseline.map { ($0.id, $0.bounds.origin) })
    origins[a.displayID] = CGPoint(
      x: (baseline.map { $0.bounds.minX }.min() ?? 0) - oa.bounds.width, y: 0)
    origins[b.displayID] = CGPoint(
      x: 0, y: (baseline.map { $0.bounds.minY }.min() ?? 0) - ob.bounds.height)
    try configure(origins)
    let arranged = try self.observe()
    evidence.append(["phase": "left-and-above", "displays": arranged.map(\.json)])
    guard let first = arranged.first(where: { $0.id == a.displayID }),
      let second = arranged.first(where: { $0.id == b.displayID })
    else { throw ProbeFailure("Observed placement displays missing", kind: .assertion) }
    try placeWindows(first, second)
    let shift = CGPoint(x: -origins[a.displayID]!.x, y: 0)
    try configure(origins.mapValues { CGPoint(x: $0.x + shift.x, y: $0.y + shift.y) })
    guard try self.observe().first(where: \.main)?.id == a.displayID else {
      throw ProbeFailure("Native main-display change was not observed", kind: .assertion)
    }
    evidence.append(["phase": "main-changed", "displays": try self.observe().map(\.json)])
    // Restore base as main before releasing the other display.
    try configure(origins)
    let previousID = b.displayID
    let previousUUID = ob.uuid
    b.release()
    try SystemObservation.wait("virtual display removal", kind: .assertion) {
      try !DisplayReadout.identifiers(profile: profile, kind: .assertion).contains(previousID)
    }
    evidence.append(["phase": "removed", "displays": try self.observe().map(\.json)])
    let readded = try create(width: 2560, height: 1600, hiDPI: true, serial: 791102)
    let reconnect = try self.observe().first(where: { $0.id == readded.displayID })
    guard reconnect?.uuid == previousUUID, reconnect?.serial == ob.serial,
      reconnect?.vendor == ob.vendor, reconnect?.product == ob.product
    else {
      throw ProbeFailure(
        "Virtual display reconnect did not preserve observed durable identity", kind: .assertion)
    }
    origins.removeValue(forKey: previousID)
    origins[readded.displayID] = CGPoint(
      x: 0, y: (baseline.map { $0.bounds.minY }.min() ?? 0) - ob.bounds.height)
    try configure(origins)
    let reconnected = try self.observe()
    evidence.append(["phase": "reconnected", "displays": reconnected.map(\.json)])
    guard let first = reconnected.first(where: { $0.id == a.displayID }),
      let second = reconnected.first(where: { $0.id == readded.displayID })
    else { throw ProbeFailure("Observed reconnect placement missing", kind: .assertion) }
    try placeWindows(first, second)
  }
  func cleanup() throws {
    let releasedIDs = owned.map(\.displayID)
    for display in owned { display.release() }
    owned.removeAll()
    var remainingIDs: [CGDirectDisplayID] = []
    do {
      try SystemObservation.wait("owned displays to disappear", kind: .cleanup) {
        remainingIDs = try DisplayReadout.identifiers(profile: profile, kind: .cleanup)
        return Set(remainingIDs) == Set(baseline.map(\.id))
      }
    } catch {
      var row: [String: Any] = [
        "phase": "display-cleanup-failed", "error": String(describing: error),
        "released_ids": releasedIDs, "baseline_ids": baseline.map(\.id),
        "fresh_online_ids": remainingIDs,
      ]
      do { row["parent_online_ids"] = try DisplayReadout.rawIdentifiers(kind: .cleanup) } catch {
        row["parent_online_ids_error"] = String(describing: error)
      }
      do { row["fresh_observer_displays"] = try observe(kind: .cleanup).map(\.json) } catch {
        row["fresh_observer_error"] = String(describing: error)
      }
      evidence.append(row)
      throw error
    }
    try configure(
      Dictionary(uniqueKeysWithValues: baseline.map { ($0.id, $0.bounds.origin) }), kind: .cleanup)
    let final = try self.observe(kind: .cleanup)
    guard final == baseline else {
      throw ProbeFailure(
        "Display cleanup did not restore baseline modes, origins, identity, and main display",
        kind: .cleanup)
    }
    evidence.append(["phase": "restored", "displays": final.map(\.json)])
  }
}
