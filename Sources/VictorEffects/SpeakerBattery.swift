import CoreBluetooth
import Foundation

/// 🔊 The connected JBL speakers' battery, for the tablet's top bar (next to
/// the phone's). macOS itself never learns it: the Go 4 has no microphone, so
/// no HFP and none of the AT-command battery reports, and it exposes no
/// standard Battery Service (0x180F) either. The only source is the channel
/// the JBL Portable app talks over — a vendor GATT service whose UUID spells
/// "excelpoint.com" — with frames reverse-engineered by open-source projects
/// (JBLControl, jbl-charge5) and confirmed on Victor's Go 4 on 2026-10-29:
/// write `AA 11 00`, get back a burst of `AA 12 <len> 00 <token> <value…>`
/// frames, `0x44` = battery (low 7 bits %, top bit charging), `0x48` = the
/// speaker's classic MAC. `docs/sound-routing.md` → *Speaker battery*.
///
/// **The speaker takes one control connection at a time**, so the phone's JBL
/// app cannot connect while we hold it. Hence a short visit every
/// `interval` — connect, ask, disconnect — never a held connection.
///
/// Only speakers that are a *connected audio output of this Mac* count
/// (`BluetoothKeepAlive.targets`, matched by MAC against the CoreAudio UID
/// `E8-26-CF-C6-97-0B:output`): a JBL in the next room advertising the same
/// service is somebody else's.
final class SpeakerBattery: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    static let shared = SpeakerBattery()

    struct Reading: Equatable {
        let pct: Int
        let charging: Bool
        let at: Date
    }

    static let service = CBUUID(string: "65786365-6C70-6F69-6E74-2E636F6D0000")
    static let notifyChar = CBUUID(string: "65786365-6C70-6F69-6E74-2E636F6D0001")
    static let writeChar = CBUUID(string: "65786365-6C70-6F69-6E74-2E636F6D0002")
    /// Harman International's Bluetooth company id, first two bytes of a JBL's
    /// manufacturer data (little-endian `57 00`).
    static let harmanCompanyId: UInt16 = 0x0057
    /// "Tell me everything": name, model, battery, MAC… in one burst. Read-only;
    /// never send `AA 01 02 82 00`, which wipes the speaker's usage counters.
    static let infoRequest: [UInt8] = [0xAA, 0x11, 0x00]

    /// Every two minutes: a battery moves ~1 % in that time at full volume, and
    /// each visit costs the phone's JBL app its connection for about a second.
    private static let interval: TimeInterval = 120
    private static let scanSeconds: TimeInterval = 6
    private static let visitSeconds: TimeInterval = 6

    /// Main queue only (CoreBluetooth is created on it, `/ping` is served on it).
    private(set) var readings: [String: Reading] = [:]
    private var central: CBCentralManager?
    private var timer: Timer?
    private var busy = false
    private var found: [UUID: CBPeripheral] = [:]
    /// What each advertiser turned out to be, learnt on its first visit, so a
    /// JBL that is not ours is visited once and then left alone.
    private var macById: [UUID: String] = [:]
    private var queue: [CBPeripheral] = []
    private var current: CBPeripheral?
    private var currentFrames: [UInt8: [UInt8]] = [:]
    private var visitDeadline: DispatchWorkItem?
    private var loggedDenied = false

    func start() {
        dispatchPrecondition(condition: .onQueue(.main))
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in self?.tick() }
        timer = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { [weak self] _ in self?.tick() }
    }

    // MARK: - /ping

    /// The fields spliced into `/ping` — flat, like every other key there.
    /// `speakerChargePct` -1 = no connected JBL has been read.
    func pingFields(now: Date = Date()) -> String {
        let r = Self.pick(readings: readings, connectedMacs: Self.connectedSpeakerMacs(),
                          defaultMac: Self.mac(fromUID: BluetoothOutput.deviceUID(BluetoothOutput.defaultOutputID())))
        guard let r else { return "\"speakerChargePct\":-1,\"speakerCharging\":false,\"speakerChargeAgeS\":0" }
        return "\"speakerChargePct\":\(r.pct),\"speakerCharging\":\(r.charging),"
            + "\"speakerChargeAgeS\":\(max(0, Int(now.timeIntervalSince(r.at))))"
    }

    /// Which reading the tablet shows: the speaker that is the Mac's default
    /// output when it has one, otherwise the emptiest connected one — the spare
    /// dying unnoticed is the failure the keep-alive already exists for.
    static func pick(readings: [String: Reading], connectedMacs: Set<String>, defaultMac: String?) -> Reading? {
        let live = readings.filter { connectedMacs.contains($0.key) }
        if let d = defaultMac, let r = live[d] { return r }
        return live.values.min { $0.pct < $1.pct }
    }

    /// `E8-26-CF-C6-97-0B:output` → `E8-26-CF-C6-97-0B`; nil for a UID that is
    /// not a Bluetooth address.
    static func mac(fromUID uid: String) -> String? {
        let head = String(uid.split(separator: ":").first ?? "")
        let parts = head.split(separator: "-")
        guard parts.count == 6, parts.allSatisfy({ $0.count == 2 && $0.allSatisfy(\.isHexDigit) }) else { return nil }
        return head.uppercased()
    }

    static func connectedSpeakerMacs() -> Set<String> {
        Set(BluetoothKeepAlive.targets(BluetoothOutput.outputDevices(), match: BluetoothOutput.speakerNameMatch)
            .compactMap { mac(fromUID: $0.uid) })
    }

    /// Which advertisers to visit this round: the ones already known to be a
    /// connected speaker of this Mac, plus — only while some connected speaker
    /// has not been identified yet — the ones never visited. Pure.
    static func toVisit(found: [UUID], macById: [UUID: String], connectedMacs: Set<String>) -> [UUID] {
        let unidentified = !connectedMacs.isSubset(of: Set(macById.values))
        return found.filter { id in
            if let mac = macById[id] { return connectedMacs.contains(mac) }
            return unidentified
        }
    }

    // MARK: - Frames (pure)

    /// Splits one notification into `token → value` pairs. A notification may
    /// carry several `AA 12 <len> 00 <token> <value…>` frames back to back;
    /// `len` counts from the `00` to the end of the value.
    static func parseInfo(_ bytes: [UInt8]) -> [UInt8: [UInt8]] {
        var out: [UInt8: [UInt8]] = [:]
        var i = 0
        while i + 5 <= bytes.count {
            guard bytes[i] == 0xAA, bytes[i + 1] == 0x12 else { i += 1; continue }
            let len = Int(bytes[i + 2])
            let end = i + 3 + len
            guard len >= 2, end <= bytes.count else { break }
            out[bytes[i + 4]] = Array(bytes[(i + 5)..<end])
            i = end
        }
        return out
    }

    /// Battery token `0x44`: low 7 bits = %, top bit = charging.
    static func battery(_ info: [UInt8: [UInt8]]) -> (pct: Int, charging: Bool)? {
        guard let b = info[0x44]?.first else { return nil }
        return (min(100, Int(b & 0x7F)), b & 0x80 != 0)
    }

    /// MAC token `0x48`, formatted the way CoreAudio writes it in a UID.
    static func mac(_ info: [UInt8: [UInt8]]) -> String? {
        guard let m = info[0x48], m.count == 6 else { return nil }
        return m.map { String(format: "%02X", $0) }.joined(separator: "-")
    }

    // MARK: - One visit round

    private func tick() {
        guard !busy, !Self.connectedSpeakerMacs().isEmpty else { return }
        if central == nil {
            // Created lazily: the first creation is what asks for the Bluetooth
            // grant, and a Mac with no JBL connected should never be asked.
            central = CBCentralManager(delegate: self, queue: .main)
            return  // centralManagerDidUpdateState starts the round
        }
        startRound()
    }

    private func startRound() {
        guard let c = central, c.state == .poweredOn, !busy else { return }
        busy = true
        found = [:]
        // First choice: the JBL's GATT over the Classic link the audio already
        // uses — no advert needed. A Go 4 stops advertising over BLE a while
        // after it connects (2026-10-29: silent after ~10 min, and the one LE
        // read it had given said 100 % where this path said 75 %), so a
        // scan-only round goes stale without a sound.
        let direct = c.retrieveConnectedPeripherals(withServices: [Self.service])
        if !direct.isEmpty {
            queue = direct
            visitNext()
            return
        }
        c.scanForPeripherals(withServices: nil, options: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.scanSeconds) { [weak self] in
            guard let self else { return }
            c.stopScan()
            self.queue = Self.toVisit(found: Array(self.found.keys), macById: self.macById,
                                      connectedMacs: Self.connectedSpeakerMacs())
                .compactMap { self.found[$0] }
            self.visitNext()
        }
    }

    private func visitNext() {
        guard let c = central, !queue.isEmpty else { busy = false; return }
        let p = queue.removeFirst()
        current = p
        currentFrames = [:]
        p.delegate = self
        c.connect(p)
        let deadline = DispatchWorkItem { [weak self] in self?.endVisit(p) }
        visitDeadline = deadline
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.visitSeconds, execute: deadline)
    }

    private func endVisit(_ p: CBPeripheral) {
        guard current === p else { return }
        visitDeadline?.cancel()
        visitDeadline = nil
        current = nil
        central?.cancelPeripheralConnection(p)
        if let mac = Self.mac(currentFrames) { macById[p.identifier] = mac }
        if let mac = Self.mac(currentFrames), let b = Self.battery(currentFrames),
           Self.connectedSpeakerMacs().contains(mac) {
            let old = readings[mac]
            readings[mac] = Reading(pct: b.pct, charging: b.charging, at: Date())
            if old?.pct != b.pct || old?.charging != b.charging {
                effectsInfo("🔊🔋 \(mac) \(b.pct)%\(b.charging ? " ⚡" : "")")
            }
        }
        visitNext()
    }

    // MARK: - CBCentralManagerDelegate

    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        switch c.state {
        case .poweredOn: startRound()
        case .unauthorized:
            if !loggedDenied { effectsError("🔊🔋 Bluetooth access denied — speaker battery off"); loggedDenied = true }
        default: break
        }
    }

    func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral,
                        advertisementData ad: [String: Any], rssi: NSNumber) {
        guard let m = ad[CBAdvertisementDataManufacturerDataKey] as? Data, m.count >= 2,
              UInt16(m[0]) | UInt16(m[1]) << 8 == Self.harmanCompanyId,
              (ad[CBAdvertisementDataIsConnectable] as? Bool) != false else { return }
        found[p.identifier] = p
    }

    func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) {
        p.discoverServices([Self.service])
    }

    func centralManager(_ c: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        endVisit(p)
    }

    // MARK: - CBPeripheralDelegate

    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        guard let s = p.services?.first(where: { $0.uuid == Self.service }) else { endVisit(p); return }
        p.discoverCharacteristics([Self.notifyChar, Self.writeChar], for: s)
    }

    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
        guard let n = s.characteristics?.first(where: { $0.uuid == Self.notifyChar }) else { endVisit(p); return }
        p.setNotifyValue(true, for: n)
    }

    func peripheral(_ p: CBPeripheral, didUpdateNotificationStateFor ch: CBCharacteristic, error: Error?) {
        guard error == nil, let w = ch.service?.characteristics?.first(where: { $0.uuid == Self.writeChar }) else {
            endVisit(p); return
        }
        p.writeValue(Data(Self.infoRequest), for: w, type: .withResponse)
    }

    func peripheral(_ p: CBPeripheral, didUpdateValueFor ch: CBCharacteristic, error: Error?) {
        guard let v = ch.value else { return }
        currentFrames.merge(Self.parseInfo([UInt8](v))) { _, new in new }
        // The burst ends with tokens past 0x48; once both answers are in,
        // there is no reason to keep the phone's app locked out any longer.
        if Self.mac(currentFrames) != nil, Self.battery(currentFrames) != nil {
            DispatchQueue.main.async { [weak self] in self?.endVisit(p) }
        }
    }
}
