import QtQuick
import qs.Commons
import qs.Ui

// The few things worth changing. Chips, one line of hint each.
Column {
  id: view
  property var panel: null

  readonly property color fg: panel ? panel.textColor : Color.popups.text
  readonly property color dim: panel ? panel.dimColor : Color.popups.text
  readonly property string face: panel ? panel.fontName : Style.font.family
  readonly property color accent: panel ? panel.accent : Color.accent

  function val(key, fallback) { return panel ? String(panel.setting(key, fallback)) : String(fallback) }
  // Numbers are compared as numbers: shell.json may hold 15, "15" or 15.0.
  function num(key, fallback) { var n = parseInt(String(panel ? panel.setting(key, fallback) : fallback), 10); return isFinite(n) ? n : fallback }

  spacing: Style.space(10)

  component Chip: Rectangle {
    property string label: ""
    property bool on: false
    signal tapped()
    height: Style.space(24)
    width: chipText.implicitWidth + Style.space(16)
    radius: Style.space(12)
    color: on ? Qt.rgba(view.accent.r, view.accent.g, view.accent.b, 0.12) : "transparent"
    border.width: 1
    border.color: on ? view.accent : Style.hoverBorderColor
    TapHandler { onTapped: parent.tapped() }
    Text {
      id: chipText
      anchors.centerIn: parent
      text: parent.label
      color: parent.on ? view.accent : view.dim
      font.family: view.face
      font.pixelSize: Style.font.caption
    }
  }

  component Hint: Text {
    width: parent.width
    wrapMode: Text.WordWrap
    color: view.dim
    font.family: view.face
    font.pixelSize: Math.max(8, Style.font.caption * 0.9)
  }

  PanelSectionHeader { width: parent.width; text: "STANDARD VARIGHET"; foreground: view.dim }
  Flow {
    width: parent.width; spacing: Style.space(5)
    Repeater {
      model: [5, 15, 30, 60]
      Chip { required property int modelData; label: modelData + " min"; on: view.num("defaultMinutes", 15) === modelData; onTapped: view.panel.persist({ defaultMinutes: modelData }) }
    }
  }
  Hint { text: "Uthevet knapp i panelet, og varigheten IPC-kommandoen enable bruker uten argument. Skriptets egen standard er 15." }

  PanelSectionHeader { width: parent.width; text: "I BAREN NÅR AV"; foreground: view.dim }
  Flow {
    width: parent.width; spacing: Style.space(5)
    Chip { label: "Dempet ikon"; on: view.val("showWhenInactive", true) !== "false"; onTapped: view.panel.persist({ showWhenInactive: true }) }
    Chip { label: "Skjult"; on: view.val("showWhenInactive", true) === "false"; onTapped: view.panel.persist({ showWhenInactive: false }) }
  }
  Hint { text: "Skjult betyr at widgeten bare dukker opp mens passwordless sudo er aktiv." }

  PanelSectionHeader { width: parent.width; text: "VARSEL FØR UTLØP"; foreground: view.dim }
  Flow {
    width: parent.width; spacing: Style.space(5)
    Repeater {
      model: [{ v: 0, label: "Av" }, { v: 30, label: "30 s" }, { v: 60, label: "1 min" }, { v: 120, label: "2 min" }]
      Chip { required property var modelData; label: modelData.label; on: view.num("notifySecondsBefore", 60) === modelData.v; onTapped: view.panel.persist({ notifySecondsBefore: modelData.v }) }
    }
  }
  Hint { text: "Varsler (på/av og før utløp) sendes bare fra primærskjermens instans. Ikonet (`icon`) endres i shell.json-oppføringen for synjan.sudo." }
}
