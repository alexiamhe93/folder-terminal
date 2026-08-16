import Foundation
import Testing
@testable import FolderTerminalCore

@Test func navigationRecordsHistoryAndClearsTheForwardTrail() {
    var state = FilePanelState(rootFolder: "/a")
    state.navigate(to: "/a/b")
    state.navigate(to: "/a/b/c")
    #expect(state.backHistory == ["/a", "/a/b"])

    // `#expect` evaluates its argument inside a closure that captures the
    // value immutably, so a mutating call has to happen outside the macro.
    let steppedBack = state.goBack()
    #expect(steppedBack)
    #expect(state.currentFolder == "/a/b")
    #expect(state.forwardHistory == ["/a/b/c"])

    // Stepping somewhere new from the middle of the trail abandons what was
    // ahead, the way a browser does.
    state.navigate(to: "/a/d")
    #expect(state.forwardHistory.isEmpty)
    #expect(state.backHistory == ["/a", "/a/b"])
}

@Test func navigatingToTheCurrentFolderRecordsNothing() {
    var state = FilePanelState(rootFolder: "/a")
    state.navigate(to: "/a")
    #expect(state.backHistory.isEmpty)

    state.navigate(to: "/a/b", recordHistory: false)
    #expect(state.currentFolder == "/a/b")
    #expect(state.backHistory.isEmpty)
}

@Test func historyStepsBothWaysWithoutLosingPlace() {
    var state = FilePanelState(rootFolder: "/a")
    state.navigate(to: "/a/b")
    let steppedBack = state.goBack()
    let steppedForward = state.goForward()
    #expect(steppedBack)
    #expect(steppedForward)
    #expect(state.currentFolder == "/a/b")
    #expect(state.backHistory == ["/a"])
    #expect(state.forwardHistory.isEmpty)

    let steppedPastTheEnd = state.goForward()
    #expect(steppedPastTheEnd == false)
    #expect(state.currentFolder == "/a/b")
}

/// Every step used to be appended and saved forever, so a long-lived panel grew
/// an unbounded list of folders in the workspace file.
@Test func historyIsCappedAndDropsItsOldestEntries() {
    var state = FilePanelState(rootFolder: "/a")
    for index in 0..<(FilePanelState.historyLimit + 50) {
        state.navigate(to: "/a/\(index)")
    }

    #expect(state.backHistory.count == FilePanelState.historyLimit)
    #expect(state.backHistory.last == "/a/\(FilePanelState.historyLimit + 48)")
    #expect(state.currentFolder == "/a/\(FilePanelState.historyLimit + 49)")
}

@Test func forwardHistoryIsCappedToo() {
    var state = FilePanelState(rootFolder: "/a")
    for index in 0..<(FilePanelState.historyLimit + 50) {
        state.navigate(to: "/a/\(index)")
    }
    while state.goBack() {}

    #expect(state.forwardHistory.count == FilePanelState.historyLimit)
}
