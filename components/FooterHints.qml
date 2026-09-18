import QtQuick
import qs.Commons

// The footer key-hint line. One faint row that tells you which keys do what
// in the current mode; the view computes the text.
Item {
    id: footer

    property string text: ""
    property color foreground: Color.foreground
    property string fontFamily: Style.font.menuFamily

    implicitHeight: Math.max(Style.space(22),
        Style.font.caption + Style.spacing.controlPaddingY)

    Text {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: footer.text
        color: Util.alpha(footer.foreground, 0.45)
        font.family: footer.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
    }
}
