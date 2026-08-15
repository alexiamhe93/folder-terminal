import AppKit
import Combine
import Darwin
import FolderTerminalCore
import SwiftTerm
import SwiftUI

/// Owns the live terminal views for the whole app.
///
/// The registry — not SwiftUI — decides when a shell dies. Adding or moving a
/// panel rewrites the layout tree, which changes the structural identity of
/// every view beneath the node that changed; SwiftUI responds by tearing down
/// the `NSViewRepresentable`s in that subtree and building new ones. When the
/// terminal view was created in `makeNSView` and killed in `dismantleNSView`,
/// that meant opening a second terminal killed the shell running in the first.
///
/// So terminals are created once, keyed by panel ID, held strongly here, and
/// handed back to whichever representable is currently hosting them. They are
/// terminated only by `terminateTerminals(keeping:)`, when the panel that owned
/// the shell is genuinely gone from the document.
@MainActor
final class TerminalRegistry: ObservableObject {
    static let defaultFontSize: CGFloat = 13
    private static let fontSizeKey = "TerminalFontSize"
    private static let fontSizeRange: ClosedRange<CGFloat> = 8...32

    private var terminals: [UUID: FocusableTerminalView] = [:]
    private var coordinators: [UUID: TerminalProcessCoordinator] = [:]
    private var documentSubscription: AnyCancellable?
    @Published private(set) var registeredTerminalIDs: Set<UUID> = []
    @Published private(set) var fontSize: CGFloat

    init() {
        let saved = UserDefaults.standard.double(forKey: Self.fontSizeKey)
        fontSize = saved > 0
            ? min(max(saved, Self.fontSizeRange.lowerBound), Self.fontSizeRange.upperBound)
            : Self.defaultFontSize
    }

    private var terminalFont: NSFont {
        .monospacedSystemFont(ofSize: fontSize, weight: .regular)
    }

    /// Watch the document for panels leaving. This is a subscription rather
    /// than an `onChange` in the view because view-level change handlers were
    /// not firing for every layout edit — a panel closed while its shell kept
    /// running with nothing on screen to reach it.
    func watchForClosedPanels(in store: WorkspaceStore) {
        documentSubscription = store.$document
            .receive(on: DispatchQueue.main)
            .sink { [weak self] document in
                self?.terminateTerminals(keeping: document.terminalPanelIDs)
            }
    }

    /// The live terminal for this panel, starting its shell on first request.
    /// Later calls return the same view with the same process still attached.
    func terminalView(
        for id: UUID,
        initialDirectory: String?,
        store: WorkspaceStore
    ) -> FocusableTerminalView {
        if let existing = terminals[id] {
            existing.onActivate = { [weak store] in store?.select(id) }
            return existing
        }

        let terminal = FocusableTerminalView(frame: NSRect(x: 0, y: 0, width: 640, height: 400))
        terminal.wantsLayer = true
        applyCurrentTheme(to: terminal)
        terminal.font = terminalFont
        terminal.onActivate = { [weak store] in store?.select(id) }
        try? terminal.setUseMetal(false)

        let coordinator = TerminalProcessCoordinator(panelID: id, store: store)
        terminal.processDelegate = coordinator
        coordinators[id] = coordinator
        terminals[id] = terminal
        registeredTerminalIDs.insert(id)

        let shell = configuredShell()
        terminal.startProcess(
            executable: shell,
            environment: terminalEnvironment(),
            execName: "-" + URL(fileURLWithPath: shell).lastPathComponent,
            currentDirectory: validDirectory(initialDirectory)
        )
        return terminal
    }

    /// Terminate every shell whose panel has left the document. This is the
    /// only path that kills a terminal.
    func terminateTerminals(keeping liveIDs: Set<UUID>) {
        for (id, terminal) in terminals where !liveIDs.contains(id) {
            let shellPID = terminal.process?.shellPid ?? 0
            terminal.terminate()
            terminal.removeFromSuperview()
            terminals.removeValue(forKey: id)
            coordinators.removeValue(forKey: id)
            registeredTerminalIDs.remove(id)
            hangUp(shellPID: shellPID)
        }
    }

