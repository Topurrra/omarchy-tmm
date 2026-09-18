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
    // Which palette the code-block highlighter should use -- true for a
    // dark card background, false for light. Panel sets this from the
    // active theme; defaults dark since that's the common case.
    property bool codeDark: true
    // Normally the column hugs the left rail so it lines up with the header and
    // footer. When the reader has the whole window to itself (the sidebar is
    // folded away), that leaves a wide empty margin on the right, so the view
    // centres the column instead for a more comfortable read.
    property bool centered: false
    // Reading column: long lines are the fastest way to make a reader tiring,
    // so the text stops well short of a wide card. Centred (full-window) mode
    // additionally keeps a gutter on each side so the column never runs edge to
    // edge, which is the whole point of centring it.
    property int columnWidth: centered
        ? Math.max(Style.space(360),
              Math.min(Style.space(760), width - Style.space(180)))
        : Math.min(width, Style.space(760))
    property string copiedText: ""
    // [{path, w, h}] from Service.getDiagrams, in the same order as the
    // `diagram` blocks. Empty until they arrive, or if they never do.
    property var diagrams: []

    readonly property var blocks: Markdown.parseBlocks(markdown)

    // ------------------------------------------------------------- quiz
    //
    // Answers live here rather than on the block objects: `blocks` is a
    // readonly binding recomputed only when `markdown` changes, so mutating a
    // question in place emits no change signal and the delegate never
    // repaints. Every mutation reassigns the whole array.
    property var quizAnswers: []
    property int quizCursor: 0
    property bool quizActive: false

    signal quizAnswered(int index, int choice, bool correct)
    signal quizCleared()

    // A phase carries at most one quiz block (true of all 954 in the corpus).
    readonly property var quizQuestions: {
        for (var i = 0; i < blocks.length; i++)
            if (blocks[i].type === "quiz") return blocks[i].questions;
        return [];
    }
    readonly property int quizCount: quizQuestions.length
    readonly property int quizDone: {
        var n = 0;
        for (var i = 0; i < quizCount; i++) {
            var v = quizAnswers[i];
            if (v !== null && v !== undefined) n++;
        }
        return n;
    }
    readonly property int quizScore: {
        var n = 0;
        for (var i = 0; i < quizCount; i++)
            if (quizAnswers[i] === quizQuestions[i].answer) n++;
        return n;
    }
    readonly property bool quizComplete: quizCount > 0 && quizDone === quizCount

    function quizChosen(qi) {
        var v = quizAnswers[qi];
        return (v === null || v === undefined) ? -1 : v;
    }

    function answerQuiz(qi, ci) {
        var qs = quizQuestions;
        if (qi < 0 || qi >= qs.length) return;
        if (ci < 0 || ci >= qs[qi].choices.length) return;
        if (quizChosen(qi) >= 0) return;            // locks on first answer

        var next = quizAnswers.slice();
        while (next.length < qs.length) next.push(null);
        next[qi] = ci;
        quizAnswers = next;
        reader.quizAnswered(qi, ci, ci === qs[qi].answer);

        for (var n = qi + 1; n < qs.length; n++) {
            if (next[n] === null || next[n] === undefined) { quizCursor = n; return; }
        }
    }

    function quizStartOver() {
        quizAnswers = [];
        quizCursor = 0;
        reader.quizCleared();
    }

    // Keeps what you got right and re-asks only what you missed, like the site.
    function quizRetryMissed() {
        var qs = quizQuestions, next = quizAnswers.slice(), first = -1;
        for (var i = 0; i < qs.length; i++) {
            if (next[i] !== qs[i].answer) { next[i] = null; if (first < 0) first = i; }
        }
        quizAnswers = next;
        if (first >= 0) quizCursor = first;
        reader.quizCleared();
    }

    function quizMove(delta) {
        if (quizCount === 0) return;
        quizCursor = Math.min(quizCount - 1, Math.max(0, quizCursor + delta));
    }
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
        // Normally left-aligned so it shares the card's left rail with the
        // header, notice and footer; centred only when the reader owns the full
        // window (sidebar folded away) and a left rail would strand the right.
        x: reader.centered ? Math.max(0, (reader.width - reader.columnWidth) / 2) : 0
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
                    : blk.type === "quiz" ? quizBlock
                    : blk.type === "diagram" ? diagramBlock
                    : blk.type === "embed" ? embedCard
                    : blk.type === "lesson" ? lessonBlock
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

    // The quiz mirrors the website's Quiz.svelte so the same phase behaves the
    // same way on the desktop: a choice locks on first answer, the correct row
    // is marked, and a wrong choice with its own `why` entry gets that specific
    // diagnosis instead of the generic explanation.
    Component {
        id: quizBlock
        Item {
            id: quizRoot
            implicitHeight: card.height + Style.space(22)

            Rectangle {
                id: card
                width: parent.width
                y: Style.space(12)
                height: body.implicitHeight + Style.space(26)
                radius: Style.cornerRadius
                color: Util.alpha(reader.foreground, 0.05)
                border.width: 1
                border.color: reader.quizActive ? Util.alpha(reader.accentColor, 0.55)
                                                : Util.alpha(reader.foreground, 0.14)

                Column {
                    id: body
                    x: Style.space(14)
                    y: Style.space(13)
                    width: parent.width - Style.space(28)
                    spacing: Style.space(14)

                    Item {
                        width: parent.width
                        height: title.implicitHeight
                        Text {
                            id: title
                            text: "Check your understanding"
                            color: reader.accentColor
                            font.family: reader.fontFamily
                            font.pixelSize: Style.font.subtitle
                            font.bold: true
                        }
                        Text {
                            anchors.right: parent.right
                            anchors.baseline: title.baseline
                            text: reader.quizComplete
                                ? reader.quizScore + " / " + reader.quizCount
                                : reader.quizCount + (reader.quizCount === 1 ? " question" : " questions")
                            color: reader.mutedColor
                            font.family: reader.fontFamily
                            font.pixelSize: Style.font.caption
                        }
                    }

                    Repeater {
                        model: blk.questions

                        Item {
                            id: qItem
                            required property var modelData
                            required property int index

                            readonly property int chosen: reader.quizChosen(index)
                            readonly property bool answered: chosen >= 0
                            readonly property bool focused: reader.quizActive && reader.quizCursor === index

                            width: body.width
                            height: qCol.implicitHeight

                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: -Style.space(6)
                                radius: Style.cornerRadius
                                color: qItem.focused ? Util.alpha(reader.accentColor, 0.07) : "transparent"
                            }

                            Column {
                                id: qCol
                                width: parent.width
                                spacing: Style.space(6)

                                Text {
                                    width: parent.width
                                    textFormat: Text.RichText
                                    text: (qItem.index + 1) + ". " + Markdown.inline(qItem.modelData.q,
                                        { code: reader.accentColor, link: reader.accentColor })
                                    color: reader.foreground
                                    font.family: reader.fontFamily
                                    font.pixelSize: reader.bodySize
                                    font.bold: true
                                    wrapMode: Text.WordWrap
                                    lineHeight: 1.4
                                    lineHeightMode: Text.ProportionalHeight
                                }

                                Repeater {
                                    model: qItem.modelData.choices

                                    Item {
                                        id: choiceRow
                                        required property var modelData
                                        required property int index

                                        readonly property bool isAnswer: qItem.modelData.answer === index
                                        readonly property bool isChosen: qItem.chosen === index
                                        readonly property bool showRight: qItem.answered && isAnswer
                                        readonly property bool showWrong: qItem.answered && isChosen && !isAnswer

                                        width: qCol.width
                                        height: choiceText.implicitHeight + Style.space(9)

                                        Rectangle {
                                            anchors.fill: parent
                                            anchors.rightMargin: Style.space(2)
                                            radius: Style.cornerRadius
                                            color: choiceRow.showRight ? Util.alpha(reader.accentColor, 0.16)
                                                 : choiceRow.showWrong ? Util.alpha(Color.urgent, 0.16)
                                                 : hover.containsMouse && !qItem.answered
                                                     ? Util.alpha(reader.foreground, 0.06)
                                                     : "transparent"
                                        }

                                        Text {
                                            id: mark
                                            x: Style.space(8)
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: Style.space(18)
                                            textFormat: Text.PlainText
                                            text: choiceRow.showRight ? "\u2713"
                                                : choiceRow.showWrong ? "\u2717"
                                                : String.fromCharCode(65 + choiceRow.index)
                                            color: choiceRow.showRight ? reader.accentColor
                                                 : choiceRow.showWrong ? Color.urgent
                                                 : reader.mutedColor
                                            font.family: reader.fontFamily
                                            font.pixelSize: Style.font.bodySmall
                                            font.bold: choiceRow.showRight || choiceRow.showWrong
                                        }

                                        Text {
                                            id: choiceText
                                            x: Style.space(28)
                                            y: Style.space(4)
                                            width: parent.width - x - Style.space(8)
                                            textFormat: Text.RichText
                                            text: Markdown.inline(choiceRow.modelData,
                                                { code: reader.accentColor, link: reader.accentColor })
                                            color: qItem.answered && !choiceRow.showRight && !choiceRow.showWrong
                                                ? reader.mutedColor : reader.foreground
                                            font.family: reader.fontFamily
                                            font.pixelSize: reader.bodySize
                                            wrapMode: Text.WordWrap
                                        }

                                        MouseArea {
                                            id: hover
                                            anchors.fill: parent
                                            hoverEnabled: !qItem.answered
                                            cursorShape: qItem.answered ? Qt.ArrowCursor : Qt.PointingHandCursor
                                            onClicked: {
                                                reader.quizActive = true;
                                                reader.quizCursor = qItem.index;
                                                reader.answerQuiz(qItem.index, choiceRow.index);
                                            }
                                        }
                                    }
                                }

                                Text {
                                    width: parent.width
                                    visible: qItem.answered && text.length > 0
                                    topPadding: Style.space(4)
                                    textFormat: Text.RichText
                                    // `why[chosen]` is the per-distractor diagnosis; it beats the
                                    // generic explanation when the reader picked that option.
                                    text: {
                                        if (!qItem.answered) return "";
                                        var q = qItem.modelData, right = qItem.chosen === q.answer;
                                        var reason = (!right && q.why && q.why[qItem.chosen]) || q.explain || "";
                                        if (!reason) return "";
                                        return (right ? "Correct. " : "Not quite. ")
                                            + Markdown.inline(reason,
                                                { code: reader.accentColor, link: reader.accentColor });
                                    }
                                    color: qItem.chosen === qItem.modelData.answer
                                        ? reader.accentColor : reader.mutedColor
                                    font.family: reader.fontFamily
                                    font.pixelSize: Style.font.bodySmall
                                    wrapMode: Text.WordWrap
                                    lineHeight: 1.4
                                    lineHeightMode: Text.ProportionalHeight
                                }
                            }
                        }
                    }

                    Item {
                        width: parent.width
                        visible: reader.quizComplete
                        height: visible ? summary.implicitHeight : 0

                        Text {
                            id: summary
                            textFormat: Text.PlainText
                            text: "You got " + reader.quizScore + " of " + reader.quizCount + "."
                                + (reader.quizScore === reader.quizCount ? "  \u2713" : "")
                            color: reader.quizScore === reader.quizCount ? reader.accentColor : reader.foreground
                            font.family: reader.fontFamily
                            font.pixelSize: Style.font.bodySmall
                            font.bold: true
                        }
                        Text {
                            anchors.right: parent.right
                            anchors.baseline: summary.baseline
                            textFormat: Text.PlainText
                            text: reader.quizScore === reader.quizCount
                                ? "r start over"
                                : "m retry the " + (reader.quizCount - reader.quizScore) + " you missed  \u00b7  r start over"
                            color: reader.mutedColor
                            font.family: reader.fontFamily
                            font.pixelSize: Style.font.caption
                        }
                    }
                }
            }
        }
    }

    // A baked, recoloured diagram. Falls back to the plain card whenever the
    // SVG is not there yet, could not be fetched, or Qt cannot draw it -- the
    // one thing it never does is print the mermaid source.
    Component {
        id: diagramBlock
        Item {
            id: diagramRoot
            implicitHeight: shown ? image.height + Style.space(18)
                                  : fallback.implicitHeight

            // `blk` reaches us through the delegate Loader's context object, so a
            // nested Loader cannot see it -- hand it down explicitly.
            readonly property var blkRef: blk
            readonly property var info: reader.diagrams[blk.ord] || null
            readonly property bool shown: info !== null && image.status === Image.Ready
            // Size from the viewBox: QSvgRenderer's own defaultSize is not
            // reliable across the three root shapes the engine emits.
            readonly property real ratio: (info && info.w > 0 && info.h > 0)
                ? info.h / info.w : 0.5

            Image {
                id: image
                visible: diagramRoot.shown
                y: Style.space(9)
                width: parent.width
                height: Math.round(parent.width * diagramRoot.ratio)
                source: diagramRoot.info ? "file://" + diagramRoot.info.path : ""
                sourceSize.width: Math.round(parent.width * 2)   // crisp on HiDPI
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                smooth: true
            }

            Loader {
                id: fallback
                property var blk: diagramRoot.blkRef
                width: parent.width
                active: !diagramRoot.shown
                sourceComponent: embedCard
            }
        }
    }

    // Diagrams and browser-only widgets. Never the raw source: a wall of
    // mermaid DSL or widget JSON is worse than a line saying what it is.
    // Used directly for `embed` blocks and as diagramBlock's fallback, so it
    // reads `blk` from whichever Loader instantiates it.
    Component {
        id: embedCard
        Item {
            id: embedRoot
            implicitHeight: card.height + Style.space(14)
            readonly property bool isDiagram: blk.type === "diagram"

            Rectangle {
                id: card
                width: parent.width
                height: embedLabel.implicitHeight + Style.space(20)
                radius: Style.cornerRadius
                color: Util.alpha(reader.foreground, 0.04)
                border.width: 1
                border.color: Util.alpha(reader.foreground, embedHover.containsMouse ? 0.22 : 0.12)

                Text {
                    id: embedLabel
                    anchors.left: parent.left
                    anchors.leftMargin: Style.space(12)
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - Style.space(24)
                    textFormat: Text.PlainText
                    text: (embedRoot.isDiagram ? "\u25ce  Diagram" : "\u25a3  Interactive")
                        + "  \u00b7  " + blk.kind
                        + (embedHover.containsMouse ? "   \u2014 press o to open it on the web" : "")
                    color: reader.mutedColor
                    font.family: reader.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    elide: Text.ElideRight
                }

                MouseArea {
                    id: embedHover
                    anchors.fill: parent
                    hoverEnabled: true
                }
            }
        }
    }

    // Practice exercises: the task and its starter code, with the hints behind
    // a count. Deliberately not an editor -- paste it into a real shell.
    Component {
        id: lessonBlock
        Item {
            id: lessonRoot
            implicitHeight: lessonCard.height + Style.space(14)
            readonly property int hintCount: (blk.lesson.hints && blk.lesson.hints.length) || 0

            Rectangle {
                id: lessonCard
                width: parent.width
                height: lessonCol.implicitHeight + Style.space(22)
                radius: Style.cornerRadius
                color: Util.alpha(reader.foreground, 0.05)
                border.width: 1
                border.color: Util.alpha(reader.foreground, 0.14)

                Column {
                    id: lessonCol
                    x: Style.space(12)
                    y: Style.space(11)
                    width: parent.width - Style.space(24)
                    spacing: Style.space(8)

                    Text {
                        textFormat: Text.PlainText
                        text: "Exercise  \u00b7  " + (blk.lesson.language || blk.lang)
                        color: reader.accentColor
                        font.family: reader.fontFamily
                        font.pixelSize: Style.font.caption
                        font.bold: true
                    }
                    Text {
                        width: parent.width
                        visible: String(blk.lesson.starterCode || "").length > 0
                        textFormat: Text.PlainText
                        text: blk.lesson.starterCode || ""
                        color: reader.foreground
                        font.family: reader.fontFamily
                        font.pixelSize: Style.font.bodySmall
                        wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                    }
                    Text {
                        textFormat: Text.PlainText
                        text: (lessonRoot.hintCount > 0
                                ? lessonRoot.hintCount + (lessonRoot.hintCount === 1 ? " hint" : " hints")
                                : "No hints")
                            + "  \u00b7  press o for the full exercise"
                        color: reader.mutedColor
                        font.family: reader.fontFamily
                        font.pixelSize: Style.font.caption
                    }
                }

                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                    onClicked: reader.copy(blk.lesson.starterCode || "") }
            }
        }
    }

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
                    text: Markdown.highlightCode(blk.text, blk.lang, reader.codeDark)
                    textFormat: Text.RichText
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
