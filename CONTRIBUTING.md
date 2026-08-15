# Contributing to Folder Terminal

Thanks for helping improve Folder Terminal. Focused bug fixes, tests, documentation, and proposals that preserve the app's explicit browser–terminal relationship are especially welcome.

## Before opening an issue

- Search existing issues and discussions for the same behaviour.
- Confirm the problem on macOS 14 or later with a current Xcode toolchain.
- For unexpected terminal behaviour, note the shell and whether a foreground process was running.
- Never include private paths, shell history, tokens, or personal files in logs or screenshots.

Use a GitHub discussion or feature-request issue before undertaking a large UI, persistence, security, or architectural change.

## Development setup

```sh
git clone https://github.com/alexiamhe93/folder-terminal.git
cd folder-terminal
swift build
swift test
```

Open `Package.swift` in Xcode to run and debug the application. The package uses Swift 5.9 tools and targets macOS 14 or later.

## Pull requests

1. Create a branch from `main`.
2. Keep the change focused and follow the conventions in nearby Swift files.
3. Add or update core tests where the project already has a test seam.
4. Run `swift build`, `swift test`, and `make app`.
5. Exercise the relevant sections of `TESTING.md` for UI or terminal changes.
6. Explain the user-visible result and list exactly what you verified in the pull request.

Do not commit `.build`, `dist`, workspace state, signing credentials, or machine-specific Xcode files.

## Safety-sensitive behaviour

Changes involving shell commands, path validation, file replacement, process termination, bookmarks, or drag-and-drop need explicit failure handling. File operations should remain recoverable where possible and must not silently overwrite existing items.

Terminal panels are owned independently of SwiftUI view identity so layout edits do not terminate running shells. A panel's shell should end only when that terminal panel is actually removed. Preserve this invariant and perform the terminal-lifetime manual regression checks for related changes.

## Licence

By contributing, you agree that your contributions will be licensed under the project's MIT License.
