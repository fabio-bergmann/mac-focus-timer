# Focus Timer

A countdown timer that lives in the macOS menu bar.

Press ⌥Space (or click the menu bar item) to open the panel, then pick a preset
or type a time and press Return. The menu bar shows the time left, with a bar
behind it that drains as the timer runs.

## What you can type

| Input | Timer |
| --- | --- |
| `25` | 25 minutes (a bare number is minutes) |
| `34m`, `34 min`, `1h`, `90s` | that long |
| `1h30`, `1h 30m`, `1.5h`, `an hour and a half` | 1 hour 30 minutes |
| `2:30`, `1:30:00` | 2 min 30 sec, 1 hr 30 min |
| `until 15:30`, `at 3pm`, `@17:00` | until that time |
| `25m write report` | 25 minutes, labelled "write report" |
| `+10m` | adds 10 minutes to the running timer |

While a timer runs, the panel also offers Pause, Add 5 min and Stop. Starting
another timer replaces the current one.

## Settings

⌘, in the panel. Presets (typed the same way as above), how the menu bar item
looks (bar colour and opacity, font weight, a fixed or fitted width, compact
`25m` or precise `24:59` time), the shortcut, what happens when a timer ends
(a sound, a glow around the screen), open at login, and updates.

## Install and update

Needs Xcode. There is no Apple Developer licence behind this, so the app is
built and signed locally rather than downloaded:

```sh
scripts/release-local.sh
```

That builds the committed `main`, installs `/Applications/Focus Timer.app` and
launches it. Later, **Settings → Check for updates** fetches `origin/main` and
rebuilds from this checkout when there are new commits.

## Development

```sh
scripts/dev.sh
```

Leave that running in a terminal tab. It builds the working tree as
"Focus Timer Dev" and relaunches it whenever a source file changes, beside the
installed app: separate settings, ⌃⌥Space as its shortcut, and an orange dot
on its menu bar item.

```sh
swift test
swift run FocusTimer --render-previews /tmp/focus-timer-previews
```

See [AGENTS.md](AGENTS.md) for how the code is laid out.
