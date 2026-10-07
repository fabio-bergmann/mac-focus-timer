# Focus Timer

A menu bar countdown timer for macOS. One global shortcut (⌥Space by default) or
a click on the menu bar item opens a Spotlight-style panel: pick a preset or
type a time ("34m", "1h30", "until 15:30"). Or press the menu bar item and pull
it down onto the screen: the further the pull, the longer the timer, and
letting go starts it in place of any running one. The menu bar shows the time
left in a rounded rectangle with a translucent bar behind it that drains.

## Working agreement (overrides the global one for this repo)

- **`main` is the only branch.** Commit straight to `main`; there is no `dev`
  here. Still never create another branch or worktree without asking.
- **Commit locally as you go; push only when Fabio says a version is ready.**
  `origin/main` is what the installed app's Update button builds, so a push
  publishes a version. Unpushed commits on `main` are the normal state.
- **A commit or push is not an install.** `scripts/release-local.sh` replaces
  `/Applications/Focus Timer.app` and relaunches it. Run it only when Fabio asks
  for a release or install in so many words, each time.
- **Releasing a version**, when asked: bump `CFBundleShortVersionString` in
  `Support/Info.plist`, commit, push, then install (the Update button in
  Settings, or `scripts/release-local.sh`).
- **Don't put the panel on Fabio's screen to check a change.** Render it instead
  (see Previews).

## The dev loop

`scripts/dev.sh` is this project's localhost. Fabio leaves it running in a
terminal tab: it builds the working tree, uncommitted edits included, as
"Focus Timer Dev" and relaunches it within a few seconds of any change under
`Sources/` or `Support/`.

- Every file you save shows up in Fabio's menu bar almost at once, so a half-done
  edit is visible too. A build that fails prints its errors in that terminal and
  leaves the last good build running.
- The dev build is a separate app: bundle id `dev.fabio.focustimer.dev`, its
  own settings and timer, ⌃⌥Space instead of ⌥Space, and an orange dot on its
  menu bar item. It never touches the installed app (`AppVariant` in
  `AppSettings.swift` is where the two differ).
- A running timer survives the relaunch, because it is stored on disk.
- The script starts the app with `open`, not by running the binary. On this
  macOS the menu bar is drawn by a system process, and a copy started straight
  from a shell never got an item there (so `swift run FocusTimer` shows
  nothing either). Anything the app prints comes back through `build/dev.log`.
- Fabio's Bartender files every new menu bar item under Hidden. A build with a
  new bundle id has to be dragged to Shown there once before it is visible.

## Commands

```sh
scripts/dev.sh                   # the dev loop above
swift build                      # compile
swift test                       # unit tests (FocusTimerCore)
swift run FocusTimer --render-previews /tmp/focus-timer-previews
scripts/build-app.sh             # build/Focus Timer.app, not installed
scripts/release-local.sh [ref]   # build a committed ref, install, relaunch
```

## Layout

- `Sources/FocusTimerCore`: everything that can be tested without a screen. The
  text parser (`DurationParser`), what the panel lists for a query (`Launcher`),
  the timer itself (`TimerState`), the menu bar text (`PillContent`,
  `DurationFormat`), and how long a pull from the menu bar is (`DragDial`).
  Time is always passed in, never read from the clock.
- `Sources/FocusTimer`: the AppKit and SwiftUI shell. `StatusItemController` and
  `PillRenderer` draw the menu bar item, `DragTimerOverlay` draws a pull from
  it, `PanelController` owns the floating panel, `LauncherView` and `SettingsView` are its two pages, `HotKey` is the
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
- **The panel always opens in the middle of the screen**, whether from the
  shortcut or a click on the menu bar item. Fabio asked for that; it also
  sidesteps the status item's window reporting an empty frame now that macOS
  draws the menu bar out of process.
- **A left press on the menu bar item is the app's, not the button's.** The
  button only ever reports a click, so a local event monitor takes the
  mouse-down first, and the press is then followed by reading the pointer and
  the mouse button on a timer, not from drag events: with the menu bar drawn
  out of process, nothing promises those reach the app, and a missed mouse-up
  would leave the overlay stuck. A press that moves under 4 points is a click.
  Control-click (the menu) and Command-drag go to the button as before. The
  line aims at the middle of the item, taken from its window's frame: the
  press itself always lands in the middle of that window, wherever it was.
- **Icons are Hugeicons Pro, stroke rounded**, the set CoWork uses. The package
  is JavaScript, so the path data of each icon is copied into
  `FocusTimerCore/Icon.swift` and drawn by `IconView`; that file says how to add
  one. Don't reach for SF Symbols. The icons are licensed, so the repo stays
  private.
- **The app icon is drawn in code** (`PreviewRenderer.drawIcon`) and rendered
  into the bundle at build time.

## Previews

`--render-previews <dir>` writes PNGs of the menu bar item in every state, of
the panel's pages and of a pull from the menu bar, light and dark, without
opening a window. Read those to
check a UI change. What they can't show is behaviour: focus, keyboard handling,
click-away and the real menu bar need the installed app.
