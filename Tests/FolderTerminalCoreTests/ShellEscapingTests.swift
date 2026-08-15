import Testing
@testable import FolderTerminalCore

@Test func quotesWhitespaceAndMetacharacters() {
    #expect(
        ShellEscaping.changeDirectoryCommand(path: "/tmp/a b;$HOME")
            == "cd -- '/tmp/a b;$HOME'\n"
    )
}

@Test func escapesSingleQuote() {
    #expect(ShellEscaping.quote("Cassius' notes") == "'Cassius'\\'' notes'")
}

@Test func emptyPathIsStillOneArgument() {
    #expect(ShellEscaping.changeDirectoryCommand(path: "") == "cd -- ''\n")
}
