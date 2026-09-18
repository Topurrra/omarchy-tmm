import QtQuick
import qs.Commons

// "Did you mean" and errors share one slim line so the layout never jumps
// between states. It collapses to zero height when there is nothing to say,
// which is why the view anchors things to its bottom rather than stacking it
// in a Column that would keep its spacing.
Item {
    id: notice

    property string errorMsg: ""
    property string statusMsg: ""
    property string suggestion: ""
    // The suggestion is only offered in search mode; the view decides when.
    property bool canSuggest: false
    // The view can force the line closed — e.g. when the whole left column it
    // lives in is tucked away in wide-mode reading.
    property bool gate: true
    property color muted: Color.foreground
    property color accent: Color.accent
    property color urgent: Color.urgent
    property string fontFamily: Style.font.menuFamily

    signal suggestionClicked()

    readonly property bool showSuggestion: canSuggest && suggestion.length > 0
        && errorMsg.length === 0 && statusMsg.length === 0

    visible: gate && (errorMsg.length > 0 || statusMsg.length > 0 || showSuggestion)
    height: visible ? noticeText.implicitHeight + Style.spacing.md * 2 : 0

    Text {
        id: noticeText
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: notice.errorMsg ? notice.errorMsg
            : notice.statusMsg ? notice.statusMsg
            : "Did you mean “" + notice.suggestion + "”?  Press ⇧⏎"
        // A status line is not a failure and not an offer: it says what just
        // happened and gets out of the way.
        color: notice.errorMsg ? notice.urgent
            : notice.statusMsg ? notice.muted : notice.accent
        font.family: notice.fontFamily
        font.pixelSize: Style.font.bodySmall
        elide: Text.ElideRight
    }

    MouseArea {
        anchors.fill: parent
        enabled: notice.showSuggestion
        cursorShape: Qt.PointingHandCursor
        onClicked: notice.suggestionClicked()
    }
}
