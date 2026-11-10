---
name: kde-desktop
description: Operate the user's KDE Plasma 6 (Wayland, Arch Linux) desktop through the `kde-desktop` CLI. It lists, focuses, moves, tiles and closes windows. It reads and operates any app's UI through the accessibility tree (press buttons, fill fields, read text, toggle settings) without stealing focus. It takes window/region screenshots with exact screen-coordinate mapping, OCRs the screen, types, clicks and presses keys, launches apps, and handles the clipboard, media playback, volume, notifications and KDE system settings (dark mode, night light, brightness, displays, Wi-Fi, power profile). Use it whenever the user wants something done in a desktop GUI app or on their screen, even without saying KDE, Wayland or GUI: "open kcalc and…", "click the…", "what's on my screen", "fill in this form", "move/arrange my windows", "pause the music", "turn the volume down", "switch to dark mode", "screenshot that window", "copy X to my clipboard". For web pages in Chrome, prefer the claude-in-chrome tools.
---

# KDE desktop control

`kde-desktop` (on PATH; source in `scripts/kde-desktop`) gives you a Plasma 6 Wayland session
through one CLI. Every command prints compact JSON (JSON lines for lists). Failures print one JSON
object on stderr: `error`, often a `hint`, sometimes `candidates`. Exit codes:
0 ok · 1 error · 2 usage · 3 missing dependency · 4 target not found/ambiguous · 5 refused for safety.

If anything fails unexpectedly, run `kde-desktop doctor` first. It checks every backend and prints
the fix (`doctor --fix` restarts a stale accessibility bus, enables accessibility, starts ydotoold).

## The user is usually at the keyboard

This is a live desktop someone is using, not a sandbox. Every focus change, raised window or
synthetic keystroke lands in the middle of what they are doing. So:

- Prefer methods that do not need focus. Accessibility actions and KWin window operations work
  on background windows. Typing and clicking need focus and race with the user's own input.
- If you must take focus, remember what was active and give it back when done:
  `PREV=$(kde-desktop win active | jq -r .id)` … `kde-desktop win activate "$PREV"`.
- Synthetic input goes to whatever has focus. The CLI therefore makes you name a target
  (`--window`), activates and verifies it, and refuses to type into or close the terminal you are
  running in (exit 5). Do not use `--allow-self` unless the user explicitly asked for exactly that.

## Choosing a method: most semantic first

1. **No GUI at all.** If the goal is a system state (dark mode, brightness, Wi-Fi, display scale,
   power profile, a config value), use the command-line/D-Bus route in `references/system.md`. It
   is faster, exact, and does not disturb the screen.
2. **Accessibility tree (`a11y`).** For anything inside a Qt/KDE, GTK or Firefox window: read
   widgets, press buttons, set text, move sliders. Exact, focus-free, verifiable.
3. **Screenshot + OCR.** For apps with no tree (games, Electron/Chromium without the a11y flag,
   canvases), or to *see* layout, colours and images. `ocr --find` returns click coordinates.
4. **Synthetic input (`input`).** Last resort, or for things only keys can do (shortcuts, typing
   into a terminal, drag-free clicking where a11y has no action). Always `--window`.

After acting, verify through the same channel: read the text back, re-run `a11y find`, check
`win get`, or take a screenshot. Report what you observed, not what you expected.

## Windows

```bash
kde-desktop win list                     # JSON lines: id, title, class, pid, frame{x,y,w,h}, client{…}, active, minimized…
kde-desktop win active
kde-desktop win activate|get|close|minimize|unminimize|maximize|unmaximize WIN
kde-desktop win move WIN X Y | resize WIN W H | place WIN X Y W H
kde-desktop win fullscreen|above WIN on|off ; kde-desktop win to-desktop WIN N
kde-desktop desk list | desk switch N ; kde-desktop screens   # geometry + cursor
```

`WIN` is a UUID from `win list`, `active`, `class:<substr>`, `title:<substr>`, `pid:<n>`, or free
text matched against title and class. An ambiguous spec fails with `candidates`; then pass the id.
`close` is graceful (the app may prompt to save). Tiling example on 1920×1040 usable area:
`place A 0 0 960 1040` and `place B 960 0 960 1040`.

## Accessibility: inspect, then act

```bash
kde-desktop a11y apps                                   # which apps expose a tree
kde-desktop a11y tree --window class:kcalc [--max 250] [--depth N] [--under PATH] [--hidden]
kde-desktop a11y find --window WIN [--role R] [--name TEXT [--exact]] [--action-filter A] [--under PATH]
kde-desktop a11y do   --window WIN (--path P | --role R --name TEXT [--exact] [--nth K]) [--action NAME]
kde-desktop a11y text|set-text|focus|value|info --window WIN (--path P | --role/--name …)
#   set-text VALUE [--append]  ·  value [--set N]  ·  --app NAME|PID works instead of --window
```

Tree lines look like `[0.0.9.0] button "Six" @856,576 99x55 {Press}`: path, role, name, states,
**global screen box**, and actions. Layout-only containers are hidden. Paths are valid until
that part of the UI changes, so re-find after navigation.

Read the tree before guessing selectors. Accessible names are often semantic, not the visible
label: KCalc's "7" button is named "Seven" and "×" is "Multiply". Qt 6 reports `button` where
older toolkits say `push button` (the CLI treats them as the same). `do` with no `--action` picks the
first of press/click/activate/toggle/jump/open. `set-text` verifies by reading back. If it reports
`verified: false`, focus the field and use `input type`.

