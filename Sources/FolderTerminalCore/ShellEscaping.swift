import Foundation

public enum ShellEscaping {
    /// POSIX-shell single-quote escaping. The result is safe as one shell argument.
    public static func quote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    public static func changeDirectoryCommand(path: String) -> String {
        "cd -- \(quote(path))\n"
    }
}
