import Foundation
import Testing
@testable import FolderTerminalCore

// MARK: - Naming

@Test func uniqueNameNumbersBeforeExtension() {
    let folder = URL(fileURLWithPath: "/tmp/x")
    let occupiedNames = ["report.txt", "report 2.txt"]
    let url = FileOperations.uniqueDestinationURL(proposedName: "report.txt", in: folder) {
        occupiedNames.contains($0.lastPathComponent)
    }
    #expect(url.lastPathComponent == "report 3.txt")
}

@Test func uniqueNameWithoutExtensionAppendsNumber() {
    let folder = URL(fileURLWithPath: "/tmp/x")
    let url = FileOperations.uniqueDestinationURL(proposedName: "untitled folder", in: folder) {
        $0.lastPathComponent == "untitled folder"
    }
    #expect(url.lastPathComponent == "untitled folder 2")
}

@Test func unoccupiedNameIsUsedVerbatim() {
    let folder = URL(fileURLWithPath: "/tmp/x")
    let url = FileOperations.uniqueDestinationURL(proposedName: "notes.md", in: folder) { _ in false }
    #expect(url.lastPathComponent == "notes.md")
}

@Test func dotfileTreatedAsExtensionless() {
    let folder = URL(fileURLWithPath: "/tmp/x")
    let url = FileOperations.uniqueDestinationURL(proposedName: ".zshrc", in: folder) {
        $0.lastPathComponent == ".zshrc"
    }
    #expect(url.lastPathComponent == ".zshrc 2")
}

@Test func duplicateNameInsertsCopyBeforeExtension() {
    #expect(FileOperations.duplicateName(for: "report.txt") == "report copy.txt")
    #expect(FileOperations.duplicateName(for: "folder") == "folder copy")
}

@Test func renameValidationRejectsBadNames() {
    #expect(throws: FileOperationError.emptyName) { try FileOperations.validateName("  ") }
    #expect(throws: FileOperationError.invalidName("a/b")) { try FileOperations.validateName("a/b") }
    #expect(throws: FileOperationError.invalidName("a:b")) { try FileOperations.validateName("a:b") }
    #expect(throws: Never.self) { try FileOperations.validateName("plain name.txt") }
}

// MARK: - Sorting

private func key(
    _ name: String,
    directory: Bool = false,
    date: Date = .distantPast,
    size: Int64 = 0
) -> FileSortKey {
    FileSortKey(name: name, isDirectory: directory, dateModified: date, size: size)
}

@Test func foldersAlwaysSortBeforeFiles() {
    #expect(FileListing.areInIncreasingOrder(
        key("zebra", directory: true), key("apple"), field: .name, ascending: true
    ))
    #expect(FileListing.areInIncreasingOrder(
        key("zebra", directory: true), key("apple"), field: .name, ascending: false
    ))
}

@Test func nameSortIsLocalizedStandard() {
    #expect(FileListing.areInIncreasingOrder(
        key("file2"), key("file10"), field: .name, ascending: true
    ))
    #expect(FileListing.areInIncreasingOrder(
        key("file10"), key("file2"), field: .name, ascending: false
    ))
}

@Test func dateSortWithNameTiebreak() {
    let older = key("b", date: Date(timeIntervalSince1970: 100))
    let newer = key("a", date: Date(timeIntervalSince1970: 200))
    #expect(FileListing.areInIncreasingOrder(older, newer, field: .dateModified, ascending: true))
    #expect(FileListing.areInIncreasingOrder(newer, older, field: .dateModified, ascending: false))

    let tieA = key("a", date: Date(timeIntervalSince1970: 100))
    let tieB = key("b", date: Date(timeIntervalSince1970: 100))
    #expect(FileListing.areInIncreasingOrder(tieA, tieB, field: .dateModified, ascending: false))
}

@Test func sizeSort() {
    #expect(FileListing.areInIncreasingOrder(
        key("small", size: 1), key("big", size: 100), field: .size, ascending: true
    ))
    #expect(FileListing.areInIncreasingOrder(
        key("big", size: 100), key("small", size: 1), field: .size, ascending: false
    ))
}

