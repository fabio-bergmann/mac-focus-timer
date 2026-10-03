# Focus Timer

A menu bar countdown timer for macOS. One global shortcut (⌥Space by default) or
a click on the menu bar item opens a Spotlight-style panel: pick a preset or
type a time ("34m", "1h30", "until 15:30"). The menu bar shows the time left in
a rounded rectangle with a translucent bar behind it that drains.

## Working agreement (overrides the global one for this repo)

- **`main` is the only branch.** Commit straight to `main`; there is no `dev`
  here. Still never create another branch or worktree without asking.
- **A commit or push is not a release.** `scripts/release-local.sh` replaces
  `/Applications/Focus Timer.app` and relaunches it. Run it only when Fabio asks
  for a release or install in so many words, each time.
- **Don't put the panel on Fabio's screen to check a change.** Render it instead
  (see Previews).

## Commands

```sh
swift build                      # compile
swift test                       # unit tests (FocusTimerCore)
swift run FocusTimer --render-previews /tmp/focus-timer-previews
scripts/build-app.sh             # build/Focus Timer.app, not installed
scripts/release-local.sh [ref]   # build a committed ref, install, relaunch
```

## Layout

- `Sources/FocusTimerCore`: everything that can be tested without a screen. The
  text parser (`DurationParser`), what the panel lists for a query (`Launcher`),
  the timer itself (`TimerState`), and the menu bar text (`PillContent`,
  `DurationFormat`). Time is always passed in, never read from the clock.
- `Sources/FocusTimer`: the AppKit and SwiftUI shell. `StatusItemController` and
  `PillRenderer` draw the menu bar item, `PanelController` owns the floating
  panel, `LauncherView` and `SettingsView` are its two pages, `HotKey` is the
  Carbon global shortcut, `UpdateService` is the Update button.
- `Support/Info.plist`: the bundle's plist. The version lives here.
- `scripts/`: building and releasing.

## Things that are the way they are on purpose

- **No Apple Developer licence.** The app is ad-hoc signed and never notarized,
  which only works because it is built on the machine it runs on (no quarantine
  flag). There is no download-and-replace updater, and there can't be one
  without the licence.
- **Updates rebuild from the checkout.** `release-local.sh` exports a committed
  ref with `git archive` (never the working tree, so a sibling session's
  unfinished edits can't ship), builds it, and installs it. It bakes the commit
  and the checkout's path into Info.plist (`FTBuildSHA`, `FTRepoPath`). The
  Update button in Settings fetches `origin/main`, compares it with that commit,
  and reruns the script with `origin/main`. The local checkout is never pulled
  or modified.
- **No package dependencies.** The bundle is assembled by hand in
  `build-app.sh`, and SwiftPM resource bundles from dependencies don't end up
  where such a bundle looks for them. The global shortcut and its recorder are
  therefore written here rather than pulled in.
- **The panel never activates the app.** It is a non-activating `NSPanel` that
  takes the keyboard, so the app in front stays in front. With no menu bar of
  its own, the panel routes ⌘C/⌘V/⌘, itself (`LauncherPanel`).
- **The app icon is drawn in code** (`PreviewRenderer.drawIcon`) and rendered
  into the bundle at build time.

## Previews

`--render-previews <dir>` writes PNGs of the menu bar item in every state and
of the panel's pages, light and dark, without opening a window. Read those to
check a UI change. What they can't show is behaviour: focus, keyboard handling,
click-away and the real menu bar need the installed app.
