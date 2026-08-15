import AppKit
import FolderTerminalCore
import SwiftUI

/// Finder-style Miller columns.
///
/// There is no separate column state: the columns are derived from the panel's
/// current folder by `ColumnPath`, so navigating from anywhere — a crumb in the
/// path bar, history, Go Here — moves the columns too, and the position
/// survives a relaunch along with the rest of the workspace.
///
/// Clicking a folder navigates into it, which appends a column; clicking a
/// folder further back truncates the chain to that point. Files are selected,
/// not navigated into.
struct ColumnBrowserView<ContextMenu: View>: View {
    let root: String
    let current: String
    let selectedEntryPaths: Set<String>
    let renamingEntryPath: String?
    @Binding var renameText: String
    let isPanelFocused: Bool
    /// Supplied by the browser so every column inherits the panel's hidden-file
    /// and sort settings.
    let entries: (URL) -> [FileEntry]
    let navigate: (URL) -> Void
    let select: (FileEntry) -> Void
    let open: (FileEntry) -> Void
    let quickLook: (FileEntry) -> Void
    let commitRename: (FileEntry) -> Void
    let cancelRename: () -> Void
    let receiveDrop: ([URL], URL) -> Void
    @ViewBuilder let contextMenu: (FileEntry) -> ContextMenu

    private var columns: [String] {
        ColumnPath.columns(root: root, current: current)
    }

    var body: some View {
        ScrollViewReader { scroller in
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    ForEach(columns, id: \.self) { folder in
                        column(folder: folder)
                            .frame(width: Theme.Metrics.columnWidth)
                            .id(folder)
                        Divider().overlay(Theme.divider)
                    }
                    // Keeps the trailing column left-aligned in a wide panel
                    // instead of stretching it.
                    Spacer(minLength: 0)
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
            .onChange(of: current) { _, folder in
                withAnimation(Theme.Motion.disclosure) {
                    scroller.scrollTo(ColumnPath.normalize(folder), anchor: .trailing)
                }
            }
            .onAppear {
                scroller.scrollTo(ColumnPath.normalize(current), anchor: .trailing)
            }
        }
        .background(Theme.panelBackground)
    }

    private func column(folder: String) -> some View {
        let url = URL(fileURLWithPath: folder)
        let onPath = ColumnPath.selectedChild(after: folder, in: columns)
        let items = entries(url)
        return ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(items) { entry in
                    FileEntryRow(
                        entry: entry,
                        isSelected: selectedEntryPaths.contains(entry.id),
                        isRenaming: renamingEntryPath == entry.id,
                        renameText: $renameText,
                        select: { handleClick(on: entry) },
                        open: { open(entry) },
                        quickLook: { quickLook(entry) },
                        commitRename: { commitRename(entry) },
                        cancelRename: cancelRename,
                        dropURLs: entry.isDirectory ? { urls in receiveDrop(urls, url) } : nil,
                        contextMenu: { contextMenu(entry) },
                        isPanelFocused: isPanelFocused,
                        isOnPath: onPath.map { ColumnPath.normalize($0) == entry.id } ?? false,
                        showsDisclosure: true
                    )
                }
                if items.isEmpty {
                    Text("Empty")
                        .font(Theme.Typography.status)
                        .foregroundStyle(Theme.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Theme.Metrics.gutter)
                        .padding(.vertical, Theme.Metrics.gap)
                }
            }
        }
        .contentShape(Rectangle())
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            loadDroppedFileURLs(providers) { urls in receiveDrop(urls, url) }
        }
    }

    /// A folder click walks the columns; a file click just selects.
    private func handleClick(on entry: FileEntry) {
        if entry.isDirectory {
            select(entry)
            navigate(entry.url)
        } else {
            select(entry)
        }
    }
}
