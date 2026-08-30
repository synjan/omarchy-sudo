import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Status with a large countdown, then the actions. Every action opens the
// same floating terminal the menu uses — password and confirmation happen
// there, never in the shell.
Panel {
  id: root
  moduleName: "synjan.sudo"
  ipcTarget: "synjan.sudo"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  readonly property var service: svc
  property string view: "main"   // main | settings

  function openSettings() { view = view === "settings" ? "main" : "settings" }
  function refresh() { svc.refresh() }
  function persist(changes) { if (hostWidget && hostWidget.persist) hostWidget.persist(changes) }

  function statusReport() {
    return JSON.stringify({
      active: svc.active,
      deadline: svc.active ? new Date(svc.deadlineMs).toISOString() : "",
      remaining: svc.active ? Model.formatCountdown(svc.deadlineMs - svc.now) : "",
      error: svc.lastError, known: svc.known,
      opened: root.opened, view: root.view, primary: root.primary
    })
  }

  onOpenedChanged: if (!opened) view = "main"

  property bool primary: true
  Service { id: svc; settings: root.settings; primary: root.primary; panelOpen: root.opened }

  readonly property color textColor: root.bar ? root.bar.foreground : Color.popups.text
  readonly property color dimColor: Qt.darker(textColor, 1.45)
  readonly property string fontName: root.bar ? root.bar.fontFamily : Style.font.family
  readonly property color accent: Color.accent
  readonly property color stateColor: Model.stateColor(svc.active, svc.lastError !== "")
  readonly property color badColor: "#f7768e"

  readonly property var durations: Model.durations(svc.defaultMinutes)

  readonly property string statusLine: {
    if (svc.lastError) return "systemctl feilet"
    if (!svc.known) return "Leser …"
    return Qt.formatDateTime(new Date(svc.now), "HH:mm:ss")
  }

  component Chip: Rectangle {
    property string label: ""
    property bool on: false
    property color tint: root.accent
    property bool usable: true
    signal tapped()
    height: Style.space(24)
    width: chipText.implicitWidth + Style.space(16)
    radius: Style.space(12)
    opacity: usable ? 1 : 0.45
    color: on ? Qt.rgba(tint.r, tint.g, tint.b, 0.12) : (chipHover.hovered ? Style.hoverFill : "transparent")
    border.width: 1
    border.color: on ? tint : Style.hoverBorderColor
    HoverHandler { id: chipHover }
    TapHandler { onTapped: if (parent.usable) parent.tapped() }
    Text {
      id: chipText
      anchors.centerIn: parent
      text: parent.label
      color: parent.on ? parent.tint : root.textColor
      font.family: root.fontName
      font.pixelSize: Style.font.caption
    }
  }

  component Dim: Text {
    wrapMode: Text.WordWrap
    color: root.dimColor
    font.family: root.fontName
    font.pixelSize: Math.max(8, Style.font.caption * 0.9)
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.view === "settings" ? root.openSettings() : root.close()
      onTabRequested: function (direction) { root.switchPanel(direction) }

      Column {
        id: content
        width: parent.width
        spacing: Style.space(9)

        // ---- header --------------------------------------------------------
        Item {
          width: parent.width
          height: heading.implicitHeight + Style.space(2)
          Rectangle {
            id: dot
            anchors.left: parent.left
            anchors.verticalCenter: heading.verticalCenter
            width: Style.space(8); height: width; radius: width / 2
            color: root.stateColor
          }
          Text {
            id: heading
            anchors.left: dot.right
            anchors.leftMargin: Style.space(8)
            anchors.right: gear.left
            elide: Text.ElideRight
            text: root.view === "settings" ? "Passwordless sudo · Innstillinger" : "Passwordless sudo"
            color: root.textColor
            font.family: root.fontName
            font.pixelSize: Style.font.subtitle
            font.bold: true
          }
          Text {
            id: gear
            anchors.right: refreshIcon.left
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: heading.verticalCenter
            text: ""
            color: root.view === "settings" ? root.accent : root.dimColor
            font.family: root.fontName
            font.pixelSize: Style.font.caption
            TapHandler { onTapped: root.openSettings() }
          }
          Text {
            id: refreshIcon
            anchors.right: parent.right
            anchors.verticalCenter: heading.verticalCenter
            text: " " + root.statusLine
            color: root.dimColor
            font.family: root.fontName
            font.pixelSize: Style.font.caption
            TapHandler { onTapped: svc.refresh() }
          }
        }

        Loader {
          width: parent.width
          active: root.view === "settings"
          visible: active
          sourceComponent: SettingsView { panel: root }
        }

        Dim { width: parent.width; visible: root.view === "main" && svc.lastError !== ""; text: svc.lastError; color: root.badColor }

        // ---- status --------------------------------------------------------
        Column {
          width: parent.width
          spacing: Style.space(3)
          visible: root.view === "main"
          Text {
            width: parent.width
            text: svc.active ? Model.formatCountdown(svc.deadlineMs - svc.now) : "Inaktiv"
            color: svc.active ? root.badColor : root.textColor
            font.family: root.fontName
            font.pixelSize: Style.font.subtitle * 1.6
            font.bold: true
          }
          Dim {
            width: parent.width
            text: svc.active
              ? "Full root uten passord for alt som kjører som deg — utløper " + Model.clockText(svc.deadlineMs) + ", så slettes sudoers-fila av systemd-timeren."
              : "sudo krever passord. Aktivering åpner root uten passord i et avgrenset tidsrom (omarchy-sudo-passwordless)."
          }
        }

        // ---- actions -------------------------------------------------------
        PanelSectionHeader { width: parent.width; visible: root.view === "main"; text: svc.active ? "NY PERIODE FRA NÅ" : "AKTIVER"; foreground: root.dimColor }
        Flow {
          width: parent.width
          spacing: Style.space(5)
          visible: root.view === "main"
          Repeater {
            model: root.durations
            Chip {
              required property int modelData
              label: (svc.active ? " " : " ") + modelData + " min"
              on: modelData === svc.defaultMinutes
              onTapped: svc.enable(modelData)
            }
          }
          Chip {
            visible: svc.active
            label: " Deaktiver nå"
            tint: root.badColor
            on: true
            onTapped: svc.disable()
          }
        }

        Dim {
          width: parent.width
          visible: root.view === "main"
          text: "Knappene åpner en flytende terminal — passord og bekreftelse skjer der, pluginen rører aldri sudoers selv. Esc lukker · midtklikk i baren oppdaterer."
        }
      }
    }
  }
}
