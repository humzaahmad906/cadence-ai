import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var scheduler: Scheduler

    @State private var customModel: String = ""
    @State private var officeLabel: String = ""
    @State private var loginItemError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.space4) {
                modelCard
                officeCard
                pathsCard
                scheduleCard
                archiveCard
            }
            .padding(DS.space6)
        }
        .background(DS.contentBG)
        .onAppear {
            let s = appState.claudeSettings
            customModel = ModelCatalog.isKnown(s.model) ? "" : s.model
            officeLabel = scheduler.network.office.label
        }
    }

    // MARK: model

    private var modelCard: some View {
        Card {
            VStack(alignment: .leading, spacing: DS.space3) {
                Text("Claude model").font(.system(size: 14, weight: .semibold))
                Text("Applies to every block that doesn't name its own model. Passed straight to `claude --model`.")
                    .font(DS.Font.caption).foregroundStyle(DS.textSecondary)

                Picker("", selection: Binding(
                    get: { ModelCatalog.isKnown(appState.claudeSettings.model) ? appState.claudeSettings.model : "__custom" },
                    set: { pick in
                        var s = appState.claudeSettings
                        if pick == "__custom" {
                            s.model = customModel
                        } else {
                            s.model = pick
                            customModel = ""
                        }
                        appState.updateClaudeSettings(s)
                    })) {
                    Text("CLI default").tag("")
                    ForEach(ModelCatalog.known) { m in
                        Text(m.note.isEmpty ? m.label : "\(m.label) — \(m.note)").tag(m.id)
                    }
                    Text("Custom…").tag("__custom")
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 320)

                HStack(spacing: DS.space2) {
                    TextField("claude-…  (any model id the CLI accepts)", text: $customModel)
                        .textFieldStyle(.roundedBorder)
                        .font(DS.Font.mono)
                        .frame(width: 320)
                    Button("Use") {
                        var s = appState.claudeSettings
                        s.model = customModel.trimmingCharacters(in: .whitespaces)
                        appState.updateClaudeSettings(s)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(customModel.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Text("A model released after this build works by typing its id — nothing in the app needs updating first.")
                    .font(DS.Font.caption).foregroundStyle(DS.textTertiary)

                Divider().overlay(DS.borderSoft)

                HStack(spacing: DS.space3) {
                    Text("Effort").font(DS.Font.callout).foregroundStyle(DS.textSecondary)
                        .frame(width: 60, alignment: .leading)
                    Picker("", selection: Binding(
                        get: { appState.claudeSettings.effort },
                        set: { v in
                            var s = appState.claudeSettings
                            s.effort = v
                            appState.updateClaudeSettings(s)
                        })) {
                        ForEach(ModelCatalog.efforts, id: \.self) { e in
                            Text(e.isEmpty ? "CLI default" : e).tag(e)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 380)
                }

                HStack {
                    Text("In use").font(DS.Font.callout).foregroundStyle(DS.textSecondary)
                        .frame(width: 60, alignment: .leading)
                    Chip(ModelCatalog.label(for: appState.claudeSettings.model), tint: DS.accent)
                    if !appState.claudeSettings.effort.isEmpty {
                        Chip(appState.claudeSettings.effort, tint: DS.purple)
                    }
                }
            }
        }
    }

    // MARK: office network

    private var officeCard: some View {
        Card {
            VStack(alignment: .leading, spacing: DS.space3) {
                Text("Office network").font(.system(size: 14, weight: .semibold))
                Text("The first time you join this network each day, Cadence notifies you — tap it to open Day. Identified by the router's MAC address, because macOS won't hand out the Wi-Fi name without Location access.")
                    .font(DS.Font.caption).foregroundStyle(DS.textSecondary)

                row("On this network now", scheduler.network.current.isEmpty ? "— offline —" : scheduler.network.current)
                row("Saved as office", scheduler.network.office.isConfigured ? scheduler.network.office.fingerprint : "not set")

                HStack(spacing: DS.space2) {
                    TextField("what to call it", text: $officeLabel)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)
                    Button("Use current network") {
                        scheduler.network.captureCurrentAsOffice(label: officeLabel)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(scheduler.network.current.isEmpty)

                    if scheduler.network.office.isConfigured {
                        Button("Forget") { scheduler.network.forgetOffice() }
                            .buttonStyle(SecondaryButtonStyle())
                    }
                }

                Toggle("Notify on arrival", isOn: Binding(
                    get: { scheduler.network.office.enabled },
                    set: { scheduler.network.setEnabled($0) }))
                    .font(DS.Font.body)

                Toggle("Open Cadence at login", isOn: Binding(
                    get: { scheduler.network.opensAtLogin },
                    set: { loginItemError = scheduler.network.setOpensAtLogin($0) }))
                    .font(DS.Font.body)

                Text("The arrival check runs the moment Cadence starts, so logging in at the office is enough to get the notification. Ignore it and it won't ask again until tomorrow.")
                    .font(DS.Font.caption).foregroundStyle(DS.textTertiary)

                if let loginItemError {
                    Text(loginItemError)
                        .font(DS.Font.caption).foregroundStyle(DS.danger)
                }

                if scheduler.network.office.isConfigured {
                    HStack(spacing: 6) {
                        StatusDot(tint: scheduler.network.current == scheduler.network.office.fingerprint ? DS.ok : DS.textTertiary)
                        Text(scheduler.network.current == scheduler.network.office.fingerprint
                             ? "You're on the office network."
                             : "Not on the office network right now.")
                            .font(DS.Font.caption).foregroundStyle(DS.textSecondary)
                    }
                }
            }
        }
    }

    // MARK: the rest

    private var pathsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("Paths").font(.system(size: 14, weight: .semibold))
                row("Claude CLI", appState.claudeSettings.binary)
                row("Workflows", CadencePaths.workflowsDir.path)
                row("Days", CadencePaths.daysDir.path)
                row("Log", CadencePaths.activityFile.path)
                row("Tickets", CadencePaths.issuesDir.path)
                row("Repos registry", CadencePaths.reposFile.path)
            }
        }
    }

    private var scheduleCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("Schedule").font(.system(size: 14, weight: .semibold))
                row("Tick", "every 60s")
                row("Block start", "announced within 5 min of the block beginning")
                row("Rollover", "at midnight — block shape and Later carry over")
            }
        }
    }

    private var archiveCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("Archive").font(.system(size: 14, weight: .semibold))
                Text("Tickets created by workflows. Off the main surface on purpose.")
                    .font(DS.Font.caption).foregroundStyle(DS.textSecondary)
                HStack {
                    Button { appState.setArtifact(.ticketsList(status: nil)) } label: {
                        Label("Open ticket archive", systemImage: "archivebox")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    Text("\(appState.tickets.count) on disk")
                        .font(DS.Font.caption).foregroundStyle(DS.textTertiary)
                }
            }
        }
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack(alignment: .top) {
            Text(k).font(.system(size: 12)).foregroundStyle(.secondary).frame(width: 160, alignment: .leading)
            Text(v).font(.system(size: 12, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                .textSelection(.enabled)
            Spacer()
        }
    }
}
