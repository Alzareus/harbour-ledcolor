#!/bin/sh
# harbour-ledcolor user service (systemd --user), never runs as root.
#
# Only runtime D-Bus requests to mce: no file under /etc is written and
# mce is never restarted. Everything done here is undone by
# "notifywatch.sh --restore" (ExecStopPost of the unit, and RPM removal).
#
# While active:
#  - the phone's stock communication LED patterns (SMS, calls, e-mail,
#    IM...) are disabled through mce's own per-pattern setting
#    (/system/osso/dsm/leds/<Pattern>), the ones we turned off are
#    recorded on disk so they can always be switched back on;
#  - incoming notifications are mapped to one of the 7 static color
#    patterns shipped in /etc/mce/89-harbour-ledcolor.ini;
#  - screen off: pending colors blink in turn; unlocking clears them;
#  - quiet hours: no LED from us, optionally every other LED pattern
#    (charging, battery...) switched off too for the duration.
#
# Emergency stop: touch ~/.config/harbour-ledcolor/disabled

set -u

CONF_DIR="$HOME/.config/harbour-ledcolor"
STATE_DIR="$HOME/.local/state/harbour-ledcolor"     # survives reboots
RUN_DIR="${XDG_RUNTIME_DIR:-/tmp}/harbour-ledcolor"  # cleared on reboot

STOCK_STATE="$STATE_DIR/stock-disabled"   # stock patterns we turned off
QUIET_STATE="$STATE_DIR/quiet-disabled"   # extra patterns off for the night

PENDING="$RUN_DIR/pending"
F_ACTIVE="$RUN_DIR/active"
F_QUIET="$RUN_DIR/quiet"          # content: defer | drop
F_SCREEN_OFF="$RUN_DIR/screen_off"
F_UNLOCKED="$RUN_DIR/unlocked"

OUR_PREFIX="PatternHarbourLedcolor"
OUR_COLORS="Red Green Blue Yellow Cyan Magenta White"

TAG="harbour-ledcolor"

log() { logger -t "$TAG" "$*" 2>/dev/null || :; }
lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# ---------------------------------------------------------------- mce

mce_call() {
    method="$1"; shift
    dbus-send --system --type=method_call --dest=com.nokia.mce \
        /com/nokia/mce/request "com.nokia.mce.request.$method" "$@" 2>/dev/null
}
mce_reply() {
    dbus-send --system --print-reply --type=method_call --dest=com.nokia.mce \
        /com/nokia/mce/request "com.nokia.mce.request.$1" 2>/dev/null
}
led_on()  { mce_call req_led_pattern_activate   "string:$1" >/dev/null || :; }
led_off() { mce_call req_led_pattern_deactivate "string:$1" >/dev/null || :; }

# Prints "true", "false" or nothing (unknown key / mce not answering).
pattern_enabled() {
    dbus-send --system --print-reply --type=method_call --dest=com.nokia.mce \
        /com/nokia/mce/request com.nokia.mce.request.get_config \
        "objpath:/system/osso/dsm/leds/$1" 2>/dev/null \
        | awk '/boolean/ {print $NF; exit}'
}
pattern_set() {
    dbus-send --system --print-reply --type=method_call --dest=com.nokia.mce \
        /com/nokia/mce/request com.nokia.mce.request.set_config \
        "objpath:/system/osso/dsm/leds/$1" "variant:boolean:$2" >/dev/null 2>&1
}

all_our_off() {
    for c in $OUR_COLORS; do led_off "$OUR_PREFIX$c"; done
}

# Pattern names known to mce, read from its (world-readable) config.
known_patterns() {
    cat /etc/mce/*.ini 2>/dev/null \
        | sed -n 's/^[[:space:]]*\(Pattern[A-Za-z0-9]*\)[[:space:]]*=.*/\1/p' \
        | grep -v "^$OUR_PREFIX" | sort -u
}
stock_comm_patterns() {
    known_patterns | grep -E '^Pattern(Communication|CommonNotification)'
}
other_patterns() {
    known_patterns | grep -vE '^Pattern(Communication|CommonNotification)'
}

