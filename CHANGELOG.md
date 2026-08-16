# Changelog

All notable changes to Folder Terminal will be documented here. Releases follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

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
