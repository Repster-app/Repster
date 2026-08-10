// AppleHealthSettingsView.swift
// Detail screen for the Apple Health integration.
//
// Lives on its own screen rather than inline in Settings: explaining a health-data
// permission honestly takes more words than a Settings row can carry, and the two
// toggles plus their caveats crowded out the rest of the Body section.

import SwiftUI

struct AppleHealthSettingsView: View {
    @AppStorage(HealthKitPreferences.enabledKey) private var isEnabled = false
    @AppStorage(HealthKitPreferences.estimatedEnergyKey) private var writesEstimatedEnergy = false
    /// Starts true so the "add your bodyweight" hint doesn't flash before the check lands.
    @State private var hasBodyweightEntry = true
    @State private var connection: AppleHealthConnectionModel

    private let bodyweightService: any BodyweightServiceProtocol

    init(healthKitService: any HealthKitServiceProtocol,
         analyticsService: any AnalyticsServiceProtocol,
         bodyweightService: any BodyweightServiceProtocol) {
        _connection = State(initialValue: AppleHealthConnectionModel(
            healthKitService: healthKitService,
            analyticsService: analyticsService,
            source: .settings
        ))
        self.bodyweightService = bodyweightService
    }

    var body: some View {
        Form {
            Section {
                Toggle("Sync Workouts", isOn: syncBinding)
                    .disabled(connection.isConnecting)
            } footer: {
                Text("Finished workouts are added to Apple Health as strength training sessions, so they count towards your activity rings.\n\nRepster only writes to Health — it never reads your health data — and it can only change or remove the workouts it wrote itself. Turning this off leaves everything already in Health untouched.")
            }

            if isEnabled {
                Section {
                    Toggle("Estimated Calories", isOn: $writesEstimatedEnergy)

                    // Without a bodyweight there's nothing to base the estimate on. The
                    // workout still syncs — it just carries no energy — so this is a hint,
                    // not an error, and the toggle deliberately stays enabled so it starts
                    // working by itself once a weight is logged.
                    if writesEstimatedEnergy && !hasBodyweightEntry {
                        Label(
                            "Add your bodyweight in Settings → Bodyweight Log to include estimated calories.",
                            systemImage: "info.circle"
                        )
                        .font(.footnote)
                        .foregroundStyle(Color.textSecondary)
                    }
                } footer: {
                    Text("Attaches an active energy estimate to each workout, worked out from your bodyweight and how long you trained. Repster doesn't measure calories, so treat it as a rough figure.")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.bg)
        .navigationTitle("Apple Health")
        .navigationBarTitleDisplayMode(.inline)
        .task { await refreshBodyweightPresence() }
        .alert("Apple Health", isPresented: Binding(
            get: { connection.alertMessage != nil },
            set: { if !$0 { connection.alertMessage = nil } }
        )) {
            Button("OK") {}
        } message: {
            Text(connection.alertMessage ?? "")
        }
    }

    /// Turning the toggle on is an explicit connect request, which is the only thing
    /// allowed to reach HealthKit's one-shot permission sheet.
    private var syncBinding: Binding<Bool> {
        Binding(
            get: { isEnabled },
            set: { newValue in
                guard newValue else {
                    connection.disable()
                    return
                }
                Task {
                    if await connection.connect() {
                        await refreshBodyweightPresence()
                    }
                }
            }
        )
    }

    private func refreshBodyweightPresence() async {
        let entries = (try? await bodyweightService.fetchAllEntries()) ?? []
        hasBodyweightEntry = !entries.isEmpty
    }
}
