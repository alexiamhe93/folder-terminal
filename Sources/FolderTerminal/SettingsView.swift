import FolderTerminalCore
import SwiftUI

/// The ⌘, preferences window. One form, two groups — deliberately small.
struct SettingsView: View {
    @ObservedObject var terminals: TerminalRegistry
    @AppStorage(AppSettings.showTooltipsKey) private var showTooltips = AppSettings.showTooltipsDefault
    @AppStorage(AppSettings.defaultViewModeKey) private var defaultViewMode = AppSettings.defaultViewModeDefault.rawValue
    @AppStorage(AppSettings.defaultShowHiddenFilesKey) private var defaultShowHiddenFiles = AppSettings.defaultShowHiddenFilesDefault
    @AppStorage(AppSettings.newPanelPlacementKey) private var newPanelPlacement = AppSettings.newPanelPlacementDefault.rawValue
    @AppStorage(AppSettings.themeKey) private var theme = AppSettings.themeDefault.rawValue

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $theme) {
                    ForEach(AppTheme.allCases) { option in
                        Text(option.displayName).tag(option.rawValue)
                    }
                }
                ThemePreview(theme: AppTheme(rawValue: theme) ?? AppSettings.themeDefault)

                LabeledContent("Terminal font size") {
                    HStack(spacing: Theme.Metrics.gap) {
                        Text("\(Int(terminals.fontSize)) pt")
                            .font(Theme.Typography.path)
                            .foregroundStyle(Theme.secondaryText)
                            .frame(width: 44, alignment: .leading)
                        Stepper("Terminal font size", value: Binding(
                            get: { terminals.fontSize },
                            set: { terminals.setFontSize($0) }
                        ), in: 8...32, step: 1)
                        .labelsHidden()
                        Button("Reset") { terminals.resetFontSize() }
                            .tip("Return the terminal to its default font size (⌘0)")
                    }
                }
            }

            Section("Panels") {
                Picker("New panels open as", selection: $newPanelPlacement) {
                    ForEach(SplitOrientation.allCases, id: \.rawValue) { orientation in
                        Text(orientation.placementName).tag(orientation.rawValue)
                    }
                }
                .tip("Where a new panel goes relative to the selected one")
                Text("Split Vertically (⌘D) and Split Horizontally (⇧⌘D) still place a panel explicitly.")
                    .font(Theme.Typography.status)
                    .foregroundStyle(Theme.secondaryText)
            }

            Section("Behaviour") {
                Toggle("Show tooltips on hover", isOn: $showTooltips)
                    .tip("Turn off to stop controls describing themselves on hover")
                Text("Tooltips name each control and its keyboard shortcut.")
                    .font(Theme.Typography.status)
                    .foregroundStyle(Theme.secondaryText)

                Picker("New browser panels open in", selection: $defaultViewMode) {
                    ForEach(FileViewMode.allCases, id: \.rawValue) { mode in
                        Text(mode.displayName).tag(mode.rawValue)
                    }
                }
                Toggle("New browser panels show hidden files", isOn: $defaultShowHiddenFiles)
                Text("Existing panels keep the view mode and options they were saved with.")
                    .font(Theme.Typography.status)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct ThemePreview: View {
    let theme: AppTheme

    var body: some View {
        let colours = Theme.previewColors(for: theme)
        HStack(spacing: Theme.Metrics.gap) {
            HStack(spacing: Theme.Metrics.tight) {
                ForEach(colours.indices, id: \.self) { index in
                    Circle()
                        .fill(colours[index])
                        .frame(width: 14, height: 14)
                        .overlay(Circle().stroke(Color.white.opacity(0.16), lineWidth: 1))
                }
            }
            Text(theme.summary)
                .font(Theme.Typography.status)
                .foregroundStyle(Theme.secondaryText)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(theme.displayName): \(theme.summary)")
    }
}
