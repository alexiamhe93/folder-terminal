import Foundation

/// Derives the chain of folders a Miller-column browser should display.
///
/// The browser keeps no separate column state: the panel's `currentFolder` is
/// the single source of truth, and the columns are recomputed from it. That
/// means column position survives a relaunch for free, and navigating by any
/// other route (the path bar, Go Here, history) moves the columns too.
///
/// Pure string work — no `FileManager` — so it is testable without a disk.
public enum ColumnPath {
    /// Folders whose contents make up the columns, outermost first.
    ///
    /// The first element is always `root`; the last is always `current`. Each
    /// column displays the contents of its own folder, and the entry matching
    /// the *next* folder in the chain is the one on the current path.
    ///
    /// If `current` is not inside `root` — a workspace whose root moved, or a
    /// panel pointed somewhere unrelated — the chain collapses to `current`
    /// alone rather than inventing a relationship that isn't there.
    public static func columns(root: String, current: String) -> [String] {
        let rootPath = normalize(root)
        let currentPath = normalize(current)
        guard rootPath != currentPath else { return [rootPath] }
        guard let relative = relativeComponents(root: rootPath, current: currentPath) else {
            return [currentPath]
        }
        var chain = [rootPath]
        var walker = rootPath
        for component in relative {
            walker = appending(component, to: walker)
            chain.append(walker)
        }
        return chain
    }

    /// The folder highlighted in the column that lists `folder`'s contents,
    /// i.e. the next step along the path. `nil` for the trailing column.
    public static func selectedChild(after folder: String, in columns: [String]) -> String? {
        let target = normalize(folder)
        guard let index = columns.firstIndex(where: { normalize($0) == target }),
              index + 1 < columns.count else { return nil }
        return columns[index + 1]
    }

    /// Path components from `root` down to `current`, or `nil` when `current`
    /// is not a descendant of `root`.
    public static func relativeComponents(root: String, current: String) -> [String]? {
        let rootPath = normalize(root)
        let currentPath = normalize(current)
        if rootPath == currentPath { return [] }
        let rootParts = components(of: rootPath)
        let currentParts = components(of: currentPath)
        guard currentParts.count > rootParts.count,
              Array(currentParts.prefix(rootParts.count)) == rootParts else { return nil }
        return Array(currentParts.dropFirst(rootParts.count))
    }

    /// Every ancestor of `path` from `/` down to `path` itself — what the path
    /// bar renders as breadcrumbs.
    public static func ancestors(of path: String) -> [String] {
        let target = normalize(path)
        guard target != "/" else { return ["/"] }
        var result = ["/"]
        var walker = "/"
        for component in components(of: target) {
            walker = appending(component, to: walker)
            result.append(walker)
        }
        return result
    }

    /// Strips repeated and trailing slashes and resolves `.`/`..` so two
    /// spellings of the same folder compare equal.
    ///
    /// Deliberately *not* `NSString.standardizingPath`: that one resolves
    /// symlinks and rewrites the `/private` prefix, which would silently
    /// disagree with the paths the rest of the app holds. This is plain string
    /// arithmetic on an absolute path.
    public static func normalize(_ path: String) -> String {
        let resolved = components(of: path)
        return resolved.isEmpty ? "/" : "/" + resolved.joined(separator: "/")
    }

    /// Path components with empties and `.` dropped and `..` applied,
    /// clamped at the filesystem root.
    private static func components(of path: String) -> [String] {
        var stack: [String] = []
        for part in path.split(separator: "/") {
            switch part {
            case ".":
                continue
            case "..":
                if !stack.isEmpty { stack.removeLast() }
            default:
                stack.append(String(part))
            }
        }
        return stack
    }

    private static func appending(_ component: String, to path: String) -> String {
        path == "/" ? "/\(component)" : "\(path)/\(component)"
    }
}
