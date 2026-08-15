import AppKit
import FolderTerminalCore
import SwiftUI

/// Copying file paths and names to the general pasteboard.
///
/// Multiple selections join with newlines, which is what a shell wants when
/// the paths are pasted into a terminal panel.
enum PathPasteboard {
    static func copy(paths: [String]) {
        guard !paths.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(paths.joined(separator: "\n"), forType: .string)
    }

    static func copy(urls: [URL]) {
        copy(paths: urls.map(\.path))
    }

    static func copyNames(urls: [URL]) {
        copy(paths: urls.map(\.lastPathComponent))
    }
}

/// A Finder-style breadcrumb for the browser's current folder.
///
/// Each crumb does two jobs: clicking it navigates to that ancestor, and its
/// dropdown lists that folder's sibling subfolders so you can step sideways
/// without going up first. Crumbs are dropped from the left when the panel is
/// too narrow, since the trailing components are the ones you are working in.
struct PathBar: View {
    let root: String
    let current: String
    let navigate: (String) -> Void
    /// Subfolders of the given folder, supplied by the browser so this view
    /// inherits the panel's hidden-file and sort settings.
    let subfolders: (String) -> [URL]

    var body: some View {
        GeometryReader { proxy in
            let visible = crumbs(fittingWidth: proxy.size.width)
            HStack(spacing: 0) {
                if visible.count < allCrumbs.count {
                    Text("…")
                        .font(Theme.Typography.status)
                        .foregroundStyle(Theme.secondaryText)
                        .padding(.trailing, Theme.Metrics.tight)
                }
                ForEach(Array(visible.enumerated()), id: \.element) { index, path in
                    if index > 0 { separator }
                    crumb(path: path, isLast: path == visible.last)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    private var separator: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 8, weight: .semibold))
            .foregroundStyle(Theme.secondaryText)
            .padding(.horizontal, 2)
    }

    private func crumb(path: String, isLast: Bool) -> some View {
        Menu {
            Button("Open This Folder") { navigate(path) }
            Button("Copy Path") { PathPasteboard.copy(paths: [path]) }
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
            }
            let children = subfolders(path)
            if !children.isEmpty {
                Divider()
                Section("Subfolders") {
                    ForEach(children, id: \.path) { child in
                        Button(child.lastPathComponent) { navigate(child.path) }
                    }
                }
            }
        } label: {
            Text(label(for: path))
                .font(isLast ? Theme.Typography.rowEmphasis : Theme.Typography.row)
                .foregroundStyle(isLast ? Theme.accentBright : Theme.secondaryText)
                .lineLimit(1)
                .padding(.horizontal, isLast ? 6 : 0)
                .padding(.vertical, isLast ? 3 : 0)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Metrics.cornerRadius)
                        .fill(isLast ? Theme.pathHighlight : .clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Metrics.cornerRadius)
                        .stroke(isLast ? Theme.pathHighlightBorder : .clear, lineWidth: 1)
                )
        } primaryAction: {
            navigate(path)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .tip(isLast ? path : "Go to \(path)")
    }

    // MARK: Crumb layout

    /// Every ancestor from the panel's root down to the current folder. When
    /// the current folder sits outside the root — a root that moved — fall
    /// back to the full filesystem path so the bar still means something.
    private var allCrumbs: [String] {
        let chain = ColumnPath.columns(root: root, current: current)
        if chain.count == 1 && ColumnPath.normalize(root) != ColumnPath.normalize(current) {
            return ColumnPath.ancestors(of: current)
        }
        return chain
    }

    private func label(for path: String) -> String {
        let name = URL(fileURLWithPath: path).lastPathComponent
        return name.isEmpty || name == "/" ? "Macintosh HD" : name
    }

    /// Drops crumbs from the left until the chain fits, always keeping at
    /// least the current folder.
    private func crumbs(fittingWidth width: CGFloat) -> [String] {
        var candidates = allCrumbs
        while candidates.count > 1 && estimatedWidth(of: candidates) > width {
            candidates.removeFirst()
        }
        return candidates
    }

    private func estimatedWidth(of paths: [String]) -> CGFloat {
        // Approximate: ~6.5 pt per character at 12 pt SF, plus the chevron and
        // menu padding per crumb. Exact enough to decide how many fit.
        paths.reduce(0) { total, path in
            total + CGFloat(label(for: path).count) * 6.5 + 20
        }
    }
}