    /// `LocalProcessTerminalView.terminate()` closes the pty and sends SIGTERM,
    /// which an interactive shell ignores — the shell and everything running
    /// under it survived a closed panel with no way left to reach them. A real
    /// terminal hangs up instead, so do that: SIGHUP to the whole foreground
    /// process group, and SIGKILL to whatever is still there a moment later.
    private func hangUp(shellPID: pid_t) {
        guard shellPID > 0 else { return }
        if kill(-shellPID, SIGHUP) != 0 { kill(shellPID, SIGHUP) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            guard kill(shellPID, 0) == 0 else { return }
            if kill(-shellPID, SIGKILL) != 0 { kill(shellPID, SIGKILL) }
        }
    }

    func activeTerminalIDs(in ids: [UUID]) -> [UUID] {
        ids.filter { terminals[$0] != nil }
    }

    func changeDirectory(path: String, terminalIDs: [UUID]) {
        let bytes = Array(ShellEscaping.changeDirectoryCommand(path: path).utf8)
        for id in terminalIDs {
            guard let terminal = terminals[id] else { continue }
            terminal.send(source: terminal, data: bytes[...])
        }
    }

    /// Terminal.app-style ⌘K: drop the scrollback locally, then ask the live
    /// shell to repaint its screen and prompt with Ctrl-L.
    func clearBuffer(terminalID: UUID) {
        guard let terminal = terminals[terminalID] else { return }
        terminal.feed(text: "\u{1b}[3J")
        let controlL: [UInt8] = [0x0C]
        terminal.send(source: terminal, data: controlL[...])
    }

    func adjustFontSize(by delta: CGFloat) {
        setFontSize(fontSize + delta)
    }

    func resetFontSize() {
        setFontSize(Self.defaultFontSize)
    }

    /// Repaints existing terminal canvases as well as future ones. The live
    /// terminal views and their processes stay in the registry, so changing a
    /// theme never restarts a shell or loses scrollback.
    func applyCurrentTheme() {
        for terminal in terminals.values { applyCurrentTheme(to: terminal) }
    }

    private func applyCurrentTheme(to terminal: FocusableTerminalView) {
        terminal.nativeForegroundColor = Theme.terminalForegroundNSColor
        terminal.nativeBackgroundColor = Theme.terminalBackgroundNSColor
        terminal.layer?.backgroundColor = terminal.nativeBackgroundColor.cgColor
        terminal.caretColor = Theme.terminalCaretNSColor
        terminal.installColors(Theme.ansiColors)
        terminal.needsDisplay = true
    }

    func setFontSize(_ size: CGFloat) {
        fontSize = min(max(size, Self.fontSizeRange.lowerBound), Self.fontSizeRange.upperBound)
        UserDefaults.standard.set(Double(fontSize), forKey: Self.fontSizeKey)
        for terminal in terminals.values {
            terminal.font = terminalFont
        }
    }
}

private func configuredShell() -> String {
    if let shell = ProcessInfo.processInfo.environment["SHELL"], !shell.isEmpty { return shell }
    if let entry = getpwuid(getuid()), let shell = entry.pointee.pw_shell { return String(cString: shell) }
    return "/bin/zsh"
}

private func terminalEnvironment() -> [String] {
    var environment = ProcessInfo.processInfo.environment
    environment["TERM"] = "xterm-256color"
    environment["COLORTERM"] = "truecolor"
    return environment.map { "\($0.key)=\($0.value)" }
}

private func validDirectory(_ path: String?) -> String {
    guard let path else { return FileManager.default.homeDirectoryForCurrentUser.path }
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
          isDirectory.boolValue,
          FileManager.default.isReadableFile(atPath: path) else {
        return FileManager.default.homeDirectoryForCurrentUser.path
    }
    return path
}

struct TerminalPanelView: View {
    let panelID: UUID
    let state: TerminalPanelState
    @ObservedObject var store: WorkspaceStore
    @ObservedObject var terminals: TerminalRegistry
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            TimelineView(.periodic(from: .now, by: 2)) { _ in
                GeometryReader { proxy in
                    headerContent(compact: proxy.size.width < 620)
                }
            }
            .frame(height: Theme.Metrics.headerHeight)
            .background(Theme.headerBackground)

