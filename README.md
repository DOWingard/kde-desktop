# kde-desktop

A command-line interface and AI-agent skill for operating a **KDE Plasma 6 Wayland** desktop.
With it an agent (or a script) can manage windows, read and operate any app's interface through
the accessibility tree without stealing focus, take exactly-mapped screenshots, OCR the screen,
send keyboard and mouse input safely, launch apps, and control the clipboard, media, volume and
notifications.

All output is JSON, so it is easy to drive from scripts and LLM agents.

```console
$ kde-desktop app launch kcalc --wait 6 | jq -r .window.id
f14f866d-927d-4de4-b945-039340776ecb
$ for b in Seven Multiply Six Equals; do kde-desktop a11y do --window class:kcalc --role button --name $b --exact >/dev/null; done
$ kde-desktop a11y text --window class:kcalc --path 0.0.0.4
{"text": "42", "length": 2, "node": "0.0.0.4"}
```

KCalc did that calculation in the background. The window the user was working in kept focus the
whole time.

## Layout

```
skills/kde-desktop/
├── SKILL.md              agent instructions (method choice, safety, recipes)
├── scripts/kde-desktop   the CLI (single Python file)
├── references/system.md  shell one-liners for KDE settings (theme, night light, displays, …)
└── evals/                agent eval cases (prompt, expected outcome, graders)
install.sh                links the skill and the CLI into place
```

## Requirements

- A KDE Plasma 6 Wayland session (KWin, D-Bus session bus)
- Python 3.11+ with PyGObject (`python-gobject`), and `python-atspi` for accessibility
- `spectacle`, `imagemagick` for screenshots. `tesseract` + `tesseract-data-eng` for OCR
- `ydotool` for keyboard/pointer input. Your user needs write access to `/dev/uinput` (logind
  normally grants it) and the `uinput` module must be loadable
- `wl-clipboard`, `playerctl`, `wireplumber` (`wpctl`), `libnotify`, `kde-cli-tools` (`kstart`)

On Arch Linux:

```bash
sudo pacman -S python-gobject python-atspi spectacle imagemagick tesseract tesseract-data-eng \
  ydotool wl-clipboard playerctl wireplumber libnotify kde-cli-tools
```

## Install

```bash
./install.sh
```

This creates two symlinks and then runs `kde-desktop doctor`:
- `~/.claude/skills/kde-desktop` → `skills/kde-desktop`
- `~/.local/bin/kde-desktop` → the CLI

Override the targets with `CLAUDE_SKILLS_DIR` and `BIN_DIR`. The script never overwrites a real
file. Re-run it at any time to repair the links.

## Commands

| Group | Commands |
|---|---|
| `win` | `list`, `active`, `get`, `activate`, `close`, `minimize`, `unminimize`, `maximize`, `unmaximize`, `move`, `resize`, `place`, `fullscreen`, `above`, `to-desktop` |
| `desk` | `list`, `switch N` |
| `screens` | screen geometry and cursor position |
| `shot` | full desktop, `--window WIN` or `--region X Y W H`; returns path, covered rectangle and scale |
| `ocr` | text lines with screen boxes; `--find TEXT` returns click centers |
| `a11y` | `apps`, `tree`, `find`, `do`, `text`, `set-text`, `focus`, `value`, `info` |
| `input` | `type`, `paste`, `key`, `click`, `scroll`, `move` (requires `--window` or `--focused`) |
| `app` | `list [QUERY]`, `launch QUERY [--url] [--wait S]` |
| `clip` | `get`, `set`, `types`, `clear` |
| `media` | `status`, `play`, `pause`, `toggle`, `next`, `prev`, `stop` |
| `volume` | `get`, `set N`, `up`, `down`, `mute`, `unmute`, `toggle-mute` (`--mic`) |
| `notify` | desktop notification |
| `doctor` | checks every backend; `--fix` restarts a stale accessibility bus, enables accessibility, starts `ydotoold` |

A window spec (`WIN`) can be a UUID from `win list`, `active`, `class:<substr>`,
`title:<substr>`, `pid:<n>`, or free text matched against title and class. Ambiguous specs fail
and list the candidates.

### Output and exit codes

stdout is compact JSON (JSON lines for lists). `a11y tree` prints an outline. On failure, stderr
gets one JSON object with `error`, usually a `hint`, and sometimes `candidates`.

| Code | Meaning |
|---|---|
| 0 | ok |
| 1 | runtime error |
| 2 | usage error |
| 3 | missing dependency or not inside a Plasma Wayland session |
| 4 | target not found or ambiguous |
| 5 | refused for safety |

### Coordinates

Every coordinate is in global logical pixels: window frames, accessibility boxes, OCR centers and
`input click --at`. Wayland toolkits report widget positions relative to their window, so the
CLI adds KWin's client origin. `shot` reports `covers` and `scale`, so a point (px, py) in an
image maps to `covers.x + px/scale`, `covers.y + py/scale`.

## How it works

- **Windows.** KWin scripts cannot return values over D-Bus. The CLI registers a temporary
  object on its own bus connection, loads a generated script through `org.kde.kwin.Scripting`,
  and the script calls back with JSON. Each round trip takes about 15 ms.
- **Accessibility.** AT-SPI via `python-atspi`. Before importing libatspi the CLI checks that the
  accessibility bus socket accepts connections, because libatspi aborts the process when it can't
  connect. Subtrees that aren't on screen are pruned, and layout-only containers are hidden from
  the outline.
- **Input.** `ydotool` through a uinput virtual device. Pointer moves are relative and libinput
  accelerates them, so the CLI closes the loop against KWin's cursor position. `doctor --fix` sets
  a flat acceleration profile on the virtual mouse.
- **Safety.** Synthetic input needs an explicit target. The target is activated and checked
  before any keys are sent. The CLI refuses to type into, click on, close or minimize the
  terminal it runs in (exit 5) unless `--allow-self` is given. Typed and pasted text is logged
  only as length plus a hash.

## Logs

Logs are JSON lines in `~/.local/state/kde-desktop/kde-desktop.log` (rotated at 1 MB × 3), with
the fields `timestamp`, `level`, `context`, `message`, `trace_id`, and on failure `error` and
`stack`. Every error printed on stderr carries the same `trace_id`. Set
`KDE_DESKTOP_LOG_LEVEL=debug` for subprocess and KWin round-trip timings.

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| `accessibility bus socket is stale` | Another session took over the bus socket path. Run `kde-desktop doctor --fix` |
| An app has no accessibility tree | It was started before accessibility was enabled, so restart it. Chromium/Electron need `--force-renderer-accessibility` |
| `input` fails with "kernel upgraded without a reboot" | The running kernel's modules are gone, so `uinput` can't load. Reboot |
| `ydotool types US-keyboard ASCII only` | Use `input paste` for Unicode (`--terminal` in terminals) |
| A file dialog's name field won't take `set-text` | It's an editable combo box that AT-SPI can't write to. Open the app on the target path (`app launch … --url`) instead |

## Evals

`skills/kde-desktop/evals/` holds agent test cases in the `claude plugin eval` layout. Each case
has `prompt.md`, `case.yaml` with the expected outcome, and one grader statement per file in
`graders/`. They run against the live desktop, so run them one at a time.
