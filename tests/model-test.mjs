// Unit tests for Model.js. Model.js is plain QML-flavoured JS with no module
// system, so it is loaded by evaluating the source and pulling the functions
// back out. Run: node tests/model-test.mjs
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const here = dirname(fileURLToPath(import.meta.url));
const source = readFileSync(join(here, "..", "Model.js"), "utf8").replace(".pragma library", "");
const exported = ["parseTimers", "formatCountdown", "clockText", "stateColor", "tooltip", "transitionNotice", "durations"];
const M = new Function(`${source}\nreturn { ${exported.join(", ")} };`)();

let checks = 0;
const failures = [];
function ok(c, msg) { checks += 1; if (!c) failures.push(msg); }
function eq(a, b, msg) { const x = JSON.stringify(a), y = JSON.stringify(b); ok(x === y, `${msg} — expected ${y}, got ${x}`); }

const UNIT = "omarchy-nopasswd-expire-synjan.timer";
// Verbatim from `systemctl list-timers <unit> --output=json` on this machine.
const REAL = '[{"next":1788125548620226,"left":1788125548620226,"last":0,"passed":0,"unit":"omarchy-nopasswd-expire-synjan.timer","activates":"omarchy-nopasswd-expire-synjan.service"}]';

// ---------------------------------------------------------------------------
// parseTimers
// ---------------------------------------------------------------------------
eq(M.parseTimers(REAL, UNIT), { active: true, deadlineMs: 1788125548620.226 }, "parseTimers: real row");
eq(M.parseTimers("[]", UNIT), { active: false, deadlineMs: 0 }, "parseTimers: empty list means off");
eq(M.parseTimers(REAL, "annen.timer"), { active: false, deadlineMs: 0 }, "parseTimers: other unit filtered out");
ok(M.parseTimers("{", UNIT) === null, "parseTimers: garbage");
ok(M.parseTimers("{}", UNIT) === null, "parseTimers: object is not a list");
eq(M.parseTimers('[{"unit":"' + UNIT + '","next":0}]', UNIT), { active: false, deadlineMs: 0 }, "parseTimers: next=0 is not a deadline");
eq(M.parseTimers('[{"unit":"' + UNIT + '","next":"nei"}]', UNIT), { active: false, deadlineMs: 0 }, "parseTimers: non-numeric next");

// ---------------------------------------------------------------------------
// formatCountdown — seconds are ceiled so the bar never shows 0:00 early.
// ---------------------------------------------------------------------------
eq(M.formatCountdown(-5), "0:00", "countdown: negative");
eq(M.formatCountdown(0), "0:00", "countdown: zero");
eq(M.formatCountdown(NaN), "0:00", "countdown: NaN");
eq(M.formatCountdown(500), "0:01", "countdown: half a second still counts");
eq(M.formatCountdown(42000), "0:42", "countdown: under a minute");
eq(M.formatCountdown(59500), "1:00", "countdown: ceil across the minute");
eq(M.formatCountdown(15 * 60000), "15:00", "countdown: quarter of an hour");
eq(M.formatCountdown(3600000), "1h 00m", "countdown: exactly one hour");
eq(M.formatCountdown(3661000), "1h 01m", "countdown: seconds dropped in the hour form");
eq(M.formatCountdown(8 * 3600000), "8h 00m", "countdown: max window");

// ---------------------------------------------------------------------------
// clockText / stateColor / tooltip
// ---------------------------------------------------------------------------
const NOON = new Date(2026, 7, 30, 12, 5, 0).getTime();
eq(M.clockText(NOON), "12:05", "clockText: local zero-padded minutes");
eq(M.clockText(0), "", "clockText: no deadline");
eq(M.stateColor(true, false), "#f7768e", "stateColor: active is red");
eq(M.stateColor(false, false), "#7a7f95", "stateColor: inactive is grey");
eq(M.stateColor(false, true), "#e0af68", "stateColor: error is yellow");
ok(M.tooltip(false, 0, NOON, false).indexOf("asks for a password") > 0, "tooltip: inactive");
ok(M.tooltip(true, NOON + 600000, NOON, false).indexOf("10:00 left") > 0, "tooltip: countdown included");
ok(M.tooltip(true, NOON, NOON, true).indexOf("could not") > 0, "tooltip: error wins");

// ---------------------------------------------------------------------------
// transitionNotice — null on first poll and on no change.
// ---------------------------------------------------------------------------
ok(M.transitionNotice(null, true, NOON) === null, "notice: first poll never notifies");
ok(M.transitionNotice(true, true, NOON) === null, "notice: unchanged");
ok(M.transitionNotice(false, true, NOON).title.indexOf("enabled") > 0, "notice: turned on");
ok(M.transitionNotice(false, true, NOON).body.indexOf("12:05") > 0, "notice: deadline in body");
ok(M.transitionNotice(true, false, 0).title.indexOf("disabled") > 0, "notice: turned off");

// ---------------------------------------------------------------------------
// durations — default injected, sorted, deduplicated.
// ---------------------------------------------------------------------------
eq(M.durations(15), [15, 30, 60], "durations: default already present");
eq(M.durations(5), [5, 15, 30, 60], "durations: default injected first");
eq(M.durations(45), [15, 30, 45, 60], "durations: default sorted into place");
eq(M.durations(NaN), [15, 30, 60], "durations: broken default ignored");

if (failures.length) {
  for (const f of failures) console.error("FAIL:", f);
  console.error(`${failures.length}/${checks} checks failed`);
  process.exit(1);
}
console.log(`${checks} checks passed`);