            TerminalRepresentable(
                panelID: panelID,
                initialDirectory: state.environmentFolder,
                isSelected: store.selectedPanelID == panelID,
                store: store,
                registry: terminals
            )
        }
        .alert("Terminal", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
    }

    private var linkedFolder: String? {
        guard let linked = state.linkedFilePanelID,
              let panel = store.panel(id: linked), case .file(let file) = panel.kind,
              !file.requiresReselection else { return nil }
        return file.currentFolder
    }

    private var canGoHere: Bool {
        guard let linkedFolder, store.isFolderAvailable(at: linkedFolder) else { return false }
        return terminals.registeredTerminalIDs.contains(panelID)
    }

    @ViewBuilder
    private func headerContent(compact: Bool) -> some View {
        HStack(spacing: Theme.Metrics.gap) {
            if compact {
                statusLabel(icon: "link", value: linkedBrowserName, help: "Linked browser")
                statusLabel(
                    icon: pinnedFolderIsUnavailable ? "exclamationmark.triangle.fill" : pinnedIcon,
                    value: pinnedFolderIsUnavailable ? "Unavailable: \(pinnedFolderName)" : pinnedFolderName,
                    help: pinnedFolderHelp,
                    isUnavailable: pinnedFolderIsUnavailable
                )
                statusLabel(icon: "terminal", value: shellStatus, help: shellStatusHelp)
            } else {
                labeledStatus(label: "Linked browser", icon: "link", value: linkedBrowserName)
                labeledStatus(
                    label: pinnedFolderIsUnavailable ? "Pinned folder unavailable" : "Pinned folder",
                    icon: pinnedFolderIsUnavailable ? "exclamationmark.triangle.fill" : pinnedIcon,
                    value: pinnedFolderName,
                    isUnavailable: pinnedFolderIsUnavailable
                )
                labeledStatus(label: "Shell", icon: "terminal", value: shellStatus)
                Spacer(minLength: 0)
                Button("Go Here in Terminal") { goHere() }
                    .disabled(!canGoHere)
                    .tip("Move this shell to the linked browser's folder (⌘⏎)")
            }

            Spacer(minLength: 0)
            overflowMenu(includesGoHere: compact)
        }
        .font(Theme.Typography.status)
        .padding(.horizontal, Theme.Metrics.gutter)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func labeledStatus(
        label: String,
        icon: String,
        value: String,
        isUnavailable: Bool = false
    ) -> some View {
        HStack(spacing: Theme.Metrics.tight) {
            Image(systemName: icon)
            Text("\(label):")
                .foregroundStyle(Theme.secondaryText)
            Text(value)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .foregroundStyle(isUnavailable ? Theme.unavailable : Theme.primaryText)
        .tip(isUnavailable ? pinnedFolderHelp : value)
    }

    private func statusLabel(
        icon: String,
        value: String,
        help: String,
        isUnavailable: Bool = false
    ) -> some View {
        Label(value, systemImage: icon)
            .lineLimit(1)
            .truncationMode(.middle)
            .foregroundStyle(isUnavailable ? Theme.unavailable : Theme.primaryText)
            .tip("\(help): \(value)")
    }

    private func overflowMenu(includesGoHere: Bool) -> some View {
        Menu {
            if includesGoHere {
                Button("Go Here in Terminal") { goHere() }
                    .disabled(!canGoHere)
                Divider()
            }
            if let pinned = state.environmentFolder {
                Button("Copy Pinned Folder Path") { PathPasteboard.copy(paths: [pinned]) }
            }
            if let working = state.lastWorkingFolder {
                Button("Copy Shell Working Path") { PathPasteboard.copy(paths: [working]) }
            }
            Divider()
            Button("Unpin") { store.unpinFolder(for: panelID) }
                .disabled(state.environmentFolder == nil)
            Menu("Linked Browser") {
                Button {
                    store.bindTerminal(panelID, to: nil)
                } label: {
                    menuLabel("None", selected: state.linkedFilePanelID == nil)
                }
                Divider()
                ForEach(store.filePanels) { panel in
                    if case .file(let file) = panel.kind {
                        Button {
                            store.bindTerminal(panelID, to: panel.id)
                        } label: {
                            menuLabel(
                                URL(fileURLWithPath: file.currentFolder).lastPathComponent,
                                selected: state.linkedFilePanelID == panel.id
                            )
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .tip("Terminal actions — pin, unpin, link a browser")
    }

    private func menuLabel(_ title: String, selected: Bool) -> some View {
        Label(title, systemImage: selected ? "checkmark" : "circle")
    }

    private var linkedBrowserName: String {
        guard let linked = state.linkedFilePanelID,
              let panel = store.panel(id: linked), case .file(let file) = panel.kind else { return "None" }
        return URL(fileURLWithPath: file.currentFolder).lastPathComponent
    }

    private var pinnedFolderIsUnavailable: Bool {
        guard let folder = state.environmentFolder else { return false }
        return !store.isFolderAvailable(at: folder)
    }

    private var pinnedIcon: String {
        state.environmentFolder == nil ? "pin.slash" : "pin.fill"
    }

    private var pinnedFolderName: String {
        guard let folder = state.environmentFolder else { return "None" }
        return URL(fileURLWithPath: folder).lastPathComponent
    }

    private var pinnedFolderHelp: String {
        guard let folder = state.environmentFolder else { return "No pinned folder" }
        return pinnedFolderIsUnavailable ? "Pinned folder unavailable: \(folder)" : folder
    }

    private var shellStatus: String {
        guard let working = state.lastWorkingFolder else { return "Waiting…" }
        if let pinned = state.environmentFolder,
           URL(fileURLWithPath: pinned).standardizedFileURL.path
            == URL(fileURLWithPath: working).standardizedFileURL.path {
            return "Shell here"
        }
        return working
    }

    private var shellStatusHelp: String {
        state.lastWorkingFolder ?? "Waiting for the shell to report its location"
    }

    private func goHere() {
        guard let linkedFolder, canGoHere else { return }
        do {
            try store.pinFolder(linkedFolder, for: panelID)
            terminals.changeDirectory(path: linkedFolder, terminalIDs: [panelID])
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

final class FocusableTerminalView: LocalProcessTerminalView {
    var onActivate: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        onActivate?()
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }
}

/// The disposable half of a terminal panel: a plain container SwiftUI is free
/// to create and destroy as the layout changes, hosting a terminal view whose
/// life is managed by `TerminalRegistry`.
private final class TerminalHostView: NSView {
    private weak var hosted: FocusableTerminalView?

    func attach(_ terminal: FocusableTerminalView) {
        guard terminal.superview !== self else { return }
        hosted = terminal
        terminal.removeFromSuperview()
        terminal.frame = bounds
        terminal.autoresizingMask = [.width, .height]
        addSubview(terminal)
    }

    /// Give the terminal up only if it is still ours. SwiftUI does not promise
    /// whether the new host is built before or after the old one is dismantled;
    /// if the terminal has already moved on, this must be a no-op rather than
    /// yanking it out of its new parent.
    func detachIfStillHosting() {
        guard let hosted, hosted.superview === self else { return }
        hosted.removeFromSuperview()
    }
}

private struct TerminalRepresentable: NSViewRepresentable {
    let panelID: UUID
    let initialDirectory: String?
    let isSelected: Bool
    let store: WorkspaceStore
    let registry: TerminalRegistry

    func makeNSView(context: Context) -> NSView {
        let host = TerminalHostView(frame: .zero)
        let terminal = registry.terminalView(
            for: panelID,
            initialDirectory: initialDirectory,
            store: store
        )
        host.attach(terminal)
        if isSelected {
            DispatchQueue.main.async { terminal.window?.makeFirstResponder(terminal) }
        }
        return host
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let host = nsView as? TerminalHostView else { return }
        let terminal = registry.terminalView(
            for: panelID,
            initialDirectory: initialDirectory,
            store: store
        )
        host.attach(terminal)
        if isSelected, terminal.window?.firstResponder !== terminal {
            DispatchQueue.main.async { terminal.window?.makeFirstResponder(terminal) }
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: ()) {
        (nsView as? TerminalHostView)?.detachIfStillHosting()
    }
}

/// Reports the shell's working directory back to the store. Held by the
/// registry for as long as its terminal lives.
private final class TerminalProcessCoordinator: NSObject, LocalProcessTerminalViewDelegate {
    let panelID: UUID
    weak var store: WorkspaceStore?

    init(panelID: UUID, store: WorkspaceStore) {
        self.panelID = panelID
        self.store = store
    }

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
    func processTerminated(source: TerminalView, exitCode: Int32?) {}

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        guard let directory else { return }
        let path = URL(string: directory)?.isFileURL == true
            ? URL(string: directory)?.path
            : directory
        guard let path else { return }
        Task { @MainActor [weak self] in
            guard let self, let store = self.store else { return }
            store.reportWorkingFolder(path, for: self.panelID)
        }
    }
}
