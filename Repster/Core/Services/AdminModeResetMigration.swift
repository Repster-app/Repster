import Foundation
import SwiftData

// One-shot reset of Admin Mode for the release that took away its switch.
//
// Until 1.6 Admin Mode was a visible toggle in Settings → Smart Suggestions, and App Store users
// found it and turned it on. The only way in or out is now an unlabelled hold on the Version row
// in Settings, so anyone left with it on would be stuck in it with no visible way back. Turns it
// off once on every install; the developer holds the version to turn it back on.
//
// Capacity Guards need nothing here: outside Admin Mode the engine keeps them on whatever was
// saved (LoadPrescriptionService), so turning this off also restores them.
//
// NOTE: Intentional direct ModelContext access for one-time recovery, matching the pattern in
// SeedService and GhostSetRepsBackfillMigration. Guarded by a UserDefaults flag so it runs at
// most once — a reset on every launch would undo the developer's hold.
enum AdminModeResetMigration {
    static let didRunKey = "didRunAdminModeReset_v1"

    static func runIfNeeded(modelContext: ModelContext, userDefaults: UserDefaults = .standard) {
        guard !userDefaults.bool(forKey: didRunKey) else { return }

        var descriptor = FetchDescriptor<HealthProfile>()
        descriptor.fetchLimit = 1
        let profile: HealthProfile?
        do {
            profile = try modelContext.fetch(descriptor).first
        } catch {
            dbg("[AdminModeResetMigration] Failed to fetch profile: \(error)")
            return
        }

        if let profile, profile.prescriptionAdminModeEnabled == true {
            profile.prescriptionAdminModeEnabled = false
            profile.updatedAt = Date()
            do {
                try modelContext.save()
                dbg("[AdminModeResetMigration] Turned Admin Mode off")
            } catch {
                dbg("[AdminModeResetMigration] Failed to save: \(error)")
                return
            }
        }

        userDefaults.set(true, forKey: didRunKey)
    }
}
