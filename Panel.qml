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
  moduleName: "matrix.grid"
  ipcTarget: "matrix.grid"
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
  readonly property string rainLauncher: Qt.resolvedUrl("screensaver/matrix-rain").toString().replace("file://", "")
  readonly property string rainWallpaper: Qt.resolvedUrl("screensaver/matrix-rain-wallpaper").toString().replace("file://", "")
  // screensaver/rain-shader reads this file each time the rain starts.
  readonly property string rainSettingsPath: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/omarchy/matrix-rain.json"
  property var rain: ({ color: "#6b7ac2", speed: 100, amount: 100 })
  // screensaver/matrix-rain-wallpaper keeps this file at "rendering" while it works.
  readonly property string wallpaperStatusPath: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/matrix-grid-screensaver/wallpaper.status"
  property bool wallpaperRendering: false
  readonly property var rainColors: [
    { name: "Blue", value: "#6b7ac2" },
    { name: "Green", value: "#3ddc6a" },
    { name: "Cyan", value: "#5fd7e6" },
    { name: "Purple", value: "#a678e2" },
    { name: "Red", value: "#e25a5a" },
    { name: "Amber", value: "#e6a23c" },
    { name: "White", value: "#c8ccd8" },
    { name: "Theme accent", value: hex(Color.accent) }
  ]
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

  function hex(color) {
    function part(value) { return ("0" + Math.round(value * 255).toString(16)).slice(-2) }
    return "#" + part(color.r) + part(color.g) + part(color.b)
  }

  function loadRain(text) {
    try {
      var saved = JSON.parse(text)
      var next = Object.assign({}, rain)
      if (/^#[0-9a-fA-F]{6}$/.test(saved.color)) next.color = saved.color.toLowerCase()
      if (saved.speed >= 25 && saved.speed <= 300) next.speed = Math.round(saved.speed)
      if (saved.amount >= 25 && saved.amount <= 300) next.amount = Math.round(saved.amount)
      rain = next
    } catch (error) {}
  }

  function setRain(key, value) {
    var next = Object.assign({}, rain)
    next[key] = value
    rain = next
    rainFile.setText(JSON.stringify(next) + "\n")
  }

  // Make the live GPU shader rain the current theme's wallpaper. The script
  // never bakes a video, so this takes about a second.
  function useAsWallpaper() {
    if (wallpaperRendering)
      return
    wallpaperRendering = true
    Quickshell.execDetached([rainWallpaper])
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
    function rainColor(color: string): void {
      if (/^#[0-9a-fA-F]{6}$/.test(color)) root.setRain("color", color.toLowerCase())
    }
    function rainSpeed(percent: int): void {
      root.setRain("speed", Math.max(25, Math.min(300, percent)))
    }
    function rainAmount(percent: int): void {
      root.setRain("amount", Math.max(25, Math.min(300, percent)))
    }
    function useAsWallpaper(): void { root.useAsWallpaper() }
  }

  // cellgrid.lua rewrites this after every layout or settings change.
  FileView {
    path: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/cellgrid-layout-changed"
    watchChanges: true
    printErrors: false
    onFileChanged: root.refresh()
  }

  FileView {
    id: rainFile
    path: root.rainSettingsPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadRain(text())
    onFileChanged: reload()
  }

  FileView {
    id: wallpaperStatus
    path: root.wallpaperStatusPath
    watchChanges: true
    printErrors: false
    onLoaded: root.wallpaperRendering = text().trim() === "rendering"
    onLoadFailed: root.wallpaperRendering = false
    onFileChanged: reload()
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

  // Label, slider from 25 % to 300 % in steps of 25, value.
  component PercentSlider: Row {
    id: percentSlider
    property string label: ""
    property int value: 100
    property int shown: value
    signal chosen(int value)

    spacing: Style.space(8)
    onValueChanged: shown = value

    Text {
      id: percentLabel
      width: Style.space(72)
      anchors.verticalCenter: parent.verticalCenter
      text: percentSlider.label
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }

    PanelSlider {
      width: parent.width - percentLabel.width - percentValue.width - parent.spacing * 2
      anchors.verticalCenter: parent.verticalCenter
      bar: root.bar
      minimum: 25
      maximum: 300
      step: 25
      value: percentSlider.value
      onMoved: function(value) { percentSlider.shown = Math.round(value / 25) * 25 }
      onReleased: function(value) { percentSlider.chosen(Math.round(value / 25) * 25) }
    }

    Text {
      id: percentValue
      width: Style.space(44)
      anchors.verticalCenter: parent.verticalCenter
      horizontalAlignment: Text.AlignRight
      text: percentSlider.shown + "%"
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      font.bold: true
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
    contentHeight: fittedContentHeight(content.implicitHeight, Style.space(800))

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

        // The matrix rain works whether or not the grid layout is on.
        PanelSeparator { width: parent.width; foreground: root.foreground }

        PanelSectionHeader {
          text: "Matrix rain"
          foreground: root.foreground
          fontFamily: root.fontFamily
        }

        Row {
          spacing: Style.space(6)

          Text {
            width: Style.space(72)
            anchors.verticalCenter: parent.verticalCenter
            text: "Colour"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }

          Repeater {
            model: root.rainColors
            Rectangle {
              id: swatch
              required property var modelData
              readonly property bool chosen: root.rain.color === modelData.value
              width: Style.space(18)
              height: width
              radius: width / 2
              color: modelData.value
              border.width: chosen ? Math.max(2, Style.space(2)) : 0
              border.color: root.foreground
              scale: swatchArea.containsMouse ? 1.15 : 1

              MouseArea {
                id: swatchArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.setRain("color", swatch.modelData.value)
              }
            }
          }
        }

        PercentSlider {
          width: parent.width
          label: "Speed"
          value: root.rain.speed
          onChosen: function(value) { root.setRain("speed", value) }
        }

        PercentSlider {
          width: parent.width
          label: "Amount"
          value: root.rain.amount
          onChosen: function(value) { root.setRain("amount", value) }
        }

        Button {
          width: parent.width
          text: "Start matrix rain"
          iconText: String.fromCodePoint(0xF0597)
          leftAlign: true
          bordered: true
          tooltipText: "Play the matrix rain screensaver now; any key or mouse movement ends it"
          onClicked: {
            root.close()
            Quickshell.execDetached([root.rainLauncher, "force"])
          }
        }

        Button {
          width: parent.width
          text: root.wallpaperRendering ? "Setting wallpaper…" : "Use as wallpaper"
          iconText: String.fromCodePoint(root.wallpaperRendering ? 0xF051F : 0xF0E09)
          leftAlign: true
          bordered: true
          enabled: !root.wallpaperRendering
          opacity: enabled ? 1 : 0.6
          tooltipText: "Make the rain, with this colour, speed and amount, the current theme's live animated background"
          onClicked: root.useAsWallpaper()
        }
      }
    }
  }
}
