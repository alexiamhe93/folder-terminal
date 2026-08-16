import FolderTerminalCore
import SwiftUI

struct WorkspaceView: View {
    @ObservedObject var store: WorkspaceStore
    let terminals: TerminalRegistry

    var body: some View {
        WorkspaceNodeView(layout: store.document.layout, store: store, terminals: terminals)
            .toolbar {
                ToolbarItemGroup {
                    // The two "add" buttons carry their titles: an icon-only
                    // toolbar gives no clue what it does on first run.
                    Button {
                        store.addPanel(
                            AppSettings.newFilePanel(at: AppSettings.homeFolder),
                            orientation: AppSettings.newPanelPlacement
                        )
                    } label: {
                        Label("New Folder Panel", systemImage: "folder.badge.plus")
                    }
                    .labelStyle(.titleAndIcon)
                    .tip("Add a folder browser panel (⇧⌘F)")

                    Button { addTerminal() } label: {
                        Label("New Terminal", systemImage: "terminal")
                    }
                    .labelStyle(.titleAndIcon)
                    .tip("Add a terminal panel (⇧⌘T)")

                    Divider()

                    Button { store.splitSelected(orientation: .vertical) } label: {
                        Label("Split Vertically", systemImage: "rectangle.split.2x1")
                    }
                    .tip("Split the selected panel left and right (⌘D)")

                    Button { store.splitSelected(orientation: .horizontal) } label: {
                        Label("Split Horizontally", systemImage: "rectangle.split.1x2")
                    }
                    .tip("Split the selected panel top and bottom (⇧⌘D)")

                    Button {
                        if let id = store.selectedPanelID { store.closePanel(id: id) }
                    } label: {
                        Label("Close Panel", systemImage: "xmark")
                    }
                    .disabled(store.document.layout.panelIDs.count < 2)
                    .tip("Close the selected panel (⌘W)")
                }
            }
            .overlay(alignment: .bottom) {
                if let error = store.persistenceError {
                    Text(error)
                        .font(Theme.Typography.status)
                        .padding(Theme.Metrics.gap)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.Metrics.gap))
                        .padding()
                }
            }
    }

    private func addTerminal() {
        let linked = store.selectedPanelID.flatMap { id -> UUID? in
            guard let panel = store.panel(id: id), case .file = panel.kind else { return nil }
            return id
        } ?? store.filePanels.first?.id
        store.addPanel(.terminal(linkedTo: linked), orientation: AppSettings.newPanelPlacement)
    }
}

private struct WorkspaceNodeView: View {
    let layout: WorkspaceLayout
    @ObservedObject var store: WorkspaceStore
    let terminals: TerminalRegistry

    var body: some View {
        switch layout {
        case .panel(let panel):
            PanelContainer(panel: panel, store: store, terminals: terminals)
        case .split(let split):
            SplitNodeView(split: split, store: store, terminals: terminals)
        }
    }
}

private struct SplitNodeView: View {
    let split: WorkspaceSplit
    @ObservedObject var store: WorkspaceStore
    let terminals: TerminalRegistry
    private let dividerThickness = Theme.Metrics.dividerThickness

    var body: some View {
        GeometryReader { proxy in
            if split.orientation == .vertical {
                let available = max(0, proxy.size.width - dividerThickness)
                HStack(spacing: 0) {
                    WorkspaceNodeView(layout: split.first, store: store, terminals: terminals)
                        .frame(width: available * split.ratio)
                    SplitDivider(axis: .horizontal) { delta in
                        store.updateRatio(splitID: split.id, ratio: split.ratio + delta / max(available, 1))
                    }
                    .frame(width: dividerThickness)
                    WorkspaceNodeView(layout: split.second, store: store, terminals: terminals)
                        .frame(width: available * (1 - split.ratio))
                }
            } else {
                let available = max(0, proxy.size.height - dividerThickness)
                VStack(spacing: 0) {
                    WorkspaceNodeView(layout: split.first, store: store, terminals: terminals)
                        .frame(height: available * split.ratio)
                    SplitDivider(axis: .vertical) { delta in
                        store.updateRatio(splitID: split.id, ratio: split.ratio + delta / max(available, 1))
                    }
                    .frame(height: dividerThickness)
                    WorkspaceNodeView(layout: split.second, store: store, terminals: terminals)
                        .frame(height: available * (1 - split.ratio))
                }
            }
        }
    }
}

private struct SplitDivider: View {
    let axis: Axis
    let onChange: (CGFloat) -> Void
    @State private var previousTranslation: CGFloat = 0
    @State private var pushedCursor = false

