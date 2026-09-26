Name:       harbour-ledcolor
Version:    2.0
Release:    1
Summary:    Notification LED colors and quiet hours
License:    GPL-3.0-or-later
URL:        https://github.com/Alzareus/harbour-ledcolor
BuildArch:  noarch
Source0:    %{name}-%{version}.tar.gz
Requires:   sailfishsilica-qt5

%description
Sailfish Silica app to pick the notification LED color for missed
calls, SMS, e-mail, other notifications and individual apps, with
quiet hours. Runs entirely as the regular user: a static mce pattern
file is installed once, then colors are driven at runtime over D-Bus.
No system file is ever rewritten and mce is never restarted by the
app itself.

%prep
%setup -q

%build

%install
install -D -m 0755 harbour-ledcolor %{buildroot}%{_bindir}/harbour-ledcolor
install -D -m 0644 harbour-ledcolor.desktop %{buildroot}%{_datadir}/applications/harbour-ledcolor.desktop
mkdir -p %{buildroot}%{_datadir}/harbour-ledcolor
cp -r qml %{buildroot}%{_datadir}/harbour-ledcolor/
install -D -m 0755 libexec/notifywatch.sh %{buildroot}/usr/libexec/harbour-ledcolor/notifywatch.sh
install -D -m 0644 systemd/harbour-ledcolor-notifywatch.service %{buildroot}/usr/lib/systemd/user/harbour-ledcolor-notifywatch.service
install -D -m 0644 mce/89-harbour-ledcolor.ini %{buildroot}/etc/mce/89-harbour-ledcolor.ini
for s in 86x86 108x108 128x128 172x172; do
    install -D -m 0644 icons/$s/harbour-ledcolor.png %{buildroot}%{_datadir}/icons/hicolor/$s/apps/harbour-ledcolor.png
done

%post
LOGT=harbour-ledcolor
INI=/etc/mce/89-harbour-ledcolor.ini

# Leftovers from 1.x (generated override + root units), if any.
systemctl disable --now harbour-ledcolor-apply.path >/dev/null 2>&1 || :
rm -f /etc/mce/90-harbour-ledcolor.ini
rm -rf /var/lib/harbour-ledcolor

mce_ok() {
    systemctl is-active --quiet mce.service &&
    dbus-send --system --print-reply --dest=com.nokia.mce \
        /com/nokia/mce/request com.nokia.mce.request.get_display_status \
        >/dev/null 2>&1
}

# Load the static patterns now, while the phone is up and reachable,
# instead of discovering a problem at the next boot. If mce does not
# come back healthy, remove our file and put mce back as it was.
INSTALL_OK=1
systemctl restart mce.service || :
i=0
until mce_ok; do
    i=$((i + 1))
    if [ "$i" -ge 15 ]; then
        INSTALL_OK=0
        break
    fi
    sleep 1
done

if [ "$INSTALL_OK" = 0 ]; then
    logger -t "$LOGT" "mce unhealthy after loading $INI - rolled back"
    echo "harbour-ledcolor: mce did not restart cleanly, pattern file removed, service NOT enabled" >&2
    rm -f "$INI"
    systemctl restart mce.service || :
    exit 0
fi

LC_USER="$(getent passwd | awk -F: '$3>=100000 && $3<200000 {print $1; exit}')"
[ -n "$LC_USER" ] || LC_USER="$(ls /home 2>/dev/null | head -n1)"
if [ -n "$LC_USER" ]; then
    LC_UID="$(id -u "$LC_USER" 2>/dev/null || true)"
    if [ -n "$LC_UID" ]; then
        export XDG_RUNTIME_DIR="/run/user/${LC_UID}"
        runuser -u "$LC_USER" -- systemctl --user daemon-reload || :
        runuser -u "$LC_USER" -- systemctl --user reset-failed harbour-ledcolor-notifywatch.service >/dev/null 2>&1 || :
        runuser -u "$LC_USER" -- systemctl --user enable harbour-ledcolor-notifywatch.service || :
        runuser -u "$LC_USER" -- systemctl --user restart harbour-ledcolor-notifywatch.service || :
    fi
else
    logger -t "$LOGT" "no user found, service not enabled"
fi

%preun
if [ "$1" = "0" ]; then
    LC_USER="$(getent passwd | awk -F: '$3>=100000 && $3<200000 {print $1; exit}')"
    if [ -n "$LC_USER" ]; then
        LC_UID="$(id -u "$LC_USER" 2>/dev/null || true)"
        LC_HOME="$(getent passwd "$LC_USER" | cut -d: -f6)"
        if [ -n "$LC_UID" ]; then
            export XDG_RUNTIME_DIR="/run/user/${LC_UID}"
            # Stopping runs ExecStopPost=--restore; run it once more
            # directly in case the service was not running.
            runuser -u "$LC_USER" -- systemctl --user disable --now harbour-ledcolor-notifywatch.service || :
            runuser -u "$LC_USER" -- env HOME="$LC_HOME" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" \
                /usr/libexec/harbour-ledcolor/notifywatch.sh --restore || :
        fi
    fi
fi

%postun
if [ "$1" = "0" ]; then
    systemctl restart mce.service || :
fi

%files
%license LICENSE
%{_bindir}/harbour-ledcolor
%{_datadir}/applications/harbour-ledcolor.desktop
%{_datadir}/harbour-ledcolor
/usr/libexec/harbour-ledcolor
/usr/lib/systemd/user/harbour-ledcolor-notifywatch.service
/etc/mce/89-harbour-ledcolor.ini
%{_datadir}/icons/hicolor/*/apps/harbour-ledcolor.png

%changelog
* Sat Sep 26 2026 harbour-ledcolor - 2.0-1
- No root service anymore: static mce patterns, runtime D-Bus control
- Stock patterns disabled/restored through mce settings, never rewritten
- mce health check with automatic rollback at install time
- Quiet hours (defer or ignore, optional full LED off)
- Unlock-based queue clearing, Nemo category detection for SMS/calls/e-mail
- Boot safety delay, emergency stop file, systemd start limit
