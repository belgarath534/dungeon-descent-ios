import Foundation
import Capacitor
import CloudKit

// A silent, automatic backup destination that sits alongside the existing
// Firebase cloud sync rather than replacing it — no sign-in screen, no
// account creation, it just uses whatever iCloud account is already signed
// into the device. Save data goes into one CKRecord in the user's PRIVATE
// CloudKit database, which CloudKit already scopes per-iCloud-account on
// its own, so there's no separate user-identity handling needed here.
@objc(iCloudSyncPlugin)
public class iCloudSyncPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "iCloudSyncPlugin"
    public let jsName = "iCloudSync"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "isAvailable", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "saveData", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "loadData", returnType: CAPPluginReturnPromise)
    ]

    private let recordType = "DDSaveData"
    private let recordName = "save"
    private let fieldName = "json"

    private var privateDatabase: CKDatabase {
        return CKContainer.default().privateCloudDatabase
    }

    private var recordID: CKRecord.ID {
        return CKRecord.ID(recordName: recordName)
    }

    @objc func isAvailable(_ call: CAPPluginCall) {
        CKContainer.default().accountStatus { status, error in
            if let error = error {
                call.resolve(["available": false, "reason": error.localizedDescription])
                return
            }
            call.resolve(["available": status == .available, "status": self.statusString(status)])
        }
    }

    private func statusString(_ status: CKAccountStatus) -> String {
        switch status {
        case .available: return "available"
        case .noAccount: return "noAccount"
        case .restricted: return "restricted"
        case .couldNotDetermine: return "couldNotDetermine"
        case .temporarilyUnavailable: return "temporarilyUnavailable"
        @unknown default: return "unknown"
        }
    }

    @objc func saveData(_ call: CAPPluginCall) {
        guard let json = call.getString("json") else {
            call.reject("Missing json string")
            return
        }
        let database = privateDatabase
        let targetID = recordID
        database.fetch(withRecordID: targetID) { existingRecord, error in
            let record: CKRecord
            if let existingRecord = existingRecord {
                record = existingRecord
            } else {
                // Not found (or any other fetch error) — start a fresh
                // record rather than failing outright. A genuine network
                // error surfaces again on the save below anyway.
                record = CKRecord(recordType: self.recordType, recordID: targetID)
            }
            record[self.fieldName] = json as CKRecordValue
            database.save(record) { _, saveError in
                if let saveError = saveError {
                    call.reject("iCloud save failed: \(saveError.localizedDescription)")
                    return
                }
                call.resolve()
            }
        }
    }

    @objc func loadData(_ call: CAPPluginCall) {
        privateDatabase.fetch(withRecordID: recordID) { record, error in
            if let error = error {
                let ckError = error as? CKError
                if ckError?.code == .unknownItem {
                    // No backup saved yet — not an error, just nothing there.
                    call.resolve(["found": false])
                    return
                }
                call.reject("iCloud load failed: \(error.localizedDescription)")
                return
            }
            guard let json = record?[self.fieldName] as? String else {
                call.resolve(["found": false])
                return
            }
            call.resolve(["found": true, "json": json])
        }
    }
}
