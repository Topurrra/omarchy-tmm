import QtQuick
import qs.Commons

// Reading progress: a hairline divider that only fills in when there is a
// document to be a fraction of the way through. Used under the reader (and the
// ask answer, which is also a document).
Rectangle {
    id: rule

    property real progress: 0
    property bool active: false
    property color divider: Util.alpha(Color.foreground, 0.14)
    property color accent: Color.accent

    height: 1
    color: divider

    Rectangle {
        width: parent.width * (rule.active ? rule.progress : 0)
        height: parent.height
        color: rule.accent
        visible: rule.active
    }
}
