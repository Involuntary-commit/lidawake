# lidawake

Keep a MacBook awake with the lid closed while it's plugged in, with no external display needed. On battery it sleeps after 10 minutes, and normal macOS sleep is left alone the rest of the time.

I made it so remote tools (SSH, remote desktop, Claude Code Remote Control) keep working while the MacBook sits closed on a shelf.

> ⚠️ **Read this first**
> - **Never put the Mac in a bag or other closed space while it's plugged in.** That's exactly when this tool keeps it awake, and it can get hot.
> - It's tested on **one** Mac: a 16" MacBook Pro (M1 Pro, 2021) on macOS 26 (Tahoe). Other models and versions may behave differently.
> - It changes a system power setting (`pmset disablesleep`). Uninstalling switches it back.
> - Provided as is, with no warranty. Use it at your own risk (see [LICENSE](LICENSE)).

## What it does

| | Lid open | Lid closed |
|---|---|---|
| **Plugged in** | Normal macOS behavior | Display off, Mac stays awake |
| **Battery (15% or more)** | Normal macOS behavior | Display off, sleeps after **10 min** |
| **Battery (under 15%)** | macOS fully in charge | Sleeps right away |

- **"Normal macOS behavior"** means your own sleep settings from System Settings still apply. Apps that keep the Mac awake, like video players, are still respected.
- **Closed while plugged in, then unplugged:** the 10 minutes start when you unplug. Plugging back in cancels the timer.
- **Remote desktop:** while a Jump Desktop session is connected, the display is left on. Switching it off would blank the remote screen and lock the Mac.

## Safety

- **Fails safe.** If it can't read the lid, the battery, or the sleep settings, it hands sleep back to macOS and shows a notification.
- **Checks itself after macOS updates.** The first time it starts on a new macOS build, it tests everything it relies on and shows a notification saying it's OK, or naming what broke.
- **Stops cleanly.** If the helper is stopped or uninstalled, normal sleep comes back immediately. If it crashes, macOS restarts it.

## Install

1. Go to [**Releases**](../../releases/latest) and download **`lidawake-<version>.zip`**.
2. Double-click the zip in your Downloads folder to unzip it.
3. Open **Terminal** (press ⌘ Space, type *Terminal*, press Return).
4. Type `sudo bash ` (with a space at the end). **Don't press Return yet.**
5. Drag **`install.sh`** from the unzipped folder into the Terminal window. Its path appears after what you typed.
6. Press Return and type your Mac password. Nothing shows while you type, which is normal. Press Return again.

It runs a self-check first. You should see `OK: everything the helper relies on still works`, followed by a few log lines.

To update later, download the new release and do the same steps. The new version replaces the old one.

**Test it once:** close the lid while plugged in and make sure the Mac stays reachable. Then unplug it with the lid closed and check that it sleeps after about 10 minutes.

## Uninstall

Same as installing, but type `sudo bash ` and drag in `install.sh`, then add ` uninstall` at the end before pressing Return:

```
sudo bash /path/to/install.sh uninstall
```

This puts the Mac back to normal sleep.

## Check it anytime

```
sudo /usr/local/bin/lidawake.sh selftest
```

The log is at `/var/log/lidawake.log`.

## How it works

`lidawake.sh` runs in the background as a system service (a launchd daemon) and checks every 5 seconds:

- **Lid state:** `ioreg` `AppleClamshellState`.
- **Power source and battery %:** `pmset -g batt`.
- **Idle time:** `HIDIdleTime`.
- **Apps holding the Mac awake:** `pmset -g assertions`.

It keeps `pmset disablesleep` on so that closing the lid doesn't sleep the Mac, then does the sleeping itself (`pmset sleepnow`) wherever macOS normally would. It turns the display off with `pmset displaysleepnow` when the lid closes.

Lid changes are noticed by checking, so the display can take up to about 5 seconds to switch off after you close the lid.

## License

[MIT](LICENSE)
