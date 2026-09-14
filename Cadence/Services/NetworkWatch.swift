import Foundation
import Network
import Combine
import ServiceManagement

/// Which network counts as the office, and when we last said so.
struct OfficeNetwork: Codable {
    /// MAC address of the default gateway — the router's LAN-side address. Stable for a given
    /// office, and readable without any permission prompt.
    var fingerprint: String = ""
    /// What to call it in the notification. Free text because we can't read the SSID.
    var label: String = "the office"
    var enabled: Bool = true
    /// yyyy-MM-dd of the last arrival we announced, so a reconnect mid-day stays quiet.
    var lastAnnounced: String = ""

    var isConfigured: Bool { !fingerprint.isEmpty }
}

/// Watches for arrival on the office network and fires once per day when it appears.
///
/// The SSID would be the obvious identifier, but macOS 14 gates it behind Location
/// authorization — `ipconfig getsummary en0` returns `SSID : <redacted>` without it. The
/// default gateway's MAC address identifies a network just as well for this purpose, needs no
/// permission, and doesn't move when you roam between APs in the same building.
@MainActor
final class NetworkWatch: ObservableObject {
    /// Fingerprint of the network we're on right now, or "" when offline.
    @Published private(set) var current: String = ""
    @Published private(set) var office = OfficeNetwork()

    /// Called when the office network appears and today's arrival hasn't been announced yet.
    var onArrive: ((OfficeNetwork) -> Void)?

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.humza.cadence.network")
    private var started = false

    init() {
        office = Self.loadOffice()
    }

    func start() {
        guard !started else { return }
        started = true
        monitor.pathUpdateHandler = { [weak self] _ in
            // The path flips before the route table settles; a beat of slack avoids reading a
            // gateway that's about to be replaced.
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                self?.refresh()
            }
        }
        monitor.start(queue: queue)
        refresh()
    }

    /// Re-read the current network and fire the arrival if this is the office. Safe to call on
    /// every scheduler tick — it's two short process spawns and a string compare.
    func refresh() {
        let fp = Self.currentFingerprint()
        let previous = current
        current = fp

        guard office.enabled, office.isConfigured, fp == office.fingerprint else { return }
        // Fire on a transition, or on first read after launch when we're already here.
        guard previous != fp || previous.isEmpty else { return }

        let today = Self.dayKey()
        guard office.lastAnnounced != today else { return }
        office.lastAnnounced = today
        Self.saveOffice(office)
        onArrive?(office)
    }

    /// Adopt whatever network we're on now as the office.
    func captureCurrentAsOffice(label: String) {
        let fp = Self.currentFingerprint()
        guard !fp.isEmpty else { return }
        office.fingerprint = fp
        office.label = label.isEmpty ? "the office" : label
        office.lastAnnounced = ""          // allow today's arrival to fire after a re-capture
        current = fp
        Self.saveOffice(office)
    }

    func forgetOffice() {
        office = OfficeNetwork(fingerprint: "", label: office.label, enabled: office.enabled, lastAnnounced: "")
        Self.saveOffice(office)
    }

    func setEnabled(_ on: Bool) {
        office.enabled = on
        Self.saveOffice(office)
    }

    // MARK: login item

    /// Whether macOS starts Cadence at login. The arrival check runs the moment the app
    /// starts, so this is what makes "logged in at the office" produce a notification —
    /// nothing fires while Cadence is closed.
    var opensAtLogin: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Returns nil on success, or a message to show the user. A failure here is usually the
    /// app not living in /Applications or ~/Applications, which SMAppService requires.
    @discardableResult
    func setOpensAtLogin(_ on: Bool) -> String? {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            objectWillChange.send()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    // MARK: fingerprint

    /// MAC of the default gateway, e.g. "6c:63:f8:74:60:69". Falls back to the gateway IP when
    /// the ARP entry hasn't been populated yet — weaker, but better than calling it offline.
    static func currentFingerprint() -> String {
        guard let routeOut = run("/sbin/route", ["-n", "get", "default"]) else { return "" }

        var gateway = ""
        var interface = ""
        for line in routeOut.split(separator: "\n") {
            let parts = line.split(separator: ":", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            guard parts.count == 2 else { continue }
            if parts[0] == "gateway"   { gateway = parts[1] }
            if parts[0] == "interface" { interface = parts[1] }
        }
        guard !gateway.isEmpty else { return "" }

        if let arpOut = run("/usr/sbin/arp", ["-n", gateway]),
           let mac = macAddress(in: arpOut) {
            return mac
        }
        return "\(interface)/\(gateway)"
    }

    /// Pull the `at <mac> on` field out of an arp line. Written out rather than regex'd so a
    /// missing entry ("no entry") returns nil instead of a partial match.
    private static func macAddress(in arpOutput: String) -> String? {
        let fields = arpOutput.split(separator: " ")
        guard let atIndex = fields.firstIndex(of: "at"), atIndex + 1 < fields.count else { return nil }
        let candidate = String(fields[atIndex + 1])
        guard candidate.contains(":"), candidate.split(separator: ":").count >= 4 else { return nil }
        return candidate.lowercased()
    }

    private static func run(_ path: String, _ args: [String]) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: persistence

    private static func loadOffice() -> OfficeNetwork {
        guard let data = try? Data(contentsOf: CadencePaths.networkFile),
              let n = try? JSONDecoder().decode(OfficeNetwork.self, from: data) else { return OfficeNetwork() }
        return n
    }

    private static func saveOffice(_ n: OfficeNetwork) {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? e.encode(n) else { return }
        try? data.write(to: CadencePaths.networkFile, options: .atomic)
    }

    static func dayKey(for date: Date = Date()) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}