    var body: some View {
        Rectangle()
            .fill(Theme.divider)
            .contentShape(Rectangle())
            // Every push must be matched by exactly one pop. Popping on a hover
            // that never pushed unbalances AppKit's cursor stack, and a divider
            // that goes away mid-hover — closing a panel, dropping one beside
            // another — never got its pop at all and left the window stuck
            // showing a resize cursor.
            .onHover { hovering in
                if hovering {
                    pushCursor()
                } else {
                    popCursor()
                }
            }
            .onDisappear(perform: popCursor)
            .gesture(DragGesture().onChanged { value in
                let translation = axis == .horizontal ? value.translation.width : value.translation.height
                onChange(translation - previousTranslation)
                previousTranslation = translation
            }.onEnded { _ in previousTranslation = 0 })
    }

    private func pushCursor() {
        guard !pushedCursor else { return }
        (axis == .horizontal ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).push()
        pushedCursor = true
    }

    private func popCursor() {
        guard pushedCursor else { return }
        NSCursor.pop()
        pushedCursor = false
    }
}

private struct PanelContainer: View {
    let panel: WorkspacePanel
    @ObservedObject var store: WorkspaceStore
    let terminals: TerminalRegistry

    var selected: Bool { store.selectedPanelID == panel.id }

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(panel: panel, store: store, terminals: terminals)
            Group {
                switch panel.kind {
                case .file(let state):
                    FilePanelView(panelID: panel.id, state: state, store: store, terminals: terminals)
                case .terminal(let state):
                    TerminalPanelView(panelID: panel.id, state: state, store: store, terminals: terminals)
                }
            }
        }
        .background(Theme.panelBackground)
        // Inactive panels keep a hairline. The active panel gets a 2pt outline
        // plus the header marker, so focus is not communicated by tint alone.
        .overlay(
            Rectangle().stroke(
                selected ? Theme.focusBorder : Theme.divider,
                lineWidth: selected ? Theme.Metrics.focusRing : 1
            )
        )
        .animation(Theme.Motion.selection, value: selected)
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded { store.select(panel.id) })
    }
}

private struct PanelHeader: View {
    let panel: WorkspacePanel
    @ObservedObject var store: WorkspaceStore
    let terminals: TerminalRegistry

    var body: some View {
        HStack(spacing: Theme.Metrics.gap) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(store.selectedPanelID == panel.id ? Theme.accentBright : .clear)
                .frame(width: 3, height: 14)
                .accessibilityHidden(true)
            Image(systemName: icon)
                .foregroundStyle(store.selectedPanelID == panel.id ? Theme.accentBright : Theme.secondaryText)
            Text(title)
                .foregroundStyle(Theme.primaryText)
                .lineLimit(1)
            Spacer(minLength: Theme.Metrics.gap)
            Menu {
                Button("Split Vertically") { store.select(panel.id); store.splitSelected(orientation: .vertical) }
                Button("Split Horizontally") { store.select(panel.id); store.splitSelected(orientation: .horizontal) }
                Divider()
                if let folder = browsedFolder {
                    Button("Copy Folder Path") { PathPasteboard.copy(paths: [folder]) }
                    Divider()
                }
                Button("Replace with Folder Browser") {
                    store.replacePanel(id: panel.id, with: AppSettings.newFilePanelKind(at: AppSettings.homeFolder))
                }
                Button("Replace with Terminal") {
                    store.replacePanel(id: panel.id, with: .terminal(TerminalPanelState(linkedFilePanelID: store.filePanels.first?.id)))
                }
                Divider()
                Button("Close Panel") { store.closePanel(id: panel.id) }
                    .disabled(store.document.layout.panelIDs.count < 2)
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .tip("Panel actions — split, replace, close")
        }
        .font(Theme.Typography.status)
        .padding(.horizontal, Theme.Metrics.gutter)
        .frame(height: Theme.Metrics.headerHeight)
        .background(store.selectedPanelID == panel.id ? Theme.headerSelectedBackground : Theme.headerBackground)
        .draggable(panel.id.uuidString)
        .dropDestination(for: String.self) { items, _ in
            guard let raw = items.first, let source = UUID(uuidString: raw), source != panel.id else { return false }
            store.movePanel(id: source, beside: panel.id, orientation: .vertical)
            return true
        }
    }

    private var icon: String {
        if case .file = panel.kind { return "folder" }
        return "terminal"
    }

    private var browsedFolder: String? {
        guard case .file(let state) = panel.kind else { return nil }
        return state.currentFolder
    }

    private var title: String {
        switch panel.kind {
        case .file(let state): return URL(fileURLWithPath: state.currentFolder).lastPathComponent
        case .terminal(let state):
            return state.environmentFolder.map { "Pinned: \(URL(fileURLWithPath: $0).lastPathComponent)" } ?? "Terminal"
        }
    }
}
