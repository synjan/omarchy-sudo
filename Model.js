.pragma library

// Pure functions: `systemctl list-timers --output=json` in, display model out.
// No QML in here so tests/model-test.mjs can run it under node.

// [] means the expiry timer is gone, i.e. passwordless sudo is off. In current
// systemd the JSON's "left" mirrors "next" (both epoch µs), so remaining time
// must be computed as next/1000 minus now.
function parseTimers(text, unit) {
  var rows
  try { rows = JSON.parse(text) } catch (e) { return null }
  if (!Array.isArray(rows)) return null
  for (var i = 0; i < rows.length; i++) {
    var row = rows[i]
    if (row && row.unit === unit && isFinite(Number(row.next)) && Number(row.next) > 0)
      return { active: true, deadlineMs: Number(row.next) / 1000 }
  }
  return { active: false, deadlineMs: 0 }
}

function formatCountdown(ms) {
  if (!isFinite(ms) || ms <= 0) return "0:00"
  var total = Math.ceil(ms / 1000)
  var h = Math.floor(total / 3600)
  var m = Math.floor((total % 3600) / 60)
  var s = total % 60
  if (h > 0) return h + "h " + (m < 10 ? "0" : "") + m + "m"
  return m + ":" + (s < 10 ? "0" : "") + s
}

function clockText(deadlineMs) {
  if (!isFinite(deadlineMs) || deadlineMs <= 0) return ""
  var d = new Date(deadlineMs)
  var h = d.getHours(), m = d.getMinutes()
  return (h < 10 ? "0" : "") + h + ":" + (m < 10 ? "0" : "") + m
}

// Red while the window is open — that is the point of the widget. Yellow when
// systemctl itself cannot be read, grey otherwise.
function stateColor(active, error) {
  if (error) return "#e0af68"
  return active ? "#f7768e" : "#7a7f95"
}

function tooltip(active, deadlineMs, now, error) {
  if (error) return "Passwordless sudo: could not read timer state"
  if (!active) return "Passwordless sudo is off — sudo asks for a password"
  return "Passwordless sudo is ON — expires " + clockText(deadlineMs) + " (" + formatCountdown(deadlineMs - now) + " left)"
}

// Notification when the state flips underneath us (menu, CLI, expiry).
// prev === null means first poll: never notify on shell start.
function transitionNotice(prev, active, deadlineMs) {
  if (prev === null || prev === active) return null
  if (active) return { title: "Passwordless sudo enabled", body: "Full root without a password until " + clockText(deadlineMs) + "." }
  return { title: "Passwordless sudo disabled", body: "sudo asks for a password again." }
}

// The durations offered in the panel: the configured default highlighted
// among the usual suspects, sorted, deduplicated.
function durations(defaultMinutes) {
  var list = [defaultMinutes, 15, 30, 60].filter(function (m, i, a) { return isFinite(m) && m >= 1 && a.indexOf(m) === i })
  list.sort(function (a, b) { return a - b })
  return list
}

// Poll output is two lines: the list-timers JSON array, then the timer's
// ActiveEnterTimestamp (empty while inactive). The human-format timestamp is
// local time; Date.parse cannot read it, so it is picked apart by regex.
function parsePoll(text, unit) {
  var lines = String(text).split("\n")
  var state = parseTimers(lines[0] || "", unit)
  if (!state) return null
  state.startedMs = 0
  for (var i = 1; i < lines.length; i++) {
    var m = lines[i].match(/(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2})/)
    if (m) { state.startedMs = new Date(+m[1], +m[2] - 1, +m[3], +m[4], +m[5], +m[6]).getTime(); break }
  }
  return state
}

// The fuse: one tick per minute up to an hour, then a fixed 60 ticks sharing
// the window. Unknown window (no start timestamp) means no fuse at all.
function fuse(windowMs, remainingMs) {
  if (!isFinite(windowMs) || windowMs <= 0) return { count: 0, filled: 0, perMinute: false }
  var minutes = Math.max(1, Math.round(windowMs / 60000))
  var count = Math.min(minutes, 60)
  var tickMs = windowMs / count
  var filled = Math.ceil(Math.max(0, Math.min(remainingMs, windowMs)) / tickMs)
  return { count: count, filled: Math.min(filled, count), perMinute: count === minutes && windowMs >= 60000 }
}

function fuseLabel(windowMs, perMinute) {
  return (perMinute ? "one tick per minute · " : "") + formatCountdown(windowMs) + " window"
}