# Turn off every listed pattern that is currently on, recording each one
# in STATE_FILE *before* touching it, so a crash in between can only
# lead to re-enabling something that was on anyway.
disable_into() {
    state_file="$1"; shift
    mkdir -p "$STATE_DIR"
    touch "$state_file"
    for p in "$@"; do
        [ "$(pattern_enabled "$p")" = "true" ] || continue
        grep -qxF "$p" "$state_file" || printf '%s\n' "$p" >> "$state_file"
        pattern_set "$p" false && log "stock pattern off: $p"
    done
}
restore_from() {
    state_file="$1"
    [ -f "$state_file" ] || return 0
    while IFS= read -r p; do
        [ -n "$p" ] || continue
        pattern_set "$p" true && log "stock pattern restored: $p"
    done < "$state_file"
    rm -f "$state_file"
}

restore_everything() {
    all_our_off
    restore_from "$QUIET_STATE"
    restore_from "$STOCK_STATE"
    rm -f "$F_ACTIVE" "$F_QUIET"
    : > "$PENDING" 2>/dev/null || :
}

# ------------------------------------------------------------- config

# One "dconf dump" per read instead of one process per key.
CFG=""
load_config() { CFG="$(dconf dump /apps/harbour-ledcolor/ 2>/dev/null || true)"; }
cfg() {
    # $1 key, $2 default. Strips the GVariant string quotes.
    v="$(printf '%s\n' "$CFG" | sed -n "s/^$1=//p" | head -n1)"
    v="$(printf '%s' "$v" | sed "s/^['\"]//; s/['\"]\$//")"
    [ -n "$v" ] && printf '%s' "$v" || printf '%s' "$2"
}

# "HH:MM" -> minutes since midnight, or nothing if malformed.
to_min() {
    printf '%s' "$1" | awk -F: '
        NF==2 && $1 ~ /^[0-9]+$/ && $2 ~ /^[0-9]+$/ && $1 < 24 && $2 < 60 {
            print $1 * 60 + $2 }'
}

in_quiet_window() {
    s="$(to_min "$(cfg quietStart 22:00)")"
    e="$(to_min "$(cfg quietEnd 07:00)")"
    [ -n "$s" ] && [ -n "$e" ] && [ "$s" != "$e" ] || return 1
    h="$(date +%H)"; m="$(date +%M)"
    now=$(( ${h#0} * 60 + ${m#0} ))
    if [ "$s" -lt "$e" ]; then
        [ "$now" -ge "$s" ] && [ "$now" -lt "$e" ]
    else
        # Window across midnight, e.g. 22:00 -> 07:00
        [ "$now" -ge "$s" ] || [ "$now" -lt "$e" ]
    fi
}

# Level-triggered: every tick compares the wanted state with the
# current one, so a missed tick or a restart can never leave things
# half-applied.
config_loop() {
    while :; do
        load_config

        if [ -f "$CONF_DIR/disabled" ] || [ "$(cfg serviceEnabled true)" = "false" ]; then
            if [ -f "$F_ACTIVE" ] || [ -f "$STOCK_STATE" ] || [ -f "$QUIET_STATE" ]; then
                log "LED management turned off, stock behaviour restored"
                restore_everything
            fi
            sleep 5
            continue
        fi

        if [ ! -f "$F_ACTIVE" ]; then
            # shellcheck disable=SC2046
            disable_into "$STOCK_STATE" $(stock_comm_patterns)
            touch "$F_ACTIVE"
            log "LED management active"
        fi

        if [ "$(cfg quietEnabled false)" = "true" ] && in_quiet_window; then
            mode="$(cfg quietMode defer)"
            [ "$mode" = "drop" ] || mode="defer"
            if [ ! -f "$F_QUIET" ]; then
                all_our_off
                [ "$mode" = "drop" ] && : > "$PENDING"
                log "quiet hours start (mode: $mode)"
            fi
            printf '%s' "$mode" > "$F_QUIET"
            if [ "$(cfg quietAllLeds true)" = "true" ]; then
                if [ ! -f "$QUIET_STATE" ]; then
                    # shellcheck disable=SC2046
                    disable_into "$QUIET_STATE" $(other_patterns)
                fi
            else
                restore_from "$QUIET_STATE"
            fi
        else
            if [ -f "$F_QUIET" ]; then
                rm -f "$F_QUIET"
                log "quiet hours end"
            fi
            restore_from "$QUIET_STATE"
        fi

        sleep 5
    done
}

# ------------------------------------------------- notification -> color

hex_to_pattern() {
    case "$(lower "$1")" in
        ff0000) echo "${OUR_PREFIX}Red" ;;
        00ff00) echo "${OUR_PREFIX}Green" ;;
        0000ff) echo "${OUR_PREFIX}Blue" ;;
        ffff00) echo "${OUR_PREFIX}Yellow" ;;
        00ffff) echo "${OUR_PREFIX}Cyan" ;;
        ff00ff) echo "${OUR_PREFIX}Magenta" ;;
        *)      echo "${OUR_PREFIX}White" ;;
    esac
}

