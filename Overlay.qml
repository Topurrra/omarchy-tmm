import QtQuick
import QtQuick.Controls
import Quickshell

// tmm.manual overlay - fullscreen reader (SEARCH / READER / CATALOG)
Item {
    id: root
    anchors.fill: parent
    visible: false
    focus: visible

    // injected by Omarchy host when available
    property var shell
    property var manifest
    property var pluginRegistry
    property var service

    // standalone fallback (sibling Service.qml)
    Service { id: tmmService }

    property string mode: "search" // search | reader | catalog
    property string currentSlug: ""
    property int currentPhase: 1
    property string guideTitle: ""
    property string phaseBody: ""
    property string suggestion: ""
    property string statusMsg: ""

    ListModel { id: resultsModel }
    ListModel { id: catalogModel }

    function svc() {
        if (typeof service !== "undefined" && service) return service;
        return tmmService;
    }
    function safeCall(fn) {
        var s = svc();
        if (!s || typeof s[fn] === "undefined") {
            statusMsg = "Service unavailable: " + fn;
            return null;
        }
        return s;
    }

    function open(payloadJson) {
        visible = true;
        mode = "search";
        forceActiveFocus();
        var q = "", slug = "", phase = 0;
        if (payloadJson) {
            try {
                var p = typeof payloadJson === "string" ? JSON.parse(payloadJson) : payloadJson;
                q = p.query || p.q || "";
                slug = p.slug || p.guide_slug || "";
                phase = p.phase || p.phase_no || 0;
            } catch (e) { statusMsg = "Bad payload"; }
        }
        if (slug && phase) {
            var s = safeCall("getPhase");
            if (s) s.getPhase(slug, phase);
        } else if (q) {
            searchField.text = q;
            doSearch(q);
        } else {
            searchField.text = "";
            searchField.forceActiveFocus();
        }
    }
    function close() { visible = false; }

    function doSearch(query) {
        var s = safeCall("search");
        if (!s) return;
        statusMsg = "Searching...";
        suggestion = "";
        s.search(query);
    }
    function openHit(slug, phaseNo, title) {
        currentSlug = slug; currentPhase = phaseNo;
        if (title) guideTitle = title;
        mode = "reader"; statusMsg = "Loading " + slug + " #" + phaseNo;
        var s = safeCall("getPhase");
        if (s) s.getPhase(slug, phaseNo);
    }
    function prevPhase() { if (mode === "reader" && currentPhase > 1) svc().getPhase(currentSlug, currentPhase - 1); }
    function nextPhase() { if (mode === "reader") svc().getPhase(currentSlug, currentPhase + 1); }
    function showCatalog() {
        mode = "catalog"; statusMsg = "Loading catalog...";
        var s = safeCall("getCatalog");
        if (s) s.getCatalog();
    }
    function pickRandom() {
        if (resultsModel.count === 0) { doSearch(searchField.text || "guide"); return; }
        var i = Math.floor(Math.random() * resultsModel.count);
        var h = resultsModel.get(i);
        openHit(h.guide_slug, h.phase_no, h.title);
    }
    function openCheatSheet() {
        searchField.text = "cheatsheet";
        mode = "search";
        doSearch("cheatsheet");
    }
    function stripFrontmatter(md) {
        if (!md) return "";
        if (md.slice(0, 3) !== "---") return md;
        var end = md.indexOf("---", 3);
        if (end < 0) return md;
        return md.slice(end + 3).replace(/^\s+/, "");
    }
    function focusSearch() { mode = "search"; searchField.forceActiveFocus(); searchField.selectAll(); }

    Connections {
        target: (typeof service !== "undefined" && service) ? service : tmmService
        function onSearchDone(results, suggest) {
            resultsModel.clear();
            var list = Array.isArray(results) ? results : (results && results.hits) || [];
            for (var i = 0; i < list.length; ++i) {
                var h = list[i];
                resultsModel.append({
                    "title": h.title || h.guide_title || h.slug || "Untitled",
                    "summary": h.summary || h.description || "",
                    "snippet": h.snippet || h.excerpt || "",
                    "guide_slug": h.guide_slug || h.slug || "",
                    "phase_no": h.phase_no || h.phase || 1
                });
            }
            root.suggestion = suggest || (results && results.suggestion) || "";
            root.statusMsg = list.length + " result(s)";
            root.mode = "search";
        }
        function onPhaseDone(slug, phase, markdown) {
            root.currentSlug = slug; root.currentPhase = phase;
            root.phaseBody = root.stripFrontmatter(markdown);
            root.mode = "reader"; root.statusMsg = slug + " phase " + phase;
        }
        function onCatalogDone(catalog) {
            catalogModel.clear();
            var list = Array.isArray(catalog) ? catalog : (catalog && (catalog.categories || catalog.guides)) || [];
            for (var i = 0; i < list.length; ++i) {
                var c = list[i];
                catalogModel.append({
                    "title": c.title || c.name || c.slug || "Untitled",
                    "summary": c.summary || c.description || "",
                    "guide_slug": c.slug || c.guide_slug || "",
                    "phase_no": 1
                });
            }
            root.mode = "catalog"; root.statusMsg = list.length + " entr(ies)";
        }
        function onError(msg) { root.statusMsg = msg; }
    }

    Keys.onPressed: (event) => {
        var inField = searchField.activeFocus;
        if (event.key === Qt.Key_Escape) { root.close(); event.accepted = true; return; }
        if (inField) return;
        var t = event.text || "";
        if (t === "q") { root.close(); event.accepted = true; }
        else if (t === "n") { root.nextPhase(); event.accepted = true; }
        else if (t === "p") { root.prevPhase(); event.accepted = true; }
        else if (t === "/") { root.focusSearch(); event.accepted = true; }
    }

    // dim background
    Rectangle {
        anchors.fill: parent
        color: "#000000"; opacity: 0.62
        MouseArea { anchors.fill: parent; onClicked: root.close() }
    }

    // centered card
    Rectangle {
        id: card
        anchors.centerIn: parent
        width: Math.min(parent.width * 0.88, 920)
        height: Math.min(parent.height * 0.88, 700)
        radius: 12; color: "#16181d"; border.color: "#2c313a"; border.width: 1
        MouseArea { anchors.fill: parent } // swallow clicks

        // header
        Item {
            id: headerBar; anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
            height: 46
            Button { anchors.left: parent.left; anchors.leftMargin: 8; anchors.verticalCenter: parent.verticalCenter
                text: root.mode === "search" ? "TMM" : "< Back"; flat: true
                onClicked: { root.mode = "search"; root.focusSearch(); } }
            Text {
                anchors.centerIn: parent; width: parent.width - 220
                horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight; color: "#e6e6e6"
                font.bold: true; font.pixelSize: 15
                text: root.mode === "reader" ? (root.guideTitle || root.currentSlug) + "  #" + root.currentPhase : "The Missing Manual"
            }
            Button { anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter
                text: "Close"; flat: true; onClicked: root.close() }
        }

        // search field
        TextField {
            id: searchField
            anchors.top: headerBar.bottom; anchors.left: parent.left; anchors.right: parent.right
            anchors.leftMargin: 12; anchors.rightMargin: 12; height: 40
            placeholderText: "Search guides... (Enter to search, / to focus)"
            onAccepted: root.doSearch(text)
        }

        // suggestion row
        Item {
            id: suggestRow; anchors.top: searchField.bottom; anchors.left: parent.left; anchors.right: parent.right
            height: root.suggestion ? 28 : 0; visible: root.suggestion !== ""
            Text { anchors.left: parent.left; anchors.leftMargin: 14; anchors.verticalCenter: parent.verticalCenter
                color: "#9aa4b2"; font.pixelSize: 12; text: "Did you mean: " + root.suggestion }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                onClicked: { searchField.text = root.suggestion; root.doSearch(root.suggestion); } }
        }

        // extras row
        Item {
            id: extrasRow; anchors.top: suggestRow.bottom; anchors.left: parent.left; anchors.right: parent.right
            height: 38
            Row {
                anchors.centerIn: parent; spacing: 8
                Button { text: "Catalog"; onClicked: root.showCatalog() }
                Button { text: "Random"; onClicked: root.pickRandom() }
                Button { text: "CheatSheet"; onClicked: root.openCheatSheet() }
                Button { text: "< Prev"; enabled: root.mode === "reader"; onClicked: root.prevPhase() }
                Button { text: "Next >"; enabled: root.mode === "reader"; onClicked: root.nextPhase() }
            }
        }

        // SEARCH results
        ListView {
            id: resultsView; visible: root.mode === "search"
            anchors.top: extrasRow.bottom; anchors.bottom: footerBar.top
            anchors.left: parent.left; anchors.right: parent.right
            anchors.margins: 12; clip: true; spacing: 6; model: resultsModel
            delegate: Rectangle {
                width: resultsView.width; height: 64; radius: 8; color: "#1e2229"
                Column {
                    anchors.fill: parent; anchors.margins: 8; spacing: 2
                    Text { text: model.title; color: "#fff"; font.bold: true; font.pixelSize: 13; elide: Text.ElideRight; width: parent.width }
                    Text { text: model.summary || model.snippet; color: "#9aa4b2"; font.pixelSize: 11; elide: Text.ElideRight; maximumLineCount: 2; wrapMode: Text.Wrap; width: parent.width }
                }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                    onClicked: root.openHit(model.guide_slug, model.phase_no, model.title) }
            }
        }

        // READER
        Flickable {
            id: readerView; visible: root.mode === "reader"
            anchors.top: extrasRow.bottom; anchors.bottom: footerBar.top
            anchors.left: parent.left; anchors.right: parent.right
            anchors.margins: 12; clip: true
            contentWidth: width; contentHeight: readerText.paintedHeight + 16
            TextArea {
                id: readerText; width: parent.width
                readOnly: true; wrapMode: Text.Wrap; selectByMouse: true
                color: "#d7dce3"; font.pixelSize: 13
                background: null
                text: root.phaseBody
            }
        }

        // CATALOG
        ListView {
            id: catalogView; visible: root.mode === "catalog"
            anchors.top: extrasRow.bottom; anchors.bottom: footerBar.top
            anchors.left: parent.left; anchors.right: parent.right
            anchors.margins: 12; clip: true; spacing: 6; model: catalogModel
            delegate: Rectangle {
                width: catalogView.width; height: 52; radius: 8; color: "#1e2229"
                Text { anchors.fill: parent; anchors.margins: 8; verticalAlignment: Text.AlignVCenter
                    color: "#fff"; font.pixelSize: 13; elide: Text.ElideRight
                    text: model.title + (model.summary ? " - " + model.summary : "") }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                    onClicked: root.openHit(model.guide_slug, 1, model.title) }
            }
        }

        // footer
        Item {
            id: footerBar; anchors.bottom: parent.bottom; anchors.left: parent.left; anchors.right: parent.right
            height: 30
            Text {
                anchors.centerIn: parent; color: "#6b7480"; font.pixelSize: 11
                text: "Esc/q close \u00b7 n/p next/prev \u00b7 / focus search  |  " + root.statusMsg
            }
        }
    }
}
