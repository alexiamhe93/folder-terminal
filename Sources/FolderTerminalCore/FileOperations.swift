import Foundation

public enum FileSortField: String, Codable, CaseIterable, Sendable {
    case name
    case dateModified
    case size
}

public struct FileSortKey: Equatable, Sendable {
    public var name: String
    public var isDirectory: Bool
    public var dateModified: Date
    public var size: Int64

    public init(name: String, isDirectory: Bool, dateModified: Date = .distantPast, size: Int64 = 0) {
        self.name = name
        self.isDirectory = isDirectory
        self.dateModified = dateModified
        self.size = size
    }
}

public enum FileListing {
    /// Finder-style ordering: folders always sort before files, ties fall back
    /// to ascending name order regardless of the primary direction.
    public static func areInIncreasingOrder(
        _ lhs: FileSortKey,
        _ rhs: FileSortKey,
        field: FileSortField,
        ascending: Bool
    ) -> Bool {
        if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
        let comparison: ComparisonResult
        switch field {
        case .name:
            comparison = lhs.name.localizedStandardCompare(rhs.name)
        case .dateModified:
            comparison = compare(lhs.dateModified, rhs.dateModified)
        case .size:
            comparison = compare(lhs.size, rhs.size)
        }
        guard comparison != .orderedSame else {
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
        return ascending ? comparison == .orderedAscending : comparison == .orderedDescending
    }

    private static func compare<Value: Comparable>(_ lhs: Value, _ rhs: Value) -> ComparisonResult {
        if lhs == rhs { return .orderedSame }
        return lhs < rhs ? .orderedAscending : .orderedDescending
    }
}

public enum FileOperationError: LocalizedError, Equatable {
    case emptyName
    case invalidName(String)
    case destinationExists(String)

    public var errorDescription: String? {
        switch self {
        case .emptyName:
            return "The name is empty."
        case .invalidName(let name):
            return "The name “\(name)” cannot contain “/” or “:”."
        case .destinationExists(let name):
            return "An item named “\(name)” already exists here."
        }
    }
}

/// Finder-style file operations. Collisions on create, duplicate, copy, and
/// move are resolved by unique-ifying the destination name (Finder's
/// "keep both"), never by replacing; rename refuses collisions outright.
public enum FileOperations {
    public static let newFolderBaseName = "untitled folder"

    // MARK: Naming (pure, testable)

    public static func validateName(_ name: String) throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw FileOperationError.emptyName
        }
        guard !name.contains("/"), !name.contains(":") else {
            throw FileOperationError.invalidName(name)
        }
    }

    public static func uniqueDestinationURL(
        proposedName: String,
        in folder: URL,
        occupied: (URL) -> Bool
    ) -> URL {
        let stem = (proposedName as NSString).deletingPathExtension
        let ext = (proposedName as NSString).pathExtension
        var index = 1
        while true {
            let name = index == 1
                ? proposedName
                : ext.isEmpty ? "\(stem) \(index)" : "\(stem) \(index).\(ext)"
            let candidate = folder.appendingPathComponent(name)
            if !occupied(candidate) { return candidate }
            index += 1
        }
    }

    public static func duplicateName(for name: String) -> String {
        let stem = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        return ext.isEmpty ? "\(stem) copy" : "\(stem) copy.\(ext)"
    }

    // MARK: Disk operations

    @discardableResult
    public static func createFolder(
        named name: String = newFolderBaseName,
        in folder: URL,
        fileManager: FileManager = .default
    ) throws -> URL {
        try validateName(name)
        let destination = uniqueDestinationURL(proposedName: name, in: folder) {
            fileManager.fileExists(atPath: $0.path)
        }
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: false)
        return destination
    }

    @discardableResult
    public static func rename(
        _ url: URL,
        to newName: String,
        fileManager: FileManager = .default
    ) throws -> URL {
        try validateName(newName)
        guard newName != url.lastPathComponent else { return url }
        let destination = url.deletingLastPathComponent().appendingPathComponent(newName)
        guard !fileManager.fileExists(atPath: destination.path) else {
            throw FileOperationError.destinationExists(newName)
        }
        try fileManager.moveItem(at: url, to: destination)
        return destination
    }

    @discardableResult
    public static func duplicate(
        _ url: URL,
        fileManager: FileManager = .default
    ) throws -> URL {
        let folder = url.deletingLastPathComponent()
        let destination = uniqueDestinationURL(
            proposedName: duplicateName(for: url.lastPathComponent),
            in: folder
        ) { fileManager.fileExists(atPath: $0.path) }
        try fileManager.copyItem(at: url, to: destination)
        return destination
    }

    @discardableResult
    public static func copy(
        _ sources: [URL],
        into folder: URL,
        fileManager: FileManager = .default
    ) throws -> [URL] {
        try sources.map { source in
            let destination = uniqueDestinationURL(
                proposedName: source.lastPathComponent,
                in: folder
            ) { fileManager.fileExists(atPath: $0.path) }
            try fileManager.copyItem(at: source, to: destination)
            return destination
        }
    }

    @discardableResult
    public static func move(
        _ sources: [URL],
        into folder: URL,
        fileManager: FileManager = .default
    ) throws -> [URL] {
        try sources.map { source in
            guard source.deletingLastPathComponent().standardizedFileURL.path
                    != folder.standardizedFileURL.path else { return source }
            let destination = uniqueDestinationURL(
                proposedName: source.lastPathComponent,
                in: folder
            ) { fileManager.fileExists(atPath: $0.path) }
            try fileManager.moveItem(at: source, to: destination)
            return destination
        }
    }

    public static func trash(
        _ urls: [URL],
        fileManager: FileManager = .default
    ) throws {
        for url in urls {
            try fileManager.trashItem(at: url, resultingItemURL: nil)
        }
    }
}
