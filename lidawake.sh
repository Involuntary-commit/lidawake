#!/bin/bash
# lidawake: keep the Mac awake with the lid closed while it's plugged in.
#   Lid closed, plugged in -> display off, stays awake.
#   Lid closed, battery    -> display off, sleeps after 10 min (at once below 15%).
#   Battery below 15%      -> hands sleep back to macOS completely.
#   Lid open               -> macOS's own idle-sleep settings, applied here because
#                             `pmset disablesleep` blocks them otherwise.
# Fails safe: if anything can't be read, normal sleep is restored.
# After a macOS update (first start on a new build) it checks itself and
# posts a notification with the result.
#
#   lidawake.sh            run (started by launchd)
#   lidawake.sh selftest   check now and print the result

CHECK_EVERY=5          # seconds between checks
BATTERY_GRACE=600      # 10 minutes on battery with the lid closed
LOW_BATTERY=15         # on battery below this %: normal macOS sleep
DISPLAY_RECHECK=60     # re-send "display off" this often while closed
LOG=/var/log/lidawake.log
BUILD_FILE=/var/db/lidawake.build

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG"; }

# Pause in a way that lets a stop signal through immediately.
nap() { sleep "$1" & wait $!; }

console_user() {
  u=$(stat -f %Su /dev/console 2>/dev/null)
  [ -n "$u" ] && [ "$u" != root ] && echo "$u"
}

notify() {
  u=$(console_user) || return 1
  launchctl asuser "$(id -u "$u")" sudo -u "$u" /usr/bin/osascript \
    -e "display notification \"$1\" with title \"Lid helper\"" >/dev/null 2>&1
}

# The real current value, read fresh every time (missing line means off).
disablesleep_now() { /usr/bin/pmset -g | awk '$1=="SleepDisabled" {v=$2} END {print v+0}'; }

set_disablesleep() {
  if [ "$(disablesleep_now)" != "$1" ]; then
    /usr/bin/pmset -a disablesleep "$1"
    log "disablesleep -> $1 ($2)"
  fi
}

read_state() {
  lid=$(/usr/sbin/ioreg -r -k AppleClamshellState -d 1 | awk -F'= ' '/"AppleClamshellState"/ {print $2; exit}')
  batt=$(/usr/bin/pmset -g batt)
  case "$(echo "$batt" | head -1)" in
    *"AC Power"*)      power=ac;      section="AC Power:" ;;
    *"Battery Power"*) power=battery; section="Battery Power:" ;;
    *)                 power="";      section="" ;;
  esac
  pct=$(echo "$batt" | grep -oE '[0-9]+%' | head -1 | tr -d '%')
  idle=$(/usr/sbin/ioreg -c IOHIDSystem -d 4 | awk '/HIDIdleTime/ {print int($NF/1000000000); exit}')
  held=$(/usr/bin/pmset -g assertions | awk '$1=="PreventUserIdleSystemSleep" {print $2; exit}')
  # This power source's idle timers from System Settings: "display sleep".
  timers=$(/usr/bin/pmset -g custom | awk -v want="$section" '
    index($0, want) == 1 {b=1; next}
    /Power:$/ {b=0}
    b && $1=="displaysleep" {d=$2}
    b && $1=="sleep" {s=$2}
    END {if (s != "") print d+0, s+0}')
  dmin=${timers% *}; smin=${timers#* }
}

is_num() { case "$1" in ''|*[!0-9]*) return 1 ;; esac; }

# Lists whatever couldn't be read; empty means everything is fine.
problems() {
  p=""
  [ "$lid" = Yes ] || [ "$lid" = No ] || p="${p}lid sensor; "
  [ -n "$power" ]  || p="${p}charger/battery; "
  is_num "$pct"    || p="${p}battery %; "
  is_num "$idle"   || p="${p}idle time; "
  is_num "$held"   || p="${p}apps keeping it awake; "
  is_num "$dmin" && is_num "$smin" || p="${p}sleep settings; "
  echo "$p"
}

selftest() {
  read_state
  p=$(problems)
  # The sleep switch itself must still work. Never switch it off with the lid
  # closed, since that would put the Mac to sleep.
  before=$(disablesleep_now)
  /usr/bin/pmset -a disablesleep 1
  [ "$(disablesleep_now)" = 1 ] || p="${p}sleep switch (on); "
  if [ "$lid" = No ]; then
    /usr/bin/pmset -a disablesleep 0
    [ "$(disablesleep_now)" = 0 ] || p="${p}sleep switch (off); "
  fi
  /usr/bin/pmset -a disablesleep "$before"
  echo "$p"
}

