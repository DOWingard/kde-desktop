# KDE Plasma 6 system settings from the shell

These are one-liners that need no GUI. They are not wrapped in `kde-desktop` because a wrapper
would add nothing. Read back the state after every change and report what actually happened.

## Contents
- Appearance (theme, colors, wallpaper, cursor)
- Night light and brightness
- Displays
- Power, session, lock
- Network
- Notifications (do not disturb)
- Generic: config files, KWin reconfigure, Plasma scripting, settings modules
- Things that need confirmation first

## Appearance

```bash
plasma-apply-colorscheme --list-schemes          # current one is marked
plasma-apply-colorscheme BreezeDark              # dark mode (BreezeLight for light)
plasma-apply-lookandfeel --list                  # global themes
plasma-apply-lookandfeel -a <package-id>         # applies the whole global theme (heavy-handed)
plasma-apply-desktoptheme --list-themes
plasma-apply-cursortheme --list-themes
plasma-apply-wallpaperimage /path/to/image.png   # all screens
```

A global theme overwrites color scheme, icons, cursor and sometimes layout. Use
`plasma-apply-colorscheme` when the user only asked for dark/light mode.

## Night light and brightness

```bash
# Night light state
qdbus6 org.kde.KWin /org/kde/KWin/NightLight org.kde.KWin.NightLight.enabled
qdbus6 org.kde.KWin /org/kde/KWin/NightLight org.kde.KWin.NightLight.currentTemperature
# Enable/disable persistently: write the config, then make KWin reload it
kwriteconfig6 --file kwinrc --group NightColor --key Active true
qdbus6 org.kde.KWin /KWin reconfigure
# Temporarily suspend (returns a cookie; pass it to uninhibit to resume)
qdbus6 org.kde.KWin /org/kde/KWin/NightLight org.kde.KWin.NightLight.inhibit

# Brightness: displays are /org/kde/ScreenBrightness/display0, display1, ... (external monitors via DDC)
D=/org/kde/ScreenBrightness/display0
qdbus6 org.kde.ScreenBrightness $D org.kde.ScreenBrightness.Display.Label
qdbus6 org.kde.ScreenBrightness $D org.kde.ScreenBrightness.Display.Brightness      # current
qdbus6 org.kde.ScreenBrightness $D org.kde.ScreenBrightness.Display.MaxBrightness   # e.g. 10000
qdbus6 org.kde.ScreenBrightness $D org.kde.ScreenBrightness.Display.SetBrightness 5000 0   # 50 %
```

## Displays

```bash
kscreen-doctor -o                                # human-readable outputs, modes, scale
kscreen-doctor -j | jq '.outputs[] | select(.enabled) | {name, scale, pos, size}'
kscreen-doctor output.HDMI-A-1.scale.1.25
kscreen-doctor output.HDMI-A-1.mode.1920x1080@60
kscreen-doctor output.DP-1.disable               # see the confirmation note below
```

## Power, session, lock

```bash
powerprofilesctl get | list | set balanced       # power-saver | balanced | performance
loginctl lock-session                            # lock the screen
systemd-inhibit --what=idle:sleep --why="<reason>" <command>   # keep awake while a command runs
qdbus6 org.kde.LogoutPrompt /LogoutPrompt promptLogout         # shows the dialog; the user decides
qdbus6 org.kde.Shutdown /Shutdown logout                       # logs out immediately (see below)
```

## Network

```bash
nmcli -t -f DEVICE,TYPE,STATE,CONNECTION device
nmcli -t -f ACTIVE,SSID,SIGNAL,SECURITY dev wifi list
nmcli radio wifi on|off
nmcli connection up "<name>"
```

Bluetooth: `bluez` is not installed on this machine, so there is no Bluetooth daemon to control.

## Notifications (do not disturb)

```bash
qdbus6 org.freedesktop.Notifications /org/freedesktop/Notifications org.freedesktop.Notifications.Inhibited
# Inhibit lasts only as long as the calling D-Bus connection, so a one-shot qdbus6 call has no
# lasting effect. For lasting DND, use the Plasma notifications applet (a11y on plasmashell).
kde-desktop notify "Title" "Body"                # send one
```

## Generic mechanisms

```bash
# Any KDE setting lives in an INI file under ~/.config (kwinrc, kdeglobals, plasmarc, kcminputrc, ...)
kreadconfig6 --file kdeglobals --group General --key ColorScheme
kwriteconfig6 --file kwinrc --group Windows --key FocusPolicy ClickToFocus
qdbus6 org.kde.KWin /KWin reconfigure            # KWin re-reads kwinrc
# Plasma shell scripting (panels, widgets, wallpapers); returns printed output
qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript 'print(desktops().length)'
# Open a specific settings page for the user, or drive it with `kde-desktop a11y`
kcmshell6 --list | grep -i <topic>
kcmshell6 kcm_kscreen
# Explore any service
qdbus6                                           # list services
qdbus6 <service> <path>                          # list methods/properties
```

When a setting has no obvious key, change it once in System Settings with the user watching
(or via `kde-desktop a11y`), then compare `~/.config` before and after to learn the key.

## Confirm before doing these

Some changes lose work or are hard to undo from a broken state. Ask first:
- logout, reboot, shutdown (`org.kde.Shutdown`, `systemctl reboot/poweroff`)
- disabling the only enabled display, or changing mode/scale on it, because a bad mode can leave
  the user without a visible screen (KDE reverts after 15 s only when the GUI dialog is used)
- turning Wi-Fi off or switching networks while the user may be on a call or downloading
- applying a global theme (it overwrites the user's customisations)
