# Verification checklist

## Automated

Run from the project directory:

```sh
swift build
make test
make app
```

`make test` rather than `swift test`: swift-testing ships as a framework, and with only the Command Line Tools installed it is present but not on any search path. `scripts/run-tests.sh` supplies the paths when a full Xcode is absent and changes nothing when one is present.

The core suite covers recursive split editing and collapse, drag-style move transformations, ratio clamping (on edit and on decode), failed moves leaving the layout untouched, browsing history (trail recording, forward-trail clearing, the 200-entry cap), owner-only workspace permissions, Codable round trips, runtime-only shell state, validated pins, terminal/file binding cleanup, missing-bookmark recovery, shell escaping, file operations (Finder-style unique naming, rename validation, sort ordering, create/rename/duplicate/copy/move/trash on disk, and legacy-payload decoding of the hidden-files and sort settings), and column-path derivation (`ColumnPathTests`: normalization, root-to-current chains, escaped roots, sibling-prefix rejection, ancestors).

## Manual workspace smoke test

1. Open `Package.swift` in Xcode and run `FolderTerminal`.
2. Create two file panels and point them at different folders.
3. Create two terminal panels; link one terminal to each file panel.
4. Add nested vertical and horizontal splits, drag panel headers to reorder, and resize every divider.
5. Browse within a file panel and change a terminal's linked browser. Confirm neither action changes the terminal or its pinned folder.
6. Use **Go Here in Terminal** in each file panel. Confirm the label names the number of linked terminals and only those terminals change directory and pin the folder.
7. In tree view, use a folder's contextual **Go Here in Terminal** action and confirm it targets that folder without first browsing into it.
8. Run `cd` manually and confirm the shell status shows its differing location while the pinned folder remains unchanged. Use **Unpin** and confirm it clears only the pin.
9. Make panels narrow and confirm secondary browser and terminal controls move into overflow menus while the primary status remains legible.
10. Close and relaunch. Confirm layout, ratios, links, browsers, and pinned folders restore, while no stale shell location appears before the new shell reports one.
10a. Drag a divider and quit with ⌘Q within a second of releasing it. Relaunch and confirm the new ratio survived — saves are debounced, so this checks the flush on termination.
10b. Hover a divider until the resize cursor appears, then close that panel from another panel's header menu while the pointer stays put. Confirm the cursor returns to normal.
11. Delete a pinned folder and confirm the terminal reports **Pinned folder unavailable** and still permits **Unpin**.
12. Single-click different files and folders in list and tree views. Confirm exactly one row in that browser is highlighted, and that navigation clears stale selection.
13. Click directly in each terminal, type `printf 'terminal-input-ok\\n'`, and confirm the command and output appear in the clicked terminal.
14. Launch `dist/FolderTerminal.app`, confirm its icon appears, and repeat the terminal-input check from the standalone bundle.
15. Press ⌘N and confirm no second workspace window appears.
16. Switch among Graphite, Midnight, and Mocha. Confirm panel chrome, breadcrumbs, selections, file listings, terminal background, caret, and ANSI colours update immediately without restarting any shell.

## File operations

1. In a file panel, use File ▸ New Folder (⌘⇧N); confirm the folder appears selected with its name in an editable field, and that a second New Folder yields `untitled folder 2`.
2. Select a file, press Return, rename it; confirm renaming to an existing name is refused with an alert and Escape cancels the edit.
3. Multi-select with ⌘-click and a range with ⇧-click; confirm the selection highlight tracks both.
4. Navigate with ↑/↓, extend with ⇧↑/⇧↓, press Space for Quick Look, ⌘↓ to open, ⌘↑ for the enclosing folder.
5. Use Duplicate (menu or context menu) on a multi-selection; confirm `name copy` / `name copy 2` siblings appear.
6. Copy a selection with ⌘C and paste with ⌘V into another file panel; confirm a colliding paste keeps both (`name 2`).
7. Move to Trash with ⌘⌫ and via the context menu; confirm the items land in the Trash (recoverable).
8. Drag rows onto a folder row and onto another panel's background; confirm the default drop moves and an ⌥-drop copies. Hold ⌥ until the drop lands — the modifier is read then, not afterwards.
9. Multi-select several files and drag them all at once onto a folder; confirm every file arrives and none is dropped or duplicated.
10. Drag a row out into Finder and confirm the file arrives.
11. Toggle Show Hidden Files and each sort option (name / date modified / size, ascending / descending); relaunch and confirm both persist per panel.
12. Run `touch marker` in a linked terminal and confirm the file panel listing refreshes by itself within a second.
13. Rename a file to a name that already exists; confirm the alert appears, the field stays open with the typed name, and Escape still cancels.

