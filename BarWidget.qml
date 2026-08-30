import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import "Model.js" as Model

// A shield glyph that turns red with a countdown while passwordless sudo is
// open — that state should be impossible to miss. Left click opens the panel,
// middle click refreshes. Optionally invisible while inactive.
BarWidget {
  id: root
  moduleName: "synjan.sudo"

  readonly property string icon: String(setting("icon", "󰟵"))
  readonly property bool showWhenInactive: String(setting("showWhenInactive", true)) !== "false"

  readonly property var service: panelLoader.item ? panelLoader.item.service : null
  readonly property bool active: service ? service.on : false
  readonly property double remaining: service ? service.deadlineMs - service.now : 0
  readonly property string lastError: service ? service.lastError : ""

  readonly property bool shown: active || showWhenInactive
  readonly property string displayText: active ? icon + " " + Model.formatCountdown(root.remaining) : icon
  // The bar can be translucent over any wallpaper, so an open window is a
  // filled badge in the theme's bar-urgent color rather than colored text —
  // the only thing that stays legible everywhere. Text color by luminance.
  readonly property bool alert: root.active || root.lastError !== ""
  readonly property color alertColor: root.bar && root.bar.urgent !== undefined ? root.bar.urgent : "#a55555"
  readonly property color pillColor: {
    if (root.alert) return Model.textOn(root.alertColor.r, root.alertColor.g, root.alertColor.b)
    return root.bar && root.bar.foreground !== undefined ? Qt.darker(root.bar.foreground, 1.45) : "#7a7f95"
  }

  function refresh() { if (service) service.refresh() }

  // ---- settings persistence (same shape as synjan.backup) -----------------
  property var pendingEntry: null

  function storedEntry() {
    var config = root.bar && root.bar.shell ? root.bar.shell.shellConfig : null
    var layout = config && config.bar ? config.bar.layout : null
    var sections = ["left", "center", "right"]
    for (var s = 0; layout && s < sections.length; s++) {
      var list = layout[sections[s]] || []
      for (var i = 0; i < list.length; i++) {
        if (list[i] && list[i].id === root.moduleName) return list[i]
      }
    }
    return null
  }

  function persist(changes) {
    var base = root.pendingEntry || root.storedEntry()
    if (!base) {
      console.warn("synjan.sudo: shell.json entry not reachable, change not saved:", JSON.stringify(changes))
      return
    }
    var entry = { id: root.moduleName }
    for (var key in base) if (key !== "id") entry[key] = base[key]
    for (var changed in changes) entry[changed] = changes[changed]
    root.settings = entry
    root.pendingEntry = entry
    persistTimer.restart()
  }

  function flushSettings() {
    if (!root.pendingEntry) return
    var entry = root.pendingEntry
    root.pendingEntry = null
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  Timer { id: persistTimer; interval: 200; onTriggered: root.flushSettings() }
  Component.onDestruction: root.flushSettings()

  // ---- popout contract ----------------------------------------------------
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function togglePanel() { if (panelLoader.item) panelLoader.item.toggle() }
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }
  readonly property real openPanelIndicatorWidth: button.labelWidth

  // One bar per monitor means one instance per monitor; only the one on the
  // first screen sends notifications. Unknown window/screen counts as primary
  // so a single screen never goes dark.
  readonly property var hostWindow: root.QsWindow ? root.QsWindow.window : null
  readonly property bool primary: {
    var w = root.hostWindow
    var screens = Quickshell.screens
    if (!w || !w.screen || !w.screen.name || !screens || screens.length === 0) return true
    return String(w.screen.name) === String(screens[0].name)
  }
  onPrimaryChanged: injectPanel()

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
    if ("primary" in target) target.primary = root.primary
  }

  implicitWidth: shown ? button.implicitWidth : 0
  implicitHeight: shown ? button.implicitHeight : 0

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: { root.injectPanel(); Qt.callLater(root.injectPanel) }
  }

  IpcHandler {
    target: "synjan.sudo"
    function refresh(): void { root.broadcast("refresh") }
    function status(): string {
      return panelLoader.item ? panelLoader.item.statusReport() : "{\"error\":\"panel not loaded\"}"
    }
    function enable(minutes: string): string {
      if (!root.service) return "no service"
      root.service.enable(minutes)
      return "opening terminal"
    }
    function disable(): string {
      if (!root.service) return "no service"
      if (!root.active) return "already inactive"
      root.service.disable()
      return "opening terminal"
    }
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.togglePanel() }
  }

  Rectangle {
    visible: root.shown && root.alert
    anchors.centerIn: button
    width: button.implicitWidth
    height: Math.max(16, button.implicitHeight - 12)
    radius: height / 2
    color: root.alertColor
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    visible: root.shown
    bar: root.bar
    text: root.vertical ? root.icon : root.displayText
    foreground: root.pillColor
    tooltipText: Model.tooltip(root.active, root.service ? root.service.deadlineMs : 0, root.service ? root.service.now : Date.now(), root.lastError !== "")
    horizontalMargin: 8.75
    verticalPadding: 8.75

    onPressed: function (b) {
      if (b === Qt.MiddleButton) root.broadcast("refresh")
      else root.togglePanel()
    }
  }
}
