# Changelog

All notable changes to Folder Terminal will be documented here. Releases follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Fixed

- Dropping several files at once no longer mutates a shared array from concurrent item-provider callbacks, and dropped files keep the order they were dragged in.
- ⌥-drop copies reliably. The modifier is now read at the moment of the drop rather than after the dropped URLs finish loading, by which time it had usually been released and the drop silently moved instead.
- Quitting immediately after a change saves it. Saves are debounced, and nothing flushed them on termination.
- A split whose saved ratio is out of range (or not a number) no longer restores with one side collapsed and no divider left to drag back.
- The resize cursor no longer sticks when a divider disappears while the pointer is over it.
- Choosing a folder that cannot be read reports the reason instead of doing nothing when the picker was opened with ⌘O.
- A rejected rename keeps the editing field open with the typed name, rather than discarding it.
- Re-pointing a browser at another folder releases the previous folder's security-scoped access instead of holding every folder ever chosen until the app quits.
- Back/forward history is capped at 200 entries per panel, so a long-lived panel no longer grows the workspace file without limit.

### Security

- The saved workspace, which records browsed folders and bookmarks to them, is now written owner-only (`0600`) inside an owner-only container (`0700`). Containers created by earlier builds are tightened on the next save.

## [0.1.0] - 2026-08-15

### Added

- Persistent split workspaces containing file-browser and terminal panels.
- Finder-style list, column, and tree views with file operations and navigation.
- Explicit browser-to-terminal links, pinned folders, and live shell-location status.
- Workspace restoration, security-scoped folder bookmarks, themes, and settings.
- Standalone macOS app packaging and automated GitHub release archives.

[Unreleased]: https://github.com/alexiamhe93/folder-terminal/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/alexiamhe93/folder-terminal/releases/tag/v0.1.0
