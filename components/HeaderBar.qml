import QtQuick
import qs.Commons

// The panel's identity row: logo, the headline for the current mode, and a
// muted status on the right. Purely presentational — every colour and the
// font come in as props so it restyles with the window it sits in.
Item {
    id: header

    property url logoSource
    property string headline: ""
    // A placeholder headline ("Search the manual…") reads dimmer than a real
    // one, so the view says which it is.
    property bool placeholder: false
    property string status: ""
    property color foreground: Color.foreground
    property color muted: Util.alpha(foreground, 0.6)
    property string fontFamily: Style.font.menuFamily

    implicitHeight: Math.max(Style.space(38),
        Style.font.heading + Style.spacing.controlPaddingY * 2)

    Image {
        id: icon
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        source: header.logoSource
        width: Style.space(20)
        height: width
        sourceSize.width: 64
        sourceSize.height: 64
        smooth: true
        mipmap: true
        fillMode: Image.PreserveAspectFit
    }

    Text {
        id: statusText
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: header.status
        color: header.muted
        font.family: header.fontFamily
        font.pixelSize: Style.font.caption
    }

    Text {
        anchors.left: icon.right
        anchors.leftMargin: Style.space(10)
        anchors.right: statusText.left
        anchors.rightMargin: Style.space(12)
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: header.headline
        color: header.foreground
        opacity: header.placeholder ? 0.58 : 1
        font.family: header.fontFamily
        font.pixelSize: Style.font.heading
        elide: Text.ElideRight
    }
}
