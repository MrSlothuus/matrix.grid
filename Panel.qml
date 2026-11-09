import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Bar dropdown for the cell-grid layout in ~/.config/hypr/cellgrid.lua. State
// lives in Hyprland's Lua runtime: read with `hyprctl repl`, changed with
// `hyprctl eval`, and cellgrid.lua saves the settings across reloads.
Panel {
  id: root
  moduleName: "slothuus.grid"
  ipcTarget: "slothuus.grid"
  manageIpc: false

  property var grid: ({
    enabled: true, handles: true, columns: 8, rows: 8,
    new_width: 3, new_height: 3, limit: 16, focused: null
  })
  property bool loaded: false
  property string failure: ""
  property bool refreshAgain: false
  readonly property bool gridOn: grid.enabled === true
  readonly property var focused: gridOn ? grid.focused : null
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property var presets: [
    { label: "1 × 1", w: 1, h: 1 },
    { label: "2 × 2", w: 2, h: 2 },
    { label: "3 × 3", w: 3, h: 3 },
    { label: "4 × 4", w: 4, h: 4 },
    { label: "Full", w: grid.columns, h: grid.rows }
  ]

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function refresh() {
    if (stateProcess.running) {
      refreshAgain = true
      return
    }
    stateProcess.running = true
  }

  function lua(code) {
    failure = ""
    Quickshell.execDetached(["hyprctl", "eval", code])
  }

  // Show the new value at once; the layout's change signal confirms it.
  function setSetting(key, value) {
    var next = Object.assign({}, grid)
    next[key] = value
    grid = next
    lua('require("hypr.cellgrid").set_setting("' + key + '", ' + JSON.stringify(value) + ')')
  }

  function sizeFocused(w, h) {
    lua('require("hypr.cellgrid").size_focused(' + w + ', ' + h + ')')
  }

  Component.onCompleted: refresh()
  onOpenedChanged: if (opened) {
    refresh()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): void { root.refresh() }
    function state(): string { return JSON.stringify(root.grid) }
  }

  // cellgrid.lua rewrites this after every layout or settings change.
  FileView {
    path: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/cellgrid-layout-changed"
    watchChanges: true
    printErrors: false
    onFileChanged: root.refresh()
  }

  Process {
    id: stateProcess
    command: ["hyprctl", "repl", 'return require("hypr.cellgrid").settings_json()']
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          root.grid = JSON.parse(text)
          root.loaded = true
          root.failure = ""
        } catch (error) {
          root.failure = "Could not read the grid layout from Hyprland. Check ~/.config/hypr/cellgrid.lua."
        }
      }
    }
    onExited: if (root.refreshAgain) {
      root.refreshAgain = false
      root.refresh()
    }
  }

  // Label, minus button, value, plus button.
  component Stepper: Row {
    id: stepper
    property string label: ""
    property int value: 0
    property int from: 1
    property int to: 16
    property color foreground: Color.foreground
    property string fontFamily: Style.font.family
    signal adjusted(int value)

    spacing: Style.space(4)

    Text {
      width: Style.space(72)
      anchors.verticalCenter: parent.verticalCenter
      text: stepper.label
      color: stepper.foreground
      font.family: stepper.fontFamily
      font.pixelSize: Style.font.body
    }
    Button {
      width: Style.space(30)
      text: "−"
      bordered: true
      enabled: stepper.enabled && stepper.value > stepper.from
      opacity: enabled ? 1 : 0.4
      onClicked: stepper.adjusted(stepper.value - 1)
    }
    Text {
      width: Style.space(28)
      anchors.verticalCenter: parent.verticalCenter
      horizontalAlignment: Text.AlignHCenter
      text: stepper.value
      color: stepper.foreground
      font.family: stepper.fontFamily
      font.pixelSize: Style.font.body
      font.bold: true
    }
    Button {
      width: Style.space(30)
      text: "+"
      bordered: true
      enabled: stepper.enabled && stepper.value < stepper.to
      opacity: enabled ? 1 : 0.4
      onClicked: stepper.adjusted(stepper.value + 1)
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: String.fromCodePoint(0xF0570)
    dimmed: root.loaded && !root.gridOn
    tooltipText: root.gridOn ? "Grid layout: " + root.grid.columns + " × " + root.grid.rows : "Grid layout is off"
    onPressed: function(mouseButton) { root.toggle() }
  }

  KeyboardPanel {
    id: popup
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: fittedContentWidth(Style.space(300))
    contentHeight: fittedContentHeight(content.implicitHeight, Style.space(620))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: content
        width: parent.width
        spacing: Style.space(8)

        Item {
          width: parent.width
          height: Math.max(title.implicitHeight, onSwitch.implicitHeight)

          Text {
            id: title
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "Grid"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
            font.bold: true
          }

          ToggleSwitch {
            id: onSwitch
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            checked: root.gridOn
            foreground: root.foreground
            onToggled: root.setSetting("enabled", !root.gridOn)
          }
        }

        Text {
          width: parent.width
          text: root.gridOn
            ? root.grid.columns + " × " + root.grid.rows + " cells on every monitor"
            : "Off: windows use Hyprland's standard tiling"
          color: root.foreground
          opacity: 0.65
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }

        Text {
          width: parent.width
          visible: root.failure !== ""
          text: root.failure
          color: Color.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }

        Column {
          width: parent.width
          spacing: Style.space(8)
          enabled: root.gridOn
          opacity: enabled ? 1 : 0.45

          PanelSeparator { width: parent.width; foreground: root.foreground }

          PanelSectionHeader {
            text: "Focused window"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Text {
            width: parent.width
            text: root.focused
              ? (root.focused.class || "Window") + " · " + root.focused.w + " × " + root.focused.h
              : "Focus a tiled window to size it"
            color: root.foreground
            opacity: root.focused ? 1 : 0.65
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            elide: Text.ElideRight
          }

          Flow {
            width: parent.width
            spacing: Style.space(6)

            Repeater {
              model: root.presets
              Button {
                required property var modelData
                text: modelData.label
                bordered: true
                selected: root.focused !== null && root.focused.w === modelData.w && root.focused.h === modelData.h
                enabled: root.focused !== null
                opacity: enabled ? 1 : 0.4
                onClicked: root.sizeFocused(modelData.w, modelData.h)
              }
            }
          }

          PanelSeparator { width: parent.width; foreground: root.foreground }

          PanelSectionHeader {
            text: "Grid size"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Stepper {
            label: "Columns"
            value: root.grid.columns
            from: 2
            to: root.grid.limit
            foreground: root.foreground
            fontFamily: root.fontFamily
            onAdjusted: function(value) { root.setSetting("columns", value) }
          }

          Stepper {
            label: "Rows"
            value: root.grid.rows
            from: 2
            to: root.grid.limit
            foreground: root.foreground
            fontFamily: root.fontFamily
            onAdjusted: function(value) { root.setSetting("rows", value) }
          }

          PanelSectionHeader {
            text: "New windows"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Stepper {
            label: "Width"
            value: root.grid.new_width
            from: 1
            to: root.grid.columns
            foreground: root.foreground
            fontFamily: root.fontFamily
            onAdjusted: function(value) { root.setSetting("new_width", value) }
          }

          Stepper {
            label: "Height"
            value: root.grid.new_height
            from: 1
            to: root.grid.rows
            foreground: root.foreground
            fontFamily: root.fontFamily
            onAdjusted: function(value) { root.setSetting("new_height", value) }
          }

          PanelSeparator { width: parent.width; foreground: root.foreground }

          Toggle {
            width: parent.width
            label: "Resize dots"
            description: "Drag the dot in a window's corner to resize it"
            checked: root.grid.handles
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: root.setSetting("handles", !root.grid.handles)
          }

          Button {
            width: parent.width
            text: "Tidy up this workspace"
            iconText: String.fromCodePoint(0xF0068)
            leftAlign: true
            bordered: true
            tooltipText: "Pack every window toward the top-left, keeping its size"
            onClicked: root.lua('require("hypr.cellgrid").tidy()')
          }

          Text {
            width: parent.width
            text: "Super+Ctrl+arrows resize · Super+drag moves\nSuper+Ctrl+G opens grid mode"
            color: root.foreground
            opacity: 0.55
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
        }
      }
    }
  }
}