# customApps is stored by the app as "name::hex" lines; dconf dump
# shows the newlines as a literal backslash-n, decoded here.
custom_apps() {
    cfg customApps "" | awk '{ gsub(/\\n/, "\n"); gsub(/\\'"'"'/, "'"'"'"); print }'
}

resolve_pattern() {
    app="$(lower "$1")"; cat="$(lower "$2")"
    load_config

    hex="$(custom_apps | while IFS= read -r entry; do
        [ -n "$entry" ] || continue
        name="$(lower "${entry%%::*}")"
        [ -n "$name" ] || continue
        case "$app" in *"$name"*) printf '%s' "${entry##*::}"; break ;; esac
    done)"

    if [ -z "$hex" ]; then
        case "$cat" in
            *sms*|*mms*)            hex="$(cfg smsColor 00ff00)" ;;
            *call*)                 hex="$(cfg callColor ff0000)" ;;
            *email*)                hex="$(cfg emailColor ffff00)" ;;
            *)                      hex="$(cfg imColor 0000ff)" ;;
        esac
    fi
    hex_to_pattern "$hex"
}

add_pending() {
    grep -qxF "$1" "$PENDING" 2>/dev/null || printf '%s\n' "$1" >> "$PENDING"
}

one_shot() {
    ( led_on "$1"; sleep 6; led_off "$1" ) &
}

handle_notification() {
    app="$1"; cat="$2"
    [ -f "$F_ACTIVE" ] || return 0
    [ -n "$app" ] || return 0

    pattern="$(resolve_pattern "$app" "$cat")"

    if [ -f "$F_QUIET" ]; then
        if [ "$(cat "$F_QUIET" 2>/dev/null)" = "defer" ]; then
            add_pending "$pattern"
            log "'$app' [$cat] -> $pattern, quiet hours: kept for later"
        else
            log "'$app' [$cat] -> $pattern, quiet hours: ignored"
        fi
        return 0
    fi

    if [ -f "$F_SCREEN_OFF" ]; then
        add_pending "$pattern"
        log "'$app' [$cat] -> $pattern, screen off: queued"
    elif [ -f "$F_UNLOCKED" ]; then
        one_shot "$pattern"
        log "'$app' [$cat] -> $pattern, in use: single blink"
    else
        add_pending "$pattern"
        one_shot "$pattern"
        log "'$app' [$cat] -> $pattern, lock screen: blink + queued"
    fi
}

