# MacPen

MacPen is a native macOS screen annotation app inspired by gInk. It is not a
direct port of the WinForms/Microsoft Ink implementation; macOS needs a native
AppKit overlay window, its own input handling, and macOS permissions for screen
capture.

## Run

```sh
swift run MacPen
```

MacPen opens its window on launch, showing that it is running, and keeps running
in the menu bar after the window is closed. Opening the app again (from Finder,
Launchpad or Spotlight), the menu bar item's "设置…" entry, or the Dock icon brings
the window back. Use `Cmd+Shift+G` or the menu to toggle the annotation overlay.
Screen capture features may require macOS Screen Recording permission.

The window holds every setting, and changes apply immediately:

- the global shortcut (click it and press a new combination) and the keys
  available while annotating
- the pen cursor style, with a preview of each
- pen width, laser pen width, duration and color
- launch at login, whether the window opens on launch, and whether MacPen keeps
  a Dock icon when the window is closed

Settings are stored in `~/Library/Application Support/MacPen/config.json`.

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

## Updates and releases

Packaged builds check for updates with [Sparkle](https://sparkle-project.org)
once a day, and from the menu bar item's "Check for Updates..." entry. The
feed is <https://helloxxy.com/works/macpen/downloads/appcast.xml> on the
website, which serves the update zip from the same server; 0.2.0 still reads
the `appcast.xml` attached to the latest GitHub release, so releases carry one
too. Every update archive is signed with an EdDSA key. The private key lives in the login
Keychain of the machine that generated it; its public half is `SUPublicEDKey`
in `Info.plist`. Back the private key up somewhere safe, because updates cannot
be signed without it:

```sh
.build/artifacts/sparkle/Sparkle/bin/generate_keys -x sparkle-private-key.txt
```

`Info.plist` is the only place the version is defined, and `CFBundleVersion`
must match `CFBundleShortVersionString` because Sparkle compares it. To release:

```sh
bash Scripts/set_version.sh 0.2.0
git commit -am "Release 0.2.0"
git tag v0.2.0
bash Scripts/release.sh --notes notes.md             # builds dist/ incl. appcast.xml
bash Scripts/release.sh --notes notes.md --publish   # pushes the tag, creates the GitHub release
bash website/scripts/sync-release.sh                 # copies the zip, DMG and appcast.xml to the website
```

Then deploy the website so installed copies see the update.

`notes.md` is Markdown; it is shown in the update window and used as the
GitHub release notes. Packaging refuses to run if HEAD is tagged with a version
that differs from `Info.plist`.

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
- Main window with live settings: global shortcut recorder, cursor styles, pen
  and laser options, launch at login
