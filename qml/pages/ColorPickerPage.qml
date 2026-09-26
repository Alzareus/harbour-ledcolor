import QtQuick 2.6
import Sailfish.Silica 1.0
import Nemo.DBus 2.0
import "../Translations.js" as T

Page {
    id: page

    property string currentHex: "ffffff"
    property string eventLabel: ""
    property var palette: []
    property string lang: "en"

    // When true, this page also lets the person (re)assign which app
    // this entry refers to (used for the free-form "Autres
    // applications" entries, not the 4 fixed system rows).
    property bool pickAppEnabled: false
    property string appName: eventLabel

    // Selection only becomes final when "Valider" is tapped - tapping a
    // swatch just previews it (border highlight + live test blink) so
    // the person can flick between colors before committing.
    property string selectedHex: currentHex

    signal colorChosen(string hex)
    signal entrySaved(string name, string hex)

    function tr(key) { return T.tr(lang, key) }

    // Statically-defined, fixed-color test patterns shipped by the
    // RPM (see /etc/mce/89-harbour-ledcolor-test.ini) - always
    // available, no root action or mce restart needed to try them.
    DBusInterface {
        id: mceRequest
        service: "com.nokia.mce"
        path: "/com/nokia/mce/request"
        iface: "com.nokia.mce.request"
        bus: DBus.SystemBus
    }

    function testBlink(paletteName) {
        var suffix = paletteName.charAt(0).toUpperCase() + paletteName.slice(1)
        mceRequest.call("req_led_pattern_activate", ["PatternHarbourLedcolorTest" + suffix])
    }

    function selectAndPreview(hex, paletteName) {
        selectedHex = hex
        testBlink(paletteName)
    }

    function openAppPicker() {
        var picker = pageStack.push(Qt.resolvedUrl("AppPickerDialog.qml"), { lang: page.lang })
        picker.appChosen.connect(function(name) {
            page.appName = name
            pageStack.pop()
        })
    }

    function confirmAndClose() {
        if (pickAppEnabled) {
            entrySaved(appName, selectedHex)
        } else {
            colorChosen(selectedHex)
        }
        pageStack.pop()
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        PullDownMenu {
            visible: pickAppEnabled
            MenuItem {
                text: page.tr("change_app_menu")
                onClicked: openAppPicker()
            }
        }

        Column {
            id: column
            width: page.width
            spacing: Theme.paddingLarge

            PageHeader {
                title: pickAppEnabled
                    ? (page.appName.length > 0 ? page.appName : page.tr("choose_app_placeholder"))
                    : eventLabel
            }

            Grid {
                x: Theme.horizontalPageMargin
                columns: 4
                spacing: Theme.paddingMedium

                Repeater {
                    model: palette
                    delegate: Rectangle {
                        width: (page.width - 2 * Theme.horizontalPageMargin - 3 * Theme.paddingMedium) / 4
                        height: width
                        radius: Theme.paddingSmall
                        color: "#" + modelData.hex
                        border.width: selectedHex === modelData.hex ? 4 : 1
                        border.color: Theme.highlightColor

                        MouseArea {
                            anchors.fill: parent
                            onClicked: selectAndPreview(modelData.hex, modelData.name)
                        }
                    }
                }
            }

            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                enabled: !pickAppEnabled || page.appName.length > 0
                text: page.tr("use_color")
                onClicked: confirmAndClose()
            }

            Item { width: 1; height: Theme.paddingLarge }
        }
    }
}
