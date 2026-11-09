import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland

// Overlay half of the Grid plugin: the cell grid shown while dragging a tile,
// and a resize dot in each visible tile's bottom-right corner.
Item {
  id: root

  property bool opened: false
  property int areaX: 0
  property int areaY: 0
  property int areaW: 1
  property int areaH: 1
  property int columns: 8
  property int rows: 8
  property real activeToken: 0
  property real closedThrough: 0

  // Corner resize handles: one small layer surface per visible grid tile.
  readonly property int handleSize: 18
  readonly property int handleInset: 2
  readonly property color accent: "#f5d568"
  property string resizeAddress: ""
  property var resizeInfo: null
  property bool resizeReleased: false
  property real pointerX: 0
  property real pointerY: 0
  property int ghostW: 1
  property int ghostH: 1
  readonly property bool resizing: resizeAddress !== "" && resizeInfo !== null

  function open(payloadJson) {
    try {
      var p = JSON.parse(payloadJson)
      if (!(p.w > 0 && p.h > 0 && p.columns > 0 && p.rows > 0)) return
      var token = Number(p.token)
      if (!isFinite(token) || token <= 0 || token <= closedThrough || token < activeToken) return
      areaX = p.x
      areaY = p.y
      areaW = p.w
      areaH = p.h
      columns = p.columns
      rows = p.rows
      activeToken = token
      opened = true
    } catch (e) {
      console.warn("Cell grid preview: invalid drag geometry", e)
    }
  }

  function close(tokenText) {
    var token = Number(tokenText)
    if (!isFinite(token) || token <= 0) token = activeToken
    closedThrough = Math.max(closedThrough, token)
    if (token >= activeToken) opened = false
  }

  function clamp(value, low, high) {
    return Math.max(low, Math.min(value, high))
  }

  function screenIndexAt(x, y) {
    var screens = Quickshell.screens
    for (var i = 0; i < screens.length; i++) {
      var s = screens[i]
      if (x >= s.x && x < s.x + s.width && y >= s.y && y < s.y + s.height) return i
    }
    return -1
  }

  // Workspace ids shown on a monitor, read from `hyprctl monitors`: Quickshell's
  // own monitor state (activeWorkspace, focusedMonitor) stays empty on this
  // Hyprland. Cleared on workspace switches so stale dots never linger.
  property var visibleWorkspaces: ({})
  property bool monitorsKnown: false

  function receiveMonitors(text) {
    try {
      var monitors = JSON.parse(text)
      var visible = {}
      for (var i = 0; i < monitors.length; i++) {
        var monitor = monitors[i]
        if (monitor.specialWorkspace && monitor.specialWorkspace.id) continue
        if (monitor.activeWorkspace) visible[monitor.activeWorkspace.id] = true
      }
      visibleWorkspaces = visible
      monitorsKnown = true
    } catch (e) {
      console.warn("Cell grid handles: could not read monitors", e)
    }
  }

  Process {
    id: monitorProcess
    command: ["hyprctl", "-j", "monitors"]
    stdout: StdioCollector {
      onStreamFinished: root.receiveMonitors(this.text)
    }
  }

  // Tiled windows on each monitor's visible workspace, keyed by address.
  // Geometry comes from the last toplevel IPC refresh.
  readonly property var handleMap: {
    if (!monitorsKnown || !handlesEnabled) return {}
    var windows = []
    var fullscreen = {}
    var toplevels = Hyprland.toplevels.values
    for (var j = 0; j < toplevels.length; j++) {
      var ipc = toplevels[j].lastIpcObject
      var workspace = toplevels[j].workspace
      if (!ipc || !ipc.at || !ipc.size || !workspace || !ipc.mapped || ipc.hidden) continue
      if (ipc.fullscreen) fullscreen[workspace.id] = true
      windows.push({ ipc: ipc, workspace: workspace.id })
    }

    var map = {}
    for (var k = 0; k < windows.length; k++) {
      var w = windows[k]
      if (w.ipc.floating || w.workspace <= 0 || !visibleWorkspaces[w.workspace] || fullscreen[w.workspace])
        continue
      var cornerX = w.ipc.at[0] + w.ipc.size[0] - handleInset
      var cornerY = w.ipc.at[1] + w.ipc.size[1] - handleInset
      var covered = false
      for (var f = 0; f < windows.length && !covered; f++) {
        var o = windows[f]
        covered = o.ipc.floating && o.workspace === w.workspace
          && cornerX > o.ipc.at[0] && cornerX < o.ipc.at[0] + o.ipc.size[0]
          && cornerY > o.ipc.at[1] && cornerY < o.ipc.at[1] + o.ipc.size[1]
      }
      var screenIndex = screenIndexAt(cornerX - 1, cornerY - 1)
      if (covered || screenIndex < 0) continue
      map[String(w.ipc.address)] = {
        x: cornerX - handleSize,
        y: cornerY - handleSize,
        screenIndex: screenIndex
      }
    }
    return map
  }
  readonly property var handleAddresses: Object.keys(handleMap)

  function refresh() {
    if (resizeAddress !== "") return
    Hyprland.refreshToplevels()
    if (!monitorProcess.running) monitorProcess.running = true
  }

  readonly property var geometryEvents: ({
    openwindow: true, closewindow: true, movewindow: true, movewindowv2: true,
    changefloatingmode: true, fullscreen: true, configreloaded: true, minimized: true
  })
  readonly property var workspaceEvents: ({
    workspace: true, workspacev2: true, activespecial: true, activespecialv2: true,
    focusedmon: true, focusedmonv2: true, moveworkspace: true, moveworkspacev2: true,
    monitoradded: true, monitoraddedv2: true, monitorremoved: true, monitorremovedv2: true
  })

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (root.workspaceEvents[event.name] && root.resizeAddress === "") {
        root.monitorsKnown = false
        refreshSoon.restart()
      } else if (root.geometryEvents[event.name]) {
        refreshSoon.restart()
      }
    }
  }

  // cellgrid.lua rewrites this file after layout changes and Grid panel
  // settings changes; it carries whether the grid and its dots are on.
  property bool handlesEnabled: true

  FileView {
    id: layoutSignal
    path: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/cellgrid-layout-changed"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        var signal = JSON.parse(text())
        root.handlesEnabled = signal.enabled !== false && signal.handles !== false
      } catch (e) {
        root.handlesEnabled = true
      }
      refreshSoon.restart()
    }
  }

  // Refresh once tiles are placed, then again after window animations settle.
  Timer {
    id: refreshSoon
    interval: 80
    onTriggered: {
      root.refresh()
      refreshSettled.restart()
    }
  }
  Timer {
    id: refreshSettled
    interval: 700
    onTriggered: root.refresh()
  }

  Component.onCompleted: refresh()

  function beginResize(address, x, y) {
    if (!/^0x[0-9a-fA-F]+$/.test(address)) return
    resizeAddress = address
    resizeInfo = null
    resizeReleased = false
    pointerX = x
    pointerY = y
    infoProcess.command = ["hyprctl", "repl", 'return require("hypr.cellgrid").grid_info("' + address + '")']
    infoProcess.running = true
  }

  function receiveInfo(text) {
    if (resizeAddress === "") return
    try {
      var info = JSON.parse(text)
      if (!(info.columns > 0 && info.rows > 0 && info.area && info.area.w > 0 && info.area.h > 0))
        throw "missing grid geometry"
      resizeInfo = info
    } catch (e) {
      // Not a grid tile (or Hyprland's layout reloaded); drop the gesture.
      endResize()
      return
    }
    areaX = resizeInfo.area.x
    areaY = resizeInfo.area.y
    areaW = resizeInfo.area.w
    areaH = resizeInfo.area.h
    columns = resizeInfo.columns
    rows = resizeInfo.rows
    updateGhost()
    if (resizeReleased) applyResize()
  }

  function moveResize(x, y) {
    pointerX = x
    pointerY = y
    if (resizeInfo) updateGhost()
  }

  // Snap the dragged corner to the nearest grid line; the top-left cell stays put.
  function updateGhost() {
    var info = resizeInfo
    var right = Math.round((pointerX - info.area.x) * info.columns / info.area.w)
    var bottom = Math.round((pointerY - info.area.y) * info.rows / info.area.h)
    ghostW = clamp(right - (info.x - 1), 1, info.columns - info.x + 1)
    ghostH = clamp(bottom - (info.y - 1), 1, Math.min(info.max_h, info.rows - info.y + 1))
  }

  function finishResize() {
    resizeReleased = true
    if (resizeInfo) applyResize()
  }

  function applyResize() {
    if (ghostW !== resizeInfo.w || ghostH !== resizeInfo.h) {
      Quickshell.execDetached(["hyprctl", "eval",
        'require("hypr.cellgrid").resize("' + resizeAddress + '", ' + ghostW + ', ' + ghostH + ')'])
    }
    endResize()
  }

  function endResize() {
    resizeAddress = ""
    resizeInfo = null
    resizeReleased = false
    refreshSoon.restart()
  }

  Process {
    id: infoProcess
    stdout: StdioCollector {
      onStreamFinished: root.receiveInfo(this.text.trim())
    }
  }

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: panel
      required property var modelData

      screen: modelData
      visible: (root.opened || root.resizing)
        && root.areaX >= modelData.x && root.areaX < modelData.x + modelData.width
        && root.areaY >= modelData.y && root.areaY < modelData.y + modelData.height
      anchors { top: true; bottom: true; left: true; right: true }
      color: "transparent"
      exclusionMode: ExclusionMode.Ignore
      WlrLayershell.namespace: "cellgrid-drag-preview"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      mask: Region {}

      Item {
        id: grid
        x: root.areaX - panel.modelData.x
        y: root.areaY - panel.modelData.y
        width: root.areaW
        height: root.areaH
        clip: true

        Repeater {
          model: root.columns + 1
          Rectangle {
            x: Math.round(index * grid.width / root.columns)
            width: 1
            height: grid.height
            color: "#99f5d568"
          }
        }
        Repeater {
          model: root.rows + 1
          Rectangle {
            y: Math.round(index * grid.height / root.rows)
            width: grid.width
            height: 1
            color: "#99f5d568"
          }
        }

        // The cells the window will occupy when the corner handle is released.
        Rectangle {
          id: ghost
          visible: root.resizing
          readonly property int cellLeft: root.resizing ? root.resizeInfo.x - 1 : 0
          readonly property int cellTop: root.resizing ? root.resizeInfo.y - 1 : 0
          x: Math.floor(grid.width * cellLeft / root.columns)
          y: Math.floor(grid.height * cellTop / root.rows)
          width: Math.floor(grid.width * (cellLeft + root.ghostW) / root.columns) - x
          height: Math.floor(grid.height * (cellTop + root.ghostH) / root.rows) - y
          color: "#26f5d568"
          border.width: 2
          border.color: root.accent

          Rectangle {
            anchors.centerIn: parent
            width: sizeLabel.implicitWidth + 20
            height: sizeLabel.implicitHeight + 10
            radius: height / 2
            color: "#cc000000"

            Text {
              id: sizeLabel
              anchors.centerIn: parent
              text: root.ghostW + " × " + root.ghostH
              color: root.accent
              font.pixelSize: 18
              font.bold: true
            }
          }
        }
      }
    }
  }

  Variants {
    model: root.handleAddresses

    PanelWindow {
      id: handle
      required property var modelData
      readonly property var spot: root.handleMap[modelData] || null
      readonly property bool dragging: root.resizeAddress === modelData
      property real originX: 0
      property real originY: 0

      screen: spot ? Quickshell.screens[spot.screenIndex] : null
      visible: spot !== null && (root.resizeAddress === "" || dragging)
      anchors { top: true; left: true }
      margins {
        left: spot ? spot.x - screen.x : 0
        top: spot ? spot.y - screen.y : 0
      }
      implicitWidth: root.handleSize
      implicitHeight: root.handleSize
      color: "transparent"
      exclusionMode: ExclusionMode.Ignore
      WlrLayershell.namespace: "cellgrid-resize-handle"
      WlrLayershell.layer: WlrLayer.Top
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

      Rectangle {
        readonly property bool lit: pointer.containsMouse || handle.dragging
        anchors.centerIn: parent
        width: lit ? 14 : 10
        height: width
        radius: width / 2
        color: root.accent
        opacity: lit ? 1 : 0.65
        border.width: 1
        border.color: "#99000000"

        Behavior on width { NumberAnimation { duration: 90 } }
      }

      MouseArea {
        id: pointer
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        cursorShape: Qt.SizeFDiagCursor

        onPressed: function(mouse) {
          handle.originX = handle.screen.x + handle.margins.left
          handle.originY = handle.screen.y + handle.margins.top
          root.beginResize(handle.modelData, handle.originX + mouse.x, handle.originY + mouse.y)
        }
        onPositionChanged: function(mouse) {
          if (pressed && handle.dragging) root.moveResize(handle.originX + mouse.x, handle.originY + mouse.y)
        }
        onReleased: if (handle.dragging) root.finishResize()
        onCanceled: if (handle.dragging) root.endResize()
      }
    }
  }
}
