import AppKit
import FolderTerminalCore
import SwiftUI

/// Resolves the ⌘W collision. AppKit installs "Close" on ⌘W in the File menu,
/// and the app's own "Close Panel" claims the same key — AppKit's wins, so a
/// stray ⌘W closed the whole window and, with it, every running shell. Panels
/// are what you close often; the window is not. So the window's Close moves to
/// ⇧⌘W and ⌘W is left to "Close Panel".
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let fileMenu = NSApp.mainMenu?.item(withTitle: "File")?.submenu else { return }
        for item in fileMenu.items where item.keyEquivalent == "w"
            && item.keyEquivalentModifierMask == .command {
            item.keyEquivalentModifierMask = [.command, .shift]
        }
    }
}

@main
struct FolderTerminalApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = WorkspaceStore()
    @StateObject private var terminals = TerminalRegistry()
    @AppStorage(AppSettings.themeKey) private var theme = AppSettings.themeDefault.rawValue

    init() {
        NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
    }

    var body: some Scene {
        // A single Window scene: the workspace store is shared app-wide, so a
        // second window would render the same panels and double-register the
        // live terminal views.
        Window("Folder Terminal", id: "main") {
            WorkspaceView(store: store, terminals: terminals)
                // Theme colours are plain semantic tokens. Rebuilding the
                // hosts makes every SwiftUI surface pick up a new set at once;
                // TerminalRegistry keeps the live shells attached throughout.
                .id(theme)
                .frame(minWidth: 900, minHeight: 580)
                .preferredColorScheme(.dark)
                .task { terminals.watchForClosedPanels(in: store) }
                .onChange(of: theme) { _, _ in terminals.applyCurrentTheme() }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            WorkspaceCommands(store: store, terminals: terminals)
        }

        Settings {
            SettingsView(terminals: terminals)
                .preferredColorScheme(.dark)
        }
    }
}

