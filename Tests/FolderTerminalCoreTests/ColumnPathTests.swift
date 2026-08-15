import Foundation
import Testing
@testable import FolderTerminalCore

// MARK: - Normalization

@Test func normalizeStripsTrailingSlashes() {
    #expect(ColumnPath.normalize("/Users/alex/") == "/Users/alex")
    #expect(ColumnPath.normalize("/Users/alex///") == "/Users/alex")
    #expect(ColumnPath.normalize("/") == "/")
    #expect(ColumnPath.normalize("") == "/")
}

@Test func normalizeResolvesRelativeComponents() {
    #expect(ColumnPath.normalize("/Users/alex/Documents/..") == "/Users/alex")
    #expect(ColumnPath.normalize("/Users/./alex") == "/Users/alex")
}

// MARK: - Columns

@Test func columnsAtRootIsSingleColumn() {
    #expect(ColumnPath.columns(root: "/Users/alex", current: "/Users/alex") == ["/Users/alex"])
}

@Test func columnsChainFromRootToCurrent() {
    let chain = ColumnPath.columns(root: "/Users/alex", current: "/Users/alex/Documents/Studio")
    #expect(chain == ["/Users/alex", "/Users/alex/Documents", "/Users/alex/Documents/Studio"])
}

@Test func columnsIgnoreTrailingSlashSpelling() {
    let chain = ColumnPath.columns(root: "/Users/alex/", current: "/Users/alex/Documents/")
    #expect(chain == ["/Users/alex", "/Users/alex/Documents"])
}

@Test func columnsCollapseWhenCurrentEscapesRoot() {
    // A root that moved, or a panel pointed somewhere unrelated: show the
    // current folder alone rather than inventing a chain.
    #expect(ColumnPath.columns(root: "/Users/alex/Documents", current: "/etc") == ["/etc"])
    #expect(ColumnPath.columns(root: "/Users/alex/Documents", current: "/Users/alex") == ["/Users/alex"])
}

@Test func columnsFromFilesystemRoot() {
    #expect(ColumnPath.columns(root: "/", current: "/Users/alex") == ["/", "/Users", "/Users/alex"])
}

@Test func columnsRejectSiblingPrefixMatch() {
    // "/Users/alexandra" must not read as a descendant of "/Users/alex".
    #expect(ColumnPath.columns(root: "/Users/alex", current: "/Users/alexandra") == ["/Users/alexandra"])
}

// MARK: - Selected child

@Test func selectedChildIsNextFolderInChain() {
    let chain = ColumnPath.columns(root: "/Users/alex", current: "/Users/alex/Documents/Studio")
    #expect(ColumnPath.selectedChild(after: "/Users/alex", in: chain) == "/Users/alex/Documents")
    #expect(ColumnPath.selectedChild(after: "/Users/alex/Documents", in: chain) == "/Users/alex/Documents/Studio")
}

@Test func trailingColumnHasNoSelectedChild() {
    let chain = ColumnPath.columns(root: "/Users/alex", current: "/Users/alex/Documents")
    #expect(ColumnPath.selectedChild(after: "/Users/alex/Documents", in: chain) == nil)
    #expect(ColumnPath.selectedChild(after: "/somewhere/else", in: chain) == nil)
}

// MARK: - Relative components

@Test func relativeComponentsBetweenRootAndCurrent() {
    #expect(ColumnPath.relativeComponents(root: "/Users/alex", current: "/Users/alex/a/b") == ["a", "b"])
    #expect(ColumnPath.relativeComponents(root: "/Users/alex", current: "/Users/alex") == [])
    #expect(ColumnPath.relativeComponents(root: "/Users/alex", current: "/Users") == nil)
}

// MARK: - Ancestors

@Test func ancestorsRunFromFilesystemRoot() {
    #expect(ColumnPath.ancestors(of: "/Users/alex/Documents") == [
        "/", "/Users", "/Users/alex", "/Users/alex/Documents",
    ])
}

@Test func ancestorsOfRootIsRootAlone() {
    #expect(ColumnPath.ancestors(of: "/") == ["/"])
}