if [ "$1" = selftest ]; then
  p=$(selftest)
  if [ -z "$p" ]; then echo "OK: everything the helper relies on still works."
  else echo "PROBLEM: can't read/use: $p"; fi
  echo "(Still worth a real test: close the lid and watch.)"
  exit 0
fi

# If the helper is stopped or removed, give the Mac back normal sleep.
trap '/usr/bin/pmset -a disablesleep 0; log "stopped, normal sleep restored"; exit 0' TERM INT

log "started"
notice=""
build=$(sw_vers -buildVersion)
if [ "$(cat "$BUILD_FILE" 2>/dev/null)" != "$build" ]; then
  p=$(selftest)
  if [ -z "$p" ]; then
    log "self-check on macOS $build: OK"
    notice="Checked itself after a macOS change ($build): all OK."
  else
    log "self-check on macOS $build: PROBLEM: $p"
    notice="macOS changed ($build) and something broke: $p Normal sleep is on until it's fixed."
  fi
  echo "$build" > "$BUILD_FILE"
fi

closed_since=""
battery_since=""
last_display_off=0
warned=""

go_to_sleep() {
  set_disablesleep 0 "$1"
  log "sleeping now"
  /usr/bin/pmset sleepnow
  closed_since=""
  battery_since=""
  nap 30   # give the Mac time to actually fall asleep
}

while true; do
  now=$(date +%s)

  # Show the self-check result once someone is logged in to see it.
  if [ -n "$notice" ] && notify "$notice"; then notice=""; fi

  read_state
  p=$(problems)
  if [ -n "$p" ]; then
    # Fail safe: anything unreadable means normal macOS sleep.
    set_disablesleep 0 "can't read: $p"
    if [ -z "$warned" ]; then
      notify "Can't read: $p Normal sleep is on, so lid-closed awake won't work." && warned=1
    fi
    closed_since=""
    nap "$CHECK_EVERY"
    continue
  fi

  if [ "$lid" = No ]; then
    if [ -n "$closed_since" ]; then
      # Just opened: wake the display ourselves, since we put it to sleep.
      log "lid opened"
      /usr/bin/caffeinate -u -t 2 &
    fi
    closed_since=""
    if [ "$power" = battery ] && [ "$pct" -lt "$LOW_BATTERY" ]; then
      # Low battery: let macOS handle sleep itself, including its emergency
      # sleep, so closing the lid sleeps at once and nothing blocks it.
      set_disablesleep 0 "battery ${pct}%, lid open"
      nap "$CHECK_EVERY"
      continue
    fi
    set_disablesleep 1 "lid open"
    # Copy macOS idle sleep: after the display + sleep timers, unless an app
    # (video, caffeinate, ...) is holding the Mac awake. A sleep timer of 0
    # means "never", as in System Settings.
    if [ "$smin" -gt 0 ] && [ "$held" -eq 0 ] && [ "$idle" -ge $(( (dmin + smin) * 60 )) ]; then
      go_to_sleep "idle ${idle}s on $power, lid open"
      continue
    fi
  else
    if [ -z "$closed_since" ]; then
      closed_since=$now
      last_display_off=0
      log "lid closed ($power, ${pct}%)"
    fi
    if [ $((now - last_display_off)) -ge "$DISPLAY_RECHECK" ]; then
      # Re-read the lid right before, so a lid opened in the last few
      # seconds never gets its display switched off.
      read_state
      [ "$lid" = Yes ] || continue   # opened meanwhile: handle it right away
      # Only the PreventSystemSleep one: it's held exactly while connected
      # (Jump's UserIsActive entries linger after disconnecting).
      if /usr/bin/pmset -g assertions | grep -q 'PreventSystemSleep named: "Jump Desktop Connect Remote Connection"'; then
        # Someone is using the Mac remotely: switching the display off would
        # blank their session and lock the screen. Jump uses its own virtual
        # display, so the closed built-in one isn't needed anyway.
        [ -z "$remote_logged" ] && log "remote session active, leaving display alone" && remote_logged=1
      else
        /usr/bin/pmset displaysleepnow
        log "display off (lid closed)"
        remote_logged=""
      fi
      last_display_off=$now
    fi
    if [ "$power" = ac ]; then
      set_disablesleep 1 "lid closed, plugged in"
    else
      # Count from when the lid closed or the charger was pulled, whichever
      # came later.
      [ -z "$battery_since" ] && battery_since=$now
      start=$closed_since
      [ "$battery_since" -gt "$start" ] && start=$battery_since
      if [ "$pct" -lt "$LOW_BATTERY" ] || [ $((now - start)) -ge "$BATTERY_GRACE" ]; then
        go_to_sleep "battery ${pct}%, lid closed $((now - start))s"
        continue
      fi
    fi
  fi

  [ "$power" = ac ] && battery_since=""
  nap "$CHECK_EVERY"
done
