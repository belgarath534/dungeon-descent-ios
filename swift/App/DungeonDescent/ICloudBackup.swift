import SwiftUI
import CloudKit
import DungeonCore

/// iCLOUD BACKUP: the save in your own iCloud (the private CloudKit
/// database of iCloud.com.dungeon.descent), no sign-in. The same record as
/// the web version's iCloudSyncPlugin (DDSaveData "save", field "json"), so a
/// backup made by the old app restores here. Off until you turn it on.
@MainActor
final class ICloudBackup: ObservableObject {
    static let shared = ICloudBackup()

    @Published var status = ""
    @Published var statusColor: UInt32 = 0x666666
    @Published var busy = false
    private var lastSync = Date.distantPast

    private let container = CKContainer(identifier: "iCloud.com.dungeon.descent")
    private var db: CKDatabase { container.privateCloudDatabase }
    private let recordID = CKRecord.ID(recordName: "save")

    static func enabled(_ store: GameStore) -> Bool { store.getItem("dd_icloud_backup_enabled") == "true" }

    func setEnabled(_ on: Bool, game: GameModel) {
        game.store.setItem("dd_icloud_backup_enabled", on ? "true" : "false")
        if on {
            Feedback.announce("iCloud backup enabled. Your save will back up automatically.")
            Task { if await checkAvailable() { await backup(game: game, silent: false) } }
        } else {
            status = ""
            Feedback.announce("iCloud backup disabled.")
        }
    }

    @discardableResult
    func checkAvailable() async -> Bool {
        do {
            let s = try await container.accountStatus()
            if s == .available {
                say("✓ iCloud is available on this device.", 0x44ff88, speak: false)
                return true
            }
            say("iCloud is not available. Sign in to iCloud in your device Settings first.", 0xffaa44)
        } catch {
            say("Could not check iCloud status.", 0xff4444)
        }
        return false
    }

    private func say(_ text: String, _ color: UInt32, speak: Bool = true) {
        status = text
        statusColor = color
        if speak { Feedback.announce(text) }
    }

    /// The web version's fields (so the old app can read it), plus the whole
    /// save under "all". (The web version backed up only those twelve keys:
    /// no gold, diamonds, items or anything newer.)
    private func payload(_ game: GameModel) -> String? {
        var p: [String: Any] = [:]
        for (field, key) in CloudAccount.fields { if let v = game.store.getItem(key) { p[field] = v } }
        p["all"] = game.snapshot()
        p["savedAt"] = Date().timeIntervalSince1970
        guard let d = try? JSONSerialization.data(withJSONObject: p) else { return nil }
        return String(data: d, encoding: .utf8)
    }

    /// syncToiCloud
    func backup(game: GameModel, silent: Bool) async {
        guard Self.enabled(game.store), let json = payload(game) else { return }
        busy = true
        defer { busy = false }
        do {
            let record: CKRecord
            do { record = try await db.record(for: recordID) } catch { record = CKRecord(recordType: "DDSaveData", recordID: recordID) }
            record["json"] = json as CKRecordValue
            _ = try await db.save(record)
            lastSync = Date()
            if !silent { say("Backed up to iCloud.", 0x44ff88) }
        } catch {
            if !silent { say("iCloud backup failed. Check your connection.", 0xff4444) }
        }
    }

    /// The automatic backup, at most every 2 minutes (like the web version).
    func autoBackup(game: GameModel) {
        guard Self.enabled(game.store), Date().timeIntervalSince(lastSync) > 120 else { return }
        lastSync = Date()
        Task { await backup(game: game, silent: true) }
    }

    /// loadFromiCloud
    func restore(game: GameModel) async {
        busy = true
        defer { busy = false }
        Feedback.announce("Checking iCloud for a saved backup. Please wait.")
        do {
            let record = try await db.record(for: recordID)
            guard let json = record["json"] as? String, let d = json.data(using: .utf8),
                  let p = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else {
                say("No iCloud backup found.", 0xffaa44)
                return
            }
            var data: [String: String] = [:]
            if let all = p["all"] as? [String: String] {
                data = all
            } else {
                for (field, key) in CloudAccount.fields { if let s = p[field] as? String, !s.isEmpty { data[key] = s } }
            }
            game.importWebSave(data, keepSwiftRuns: true)
            game.saveNow()
            say("Restored from iCloud backup.", 0x44ff88)
        } catch let e as CKError where e.code == .unknownItem {
            say("No iCloud backup found.", 0xffaa44)
        } catch {
            say("iCloud restore failed. Check your connection.", 0xff4444)
        }
    }
}

/// #icloud-backup-section, in Settings → Account.
struct ICloudBackupSection: View {
    @EnvironmentObject var game: GameModel
    @ObservedObject var backup = ICloudBackup.shared
    @State private var on = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("🍎 iCloud Backup").font(Theme.cinzel(11.5)).foregroundStyle(Color(hex: 0xcccccc))
                Spacer()
                Button(on ? "On" : "Off") {
                    on.toggle()
                    backup.setEnabled(on, game: game)
                }
                .buttonStyle(ToggleButtonStyle(on: on))
                .accessibilityLabel("Automatic iCloud backup, currently \(on ? "on" : "off")")
            }
            Text("Backs your whole save up to your own iCloud account automatically — no sign-in needed, separate from the account system. Off by default.")
                .font(Theme.crimson(12, italic: true)).foregroundStyle(Color(hex: 0x888888))
            if !backup.status.isEmpty {
                Text(backup.status).font(Theme.cinzel(10)).foregroundStyle(Color(hex: backup.statusColor))
            }
            HStack(spacing: 8) {
                if on {
                    Button("☁ Back Up Now") { Task { await backup.backup(game: game, silent: false) } }
                        .buttonStyle(WebButtonStyle(kind: .ghost)).disabled(backup.busy)
                        .accessibilityLabel("Back up to iCloud now")
                }
                Button("Restore from iCloud") { Task { await backup.restore(game: game) } }
                    .buttonStyle(WebButtonStyle(kind: .ghost)).disabled(backup.busy)
                    .accessibilityLabel("Restore save data from iCloud backup. This replaces the save on this device.")
            }
        }
        .padding(12).background(Color(hex: 0x0a0a0a)).overlay(Rectangle().stroke(Color(hex: 0x333333)))
        .onAppear {
            on = ICloudBackup.enabled(game.store)
            if on { Task { await backup.checkAvailable() } }
        }
    }
}
