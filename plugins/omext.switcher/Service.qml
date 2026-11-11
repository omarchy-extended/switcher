import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons
import qs.Commons as Commons

// Alt + Tab as a window switcher (omext switcher, from omarchy-extended). Hold
// Alt and press Tab: the open windows show, the one used last first. Each Tab
// steps on (Shift + Tab back); letting go of Alt goes to the one chosen. Escape
// leaves things as they were. The keys are Hyprland's (hypr/switcher.lua), and
// reach this through global shortcuts: nothing is started per keypress.
Item {
  id: root

  property var shell: null
  property var manifest: null

  readonly property var appLibrary: shell ? shell.appLibrary : null
  readonly property string dockTool: Quickshell.env("HOME") + "/.local/bin/omext-dock"

  property var clients: []
  property var monitors: []
  property var docks: []   // `omext-dock list`'s docks, when omext docks is here

  // omext core: which app a window is, going to a window, settings.
  readonly property string coreDir: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/omarchy/plugins/omext.core"
  Loader { id: coreApps; source: "file://" + root.coreDir + "/Apps.qml" }
  Loader { id: coreWindows; source: "file://" + root.coreDir + "/Windows.qml" }
  // ~/.config/omext/switcher.json: "docked": false leaves the omext docks'
  // apps out, "minimized": false the minimized windows.
  Loader { id: coreOwn; Component.onCompleted: setSource("file://" + root.coreDir + "/Settings.qml", { name: "switcher" }) }
  readonly property var config: coreOwn.item ? coreOwn.item.values : ({})

  // address -> {dock, app, icon, name}: the windows in an omext dock.
  readonly property var docked: {
    var out = {}
    for (var d of root.docks)
      for (var a of (d.apps || []))
        if (a.address) out[a.address] = { dock: d.id, app: a.id, icon: a.icon || "", name: a.name || "" }
    return out
  }

  function iconSource(name) {
    return root.appLibrary ? root.appLibrary.iconSource(name) : (Quickshell.iconPath(name, true) || Quickshell.iconPath("application-x-executable", true))
  }
  function entryOf(c) {
    if (coreApps.item) return coreApps.item.ofWindow(c)
    return DesktopEntries.heuristicLookup(c.class) || DesktopEntries.heuristicLookup(c.initialClass)
  }
  function iconOf(c) {
    var d = root.docked[c.address]
    if (d && d.icon) return root.iconSource(d.icon)
    var e = root.entryOf(c)
    return root.iconSource(e && e.icon ? e.icon : String(c.class || "").toLowerCase())
  }
  function appName(c) {
    var d = root.docked[c.address]
    if (d && d.name) return d.name
    var e = root.entryOf(c)
    return e ? e.name : String(c.class || "")
  }
  function detailOf(c) {
    var t = String(c.title || "").trim(), n = root.appName(c)
    return t && t.toLowerCase() !== n.toLowerCase() ? t : ""
  }
  function placeOf(c) {
    if (root.docked[c.address]) return "Dock"
    if (c.workspace && c.workspace.name === "special:minimized") return "Minimized"
    return ""
  }

  // The windows to step through: last used first (Hyprland's focus history).
  function ordered() {
    var list = root.clients.filter(function(c) {
      if (!c || !c.address || c.mapped === false) return false
      if (root.docked[c.address]) return root.config.docked !== false
      if (!c.workspace) return false
      if (c.workspace.name === "special:minimized") return root.config.minimized !== false
      return c.workspace.id > 0
    })
    // By when each was last used (see `used`), the window in front first; one
    // not used yet after those, in Hyprland's order.
    var rank = {}
    root.used.forEach((a, i) => { rank[a] = i })
    function place(c) {
      if (c.focusHistoryID === 0) return -1
      return rank[c.address] !== undefined ? rank[c.address] : 100000 + c.focusHistoryID
    }
    list.sort((a, b) => place(a) - place(b))
    return list
  }

  // The switcher's own record of which windows were used, last first. Hyprland's
  // focus history counts every window the pointer passed over (focus follows
  // the mouse), so the order there is not the order you worked in. Here a
  // window counts as used once it has had the focus for `dwell` (you stopped
  // in it), or when you chose it in the list. Kept while the shell runs. The
  // windows it has no record of come after the others, in Hyprland's order.
  property var used: []
  property string focusedNow: ""
  readonly property int dwell: 700
  readonly property int usedKept: 100   // at most; a closed window leaves it at once
  function noteUsed(addr) {
    if (!addr) return
    root.used = [addr].concat(root.used.filter(a => a !== addr)).slice(0, root.usedKept)
  }
  Timer { id: dwellTimer; interval: root.dwell; onTriggered: root.noteUsed(root.focusedNow) }

  // --- stepping ---------------------------------------------------------------

  property bool open: false     // Alt is held, stepping
  property bool shown: false    // the list is up (a moment after: a quick Alt + Tab shows nothing)
  property var list: []
  property int index: 0
  property string screenName: ""

  Timer { id: showSoon; interval: 140; onTriggered: if (root.open) root.shown = true }

  function step(by) {
    if (!root.open) {
      var l = root.ordered()
      if (l.length === 0) return
      root.list = l
      // From the window in front: the one used before it (or the last, going back).
      var front = l[0].focusHistoryID === 0
      root.index = by > 0 ? (front ? Math.min(1, l.length - 1) : 0) : l.length - 1
      var m = root.monitors.find(x => x.focused)
      root.screenName = m ? m.name : ""
      root.open = true
      showSoon.restart()
      return
    }
    var n = root.list.length
    root.index = (root.index + by + n) % n
    if (!root.shown) { showSoon.stop(); root.shown = true }  // a second Tab: show it now
  }

  function leave() {
    showSoon.stop()
    root.open = false
    root.shown = false
  }

  function commit(at) {
    if (!root.open) return
    var c = root.list[at === undefined ? root.index : at]
    root.leave()
    if (c) root.noteUsed(c.address)
    if (c && coreWindows.item) coreWindows.item.goTo(c, root.docked[c.address] || null, null)
    refreshSoon.restart()
  }

  function cancel() { root.leave() }

  // Hyprland's binds reach these (hl.dsp.global("omext:switcher-next") ...).
  GlobalShortcut { appid: "omext"; name: "switcher-next"; description: "Switch window: the next"; onPressed: root.step(1) }
  GlobalShortcut { appid: "omext"; name: "switcher-prev"; description: "Switch window: the one before"; onPressed: root.step(-1) }
  GlobalShortcut { appid: "omext"; name: "switcher-release"; description: "Switch window: go to the one chosen"; onPressed: root.commit() }

  ShellIpc {
    target: "omext.switcher"
    function next(): void { root.step(1) }
    function prev(): void { root.step(-1) }
    function commit(): void { root.commit() }
    function cancel(): void { root.cancel() }
    function refresh(): void { root.refresh(); root.refreshDocks() }
    function order(): string { return root.ordered().map(c => c.class).join(" ") }  // the list's order now (to check it)
  }

  // --- the windows ------------------------------------------------------------

  function refresh() {
    if (!clientsProc.running) clientsProc.running = true
    else clientsAgain = true
  }
  property bool clientsAgain: false
  function refreshDocks() { if (!dockProc.running) dockProc.running = true }

  Process {
    id: clientsProc
    command: ["bash", "-c", "printf '{\"clients\":%s,\"monitors\":%s}' \"$(hyprctl clients -j)\" \"$(hyprctl monitors -j)\""]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var all = JSON.parse(text)
          root.clients = all.clients || []
          root.monitors = all.monitors || []
        } catch (e) {}
      }
    }
    onExited: if (root.clientsAgain) { root.clientsAgain = false; Qt.callLater(root.refresh) }
  }
  Process {
    id: dockProc
    command: ["bash", "-c", '[ -x "$0" ] && "$0" list 2>/dev/null || echo "{}"', root.dockTool]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: { try { root.docks = JSON.parse(text).docks || [] } catch (e) { root.docks = [] } }
    }
  }
  Timer { id: refreshSoon; interval: 60; onTriggered: root.refresh() }
  Timer { id: docksSoon; interval: 400; onTriggered: root.refreshDocks() }
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      var name = String(event.name)
      if (name === "closewindow") {
        var gone = "0x" + String(event.data || "").trim()
        if (root.used.indexOf(gone) !== -1) root.used = root.used.filter(x => x !== gone)
      }
      if (name === "activewindowv2") {
        var a = String(event.data || "").trim()
        root.focusedNow = a ? "0x" + a : ""
        dwellTimer.restart()
      }
      if (/^(openwindow|closewindow|movewindow|windowtitle|activewindow|workspace|focusedmon|monitoradded|monitorremoved|minimized|activespecial)/.test(name))
        refreshSoon.restart()
      if (/^(openwindow|closewindow|movewindow|monitoradded|monitorremoved|configreloaded)/.test(name))
        docksSoon.restart()
    }
  }
  Component.onCompleted: { refresh(); refreshDocks() }

  // --- the list ---------------------------------------------------------------

  PanelWindow {
    id: win
    // A tile: the window's picture (its icon, where there is none: a window
    // hidden away can't be pictured), then its icon, app and title.
    //
    // The list has the screen's shape: as many across and down as make a block
    // about as wide for its height as the screen is (four windows two by two,
    // six three by two), not one long row. It grows with the windows up to
    // `most` of the screen each way; past that it shows what fits, and moves
    // down the rows as the choice does.
    // Text at Omarchy's text sizes (its base size), and the room under a
    // picture for it along with that; the pictures keep their size.
    readonly property real fs: Commons.Style.fontScale
    readonly property int tileW: 172
    readonly property int gap: 16
    readonly property int pad: 18
    readonly property real most: 0.8
    readonly property int shotH: Math.round(tileW * 0.58)
    readonly property int textH: Math.round(58 * fs)
    readonly property int tileH: shotH + textH
    readonly property int cellW: tileW + gap
    readonly property int cellH: tileH + gap
    readonly property int count: root.list.length
    readonly property int maxCols: Math.max(1, Math.floor((width * most - 2 * pad + gap) / cellW))
    readonly property int maxRows: Math.max(1, Math.floor((height * most - 2 * pad + gap) / cellH))
    readonly property int perRow: {
      if (count <= 1 || height <= 0) return 1
      var shaped = Math.round(Math.sqrt(count * (width / height) * cellH / cellW))
      var cols = Math.max(1, Math.min(count, maxCols, shaped))
      // More rows than fit: wider first, to its most, before it has to move.
      if (Math.ceil(count / cols) > maxRows) cols = Math.min(count, maxCols, Math.max(cols, Math.ceil(count / maxRows)))
      return cols
    }
    readonly property int rows: Math.ceil(count / perRow)
    readonly property int rowsShown: Math.min(rows, maxRows)

    screen: Quickshell.screens.find(s => s.name === root.screenName) || Quickshell.screens[0]
    visible: root.shown
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "omext-switcher"
    // The keys come here while it's up: Alt let go, Escape, the arrows.
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    MouseArea { anchors.fill: parent; onClicked: root.cancel() }  // a click beside it

    Item {
      id: keys
      anchors.fill: parent
      focus: true
      Keys.onPressed: function(e) {
        if (e.key === Qt.Key_Escape) root.cancel()
        else if (e.key === Qt.Key_Right || e.key === Qt.Key_Tab) root.step(1)
        else if (e.key === Qt.Key_Left || e.key === Qt.Key_Backtab) root.step(-1)
        else if (e.key === Qt.Key_Down) root.index = Math.min(root.list.length - 1, root.index + win.perRow)
        else if (e.key === Qt.Key_Up) root.index = Math.max(0, root.index - win.perRow)
        else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Space) root.commit()
        else return
        e.accepted = true
      }
      Keys.onReleased: function(e) {
        if (e.key === Qt.Key_Alt) { root.commit(); e.accepted = true }
      }
    }

    Rectangle {
      id: card
      anchors.centerIn: parent
      width: win.perRow * win.cellW - win.gap + 2 * win.pad
      height: win.rowsShown * win.cellH - win.gap + 2 * win.pad
      radius: 12
      color: Commons.Color.popups.background
      border.width: 1
      border.color: Commons.Color.popups.border
      MouseArea { anchors.fill: parent }  // not through to the one that cancels

      Flickable {
        id: scroller
        x: win.pad; y: win.pad
        width: parent.width - 2 * win.pad
        height: parent.height - 2 * win.pad
        contentWidth: width
        contentHeight: flow.height
        clip: win.rows > win.rowsShown
        interactive: win.rows > win.rowsShown
        boundsBehavior: Flickable.StopAtBounds
        // The chosen window's row in view: the list moves a row at a time.
        readonly property int chosenRow: Math.floor(root.index / win.perRow)
        property int firstRow: 0
        onChosenRowChanged: follow()
        function follow() {
          if (chosenRow < firstRow) firstRow = chosenRow
          else if (chosenRow >= firstRow + win.rowsShown) firstRow = chosenRow - win.rowsShown + 1
          firstRow = Math.max(0, Math.min(firstRow, win.rows - win.rowsShown))
          contentY = firstRow * win.cellH
        }
        Connections { target: root; function onShownChanged() { scroller.firstRow = 0; scroller.follow() } }
        Behavior on contentY { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

      Flow {
        id: flow
        width: scroller.width
        spacing: win.gap
        Repeater {
          model: root.list
          Rectangle {
            id: tile
            required property var modelData
            required property int index
            readonly property bool chosen: index === root.index
            width: win.tileW; height: win.tileH
            radius: 8
            color: chosen ? Commons.Util.alpha(Commons.Color.accent, 0.22) : hit.containsMouse ? Commons.Util.alpha(Commons.Color.foreground, 0.07) : "transparent"
            border.width: chosen ? 2 : 0
            border.color: Commons.Color.accent
            // Hyprland's own handle on the window, to picture it.
            readonly property var handle: root.shown ? (Hyprland.toplevels.values.find(t => "0x" + t.address === tile.modelData.address) || null) : null
            Item {
              id: shot
              x: 6; y: 6
              width: parent.width - 12; height: win.shotH
              Rectangle {  // behind a see-through window (a terminal): not the list's own background
                anchors.fill: view
                anchors.margins: -1
                visible: view.hasContent
                color: Commons.Color.background
                border.width: 1
                border.color: Commons.Util.alpha(Commons.Color.foreground, 0.14)
              }
              ScreencopyView {
                id: view
                anchors.centerIn: parent
                captureSource: tile.handle ? tile.handle.wayland : null
                constraintSize: Qt.size(shot.width, shot.height)
                live: root.shown
                visible: hasContent
              }
              Image {  // no picture: its icon, large
                anchors.centerIn: parent
                visible: !view.hasContent
                width: Math.min(52, win.shotH - 16); height: width
                source: visible ? root.iconOf(tile.modelData) : ""
                sourceSize: Qt.size(112, 112)
                fillMode: Image.PreserveAspectFit
              }
            }
            // Its icon and app, then its title: centred under the picture.
            Row {
              id: nameRow
              anchors.horizontalCenter: parent.horizontalCenter
              y: win.shotH + Math.round(11 * win.fs)
              spacing: 6
              Image {
                id: icon
                anchors.verticalCenter: parent.verticalCenter
                width: Math.round(16 * win.fs); height: width
                visible: view.hasContent
                source: root.iconOf(tile.modelData)
                sourceSize: Qt.size(36, 36)
                fillMode: Image.PreserveAspectFit
              }
              Text {
                id: name
                width: Math.min(implicitWidth, tile.width - 20 - (icon.visible ? icon.width + nameRow.spacing : 0))
                elide: Text.ElideRight
                text: root.appName(tile.modelData)
                color: Commons.Color.popups.text
                font.family: Commons.Style.font.family
                font.pixelSize: Commons.Style.font.body
                font.bold: tile.chosen
              }
            }
            Text {
              x: 10; y: win.shotH + Math.round(32 * win.fs)
              width: parent.width - 20
              horizontalAlignment: Text.AlignHCenter
              elide: Text.ElideRight
              text: root.detailOf(tile.modelData) || root.placeOf(tile.modelData)
              color: Commons.Util.alpha(Commons.Color.popups.text, 0.6)
              font.family: Commons.Style.font.family
              font.pixelSize: Commons.Style.font.bodySmall
            }
            // Where it is, when not on a workspace: in a dock, minimized.
            Rectangle {
              visible: placeTag.text !== "" && root.detailOf(tile.modelData) !== ""
              x: parent.width - width - 10; y: 10
              width: placeTag.implicitWidth + 10; height: placeTag.implicitHeight + 4; radius: height / 2
              color: Commons.Util.alpha(Commons.Color.popups.background, 0.85)
              Text {
                id: placeTag
                anchors.centerIn: parent
                text: root.placeOf(tile.modelData)
                color: Commons.Util.alpha(Commons.Color.popups.text, 0.75)
                font.family: Commons.Style.font.family
                font.pixelSize: Commons.Style.font.caption
              }
            }
            MouseArea {
              id: hit
              anchors.fill: parent
              hoverEnabled: true
              onClicked: root.commit(tile.index)
            }
          }
        }
      }
      }

      // More above or below than shows.
      Rectangle {
        visible: win.rows > win.rowsShown
        x: parent.width - 8; width: 3; radius: 1.5
        y: win.pad + (parent.height - 2 * win.pad) * scroller.firstRow / win.rows
        height: (parent.height - 2 * win.pad) * win.rowsShown / win.rows
        color: Commons.Util.alpha(Commons.Color.foreground, 0.35)
        Behavior on y { NumberAnimation { duration: 120 } }
      }
    }
  }
}
