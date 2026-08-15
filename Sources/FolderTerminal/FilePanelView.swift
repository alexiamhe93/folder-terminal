import AppKit
import FolderTerminalCore
import SwiftUI
import UniformTypeIdentifiers
import _QuickLook_SwiftUI

struct FileEntry: Identifiable, Hashable {
    let url: URL
    let isDirectory: Bool
    let dateModified: Date
    let size: Int64
    var id: String { url.path }

    init(url: URL, isDirectory: Bool, dateModified: Date = .distantPast, size: Int64 = 0) {
        self.url = url
        self.isDirectory = isDirectory
        self.dateModified = dateModified
        self.size = size
    }
}

/// Menu-bar actions the focused file browser publishes so WorkspaceCommands
/// can route File-menu items (New Folder, Open, Move to Trash, …) to it.
struct FileBrowserActions {
    var newFolder: () -> Void
    var openSelection: (() -> Void)?
    var renameSelection: (() -> Void)?
    var duplicateSelection: (() -> Void)?
    var trashSelection: (() -> Void)?
    var enclosingFolder: (() -> Void)?
    /// Copies the selection's paths, or the browsed folder's path when nothing
    /// is selected — so ⌥⌘C always has a sensible answer.
    var copyPaths: () -> Void = {}
    var copyNames: (() -> Void)?
}

/// Reads dropped item providers into file URLs and delivers them on the main
/// queue once every provider has reported. Shared by the list and column
/// browsers.
func loadDroppedFileURLs(
    _ providers: [NSItemProvider],
    completion: @escaping ([URL]) -> Void
) -> Bool {
    let fileProviders = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
    guard !fileProviders.isEmpty else { return false }
    var urls: [URL] = []
    let group = DispatchGroup()
    for provider in fileProviders {
        group.enter()
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            if let url { urls.append(url) }
            group.leave()
        }
    }
    group.notify(queue: .main) {
        if !urls.isEmpty { completion(urls) }
    }
    return true
}

struct FileBrowserActionsKey: FocusedValueKey {
    typealias Value = FileBrowserActions
}

extension FocusedValues {
    var fileBrowserActions: FileBrowserActions? {
        get { self[FileBrowserActionsKey.self] }
        set { self[FileBrowserActionsKey.self] = newValue }
    }
}

/// Watches one directory for content changes with a short debounce so the
/// listing refreshes after both our own operations and external ones
/// (a linked terminal's `mv`/`rm`, Finder, etc.).
@MainActor
final class FolderWatcher {
    private var source: DispatchSourceFileSystemObject?
    private var pending: DispatchWorkItem?

    func watch(path: String, onChange: @escaping () -> Void) {
        stop()
        let descriptor = open(path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .delete, .rename],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            guard let self else { return }
            self.pending?.cancel()
            let item = DispatchWorkItem(block: onChange)
            self.pending = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: item)
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        self.source = source
    }

    func stop() {
        pending?.cancel()
        pending = nil
        source?.cancel()
        source = nil
    }
}

struct FilePanelView: View {
    let panelID: UUID
    let state: FilePanelState
    @ObservedObject var store: WorkspaceStore
    @ObservedObject var terminals: TerminalRegistry
    @State private var quickLookURL: URL?
    @State private var errorMessage: String?
    @State private var listing: [FileEntry] = []
    @State private var selectedEntryPaths: Set<String> = []
    @State private var selectionAnchorPath: String?
    @State private var renamingEntryPath: String?
    @State private var renameText = ""
    @State private var listingVersion = 0
    @State private var watcher = FolderWatcher()
    @FocusState private var browserFocused: Bool

    private struct ListingKey: Hashable {
        let folder: String
        let showHidden: Bool
        let sortField: FileSortField
        let sortAscending: Bool
        let version: Int
    }

