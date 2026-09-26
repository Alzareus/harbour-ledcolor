import QtQuick 2.6
import Sailfish.Silica 1.0
import Nemo.Configuration 1.0
import "../Translations.js" as T

Page {
    id: page
    allowedOrientations: Orientation.All

    readonly property var safePalette: [
        { name: "red",     hex: "ff0000" },
        { name: "green",   hex: "00ff00" },
        { name: "blue",    hex: "0000ff" },
        { name: "yellow",  hex: "ffff00" },
        { name: "cyan",    hex: "00ffff" },
        { name: "magenta", hex: "ff00ff" },
        { name: "white",   hex: "ffffff" }
    ]

    ConfigurationValue {
        id: languageConfig
        key: "/apps/harbour-ledcolor/language"
        defaultValue: "en"
    }
    property string lang: languageConfig.value

    function tr(key) { return T.tr(lang, key) }

    // dconf keys read by the user service - see
    // /usr/libexec/harbour-ledcolor/notifywatch.sh
    ConfigurationValue { id: callColorConfig;  key: "/apps/harbour-ledcolor/callColor";  defaultValue: "ff0000" }
    ConfigurationValue { id: smsColorConfig;   key: "/apps/harbour-ledcolor/smsColor";   defaultValue: "00ff00" }
    ConfigurationValue { id: emailColorConfig; key: "/apps/harbour-ledcolor/emailColor"; defaultValue: "ffff00" }
    ConfigurationValue { id: imColorConfig;    key: "/apps/harbour-ledcolor/imColor";    defaultValue: "0000ff" }

    // Free-form list of manually added apps: "name::hexcolor" lines.
    // Read by the notifywatch user service to match incoming
    // notifications, so both sides must parse it the same way.
    ConfigurationValue { id: customAppsConfig; key: "/apps/harbour-ledcolor/customApps"; defaultValue: "" }

    function parseCustomApps(raw) {
        var out = []
        if (!raw) return out
        var lines = raw.split("\n")
        for (var i = 0; i < lines.length; i++) {
            if (lines[i].length === 0) continue
            var sep = lines[i].indexOf("::")
            if (sep < 0) continue
            out.push({ name: lines[i].substring(0, sep), color: lines[i].substring(sep + 2) })
        }
        return out
    }
    function serializeCustomApps(list) {
        var lines = []
        for (var i = 0; i < list.length; i++) {
            lines.push(list[i].name + "::" + list[i].color)
        }
        return lines.join("\n")
    }
    property var customApps: parseCustomApps(customAppsConfig.value)

    function addCustomApp(name, hex) {
        var list = parseCustomApps(customAppsConfig.value)
        list.push({ name: name, color: hex })
        customAppsConfig.value = serializeCustomApps(list)
    }
    function updateCustomApp(idx, name, hex) {
        var list = parseCustomApps(customAppsConfig.value)
        if (idx >= 0 && idx < list.length) {
            list[idx] = { name: name, color: hex }
            customAppsConfig.value = serializeCustomApps(list)
        }
    }
    function removeCustomApp(idx) {
        var list = parseCustomApps(customAppsConfig.value)
        if (idx >= 0 && idx < list.length) {
            list.splice(idx, 1)
            customAppsConfig.value = serializeCustomApps(list)
        }
    }

    // Read by the user service (notifywatch.sh) every few seconds.
    // serviceEnabled=false puts the phone's stock LED behaviour back.
    ConfigurationValue { id: serviceEnabledConfig; key: "/apps/harbour-ledcolor/serviceEnabled"; defaultValue: true }
    ConfigurationValue { id: quietEnabledConfig;   key: "/apps/harbour-ledcolor/quietEnabled";   defaultValue: false }
    ConfigurationValue { id: quietStartConfig;     key: "/apps/harbour-ledcolor/quietStart";     defaultValue: "22:00" }
    ConfigurationValue { id: quietEndConfig;       key: "/apps/harbour-ledcolor/quietEnd";       defaultValue: "07:00" }
    ConfigurationValue { id: quietModeConfig;      key: "/apps/harbour-ledcolor/quietMode";      defaultValue: "defer" }
    ConfigurationValue { id: quietAllLedsConfig;   key: "/apps/harbour-ledcolor/quietAllLeds";   defaultValue: true }

    function pad2(n) { return (n < 10 ? "0" : "") + n }

    function openTimePicker(cfg) {
        var parts = String(cfg.value).split(":")
        var h = parseInt(parts[0], 10)
        var m = parseInt(parts[1], 10)
        var dialog = pageStack.push("Sailfish.Silica.TimePickerDialog", {
            hour: isNaN(h) ? 22 : h,
            minute: isNaN(m) ? 0 : m,
            hourMode: DateTime.TwentyFourHours
        })
        dialog.accepted.connect(function() {
            cfg.value = pad2(dialog.hour) + ":" + pad2(dialog.minute)
        })
    }

    function configFor(settingsKey) {
        switch (settingsKey) {
        case "callColor":  return callColorConfig
        case "smsColor":   return smsColorConfig
        case "emailColor": return emailColorConfig
        case "imColor":    return imColorConfig
        }
        return null
    }

    ListModel {
        id: systemEventModel
        ListElement { labelKey: "call";  settingsKey: "callColor" }
        ListElement { labelKey: "sms";   settingsKey: "smsColor" }
        ListElement { labelKey: "email"; settingsKey: "emailColor" }
        ListElement { labelKey: "other"; settingsKey: "imColor" }
    }

    function colorFor(settingsKey) {
        return "#" + configFor(settingsKey).value
    }

    function openPicker(labelKey, settingsKey) {
        var dialog = pageStack.push(Qt.resolvedUrl("ColorPickerPage.qml"), {
            currentHex: configFor(settingsKey).value,
            eventLabel: page.tr(labelKey),
            palette: safePalette,
            lang: page.lang
        })
        dialog.colorChosen.connect(function(hex) {
            configFor(settingsKey).value = hex
        })
    }

    function openAddApp() {
        var picker = pageStack.push(Qt.resolvedUrl("AppPickerDialog.qml"), { lang: page.lang })
        picker.appChosen.connect(function(name) {
            var dialog = pageStack.replace(Qt.resolvedUrl("ColorPickerPage.qml"), {
                currentHex: "00ffff",
                palette: safePalette,
                lang: page.lang,
                pickAppEnabled: true,
                appName: name
            })
            dialog.entrySaved.connect(function(finalName, hex) {
                addCustomApp(finalName, hex)
            })
        })
    }

    function openEditApp(idx, currentName, currentHex) {
        var dialog = pageStack.push(Qt.resolvedUrl("ColorPickerPage.qml"), {
            currentHex: currentHex,
            palette: safePalette,
            lang: page.lang,
            pickAppEnabled: true,
            appName: currentName
        })
        dialog.entrySaved.connect(function(name, hex) {
            updateCustomApp(idx, name, hex)
        })
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        PullDownMenu {
            MenuItem {
                text: page.tr("add_app_menu")
                onClicked: openAddApp()
            }
            MenuItem {
                text: page.tr("language_menu")
                onClicked: {
                    var p = pageStack.push(Qt.resolvedUrl("LanguagePage.qml"), { currentLanguage: page.lang })
                    p.languageChosen.connect(function(code) { languageConfig.value = code })
                }
            }
        }

        RemorsePopup { id: remorse }

        Column {
            id: column
            width: page.width

            PageHeader {
                title: page.tr("app_title")
            }

            TextSwitch {
                text: page.tr("manage_led")
                description: page.tr("manage_led_desc")
                automaticCheck: false
                checked: serviceEnabledConfig.value === true
                onClicked: serviceEnabledConfig.value = !checked
            }

            SectionHeader { text: page.tr("section_events") }

            Repeater {
                model: systemEventModel
                delegate: BackgroundItem {
                    width: page.width
                    height: Theme.itemSizeMedium

                    Rectangle {
                        id: swatch
                        anchors {
                            left: parent.left
                            leftMargin: Theme.horizontalPageMargin
                            verticalCenter: parent.verticalCenter
                        }
                        width: Theme.iconSizeMedium
                        height: width
                        radius: width / 2
                        color: colorFor(model.settingsKey)
                        border.color: Theme.primaryColor
                        border.width: 1
                    }

                    Label {
                        anchors {
                            left: swatch.right
                            leftMargin: Theme.paddingLarge
                            right: parent.right
                            rightMargin: Theme.horizontalPageMargin
                            verticalCenter: parent.verticalCenter
                        }
                        text: page.tr(model.labelKey)
                        truncationMode: TruncationMode.Fade
                    }

                    onClicked: openPicker(model.labelKey, model.settingsKey)
                }
            }

            SectionHeader {
                text: page.tr("apps_row")
                visible: page.customApps.length > 0
            }

            Repeater {
                model: page.customApps
                delegate: ListItem {
                    id: customItem
                    width: page.width
                    contentHeight: Theme.itemSizeMedium

                    menu: ContextMenu {
                        MenuItem {
                            text: page.tr("edit_menu")
                            onClicked: openEditApp(index, modelData.name, modelData.color)
                        }
                        MenuItem {
                            text: page.tr("delete_menu")
                            onClicked: remorse.execute(page.tr("delete_app_remorse"), function() {
                                removeCustomApp(index)
                            })
                        }
                    }

                    onClicked: openEditApp(index, modelData.name, modelData.color)

                    Rectangle {
                        id: customSwatch
                        anchors {
                            left: parent.left
                            leftMargin: Theme.horizontalPageMargin
                            verticalCenter: parent.verticalCenter
                        }
                        width: Theme.iconSizeMedium
                        height: width
                        radius: width / 2
                        color: "#" + modelData.color
                        border.color: Theme.primaryColor
                        border.width: 1
                    }

                    Label {
                        anchors {
                            left: customSwatch.right
                            leftMargin: Theme.paddingLarge
                            right: parent.right
                            rightMargin: Theme.horizontalPageMargin
                            verticalCenter: parent.verticalCenter
                        }
                        text: modelData.name
                        truncationMode: TruncationMode.Fade
                    }
                }
            }

            SectionHeader { text: page.tr("section_quiet") }

            TextSwitch {
                text: page.tr("quiet_enable")
                description: page.tr("quiet_enable_desc")
                automaticCheck: false
                checked: quietEnabledConfig.value === true
                onClicked: quietEnabledConfig.value = !checked
            }

            Column {
                width: parent.width
                visible: quietEnabledConfig.value === true

                ValueButton {
                    label: page.tr("quiet_start")
                    value: quietStartConfig.value
                    onClicked: openTimePicker(quietStartConfig)
                }

                ValueButton {
                    label: page.tr("quiet_end")
                    value: quietEndConfig.value
                    onClicked: openTimePicker(quietEndConfig)
                }

                ComboBox {
                    label: page.tr("quiet_mode")
                    description: quietModeConfig.value === "drop"
                        ? page.tr("quiet_mode_drop_desc")
                        : page.tr("quiet_mode_defer_desc")
                    currentIndex: quietModeConfig.value === "drop" ? 1 : 0
                    menu: ContextMenu {
                        MenuItem {
                            text: page.tr("quiet_mode_defer")
                            onClicked: quietModeConfig.value = "defer"
                        }
                        MenuItem {
                            text: page.tr("quiet_mode_drop")
                            onClicked: quietModeConfig.value = "drop"
                        }
                    }
                }

                TextSwitch {
                    text: page.tr("quiet_all_leds")
                    description: page.tr("quiet_all_leds_desc")
                    automaticCheck: false
                    checked: quietAllLedsConfig.value === true
                    onClicked: quietAllLedsConfig.value = !checked
                }
            }


            Item { width: 1; height: Theme.paddingLarge }
        }
    }
}
