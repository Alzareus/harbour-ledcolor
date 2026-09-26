import QtQuick 2.6
import Sailfish.Silica 1.0
import Nemo.Configuration 1.0
import "../Translations.js" as T

Page {
    id: page
    property string lang: "en"

    // Navigation is entirely owned by whoever pushed this page - it
    // never pops or replaces itself, only reports the choice. This
    // avoids racing this page's own transition against the caller's
    // next push/replace.
    signal appChosen(string name)

    ConfigurationValue {
        id: installedAppsConfig
        key: "/apps/harbour-ledcolor/installedApps"
        defaultValue: ""
    }

    readonly property var appNames: {
        var raw = installedAppsConfig.value
        if (!raw || raw.length === 0) return []
        var parts = raw.split(";")
        var out = []
        for (var i = 0; i < parts.length; i++) {
            if (parts[i].length > 0) out.push(parts[i])
        }
        return out
    }

    SilicaListView {
        anchors.fill: parent
        header: PageHeader { title: T.tr(page.lang, "choose_app_placeholder") }
        model: appNames

        ViewPlaceholder {
            enabled: appNames.length === 0
            text: "..."
        }

        delegate: BackgroundItem {
            width: parent.width
            height: Theme.itemSizeSmall

            Label {
                anchors {
                    left: parent.left
                    leftMargin: Theme.horizontalPageMargin
                    right: parent.right
                    rightMargin: Theme.horizontalPageMargin
                    verticalCenter: parent.verticalCenter
                }
                text: modelData
                truncationMode: TruncationMode.Fade
            }

            onClicked: appChosen(modelData)
        }
        VerticalScrollDecorator {}
    }
}