    var body: some View {
        VStack(spacing: 0) {
            navigationBar
            Divider()
            if browserFolderIsUnavailable {
                inaccessibleFolder
            } else {
                switch state.viewMode {
                case .list: listView
                case .column: columnView
                case .tree: treeView
                }
            }
        }
        .quickLookPreview($quickLookURL)
        .alert("Folder Browser", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
        .task(id: ListingKey(
            folder: state.currentFolder,
            showHidden: state.showHiddenFiles,
            sortField: state.sortField,
            sortAscending: state.sortAscending,
            version: listingVersion
        )) {
            reloadListing()
        }
        .onChange(of: state.currentFolder) { _, folder in
            clearSelection()
            renamingEntryPath = nil
            startWatching(folder)
        }
        .onAppear { startWatching(state.currentFolder) }
        .onDisappear { watcher.stop() }
        .focusedValue(\.fileBrowserActions, browserActions)
    }

    // MARK: Navigation bar

    private var navigationBar: some View {
        GeometryReader { proxy in
            // The expanded bar needs enough room for a useful breadcrumb, not
            // merely enough room to squeeze every control onto one line.
            if proxy.size.width < 820 {
                compactNavigationBar
            } else {
                expandedNavigationBar
            }
        }
        .frame(height: Theme.Metrics.headerHeight)
        .background(Theme.headerBackground)
    }

    private var expandedNavigationBar: some View {
        HStack(spacing: Theme.Metrics.tight) {
            historyControls

            pathBar

            viewPicker

            listOptionsMenu

            Button { chooseFolder() } label: {
                Label("Choose Root", systemImage: "folder")
            }
            .font(Theme.Typography.status)
            .tip("Choose the root folder for this browser")
            Button(goHereTitle) { goHere(path: state.currentFolder) }
                .font(Theme.Typography.status)
                .tip("Pin this folder and move each linked shell to it (⌘⏎)")
                .disabled(!canGoHere)
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, Theme.Metrics.gap)
        .frame(maxHeight: .infinity)
    }

    private var compactNavigationBar: some View {
        HStack(spacing: Theme.Metrics.tight) {
            historyControls
            pathBar
            Menu {
                Button(goHereTitle) { goHere(path: state.currentFolder) }
                    .disabled(!canGoHere)
                Button("Copy Folder Path") { PathPasteboard.copy(paths: [state.currentFolder]) }
                Divider()
                viewModePicker
                listOptionsContent
                Button("Choose Root Folder…") { chooseFolder() }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .tip("Browser options")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, Theme.Metrics.gap)
        .frame(maxHeight: .infinity)
    }

    private var historyControls: some View {
        Group {
            Button { goBack() } label: { Image(systemName: "chevron.left") }
                .disabled(state.backHistory.isEmpty)
                .tip("Back")
            Button { goForward() } label: { Image(systemName: "chevron.right") }
                .disabled(state.forwardHistory.isEmpty)
                .tip("Forward")
            Button { navigate(to: URL(fileURLWithPath: state.rootFolder), recordHistory: true) } label: {
                Image(systemName: "house")
            }
            .disabled(state.currentFolder == state.rootFolder)
            .tip("Back to the root folder")
        }
    }

    /// Breadcrumbs for the browsed folder. Each crumb navigates on click and
    /// lists its subfolders on the dropdown, so you can move sideways without
    /// walking up first.
    private var pathBar: some View {
        PathBar(
            root: state.rootFolder,
            current: state.currentFolder,
            navigate: { path in
                browserFocused = true
                navigate(to: URL(fileURLWithPath: path), recordHistory: true)
            },
            subfolders: { path in
                entries(at: URL(fileURLWithPath: path))
                    .filter(\.isDirectory)
                    .map(\.url)
            }
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .contextMenu {
            Button("Copy Folder Path") { PathPasteboard.copy(paths: [state.currentFolder]) }
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([currentFolderURL])
            }
        }
    }

    private var viewModeBinding: Binding<FileViewMode> {
        Binding(
            get: { state.viewMode },
            set: { mode in updateState { $0.viewMode = mode } }
        )
    }

    private var viewPicker: some View {
        Picker("View", selection: viewModeBinding) {
            ForEach(FileViewMode.allCases, id: \.self) { mode in
                Image(systemName: mode.symbolName).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 104)
        .tip("View as list, columns, or tree")
    }

    /// The same choice as `viewPicker`, in menu form for the compact bar.
    private var viewModePicker: some View {
        Picker("View", selection: viewModeBinding) {
            ForEach(FileViewMode.allCases, id: \.self) { mode in
                Text(mode.displayName).tag(mode)
            }
        }
    }

    private var listOptionsMenu: some View {
        Menu {
            listOptionsContent
        } label: {
            Image(systemName: "arrow.up.arrow.down")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .tip("Sort and visibility options")
    }

    @ViewBuilder
    private var listOptionsContent: some View {
        Picker("Sort By", selection: Binding(
            get: { state.sortField },
            set: { field in updateState { $0.sortField = field } }
        )) {
            Text("Name").tag(FileSortField.name)
            Text("Date Modified").tag(FileSortField.dateModified)
            Text("Size").tag(FileSortField.size)
        }
        Picker("Order", selection: Binding(
            get: { state.sortAscending },
            set: { ascending in updateState { $0.sortAscending = ascending } }
        )) {
            Text("Ascending").tag(true)
            Text("Descending").tag(false)
        }
        Divider()
        Toggle("Show Hidden Files", isOn: Binding(
            get: { state.showHiddenFiles },
            set: { show in updateState { $0.showHiddenFiles = show } }
        ))
    }

    // MARK: List view

    private var listView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(listing) { entry in
                    FileEntryRow(
                        entry: entry,
                        isSelected: selectedEntryPaths.contains(entry.id),
                        isRenaming: renamingEntryPath == entry.id,
                        renameText: $renameText,
                        select: { handleClick(on: entry) },
                        open: { open(entry) },
                        quickLook: { quickLookSelection(fallback: entry) },
                        commitRename: { commitRename(of: entry) },
                        cancelRename: { renamingEntryPath = nil },
                        dropURLs: entry.isDirectory
                            ? { urls in receiveDrop(urls, into: entry.url) }
                            : nil,
                        contextMenu: { entryContextMenu(for: entry) },
                        isPanelFocused: browserFocused
                    )
                    Divider()
                        .overlay(Theme.divider)
                        .padding(.leading, Theme.Metrics.gap * 2 + Theme.Metrics.iconSize)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { clearSelection(); browserFocused = true }
        .focusable()
        .focusEffectDisabled()
        .focused($browserFocused)
        .onMoveCommand(perform: moveSelection)
        .onKeyPress(.space) { quickLookSelection(fallback: nil); return .handled }
        .onKeyPress(.return) { beginRenamingSelection(); return .handled }
        .copyable(selectedURLs)
        .pasteDestination(for: URL.self) { urls in
            perform { try FileOperations.copy(urls, into: currentFolderURL) }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            loadDroppedFileURLs(providers) { urls in receiveDrop(urls, into: currentFolderURL) }
        }
    }

    // MARK: Column view

    private var columnView: some View {
        ColumnBrowserView(
            root: state.rootFolder,
            current: state.currentFolder,
            selectedEntryPaths: selectedEntryPaths,
            renamingEntryPath: renamingEntryPath,
            renameText: $renameText,
            isPanelFocused: browserFocused,
            entries: { folder in entries(at: folder) },
            navigate: { url in
                browserFocused = true
                navigate(to: url, recordHistory: true)
            },
            select: { entry in handleClick(on: entry) },
            open: { entry in open(entry) },
            quickLook: { entry in if !entry.isDirectory { quickLookURL = entry.url } },
            commitRename: { entry in commitRename(of: entry) },
            cancelRename: { renamingEntryPath = nil },
            receiveDrop: { urls, folder in receiveDrop(urls, into: folder) },
            contextMenu: { entry in entryContextMenu(for: entry) }
        )
        .focusable()
        .focusEffectDisabled()
        .focused($browserFocused)
        .onMoveCommand(perform: moveSelection)
        .onKeyPress(.space) { quickLookSelection(fallback: nil); return .handled }
        .onKeyPress(.return) { beginRenamingSelection(); return .handled }
        .copyable(selectedURLs)
        .pasteDestination(for: URL.self) { urls in
            perform { try FileOperations.copy(urls, into: currentFolderURL) }
        }
    }

    // MARK: Tree view

    private var treeView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(entries(at: URL(fileURLWithPath: state.rootFolder))) { entry in
                    TreeEntryRow(
                        entry: entry,
                        depth: 0,
                        goHereTitle: goHereTitle,
                        canGoHere: canGoHere,
                        selectedEntryPaths: $selectedEntryPaths,
                        listingVersion: listingVersion,
                        showHiddenFiles: state.showHiddenFiles,
                        sortField: state.sortField,
                        sortAscending: state.sortAscending,
                        preview: { url in
                            if FileManager.default.fileExists(atPath: url.path) {
                                quickLookURL = url
                            }
                        },
                        goHere: { url in goHere(path: url.path) },
                        trash: { url in perform { try FileOperations.trash([url]) } },
                        duplicate: { url in perform { try FileOperations.duplicate(url) } }
                    )
                }
            }
            .padding(.vertical, 4)
        }
        .focusable()
        .focusEffectDisabled()
        .focused($browserFocused)
    }

    private var inaccessibleFolder: some View {
        ContentUnavailableView {
            Label("Folder Unavailable", systemImage: "folder.badge.questionmark")
        } description: {
            Text("The saved folder is missing or access could not be restored. The rest of the workspace is intact.")
        } actions: {
            Button("Choose Folder…") { chooseFolder() }
        }
    }

    // MARK: Listing

    private var currentFolderURL: URL {
        URL(fileURLWithPath: state.currentFolder)
    }

    private func reloadListing() {
        listing = entries(at: currentFolderURL)
        let existing = Set(listing.map(\.id))
        selectedEntryPaths.formIntersection(existing)
        if let anchor = selectionAnchorPath, !existing.contains(anchor) {
            selectionAnchorPath = nil
        }
    }

    private func entries(at folder: URL) -> [FileEntry] {
        do {
            var options: FileManager.DirectoryEnumerationOptions = []
            if !state.showHiddenFiles { options.insert(.skipsHiddenFiles) }
            let urls = try FileManager.default.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey, .fileSizeKey],
                options: options
            )
            return urls.map { url in
                let values = try? url.resourceValues(
                    forKeys: [.isDirectoryKey, .contentModificationDateKey, .fileSizeKey]
                )
                return FileEntry(
                    url: url,
                    isDirectory: values?.isDirectory == true,
                    dateModified: values?.contentModificationDate ?? .distantPast,
                    size: Int64(values?.fileSize ?? 0)
                )
            }.sorted {
                FileListing.areInIncreasingOrder(
                    sortKey($0), sortKey($1),
                    field: state.sortField,
                    ascending: state.sortAscending
                )
            }
        } catch {
            DispatchQueue.main.async { errorMessage = error.localizedDescription }
            return []
        }
    }

    private func sortKey(_ entry: FileEntry) -> FileSortKey {
        FileSortKey(
            name: entry.url.lastPathComponent,
            isDirectory: entry.isDirectory,
            dateModified: entry.dateModified,
            size: entry.size
        )
    }

    private func startWatching(_ folder: String) {
        watcher.watch(path: folder) { listingVersion += 1 }
    }

    // MARK: Selection

    private var selectedEntries: [FileEntry] {
        listing.filter { selectedEntryPaths.contains($0.id) }
    }

    private var selectedURLs: [URL] {
        selectedEntries.map(\.url)
    }

    private func clearSelection() {
        selectedEntryPaths = []
        selectionAnchorPath = nil
    }

    private func handleClick(on entry: FileEntry) {
        browserFocused = true
        let modifiers = NSApp.currentEvent?.modifierFlags ?? []
        if modifiers.contains(.command) {
            if selectedEntryPaths.contains(entry.id) {
                selectedEntryPaths.remove(entry.id)
            } else {
                selectedEntryPaths.insert(entry.id)
                selectionAnchorPath = entry.id
            }
        } else if modifiers.contains(.shift),
                  let anchor = selectionAnchorPath,
                  let anchorIndex = listing.firstIndex(where: { $0.id == anchor }),
                  let entryIndex = listing.firstIndex(where: { $0.id == entry.id }) {
            let range = min(anchorIndex, entryIndex)...max(anchorIndex, entryIndex)
            selectedEntryPaths = Set(listing[range].map(\.id))
        } else {
            selectedEntryPaths = [entry.id]
            selectionAnchorPath = entry.id
        }
    }

    private func moveSelection(_ direction: MoveCommandDirection) {
        let delta: Int
        switch direction {
        case .up: delta = -1
        case .down: delta = 1
        // Finder's column keys, and harmless in the other modes: left steps
        // out to the enclosing folder, right steps into the selected one.
        case .left:
            navigateUp()
            return
        case .right:
            if let entry = selectedEntries.first, entry.isDirectory {
                navigate(to: entry.url, recordHistory: true)
            }
            return
        @unknown default: return
        }
        guard !listing.isEmpty else { return }
        let referencePath = selectionAnchorPath ?? selectedEntryPaths.first
        let nextIndex: Int
        if let referencePath, let index = listing.firstIndex(where: { $0.id == referencePath }) {
            nextIndex = min(max(index + delta, 0), listing.count - 1)
        } else {
            nextIndex = delta > 0 ? 0 : listing.count - 1
        }
        let entry = listing[nextIndex]
        if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
            selectedEntryPaths.insert(entry.id)
        } else {
            selectedEntryPaths = [entry.id]
        }
        selectionAnchorPath = entry.id
    }

    // MARK: Operations

    /// Runs a file operation, surfaces any error, and refreshes the listing.
    private func perform(_ operation: () throws -> Void) {
        do { try operation() } catch { errorMessage = error.localizedDescription }
        listingVersion += 1
    }

    private var browserActions: FileBrowserActions? {
        guard !browserFolderIsUnavailable else { return nil }
        let hasSelection = !selectedEntries.isEmpty
        let single = selectedEntries.count == 1 ? selectedEntries[0] : nil
        return FileBrowserActions(
            newFolder: { newFolder() },
            openSelection: hasSelection ? { openSelection() } : nil,
            renameSelection: single != nil ? { beginRenamingSelection() } : nil,
            duplicateSelection: hasSelection ? { duplicateSelection() } : nil,
            trashSelection: hasSelection ? { trashSelection() } : nil,
            enclosingFolder: canNavigateUp ? { navigateUp() } : nil,
            // With nothing selected, the browsed folder is the obvious thing
            // to mean by "copy the path".
            copyPaths: {
                PathPasteboard.copy(paths: hasSelection
                    ? selectedURLs.map(\.path)
                    : [state.currentFolder])
            },
            copyNames: hasSelection ? { PathPasteboard.copyNames(urls: selectedURLs) } : nil
        )
    }

    private func newFolder() {
        perform {
            let folder = try FileOperations.createFolder(in: currentFolderURL)
            selectedEntryPaths = [folder.path]
            selectionAnchorPath = folder.path
            renameText = folder.lastPathComponent
            renamingEntryPath = folder.path
        }
    }

    private func open(_ entry: FileEntry) {
        if entry.isDirectory { navigate(to: entry.url, recordHistory: true) }
        else { NSWorkspace.shared.open(entry.url) }
    }

    private func openSelection() {
        for entry in selectedEntries { open(entry) }
    }

    private func quickLookSelection(fallback: FileEntry?) {
        let target = selectedEntries.first(where: { !$0.isDirectory }) ?? fallback
        if let target, !target.isDirectory { quickLookURL = target.url }
    }

    private func beginRenamingSelection() {
        guard let entry = selectedEntries.first, selectedEntries.count == 1 else { return }
        renameText = entry.url.lastPathComponent
        renamingEntryPath = entry.id
    }

    private func commitRename(of entry: FileEntry) {
        renamingEntryPath = nil
        guard renameText != entry.url.lastPathComponent else { return }
        perform {
            let renamed = try FileOperations.rename(entry.url, to: renameText)
            selectedEntryPaths = [renamed.path]
            selectionAnchorPath = renamed.path
        }
    }

    private func duplicateSelection() {
        perform {
            let copies = try selectedEntries.map { try FileOperations.duplicate($0.url) }
            selectedEntryPaths = Set(copies.map(\.path))
            selectionAnchorPath = copies.first?.path
        }
    }

    private func trashSelection() {
        perform {
            try FileOperations.trash(selectedURLs)
            clearSelection()
        }
    }

    private var canNavigateUp: Bool {
        let current = currentFolderURL.standardizedFileURL.path
        return current != "/" && current != URL(fileURLWithPath: state.rootFolder).standardizedFileURL.path
    }

    private func navigateUp() {
        guard canNavigateUp else { return }
        navigate(to: currentFolderURL.deletingLastPathComponent(), recordHistory: true)
    }

    // MARK: Drag and drop

    /// Finder semantics: drops move by default, ⌥-drops copy. Drops that
    /// already live in the destination are no-ops (handled by `move`).
    private func receiveDrop(_ urls: [URL], into folder: URL) {
        let copy = NSApp.currentEvent?.modifierFlags.contains(.option) == true
        let sources = urls.filter { $0.standardizedFileURL != folder.standardizedFileURL }
        guard !sources.isEmpty else { return }
        perform {
            if copy {
                try FileOperations.copy(sources, into: folder)
            } else {
                try FileOperations.move(sources, into: folder)
            }
        }
    }

    // MARK: Context menu

    @ViewBuilder
    private func entryContextMenu(for entry: FileEntry) -> some View {
        let targets = selectedEntryPaths.contains(entry.id) ? selectedEntries : [entry]
        let targetURLs = targets.map(\.url)
        Button(entry.isDirectory ? "Open Folder" : "Open") { open(entry) }
        if !entry.isDirectory {
            Button("Quick Look") { quickLookURL = entry.url }
        }
        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting(targetURLs) }
        Divider()
        Button(targetURLs.count > 1 ? "Copy \(targetURLs.count) Paths" : "Copy Path") {
            PathPasteboard.copy(urls: targetURLs)
        }
        .keyboardShortcut("c", modifiers: [.command, .option])
        Button("Copy Name") { PathPasteboard.copyNames(urls: targetURLs) }
        Button("Copy Enclosing Folder Path") {
            PathPasteboard.copy(paths: [entry.url.deletingLastPathComponent().path])
        }
        Divider()
        Button("New Folder") { newFolder() }
        Button("Rename") {
            selectedEntryPaths = [entry.id]
            selectionAnchorPath = entry.id
            renameText = entry.url.lastPathComponent
            renamingEntryPath = entry.id
        }
        Button("Duplicate") {
            perform {
                let copies = try targetURLs.map { try FileOperations.duplicate($0) }
                selectedEntryPaths = Set(copies.map(\.path))
            }
        }
        Button("Move to Trash", role: .destructive) {
            perform {
                try FileOperations.trash(targetURLs)
                clearSelection()
            }
        }
    }

    // MARK: Navigation

    private func navigate(to url: URL, recordHistory: Bool) {
        updateState { value in
            if recordHistory && value.currentFolder != url.path {
                value.backHistory.append(value.currentFolder)
                value.forwardHistory = []
            }
            value.currentFolder = url.path
        }
    }

    private func goBack() {
        updateState { value in
            guard let destination = value.backHistory.popLast() else { return }
            value.forwardHistory.append(value.currentFolder)
            value.currentFolder = destination
        }
    }

    private func goForward() {
        updateState { value in
            guard let destination = value.forwardHistory.popLast() else { return }
            value.backHistory.append(value.currentFolder)
            value.currentFolder = destination
        }
    }

    private func updateState(_ transform: (inout FilePanelState) -> Void) {
        store.updatePanel(id: panelID) { panel in
            guard case .file(var fileState) = panel.kind else { return }
            transform(&fileState)
            panel.kind = .file(fileState)
        }
    }

    private func chooseFolder() {
        FolderPicker.choose { url in
            guard let url else { return }
            do { try store.setFolder(url, for: panelID) }
            catch { errorMessage = error.localizedDescription }
        }
    }

    private var browserFolderIsUnavailable: Bool {
        state.requiresReselection || !store.isFolderAvailable(at: state.currentFolder)
    }

    // MARK: Linked terminals

    private var linkedTerminalIDs: [UUID] {
        store.terminalsLinked(to: panelID).map(\.id)
    }

    private var actionableTerminalIDs: [UUID] {
        let linkedIDs = linkedTerminalIDs
        return linkedIDs.filter { terminals.registeredTerminalIDs.contains($0) }
    }

    private var canGoHere: Bool {
        !linkedTerminalIDs.isEmpty
            && actionableTerminalIDs.count == linkedTerminalIDs.count
            && store.isFolderAvailable(at: state.currentFolder)
    }

    private var goHereTitle: String {
        let count = linkedTerminalIDs.count
        return count <= 1 ? "Go Here in Terminal" : "Go Here in \(count) Terminals"
    }

    private func goHere(path: String) {
        let terminalIDs = actionableTerminalIDs
        guard !terminalIDs.isEmpty else { return }
        do {
            try store.pinFolder(path, for: terminalIDs)
            terminals.changeDirectory(path: path, terminalIDs: terminalIDs)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// One file or folder row. Shared by the list and column browsers so a row
/// looks and behaves the same in both.
struct FileEntryRow<ContextMenu: View>: View {
    let entry: FileEntry
    let isSelected: Bool
    let isRenaming: Bool
    @Binding var renameText: String
    let select: () -> Void
    let open: () -> Void
    let quickLook: () -> Void
    let commitRename: () -> Void
    let cancelRename: () -> Void
    let dropURLs: (([URL]) -> Void)?
    @ViewBuilder let contextMenu: () -> ContextMenu
    /// Whether the owning panel has keyboard focus, so selection can be drawn
    /// the way Finder does it — accent when active, grey when not.
    var isPanelFocused = true
    /// Column browser: this folder is the one the path continues through.
    var isOnPath = false
    /// Column browser: draw a trailing chevron on folders.
    var showsDisclosure = false
    @State private var dropTargeted = false
    @State private var hovering = false
    @FocusState private var renameFieldFocused: Bool

    var body: some View {
        HStack(spacing: Theme.Metrics.gap) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: entry.url.path))
                .resizable()
                .frame(width: Theme.Metrics.iconSize, height: Theme.Metrics.iconSize)
            if isRenaming {
                TextField("Name", text: $renameText)
                    .textFieldStyle(.roundedBorder)
                    .font(Theme.Typography.row)
                    .focused($renameFieldFocused)
                    .onSubmit(commitRename)
                    .onExitCommand(perform: cancelRename)
                    .onAppear { renameFieldFocused = true }
            } else {
                Text(entry.url.lastPathComponent)
                    .font(isOnPath ? Theme.Typography.rowEmphasis : Theme.Typography.row)
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: Theme.Metrics.tight)
            if showsDisclosure && entry.isDirectory && !isRenaming {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .padding(.horizontal, Theme.Metrics.gap)
        .frame(height: Theme.Metrics.rowHeight)
        .background(selectionShape(fill: rowBackground, bordered: showsSelectionBorder))
        .animation(Theme.Motion.selection, value: isSelected)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2, perform: open)
        .onTapGesture(count: 1, perform: select)
        .accessibilityValue(isSelected ? "Selected" : "")
        .onDrag { NSItemProvider(contentsOf: entry.url) ?? NSItemProvider() }
        .modifier(FolderDropModifier(dropURLs: dropURLs, targeted: $dropTargeted))
        .contextMenu { contextMenu() }
    }

    private var rowBackground: Color {
        if dropTargeted { return Theme.selectionHighlight }
        if isSelected { return isPanelFocused ? Theme.selectionHighlight : Theme.inactiveSelectionHighlight }
        if isOnPath { return Theme.inactiveSelectionHighlight.opacity(0.6) }
        if hovering { return Theme.hoverHighlight }
        return .clear
    }

    /// The accent fill alone still reads soft at this row height, so a live
    /// selection also takes the brighter stroke. An unfocused panel's rows keep
    /// the flat grey fill — the missing border is part of how you tell which
    /// list the keyboard is pointed at.
    private var showsSelectionBorder: Bool {
        dropTargeted || (isSelected && isPanelFocused)
    }
}

