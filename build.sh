#!/bin/sh
# Builds the noarch RPM into ./build/ (needs rpmbuild: "apt install rpm"
# on Debian/Ubuntu, "dnf install rpm-build" on Fedora). The package is
# pure QML + shell, so no Sailfish SDK is required.
set -eu
cd "$(dirname "$0")"

NAME=harbour-ledcolor
VERSION="$(sed -n 's/^Version:[[:space:]]*//p' rpm/$NAME.spec)"
TOP="$PWD/build"
SRC="$NAME-$VERSION"

rm -rf "$TOP"
mkdir -p "$TOP/SOURCES" "$TOP/stage/$SRC"
cp -r qml libexec systemd mce icons harbour-ledcolor harbour-ledcolor.desktop LICENSE \
    "$TOP/stage/$SRC/"
tar -C "$TOP/stage" -czf "$TOP/SOURCES/$SRC.tar.gz" "$SRC"

# The static mce file must stay strictly valid: a broken line there is
# the one thing in this package that could upset mce.
awk '/^#/ || /^$/ || $0 == "[LEDPatternHybris]" { next }
     $0 !~ /^PatternHarbourLedcolor[A-Za-z]+=[0-9]+;[0-7];[0-9]+;[0-9]+;[0-9]+;[0-9a-f]{6}$/ {
         print "invalid mce line: " $0; bad = 1 }
     END { exit bad }' mce/89-harbour-ledcolor.ini
dups="$(grep '^Pattern' mce/89-harbour-ledcolor.ini | cut -d= -f1 | sort | uniq -d)"
[ -z "$dups" ] || { echo "duplicate mce patterns: $dups"; exit 1; }

sh -n libexec/notifywatch.sh

rpmbuild --define "_topdir $TOP" -bb rpm/$NAME.spec
find "$TOP/RPMS" -name '*.rpm' -exec cp {} "$TOP/" \;
ls -1 "$TOP"/*.rpm