struct WorkspaceCommands: Commands {
    @ObservedObject var store: WorkspaceStore
    @ObservedObject var terminals: TerminalRegistry
    @FocusedValue(\.fileBrowserActions) private var browserActions

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("New Folder Panel") { addFile() }
                .keyboardShortcut("f", modifiers: [.command, .shift])
            Button("New Terminal Panel") { addTerminal() }
                .keyboardShortcut("t", modifiers: [.command, .shift])
            Divider()
            Button("New Folder") { browserActions?.newFolder() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(browserActions == nil)
        }
        CommandMenu("File Browser") {
            Button("Open Selection") { browserActions?.openSelection?() }
                .keyboardShortcut(.downArrow, modifiers: .command)
                .disabled(browserActions?.openSelection == nil)
            Button("Enclosing Folder") { browserActions?.enclosingFolder?() }
                .keyboardShortcut(.upArrow, modifiers: .command)
                .disabled(browserActions?.enclosingFolder == nil)
            Divider()
            Button("Copy Path") { browserActions?.copyPaths() }
                .keyboardShortcut("c", modifiers: [.command, .option])
                .disabled(browserActions == nil)
            Button("Copy Name") { browserActions?.copyNames?() }
                .disabled(browserActions?.copyNames == nil)
            Divider()
            Button("Rename") { browserActions?.renameSelection?() }
                .disabled(browserActions?.renameSelection == nil)
            Button("Duplicate") { browserActions?.duplicateSelection?() }
                .disabled(browserActions?.duplicateSelection == nil)
            Divider()
            Button("Move to Trash") { browserActions?.trashSelection?() }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(browserActions?.trashSelection == nil)
        }
        CommandMenu("Terminal") {
            Button("Clear Terminal") {
                if let id = selectedRegisteredTerminalID { terminals.clearBuffer(terminalID: id) }
            }
            .keyboardShortcut("k", modifiers: .command)
            .disabled(selectedRegisteredTerminalID == nil)
            Divider()
            Button("Increase Font Size") { terminals.adjustFontSize(by: 1) }
                .keyboardShortcut("=", modifiers: .command)
            Button("Decrease Font Size") { terminals.adjustFontSize(by: -1) }
                .keyboardShortcut("-", modifiers: .command)
            Button("Reset Font Size") { terminals.resetFontSize() }
                .keyboardShortcut("0", modifiers: .command)
        }
        CommandMenu("Panel") {
            Button("Split Vertically") { store.splitSelected(orientation: .vertical) }
                .keyboardShortcut("d", modifiers: .command)
                .disabled(store.selectedPanelID == nil)
            Button("Split Horizontally") { store.splitSelected(orientation: .horizontal) }
                .keyboardShortcut("d", modifiers: [.command, .shift])
                .disabled(store.selectedPanelID == nil)
            Divider()
            Button("Choose Folder…") { chooseFolderForSelection() }
                .keyboardShortcut("o", modifiers: .command)
                .disabled(selectedFilePanel == nil)
            Button(goHereTitle) { goHereFromSelectedBrowser() }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!canGoHere)
            Divider()
            Button("Close Panel") {
                if let id = store.selectedPanelID { store.closePanel(id: id) }
            }
            .keyboardShortcut("w", modifiers: .command)
            .disabled(store.selectedPanelID == nil || store.document.layout.panelIDs.count < 2)
        }
    }

    private func addFile() {
        store.addPanel(
            AppSettings.newFilePanel(at: AppSettings.homeFolder),
            orientation: AppSettings.newPanelPlacement
        )
    }

    private func addTerminal() {
        let selected = store.selectedPanelID
        let linked = selected.flatMap { id -> UUID? in
            guard let panel = store.panel(id: id), case .file = panel.kind else { return nil }
            return id
        } ?? store.filePanels.first?.id
        store.addPanel(.terminal(linkedTo: linked), orientation: AppSettings.newPanelPlacement)
    }

    private func chooseFolderForSelection() {
        guard let id = store.selectedPanelID,
              let panel = store.panel(id: id), case .file = panel.kind else { return }
        FolderPicker.choose { url in
            if let url { try? store.setFolder(url, for: id) }
        }
    }

    private var selectedRegisteredTerminalID: UUID? {
        guard let id = store.selectedPanelID,
              let panel = store.panel(id: id), case .terminal = panel.kind,
              terminals.registeredTerminalIDs.contains(id) else { return nil }
        return id
    }

    private var selectedFilePanel: (id: UUID, state: FilePanelState)? {
        guard let id = store.selectedPanelID,
              let panel = store.panel(id: id), case .file(let state) = panel.kind else { return nil }
        return (id, state)
    }

    private var selectedLinkedTerminalIDs: [UUID] {
        guard let selectedFilePanel else { return [] }
        return store.terminalsLinked(to: selectedFilePanel.id).map(\.id)
    }

    private var canGoHere: Bool {
        guard let selectedFilePanel else { return false }
        let terminalIDs = selectedLinkedTerminalIDs
        return !terminalIDs.isEmpty
            && terminalIDs.allSatisfy { terminals.registeredTerminalIDs.contains($0) }
            && store.isFolderAvailable(at: selectedFilePanel.state.currentFolder)
    }

    private var goHereTitle: String {
        let count = selectedLinkedTerminalIDs.count
        return count <= 1 ? "Go Here in Terminal" : "Go Here in \(count) Terminals"
    }

    private func goHereFromSelectedBrowser() {
        guard let selectedFilePanel, canGoHere else { return }
        let terminalIDs = selectedLinkedTerminalIDs
        do {
            try store.pinFolder(selectedFilePanel.state.currentFolder, for: terminalIDs)
            terminals.changeDirectory(path: selectedFilePanel.state.currentFolder, terminalIDs: terminalIDs)
        } catch {
            return
        }
    }
}

enum FolderPicker {
    static func choose(completion: @escaping (URL?) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.begin { response in completion(response == .OK ? panel.url : nil) }
    }
}