## Column view and the path bar

1. Add a new folder panel; confirm it opens in **column** view.
2. Click down three levels. Confirm each click appends a column, the columns scroll to keep the newest one in view, and the folder you came through stays marked on the path.
3. Click a folder in an earlier column; confirm the chain truncates there and re-extends.
4. Use ← and → to step out of and into folders, ↑/↓ within a column, Space for Quick Look, Return to rename.
5. Switch to List and Tree with the segmented picker; relaunch and confirm the mode persists per panel.
6. **Migration:** confirm a workspace saved before this change still opens, on the view mode it was saved with, with its folders intact.
7. In the path bar, click an ancestor crumb to jump up; open a crumb's dropdown and pick a sibling subfolder to jump sideways. Confirm both work in all three view modes.
8. Narrow the panel until crumbs drop from the left; confirm the current folder is always the one kept.

## Copy path

1. Right-click a row ▸ **Copy Path**; paste into a terminal panel and confirm the path is exact.
2. Multi-select several rows and use **Copy Paths**; confirm one path per line.
3. Copy the path of a file whose name contains spaces; confirm nothing is escaped or mangled.
4. Use **Copy Name** and **Copy Enclosing Folder Path** and confirm each gives what it says.
5. With nothing selected, use File Browser ▸ **Copy Path** (⌥⌘C); confirm it copies the browsed folder.
6. Right-click the path bar, and use the panel header's ▸ **Copy Folder Path**; confirm both copy the current folder.

## Tooltips and Settings

1. Hover every toolbar and navigation button; confirm each names its action and, where it has one, its shortcut.
2. Open Settings (⌘,), turn **Show tooltips on hover** off, and confirm hovering stops producing tooltips without a relaunch.
3. Change **New browser panels open in** and **show hidden files**; add a panel and confirm the new panel honours both while existing panels are untouched.
4. Change the terminal font size from Settings and confirm every terminal follows, and that ⌘= / ⌘- / ⌘0 still agree with it.
5. Change the theme while a long-running shell is active. Confirm its process and scrollback survive and the selected panel/current breadcrumb remain obvious without relying on colour alone.

## Terminal lifetime

The regression this guards: opening a second terminal used to kill the shell running in the first.

1. Start a long-running interactive session (Claude Code, `top`, an editor) in a terminal panel.
2. Add a terminal panel (⇧⌘T), then a folder panel (⇧⌘F), then drag a panel header to move it. After each, confirm the original session is still running and still accepts input.
3. Select the added terminal and close it (⌘W). Confirm its shell — and anything running under it — exits, while every other panel's shell survives. `pgrep -P $(pgrep -f FolderTerminal)` should drop by exactly one.
4. Replace a terminal panel with a folder browser from its header menu; confirm that shell exits too.
5. Confirm ⌘W closes a panel rather than the window, and that ⇧⌘W closes the window.

## New panel placement

1. In Settings, set **New panels open as** to Rows; add panels and confirm each new one stacks below the selected panel.
2. Switch to Columns and confirm new panels arrive beside it instead.
3. Confirm ⌘D and ⇧⌘D still split explicitly, regardless of the preference.

## Terminal QoL

1. Fill a terminal with output, press ⌘K; confirm the scrollback clears and the prompt repaints.
2. Press ⌘= / ⌘- / ⌘0; confirm every terminal's font size changes together and the size survives relaunch.

## Terminal and file behavior

- Run ANSI/true-colour output and Unicode/emoji text.
- Check resize, scrollback, selection, copy/paste, `Ctrl-C`, and a full-screen `vim` session.
- Start interactive Claude Code and Codex sessions.
- Quick Look a file and open it in its default application.
- Remove or revoke a saved folder, relaunch, and confirm only that panel asks for reselection.