# Parses dbus-monitor's view of Notify(app_name, replaces_id, icon,
# summary, body, actions, hints, timeout): first top-level string is
# the app name, hints["category"] the Nemo category; the final
# top-level int32 (timeout) marks the end of the call.
notify_watch() {
    dbus-monitor --session "type='method_call',interface='org.freedesktop.Notifications',member='Notify'" 2>/dev/null \
    | awk '
        /^method call.*member=Notify/ { inmsg=1; app=""; cat=""; gotapp=0; wantcat=0; next }
        !inmsg { next }
        /^   string "/ && !gotapp {
            s=$0; sub(/^   string "/, "", s); sub(/"$/, "", s); app=s; gotapp=1; next
        }
        /string "category"/ { wantcat=1; next }
        wantcat && /variant/ {
            s=$0; sub(/.*string "/, "", s); sub(/".*$/, "", s); cat=s; wantcat=0; next
        }
        /^   int32 / {
            gsub(/\t/, " ", app); gsub(/\t/, " ", cat)
            printf "%s\t%s\n", app, cat; fflush(); inmsg=0; next
        }' \
    | while IFS="$(printf '\t')" read -r app cat; do
        handle_notification "$app" "$cat"
    done
}

# ------------------------------------------------------- screen / lock

display_poll() {
    while :; do
        st="$(lower "$(mce_reply get_display_status | sed -n 's/.*string "\(.*\)".*/\1/p')")"
        case "$st" in
            *off*)
                touch "$F_SCREEN_OFF"; rm -f "$F_UNLOCKED"
                ;;
            "")
                : # mce not answering: keep the previous state
                ;;
            *)
                rm -f "$F_SCREEN_OFF"
                tk="$(lower "$(mce_reply get_tklock_mode | sed -n 's/.*string "\(.*\)".*/\1/p')")"
                case "$tk" in
                    *unlocked*)
                        touch "$F_UNLOCKED"
                        if [ -s "$PENDING" ]; then
                            : > "$PENDING"
                            all_our_off
                            log "unlocked: pending queue cleared"
                        fi
                        ;;
                    *) rm -f "$F_UNLOCKED" ;;
                esac
                ;;
        esac
        sleep 1
    done
}

cycle_ok() {
    [ -f "$F_ACTIVE" ] && [ ! -f "$F_QUIET" ] && [ -f "$F_SCREEN_OFF" ] && [ -s "$PENDING" ]
}

cycle_leds() {
    while :; do
        if cycle_ok; then
            # Copy first: the list may change while we loop over it.
            list="$(cat "$PENDING" 2>/dev/null)"
            for p in $list; do
                cycle_ok || break
                led_on "$p"; sleep 1.6; led_off "$p"; sleep 1.4
            done
        else
            sleep 1
        fi
    done
}

# ------------------------------------------------------- app list

publish_installed_apps() {
    list="$(
        for f in /usr/share/applications/*.desktop "$HOME"/.local/share/applications/*.desktop; do
            [ -f "$f" ] || continue
            grep -q '^NoDisplay=true' "$f" 2>/dev/null && continue
            name="$(grep -m1 '^Name=' "$f" 2>/dev/null | cut -d= -f2-)"
            [ -n "$name" ] && printf '%s\n' "$name"
        done | sort -u | tr '\n' ';'
    )"
    escaped="$(printf '%s' "$list" | sed "s/'/\\\\'/g")"
    dconf write /apps/harbour-ledcolor/installedApps "'${escaped}'" 2>/dev/null || :
}

# ---------------------------------------------------------------- main

mkdir -p "$RUN_DIR" "$STATE_DIR"

if [ "${1:-}" = "--restore" ]; then
    restore_everything
    log "restore done"
    exit 0
fi

if [ -f "$CONF_DIR/disabled" ]; then
    log "emergency stop file present ($CONF_DIR/disabled), not starting"
    restore_everything
    exit 0
fi

# Never compete with the boot sequence: if the phone just started,
# let mce, lipstick and the rest settle first.
up="$(cut -d. -f1 /proc/uptime 2>/dev/null || echo 999)"
if [ "$up" -lt 120 ]; then
    sleep $(( 120 - up ))
fi

# A previous run may have been killed without --restore (crash, power
# loss): start from a clean, stock state, then re-apply.
restore_everything
: > "$PENDING"
rm -f "$F_SCREEN_OFF" "$F_UNLOCKED"

publish_installed_apps

notify_watch &
display_poll &
cycle_leds &
config_loop
