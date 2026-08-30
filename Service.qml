import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

// Data layer: polls the transient expiry timer that omarchy-sudo-passwordless
// creates. The sudoers file itself is root-only; the timer is the readable
// signal, and it is exactly what the toggle script trusts for its own stale
// check. No UI in here.
Item {
  id: service
  visible: false

  property var settings: ({})
  // One bar per monitor means one Service per monitor. systemctl is local and
  // cheap so every instance polls for itself; only the primary notifies.
  property bool primary: true
  property bool panelOpen: false
  onPanelOpenChanged: if (panelOpen) refresh()

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }
  function intSetting(name, fallback, minimum, maximum) {
    var value = parseInt(String(setting(name, fallback)), 10)
    if (!isFinite(value)) value = fallback
    return Math.max(minimum, Math.min(maximum, value))
  }

  readonly property int defaultMinutes: intSetting("defaultMinutes", 15, 1, 480)
  readonly property int notifySecondsBefore: intSetting("notifySecondsBefore", 60, 0, 900)

  readonly property string timerUnit: "omarchy-nopasswd-expire-" + Quickshell.env("USER") + ".timer"

  property bool active: false
  property double deadlineMs: 0
  property double startedMs: 0
  // Length of the current window, for the fuse. 0 while unknown.
  readonly property double windowMs: active && startedMs > 0 && deadlineMs > startedMs ? deadlineMs - startedMs : 0
  // First successful poll done; before that the state is unknown and no
  // transition notification may fire.
  property bool known: false
  property string lastError: ""
  property double now: Date.now()
  property double fastUntil: 0
  property double warnedDeadline: 0

  readonly property double remainingMs: active ? deadlineMs - now : 0

  function refresh() {
    if (pollProc.running) return
    pollProc.running = true
  }

  // enable/extend and disable all go through the same floating terminal the
  // SUPER+SPACE menu uses: the terminal owns the password prompt and the
  // confirm dialog; this plugin never touches sudoers itself. Without a
  // minutes argument the script disables when the window is open.
  function enable(minutes) {
    var m = parseInt(String(minutes), 10)
    if (!isFinite(m) || m < 1) m = defaultMinutes
    Quickshell.execDetached(["omarchy-launch-floating-terminal-with-presentation", "omarchy-sudo-passwordless", String(m)])
    watchForChange()
  }
  function disable() {
    Quickshell.execDetached(["omarchy-launch-floating-terminal-with-presentation", "omarchy-sudo-passwordless"])
    watchForChange()
  }
  // The user is typing a password in that terminal; poll fast until the state
  // flips or a minute passes.
  function watchForChange() {
    fastUntil = Date.now() + 60000
    fastTimer.restart()
  }

  Process {
    id: pollProc
    command: ["bash", "-c",
      "systemctl list-timers '" + service.timerUnit + "' --output=json; " +
      "systemctl show '" + service.timerUnit + "' -p ActiveEnterTimestamp --value"]
    stdout: StdioCollector { id: pollOut; waitForEnd: true }
    stderr: StdioCollector { id: pollErr; waitForEnd: true }
    onExited: function (code) {
      if (code !== 0) {
        var detail = String(pollErr.text || "").trim()
        service.lastError = detail ? detail.split("\n").pop() : "systemctl failed (" + code + ")"
        return
      }
      var state = Model.parsePoll(String(pollOut.text || ""), service.timerUnit)
      if (!state) { service.lastError = "unexpected systemctl output"; return }
      service.lastError = ""
      service.now = Date.now()
      var prev = service.known ? service.active : null
      service.known = true
      service.active = state.active
      // A fresh deadline (activation or extension) re-arms the expiry warning.
      if (state.deadlineMs !== service.deadlineMs) service.warnedDeadline = 0
      service.deadlineMs = state.deadlineMs
      service.startedMs = state.startedMs
      if (prev !== null && prev !== state.active) service.fastUntil = 0
      if (service.primary) {
        var notice = Model.transitionNotice(prev, state.active, state.deadlineMs)
        if (notice) Quickshell.execDetached(["omarchy-notification-send", notice.title, notice.body])
      }
    }
  }

  function checkExpiryWarning() {
    if (!primary || !active || notifySecondsBefore <= 0) return
    var left = deadlineMs - now
    if (left > 0 && left <= notifySecondsBefore * 1000 && warnedDeadline !== deadlineMs) {
      warnedDeadline = deadlineMs
      Quickshell.execDetached(["omarchy-notification-send", "Passwordless sudo expires soon",
        Model.formatCountdown(left) + " left — extend from the panel if you need more."])
    }
  }

  // 1 s tick drives the countdown; only needed while it is counting down.
  // Suspend/resume can shift a monotonic deadline, so the periodic poll below
  // re-reads it rather than trusting this clock alone.
  Timer {
    interval: 1000
    running: service.active
    repeat: true
    onTriggered: {
      service.now = Date.now()
      service.checkExpiryWarning()
      // Right after the deadline the timer fires and removes itself; confirm.
      if (service.now > service.deadlineMs) service.refresh()
    }
  }

  Timer {
    interval: service.active ? 5000 : 30000
    running: true
    repeat: true
    onTriggered: service.refresh()
  }

  Timer {
    id: fastTimer
    interval: 2000
    repeat: true
    onTriggered: {
      if (Date.now() > service.fastUntil) { fastTimer.stop(); return }
      service.refresh()
    }
  }

  Component.onCompleted: Qt.callLater(refresh)
}
