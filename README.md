# MacPen

MacPen is a native macOS screen annotation app inspired by gInk. It is not a
direct port of the WinForms/Microsoft Ink implementation; macOS needs a native
AppKit overlay window, its own input handling, and macOS permissions for screen
capture.

## Run

```sh
swift run MacPen
```

MacPen appears as a menu bar item. Use `Cmd+Shift+G` or the menu to toggle the
annotation overlay. Screen capture features may require macOS Screen Recording
permission.

## Build an app bundle

```sh
bash Scripts/package_app.sh
open dist/MacPen.app
```

The packaging script writes:

- `dist/MacPen.app`
- `dist/MacPen-macos-<architecture>.zip`
- `dist/MacPen-macos-<architecture>.dmg`

The bundle is ad-hoc signed for local distribution. The DMG includes
`MacPen.app` and an `/Applications` shortcut. It is not notarized.

## Codex local run

```sh
./script/build_and_run.sh
```

## Current feature set

- Full-screen transparent overlay across all connected displays
- Status bar menu
- Mouse/stylus drawing with pressure-aware width
- Multiple pen colors plus highlighter
- Eraser, undo, clear, and hide/show ink
- Region screenshot to `~/Pictures/MacPen`
- Click-through pointer mode