Patterns that save a lot of trial and error:
- **Menus.** Qt menu items are in the tree even while the menu is closed, but they are not marked
  showing, so add `--hidden`. Their `Press` triggers the command directly, with no need to open the
  menu: `a11y do --window W --hidden --role "menu item" --name "Save" --exact`.
- **Modal dialogs.** An action that opens a modal dialog returns `ok` with a `note` ("no reply").
  The app is blocked inside the dialog. Find the dialog with `win list`. KDE file dialogs are not
  flagged `dialog`, so match by title (`title:Save File`).
- **Avoid file dialogs.** Their filename box is an editable combo box whose text AT-SPI cannot set.
  Open the app on the target path instead (`app launch org.kde.kate --url /abs/path.txt`). Then
  plain "Save" writes there without a dialog. If a dialog is unavoidable, typing needs `input`.
- **Editors.** Kate's document view is a `text` node: `set-text` replaces the whole document and
  verifies by reading back.

No tree, or an empty one? Apps started before accessibility was enabled must be restarted.
Chromium/Electron apps need `--force-renderer-accessibility`. Otherwise fall back to OCR.

## Screenshots and OCR

```bash
kde-desktop shot [--window WIN [--no-activate] | --region X Y W H] [--max-width 1568] [--out PATH]
kde-desktop ocr  [same targeting] [--find "Save"]       # lines (or matches) with box + center
```

`shot` returns `path` (read it with the Read tool to see it), `covers` (the screen rectangle),
and `scale`. To click something you saw at image pixel (px, py):
`screen_x = covers.x + px / scale`, `screen_y = covers.y + py / scale`. Window shots raise the
window first (restore focus after) unless `--no-activate`. Then anything on top is captured.
Prefer window/region shots to full-desktop ones: they are smaller, cheaper to view and include
less of the user's private screen. OCR needs English data; `doctor` says if it is missing.

## Synthetic input

```bash
kde-desktop input key   ctrl+l --window WIN             # chords: ctrl shift alt super + key; several allowed
kde-desktop input type  "ascii text" --window WIN       # US-layout ASCII only
kde-desktop input paste "any Ünïcode ✓" --window WIN [--terminal]   # via clipboard, restored afterwards
kde-desktop input click --window WIN --at X Y [--button right] [--double]
kde-desktop input scroll 3 --window WIN --at X Y        # positive = down
kde-desktop input move X Y
```

Coordinates are global logical pixels, the same space as `win list` frames, tree boxes and
OCR centers. `click --at` refuses a point outside the target window. In terminals, paste needs
`--terminal` (ctrl+shift+v). Input runs through ydotool/uinput. If `doctor` reports it
unavailable (e.g. "kernel upgraded without a reboot"), say so and use `a11y` instead.

## Apps, clipboard, media, volume, notifications

```bash
kde-desktop app list [QUERY]                            # desktop entries: id, name
kde-desktop app launch kcalc [--url FILE_OR_URL] [--wait 8]   # --wait returns the new window JSON
kde-desktop clip get | set "text" | set --file img.png --type image/png | get --type image/png --out f.png | types | clear
kde-desktop media status | play | pause | toggle | next | prev [--player firefox]
kde-desktop volume [get | set 40 | up | down | mute | unmute | toggle-mute] [--step 5] [--mic]
kde-desktop notify "Title" "Body" [--urgency low|normal|critical]
```

A launched app usually takes focus. Restore the user's window afterwards if you only need the
app in the background. `clip set` replaces what the user had copied, so mention it when you do it.

## Worked example: write and save a document without stealing focus

```bash
PREV=$(kde-desktop win active | jq -r .id)
W=$(kde-desktop app launch org.kde.kate --url "$HOME/notes/todo.txt" --wait 8 | jq -r .window.id)
kde-desktop win activate "$PREV" >/dev/null               # give the user their window back
P=$(kde-desktop a11y find --window "$W" --role text --max 1 | jq -r .path)
kde-desktop a11y set-text --window "$W" --path "$P" $'first line\nsecond line'
kde-desktop a11y do --window "$W" --hidden --role "menu item" --name Save --exact
cat "$HOME/notes/todo.txt"                               # verify on disk, then close
kde-desktop win close "$W"
```

## Worked example: background calculation

```bash
PREV=$(kde-desktop win active | jq -r .id)
kde-desktop app launch kcalc --wait 6 >/dev/null && kde-desktop win activate "$PREV" >/dev/null
kde-desktop a11y tree --window class:kcalc --max 40     # learn names: Seven, Multiply, Equals…
for b in Seven Multiply Six Equals; do kde-desktop a11y do --window class:kcalc --role button --name $b --exact; done
kde-desktop a11y find --window class:kcalc --role text   # → the display node path
kde-desktop a11y text --window class:kcalc --path 0.0.0.4    # {"text": "42", …}
```

## Boundaries

- Ask before actions that are outward-facing or lose work: sending messages or email, posting,
  purchases, deleting files, closing windows with unsaved changes, logout/reboot, display changes
  that could blank the only screen (see `references/system.md`).
- Do not read or type into password fields or password managers unless the user asked for that
  exact action. Do not paste screen contents (other people's messages, mail) into your reply
  beyond what the task needs.
- Diagnostics live in `~/.local/state/kde-desktop/kde-desktop.log` (JSON lines, `trace_id` matches
  the one in error output). Typed and pasted text is logged only as length + hash.
