import QtQuick
import Quickshell
import qs.Commons
import "Markdown.js" as Markdown

// Block-rendered markdown view for one phase.
//
// Phase bodies are parsed into typed blocks (Markdown.js) and drawn as real
// QML: headings with a scale, code in copyable cards, quotes with a rule,
// tables as a grid. Everything reads its color from the active Omarchy
// theme, so the reader repaints when the user switches themes.
Flickable {
    id: reader

    property string markdown: ""
    property color foreground: Color.menu.text
    property color accentColor: Color.accent
    property color mutedColor: Util.alpha(foreground, 0.62)
    property string fontFamily: Style.font.menuFamily
    property int bodySize: Style.font.subtitle
    // Reading column: long lines are the fastest way to make a reader tiring,
    // so the text stops well short of a wide card.
    property int columnWidth: Math.min(width, Style.space(760))
    property string copiedText: ""

    readonly property var blocks: Markdown.parseBlocks(markdown)
    readonly property real progress: contentHeight > height
        ? Math.min(1, Math.max(0, contentY / (contentHeight - height)))
        : (markdown ? 1 : 0)

    signal linkActivated(string url)

    clip: true
    contentWidth: width
    contentHeight: column.height + Style.space(28)
    boundsBehavior: Flickable.StopAtBounds
    flickDeceleration: 4000
    maximumFlickVelocity: 3800

    function scrollBy(delta) {
        var max = Math.max(0, contentHeight - height);
        contentY = Math.min(max, Math.max(0, contentY + delta));
    }
    function scrollPage(direction) { scrollBy(direction * height * 0.85); }
    function toTop() { contentY = 0; }
    function toBottom() { contentY = Math.max(0, contentHeight - height); }

    function copy(text) {
        if (!text) return;
        Quickshell.execDetached(["wl-copy", "--", text]);
        reader.copiedText = text;
        copiedReset.restart();
    }

    Timer { id: copiedReset; interval: 1400; onTriggered: reader.copiedText = "" }

    onMarkdownChanged: contentY = 0

    Column {
        id: column
        // Left-aligned rather than centred: the header, notice and footer all
        // share the card's left rail, and an inset text column reads as a
        // mistake next to them.
        x: 0
        width: reader.columnWidth
        spacing: 0

        Repeater {
            model: reader.blocks

            Loader {
                required property var modelData
                required property int index

                readonly property var blk: modelData
                readonly property bool firstBlock: index === 0

                width: column.width
                height: item ? item.implicitHeight : 0
                sourceComponent: blk.type === "heading" ? headingBlock
                    : blk.type === "code" ? codeBlock
                    : blk.type === "bullet" ? bulletBlock
                    : blk.type === "quote" ? quoteBlock
                    : blk.type === "rule" ? ruleBlock
                    : blk.type === "table" ? tableBlock
                    : paraBlock
            }
        }
    }

    // --------------------------------------------------------- block types

    Component {
        id: headingBlock
        Item {
            implicitHeight: label.implicitHeight + topGap + Style.space(6)
            readonly property int topGap: firstBlock ? 0 : (blk.level <= 2 ? Style.space(22) : Style.space(14))

            Text {
                id: label
                y: parent.topGap
                width: parent.width
                textFormat: Text.RichText
                text: Markdown.inline(blk.text, { code: reader.accentColor, link: reader.accentColor })
                color: blk.level <= 2 ? reader.accentColor : reader.foreground
                font.family: reader.fontFamily
                font.bold: true
                font.pixelSize: blk.level === 1 ? Style.font.heading
                    : blk.level === 2 ? Style.font.title
                    : Style.font.subtitle
                wrapMode: Text.WordWrap
            }
        }
    }

    Component {
        id: paraBlock
        Item {
            implicitHeight: body.implicitHeight + Style.space(10)
            Text {
                id: body
                width: parent.width
                textFormat: Text.RichText
                text: Markdown.inline(blk.text, { code: reader.accentColor, link: reader.accentColor })
                color: reader.foreground
                font.family: reader.fontFamily
                font.pixelSize: reader.bodySize
                lineHeight: 1.45
                lineHeightMode: Text.ProportionalHeight
                wrapMode: Text.WordWrap
                onLinkActivated: url => reader.linkActivated(url)

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.NoButton
                    cursorShape: body.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor
                }
            }
        }
    }

    Component {
        id: bulletBlock
        Item {
            implicitHeight: Math.max(marker.implicitHeight, text.implicitHeight) + Style.space(4)
            readonly property int indent: Style.space(10) + blk.depth * Style.space(16)

            Text {
                id: marker
                x: parent.indent
                width: Style.space(18)
                text: blk.marker
                color: reader.accentColor
                font.family: reader.fontFamily
                font.pixelSize: reader.bodySize
                lineHeight: 1.45
                lineHeightMode: Text.ProportionalHeight
            }
            Text {
                id: text
                x: parent.indent + Style.space(18)
                width: parent.width - x
                textFormat: Text.RichText
                text: Markdown.inline(blk.text, { code: reader.accentColor, link: reader.accentColor })
                color: reader.foreground
                font.family: reader.fontFamily
                font.pixelSize: reader.bodySize
                lineHeight: 1.45
                lineHeightMode: Text.ProportionalHeight
                wrapMode: Text.WordWrap
                onLinkActivated: url => reader.linkActivated(url)
            }
        }
    }

    Component {
        id: quoteBlock
        Item {
            implicitHeight: quoteText.implicitHeight + Style.space(18)

            Rectangle {
                x: 0
                y: Style.space(4)
                width: Math.max(1, Style.space(2))
                height: quoteText.implicitHeight
                color: reader.accentColor
                opacity: 0.7
            }
            Text {
                id: quoteText
                x: Style.space(14)
                y: Style.space(4)
                width: parent.width - x
                textFormat: Text.RichText
                text: Markdown.inline(blk.text, { code: reader.accentColor, link: reader.accentColor })
                color: reader.mutedColor
                font.family: reader.fontFamily
                font.pixelSize: reader.bodySize
                font.italic: true
                lineHeight: 1.45
                lineHeightMode: Text.ProportionalHeight
                wrapMode: Text.WordWrap
            }
        }
    }

    Component {
        id: ruleBlock
        Item {
            implicitHeight: Style.space(26)
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                height: 1
                color: Util.alpha(reader.foreground, 0.16)
            }
        }
    }

    // Code is the payload of a technical guide, so it gets a real card:
    // bordered, hover-lit, and click-to-copy with an inline confirmation.
    Component {
        id: codeBlock
        Item {
            id: codeRoot
            implicitHeight: card.height + Style.space(14)
            readonly property bool copied: reader.copiedText === blk.text
            readonly property int labelHeight: blk.lang.length > 0 ? langLabel.implicitHeight : 0

            Rectangle {
                id: card
                width: parent.width
                height: codeText.implicitHeight + Style.space(20) + codeRoot.labelHeight
                radius: Style.cornerRadius
                color: Util.alpha(reader.foreground, 0.05)
                border.width: 1
                border.color: Util.alpha(reader.foreground, hover.containsMouse ? 0.22 : 0.12)

                Text {
                    id: langLabel
                    visible: blk.lang.length > 0 || hover.containsMouse || codeRoot.copied
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.topMargin: Style.space(6)
                    anchors.rightMargin: Style.space(10)
                    textFormat: Text.PlainText
                    text: codeRoot.copied ? "copied"
                        : hover.containsMouse ? (blk.lang ? blk.lang + "  ·  click to copy" : "click to copy")
                        : blk.lang
                    color: codeRoot.copied ? reader.accentColor : reader.mutedColor
                    font.family: reader.fontFamily
                    font.pixelSize: Style.font.caption
                }

                // Long lines wrap rather than scroll horizontally: a command
                // you cannot see in full is worse than one that folds, and
                // click-to-copy always yields the original text.
                Text {
                    id: codeText
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.topMargin: Style.space(10) + codeRoot.labelHeight
                    anchors.leftMargin: Style.space(12)
                    anchors.rightMargin: Style.space(12)
                    text: blk.text
                    textFormat: Text.PlainText
                    color: reader.foreground
                    font.family: reader.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    lineHeight: 1.4
                    lineHeightMode: Text.ProportionalHeight
                    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                }

                MouseArea {
                    id: hover
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: reader.copy(blk.text)
                }
            }
        }
    }

    Component {
        id: tableBlock
        Item {
            id: tableRoot
            implicitHeight: grid.height + Style.space(18)
            readonly property int columnCount: Math.max(1, blk.header.length)
            readonly property real cellWidth: width / columnCount

            Column {
                id: grid
                width: parent.width
                spacing: 0

                Row {
                    width: parent.width
                    Repeater {
                        model: blk.header
                        Text {
                            required property var modelData
                            width: tableRoot.cellWidth
                            padding: Style.space(6)
                            textFormat: Text.RichText
                            text: Markdown.inline(modelData, { code: reader.accentColor, link: reader.accentColor })
                            color: reader.accentColor
                            font.family: reader.fontFamily
                            font.pixelSize: Style.font.bodySmall
                            font.bold: true
                            wrapMode: Text.WordWrap
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 1
                    color: Util.alpha(reader.foreground, 0.2)
                }

                // Each row is an Item so the zebra stripe can sit behind the
                // cells; a Rectangle inside the Row would become a cell.
                Repeater {
                    model: blk.rows

                    Item {
                        id: rowItem
                        required property var modelData
                        required property int index

                        width: grid.width
                        height: cells.height

                        Rectangle {
                            anchors.fill: parent
                            color: rowItem.index % 2 === 1 ? Util.alpha(reader.foreground, 0.04) : "transparent"
                        }

                        Row {
                            id: cells
                            width: parent.width
                            Repeater {
                                model: rowItem.modelData
                                Text {
                                    required property var modelData
                                    width: tableRoot.cellWidth
                                    padding: Style.space(6)
                                    textFormat: Text.RichText
                                    text: Markdown.inline(modelData, { code: reader.accentColor, link: reader.accentColor })
                                    color: reader.foreground
                                    font.family: reader.fontFamily
                                    font.pixelSize: Style.font.bodySmall
                                    wrapMode: Text.WordWrap
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
