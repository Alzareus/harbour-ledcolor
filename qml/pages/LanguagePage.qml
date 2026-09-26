import QtQuick 2.6
import Sailfish.Silica 1.0
import "../Translations.js" as T

Page {
    id: page
    property string currentLanguage: "en"
    signal languageChosen(string code)

    SilicaListView {
        anchors.fill: parent
        model: T.languageNames()
        header: PageHeader { title: T.tr(page.currentLanguage, "language_title") }
        delegate: BackgroundItem {
            width: page.width
            height: Theme.itemSizeMedium
            Label {
                anchors {
                    left: parent.left; leftMargin: Theme.horizontalPageMargin
                    verticalCenter: parent.verticalCenter
                }
                text: modelData.label
            }
            Icon {
                visible: modelData.code === page.currentLanguage
                anchors {
                    right: parent.right; rightMargin: Theme.horizontalPageMargin
                    verticalCenter: parent.verticalCenter
                }
                source: "image://theme/icon-m-accept"
            }
            onClicked: {
                languageChosen(modelData.code)
                pageStack.pop()
            }
        }
        VerticalScrollDecorator {}
    }
}
