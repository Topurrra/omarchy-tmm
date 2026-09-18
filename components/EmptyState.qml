import QtQuick
import qs.Commons

// The empty / loading / welcome state. A blank panel is the least helpful
// thing a manual can show, so every one of these says what to do next. The
// welcome screen is the one state that is about identity rather than about
// what you are doing, so it gets the real logo; the rest get a glyph.
Item {
    id: empty

    property bool welcome: false
    property url logoSource
    property string glyph: ""
    property string title: ""
    property string hint: ""
    property color foreground: Color.foreground
    property color muted: Util.alpha(foreground, 0.6)
    property color accent: Color.accent
    property string fontFamily: Style.font.menuFamily

    Column {
        anchors.centerIn: parent
        width: parent.width * 0.8
        spacing: Style.space(10)

        Image {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: empty.welcome
            source: empty.logoSource
            width: Style.space(72)
            height: width
            sourceSize.width: 256
            sourceSize.height: 256
            smooth: true
            mipmap: true
            fillMode: Image.PreserveAspectFit
        }

        Text {
            width: parent.width
            visible: !empty.welcome
            horizontalAlignment: Text.AlignHCenter
            textFormat: Text.PlainText
            text: empty.glyph
            color: empty.accent
            opacity: 0.75
            font.family: empty.fontFamily
            font.pixelSize: Style.font.displayLarge
        }

        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
            text: empty.title
            color: empty.foreground
            opacity: 0.85
            font.family: empty.fontFamily
            font.pixelSize: Style.font.title
        }

        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
            text: empty.hint
            color: empty.muted
            font.family: empty.fontFamily
            font.pixelSize: Style.font.bodySmall
            lineHeight: 1.5
            lineHeightMode: Text.ProportionalHeight
        }
    }
}