/// Rounded, inset selection backing shared by the browser row views.
@ViewBuilder
func selectionShape(fill: Color, bordered: Bool) -> some View {
    RoundedRectangle(cornerRadius: Theme.Metrics.cornerRadius)
        .fill(fill)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Metrics.cornerRadius)
                .stroke(bordered ? Theme.selectionBorder : .clear, lineWidth: 1)
        )
        .padding(.horizontal, 2)
}

private struct FolderDropModifier: ViewModifier {
    let dropURLs: (([URL]) -> Void)?
    @Binding var targeted: Bool

    func body(content: Content) -> some View {
        if let dropURLs {
            content.onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
                var urls: [URL] = []
                let group = DispatchGroup()
                for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                    group.enter()
                    _ = provider.loadObject(ofClass: URL.self) { url, _ in
                        if let url { urls.append(url) }
                        group.leave()
                    }
                }
                group.notify(queue: .main) {
                    if !urls.isEmpty { dropURLs(urls) }
                }
                return true
            }
        } else {
            content
        }
    }
}

private struct TreeEntryRow: View {
    let entry: FileEntry
    let depth: Int
    let goHereTitle: String
    let canGoHere: Bool
    @Binding var selectedEntryPaths: Set<String>
    let listingVersion: Int
    let showHiddenFiles: Bool
    let sortField: FileSortField
    let sortAscending: Bool
    let preview: (URL) -> Void
    let goHere: (URL) -> Void
    let trash: (URL) -> Void
    let duplicate: (URL) -> Void
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Theme.Metrics.tight) {
                if entry.isDirectory {
                    Button {
                        selectedEntryPaths = [entry.id]
                        withAnimation(Theme.Motion.disclosure) { expanded.toggle() }
                    } label: {
                        Image(systemName: expanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Theme.secondaryText)
                            .frame(width: 12)
                    }.buttonStyle(.plain)
                } else {
                    Color.clear.frame(width: 12)
                }
                Image(nsImage: NSWorkspace.shared.icon(forFile: entry.url.path))
                    .resizable()
                    .frame(width: Theme.Metrics.iconSize, height: Theme.Metrics.iconSize)
                Text(entry.url.lastPathComponent)
                    .font(Theme.Typography.row)
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.leading, CGFloat(depth) * Theme.Metrics.treeIndent + Theme.Metrics.gap)
            .padding(.trailing, Theme.Metrics.gap)
            .frame(height: Theme.Metrics.rowHeight)
            .background(selectionShape(
                fill: isSelected ? Theme.selectionHighlight : .clear,
                bordered: isSelected
            ))
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                if entry.isDirectory { expanded.toggle() }
                else { NSWorkspace.shared.open(entry.url) }
            }
            .onTapGesture(count: 1) {
                selectedEntryPaths = [entry.id]
            }
            .accessibilityValue(isSelected ? "Selected" : "")
            .onDrag { NSItemProvider(contentsOf: entry.url) ?? NSItemProvider() }
            .contextMenu {
                if entry.isDirectory {
                    Button(goHereTitle) { goHere(entry.url) }
                        .disabled(!canGoHere)
                    Divider()
                }
                if !entry.isDirectory { Button("Quick Look") { preview(entry.url) } }
                Button("Open") { NSWorkspace.shared.open(entry.url) }
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([entry.url]) }
                Divider()
                Button("Copy Path") { PathPasteboard.copy(urls: [entry.url]) }
                    .keyboardShortcut("c", modifiers: [.command, .option])
                Button("Copy Name") { PathPasteboard.copyNames(urls: [entry.url]) }
                Button("Copy Enclosing Folder Path") {
                    PathPasteboard.copy(paths: [entry.url.deletingLastPathComponent().path])
                }
                Divider()
                Button("Duplicate") { duplicate(entry.url) }
                Button("Move to Trash", role: .destructive) { trash(entry.url) }
            }

            if expanded && entry.isDirectory {
                ForEach(children) { child in
                    TreeEntryRow(
                        entry: child,
                        depth: depth + 1,
                        goHereTitle: goHereTitle,
                        canGoHere: canGoHere,
                        selectedEntryPaths: $selectedEntryPaths,
                        listingVersion: listingVersion,
                        showHiddenFiles: showHiddenFiles,
                        sortField: sortField,
                        sortAscending: sortAscending,
                        preview: preview,
                        goHere: goHere,
                        trash: trash,
                        duplicate: duplicate
                    )
                }
            }
        }
    }

    private var isSelected: Bool {
        selectedEntryPaths.contains(entry.id)
    }

    private var children: [FileEntry] {
        var options: FileManager.DirectoryEnumerationOptions = []
        if !showHiddenFiles { options.insert(.skipsHiddenFiles) }
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: entry.url,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey, .fileSizeKey],
            options: options
        )) ?? []
        return urls.map { url in
            let values = try? url.resourceValues(
                forKeys: [.isDirectoryKey, .contentModificationDateKey, .fileSizeKey]
            )
            return FileEntry(
                url: url,
                isDirectory: values?.isDirectory == true,
                dateModified: values?.contentModificationDate ?? .distantPast,
                size: Int64(values?.fileSize ?? 0)
            )
        }.sorted {
            FileListing.areInIncreasingOrder(
                FileSortKey(name: $0.url.lastPathComponent, isDirectory: $0.isDirectory, dateModified: $0.dateModified, size: $0.size),
                FileSortKey(name: $1.url.lastPathComponent, isDirectory: $1.isDirectory, dateModified: $1.dateModified, size: $1.size),
                field: sortField,
                ascending: sortAscending
            )
        }
    }
}
