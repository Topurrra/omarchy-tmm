import QtQuick
import qs.Commons

// Keyboard-first result list, shared by search hits and the catalog.
//
// The cursor is a model index rather than Qt focus, which is what the rest
// of Omarchy does (menu, clipboard, emojis): typing always goes to the
// filter, and the mouse only moves the cursor instead of fighting it.
ListView {
    id: list

    property bool cursorActive: true
    property int cursorIndex: 0
    property color foreground: Color.menu.text
    property color mutedColor: Util.alpha(foreground, 0.6)
    property color selectedBackground: Color.menu.selectedBackground
    property color selectedText: Color.menu.selectedText
    property color accentColor: Color.accent
    property string fontFamily: Style.font.menuFamily
    // Catalog entries carry no summary, so they get a denser single-line row:
    // more of a 367-guide library fits on screen at once.
    property bool compact: false
    property int rowHeight: compact
        ? Math.max(Style.space(34), Style.font.subtitle + Style.spacing.rowPaddingX)
        : Math.max(Style.space(52),
            Style.font.subtitle + Style.font.caption + Style.spacing.rowPaddingX * 2)

    signal activated(int index)

    clip: true
    spacing: Style.space(3)
    boundsBehavior: Flickable.StopAtBounds
    highlightMoveDuration: 0
    currentIndex: cursorActive ? cursorIndex : -1

    function moveCursor(delta) {
        if (count === 0) return;
        if (!cursorActive) {
            cursorActive = true;
            cursorIndex = delta < 0 ? count - 1 : 0;
        } else {
            cursorIndex = (cursorIndex + delta + count) % count;
        }
        positionViewAtIndex(cursorIndex, ListView.Contain);
    }

    function movePage(delta) {
        if (count === 0) return;
        var rows = Math.max(1, Math.floor(height / (rowHeight + spacing)));
        cursorActive = true;
        cursorIndex = Math.min(count - 1, Math.max(0, cursorIndex + delta * rows));
        positionViewAtIndex(cursorIndex, ListView.Contain);
    }

    function moveToEdge(which) {
        if (count === 0) return;
        cursorActive = true;
        cursorIndex = which < 0 ? 0 : count - 1;
        positionViewAtIndex(cursorIndex, ListView.Contain);
    }

    function activateCursor() {
        if (cursorActive && cursorIndex >= 0 && cursorIndex < count) activated(cursorIndex);
    }

    delegate: Rectangle {
        id: row

        required property int index
        required property string title
        required property string summary
        required property string badge
        required property int phase_no

        readonly property bool hasCursor: list.cursorActive && index === list.cursorIndex

        width: ListView.view.width
        height: list.rowHeight
        radius: Style.cornerRadius
        color: hasCursor ? list.selectedBackground : "transparent"

        // Cursor marker. Omarchy's surfaces are flat, so the affordance is a
        // rule and a color shift rather than a shadow.
        Rectangle {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(1, Style.space(2))
            height: parent.height - Style.space(12)
            radius: width
            color: list.accentColor
            visible: row.hasCursor
        }

        // Sized to its content and vertically centred, so one-line and
        // two-line rows both sit correctly without branching on anchors.
        Item {
            id: rowBody
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: Style.space(14)
            anchors.rightMargin: Style.space(12)
            anchors.verticalCenter: parent.verticalCenter
            height: titleText.height + (summaryText.visible ? summaryText.height + Style.space(2) : 0)

            Text {
                id: badgeText
                anchors.right: parent.right
                anchors.verticalCenter: titleText.verticalCenter
                textFormat: Text.PlainText
                visible: row.badge.length > 0
                text: row.badge
                color: row.hasCursor ? list.accentColor : list.mutedColor
                font.family: list.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
                width: Math.min(implicitWidth, parent.width * 0.32)
                horizontalAlignment: Text.AlignRight
            }

            Text {
                id: titleText
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.right: badgeText.visible ? badgeText.left : parent.right
                anchors.rightMargin: badgeText.visible ? Style.space(10) : 0
                textFormat: Text.PlainText
                text: row.phase_no > 0 ? row.title + "  ·  phase " + row.phase_no : row.title
                color: row.hasCursor ? list.selectedText : list.foreground
                font.family: list.fontFamily
                font.pixelSize: Style.font.subtitle
                font.bold: row.hasCursor
                elide: Text.ElideRight
            }

            Text {
                id: summaryText
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: titleText.bottom
                anchors.topMargin: Style.space(2)
                textFormat: Text.PlainText
                visible: row.summary.length > 0
                text: row.summary
                color: list.mutedColor
                font.family: list.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
                maximumLineCount: 1
            }
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onContainsMouseChanged: if (containsMouse) {
                list.cursorActive = true;
                list.cursorIndex = row.index;
            }
            onClicked: {
                list.cursorActive = true;
                list.cursorIndex = row.index;
                list.activated(row.index);
            }
        }
    }
}