// MARK: - Disk operations

private func temporaryOperationsFolder() -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("FileOperationsTests-\(UUID().uuidString)", isDirectory: true)
    try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@Test func createFolderUniquifies() throws {
    let root = temporaryOperationsFolder()
    defer { try? FileManager.default.removeItem(at: root) }

    let first = try FileOperations.createFolder(in: root)
    let second = try FileOperations.createFolder(in: root)
    #expect(first.lastPathComponent == "untitled folder")
    #expect(second.lastPathComponent == "untitled folder 2")
    var isDirectory: ObjCBool = false
    #expect(FileManager.default.fileExists(atPath: second.path, isDirectory: &isDirectory))
    #expect(isDirectory.boolValue)
}

@Test func renameMovesAndRefusesCollision() throws {
    let root = temporaryOperationsFolder()
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("a.txt")
    let blocker = root.appendingPathComponent("b.txt")
    try Data("a".utf8).write(to: file)
    try Data("b".utf8).write(to: blocker)

    let renamed = try FileOperations.rename(file, to: "c.txt")
    #expect(renamed.lastPathComponent == "c.txt")
    #expect(!FileManager.default.fileExists(atPath: file.path))
    #expect(throws: FileOperationError.destinationExists("b.txt")) {
        try FileOperations.rename(renamed, to: "b.txt")
    }
}

@Test func duplicateCreatesCopySuffix() throws {
    let root = temporaryOperationsFolder()
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("notes.md")
    try Data("hello".utf8).write(to: file)

    let copy = try FileOperations.duplicate(file)
    let copy2 = try FileOperations.duplicate(file)
    #expect(copy.lastPathComponent == "notes copy.md")
    #expect(copy2.lastPathComponent == "notes copy 2.md")
    #expect(try Data(contentsOf: copy2) == Data("hello".utf8))
}

@Test func copyIntoFolderKeepsBothOnCollision() throws {
    let root = temporaryOperationsFolder()
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("a.txt")
    try Data("source".utf8).write(to: source)
    let destinationFolder = try FileOperations.createFolder(named: "dest", in: root)
    try Data("existing".utf8).write(to: destinationFolder.appendingPathComponent("a.txt"))

    let copied = try FileOperations.copy([source], into: destinationFolder)
    #expect(copied.map(\.lastPathComponent) == ["a 2.txt"])
    #expect(FileManager.default.fileExists(atPath: source.path))
}

@Test func moveIntoFolderAndSameFolderIsNoOp() throws {
    let root = temporaryOperationsFolder()
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("a.txt")
    try Data("source".utf8).write(to: source)
    let destinationFolder = try FileOperations.createFolder(named: "dest", in: root)

    let unmoved = try FileOperations.move([source], into: root)
    #expect(unmoved == [source])

    let moved = try FileOperations.move([source], into: destinationFolder)
    #expect(moved.map(\.lastPathComponent) == ["a.txt"])
    #expect(!FileManager.default.fileExists(atPath: source.path))
}

// MARK: - State compatibility

@Test func filePanelStateDecodesLegacyPayloadWithDefaults() throws {
    let legacy = """
    {
        "rootFolder": "/tmp",
        "currentFolder": "/tmp",
        "backHistory": [],
        "forwardHistory": [],
        "viewMode": "list",
        "requiresReselection": false
    }
    """
    let state = try JSONDecoder().decode(FilePanelState.self, from: Data(legacy.utf8))
    #expect(state.showHiddenFiles == false)
    #expect(state.sortField == .name)
    #expect(state.sortAscending == true)
}

@Test func filePanelStateRoundTripsNewFields() throws {
    var state = FilePanelState(rootFolder: "/tmp")
    state.showHiddenFiles = true
    state.sortField = .dateModified
    state.sortAscending = false
    let data = try JSONEncoder().encode(state)
    let decoded = try JSONDecoder().decode(FilePanelState.self, from: data)
    #expect(decoded == state)
}
