// Unit tests for Model.js. Run with tests/run (node, no dependencies).
//
// The tests that matter most here are the timezone ones: an all-day event is
// a floating date and a timed event is an instant, and treating either as the
// other slides the whole agenda onto the wrong day.

const assert = require("node:assert/strict")
const Model = require("../Model.js")

const tests = []
function test(name, fn) { tests.push([name, fn]) }

// ---------------------------------------------------------------------------
// Parsing
// ---------------------------------------------------------------------------

const timedEvent = {
  id: 170737253,
  occurrence_id: "170737253_2026-09-14",
  title: "Product Team Standup",
  all_day: false,
  starts_at: "2026-09-14T16:30:00Z",
  ends_at: "2026-09-14T17:00:00Z",
  location: "",
  calendar: "josh.fabean@bluedroplabs.com",
  color: "blue",
  join_url: "https://stacker.zoom.us/j/83013520324",
  join_title: "Join Zoom",
  url: "https://app.hey.com/calendar/events/170737253/occurrences/2026-09-14/edit",
  status: "needs_action"
}

const allDayTrip = {
  id: 170737312,
  occurrence_id: "",
  title: "Daytona",
  all_day: true,
  starts_at: "2026-09-13T00:00:00Z",
  ends_at: "2026-09-16T00:00:00Z",
  calendar: "Personal",
  color: "blue",
  join_url: "",
  join_title: "",
  url: "https://app.hey.com/calendar/events/170737312/edit",
  status: "accepted"
}

const allDaySingle = {
  id: 172,
  occurrence_id: "",
  title: "Linode Bill Due",
  all_day: true,
  starts_at: "2026-09-30T00:00:00Z",
  ends_at: "2026-09-30T00:00:00Z",
  calendar: "Nextcloud",
  color: "purple",
  join_url: "",
  join_title: "",
  url: "",
  status: ""
}

test("parseEvents reads the CLI's projected array", () => {
  const events = Model.parseEvents(JSON.stringify([timedEvent, allDayTrip]))
  assert.equal(events.length, 2)
  assert.equal(events[0].title, "Product Team Standup")
  assert.equal(events[0].allDay, false)
  assert.equal(events[1].allDay, true)
})

test("parseEvents rejects anything that is not an array of events", () => {
  assert.equal(Model.parseEvents(""), null)
  assert.equal(Model.parseEvents("not json"), null)
  assert.equal(Model.parseEvents('{"ok":true}'), null)
  assert.equal(Model.parseEvents(null), null)
  assert.deepEqual(Model.parseEvents("[]"), [])
})

test("parseEvents drops entries with no start", () => {
  const events = Model.parseEvents(JSON.stringify([{ title: "ghost" }, timedEvent]))
  assert.equal(events.length, 1)
  assert.equal(events[0].title, "Product Team Standup")
})

test("safeUrl passes https and drops everything else", () => {
  assert.equal(Model.safeUrl("https://meet.google.com/abc-defg-hij"), "https://meet.google.com/abc-defg-hij")
  assert.equal(Model.safeUrl("http://example.com"), "")
  assert.equal(Model.safeUrl("javascript:alert(1)"), "")
  assert.equal(Model.safeUrl("file:///etc/passwd"), "")
  assert.equal(Model.safeUrl("https://x.com/a b"), "")
  assert.equal(Model.safeUrl(""), "")
})

test("event text is length-capped", () => {
  const long = Model.normalizeEvent(Object.assign({}, timedEvent, { title: "x".repeat(5000) }))
  assert.equal(long.title.length, 256)
})

// ---------------------------------------------------------------------------
// Day placement — the timezone-sensitive half
// ---------------------------------------------------------------------------

test("an all-day event lands on its own date regardless of timezone", () => {
  // Read as an instant, 2026-09-30T00:00:00Z is the 29th anywhere west of
  // Greenwich. It has to stay the 30th.
  const [event] = Model.parseEvents(JSON.stringify([allDaySingle]))
  assert.deepEqual(Model.eventDayKeys(event), ["2026-09-30"])
})

test("a multi-day all-day event spans its days with an exclusive end", () => {
  // HEY writes the 13th–15th as starts 13, ends 16.
  const [event] = Model.parseEvents(JSON.stringify([allDayTrip]))
  assert.deepEqual(Model.eventDayKeys(event), ["2026-09-13", "2026-09-14", "2026-09-15"])
})

test("a timed event lands on its local day", () => {
  const [event] = Model.parseEvents(JSON.stringify([timedEvent]))
  const expected = Model.keyForDate(new Date(Date.parse("2026-09-14T16:30:00Z")))
  assert.deepEqual(Model.eventDayKeys(event), [expected])
})

// A timed event is an instant, so the local day it falls on moves with the
// zone. Where a test needs two events on one named day, it has to say that in
// local wall-clock terms rather than in UTC.
function atLocal(hours, minutes) {
  return new Date(2026, 8, 14, hours, minutes).toISOString()
}

test("eventsForDay sorts all-day first, then by start", () => {
  const late = Object.assign({}, timedEvent, { id: 2, title: "Late", starts_at: atLocal(20, 0), ends_at: atLocal(21, 0) })
  const early = Object.assign({}, timedEvent, { id: 3, title: "Early", starts_at: atLocal(9, 0), ends_at: atLocal(10, 0) })
  const events = Model.parseEvents(JSON.stringify([late, early, allDayTrip]))
  const day = Model.eventsForDay(events, "2026-09-14")
  assert.deepEqual(day.map(e => e.title), ["Daytona", "Early", "Late"])
})

test("weekDays keeps empty days", () => {
  const events = Model.parseEvents(JSON.stringify([allDaySingle]))
  const days = Model.weekDays(events, "2026-09-28", "2026-09-30")
  assert.equal(days.length, 7)
  assert.deepEqual(days.map(d => d.count), [0, 0, 1, 0, 0, 0, 0])
  assert.equal(days[2].today, true)
  assert.equal(days[0].past, true)
  assert.equal(days[3].past, false)
})

test("weekStartKey snaps to Monday, the week HEY answers", () => {
  assert.equal(Model.weekStartKey("2026-09-04"), "2026-08-31") // Friday → Monday
  assert.equal(Model.weekStartKey("2026-08-31"), "2026-08-31") // Monday → itself
  assert.equal(Model.weekStartKey("2026-09-06"), "2026-08-31") // Sunday → same week
})

test("addDays crosses months and years", () => {
  assert.equal(Model.addDays("2026-08-31", 1), "2026-09-01")
  assert.equal(Model.addDays("2026-12-31", 1), "2027-01-01")
  assert.equal(Model.addDays("2026-03-01", -1), "2026-02-28")
})

// ---------------------------------------------------------------------------
// Now
// ---------------------------------------------------------------------------

const noon = Date.parse("2026-09-14T16:45:00Z") // inside the standup

test("isNow and hasEnded bracket a timed event", () => {
  const [event] = Model.parseEvents(JSON.stringify([timedEvent]))
  assert.equal(Model.isNow(event, noon), true)
  assert.equal(Model.hasEnded(event, noon), false)
  assert.equal(Model.hasEnded(event, Date.parse("2026-09-14T17:00:00Z")), true)
  assert.equal(Model.isNow(event, Date.parse("2026-09-14T15:00:00Z")), false)
})

test("an all-day event is never 'now' and never 'ended'", () => {
  const [event] = Model.parseEvents(JSON.stringify([allDayTrip]))
  assert.equal(Model.isNow(event, noon), false)
  assert.equal(Model.hasEnded(event, noon), false)
})

test("currentOrNextEvent prefers the meeting you are in", () => {
  const later = Object.assign({}, timedEvent, { id: 9, title: "Later", starts_at: "2026-09-14T18:00:00Z", ends_at: "2026-09-14T19:00:00Z" })
  const events = Model.parseEvents(JSON.stringify([later, timedEvent]))
  assert.equal(Model.currentOrNextEvent(events, noon).title, "Product Team Standup")
})

test("currentOrNextEvent falls to the next one once it ends", () => {
  const later = Object.assign({}, timedEvent, { id: 9, title: "Later", starts_at: "2026-09-14T18:00:00Z", ends_at: "2026-09-14T19:00:00Z" })
  const events = Model.parseEvents(JSON.stringify([later, timedEvent]))
  assert.equal(Model.currentOrNextEvent(events, Date.parse("2026-09-14T17:30:00Z")).title, "Later")
})

test("an all-day event only reaches the bar when no timed one is left", () => {
  const events = Model.parseEvents(JSON.stringify([allDayTrip, timedEvent]))
  assert.equal(Model.currentOrNextEvent(events, Date.parse("2026-09-14T09:00:00Z")).title, "Product Team Standup")
  assert.equal(Model.currentOrNextEvent(events, Date.parse("2026-09-14T23:00:00Z")).title, "Daytona")
})

test("currentOrNextEvent survives an empty day", () => {
  assert.equal(Model.currentOrNextEvent([], noon), null)
  assert.equal(Model.currentOrNextEvent(null, noon), null)
})

// ---------------------------------------------------------------------------
// Formatting
// ---------------------------------------------------------------------------

test("formatTime is compact in both conventions", () => {
  const at = (h, m) => new Date(2026, 8, 14, h, m)
  assert.equal(Model.formatTime(at(16, 30), false), "4:30p")
  assert.equal(Model.formatTime(at(16, 30), true), "16:30")
  assert.equal(Model.formatTime(at(0, 5), false), "12:05a")
  assert.equal(Model.formatTime(at(12, 0), false), "12:00p")
  assert.equal(Model.formatTime(at(9, 0), true), "09:00")
})

test("truncate trims at a word boundary when one is near", () => {
  assert.equal(Model.truncate("short", 24), "short")
  // Cut at the space, then the dangling colon goes too.
  assert.equal(Model.truncate("Product Team Standup: strategy + sprint planning", 24), "Product Team Standup…")
  assert.equal(Model.truncate("x".repeat(40), 24), "x".repeat(23) + "…")
})

test("imminentEvent fires inside the lead window and not before", () => {
  const [event] = Model.parseEvents(JSON.stringify([timedEvent]))
  const start = Date.parse("2026-09-14T16:30:00Z")
  // 20 minutes out, with a 15-minute lead: nothing yet.
  assert.equal(Model.imminentEvent([event], start - 20 * 60000, 15), null)
  // 10 minutes out: the icon lights.
  assert.equal(Model.imminentEvent([event], start - 10 * 60000, 15).title, "Product Team Standup")
})

test("imminentEvent stays lit while the event runs, and goes out after", () => {
  const [event] = Model.parseEvents(JSON.stringify([timedEvent]))
  assert.equal(Model.imminentEvent([event], noon, 15).title, "Product Team Standup")
  assert.equal(Model.imminentEvent([event], Date.parse("2026-09-14T17:00:00Z"), 15), null)
})

test("imminentEvent ignores all-day events entirely", () => {
  const [trip] = Model.parseEvents(JSON.stringify([allDayTrip]))
  assert.equal(Model.imminentEvent([trip], noon, 15), null)
  assert.equal(Model.imminentEvent([trip], noon, 240), null)
})

test("a zero lead turns the icon off", () => {
  const [event] = Model.parseEvents(JSON.stringify([timedEvent]))
  assert.equal(Model.imminentEvent([event], noon, 0), null)
})

test("imminentEvent picks the soonest of several in the window", () => {
  const start = Date.parse("2026-09-14T16:30:00Z")
  const later = Object.assign({}, timedEvent, { id: 9, title: "Later", starts_at: "2026-09-14T16:40:00Z", ends_at: "2026-09-14T17:40:00Z" })
  const events = Model.parseEvents(JSON.stringify([later, timedEvent]))
  assert.equal(Model.imminentEvent(events, start - 5 * 60000, 15).title, "Product Team Standup")
})

test("normalizedAlertLead clamps and defaults", () => {
  assert.equal(Model.normalizedAlertLead(15), 15)
  assert.equal(Model.normalizedAlertLead(0), 0)
  assert.equal(Model.normalizedAlertLead(-5), 15)
  assert.equal(Model.normalizedAlertLead("nope"), 15)
  assert.equal(Model.normalizedAlertLead(9999), 240)
})

test("minutesUntil counts down, then goes negative once under way", () => {
  const [event] = Model.parseEvents(JSON.stringify([timedEvent]))
  const start = Date.parse("2026-09-14T16:30:00Z")
  assert.equal(Model.minutesUntil(event, start - 12 * 60000), 12)
  assert.equal(Model.minutesUntil(event, start), 0)
  assert.ok(Model.minutesUntil(event, noon) < 0)
})

test("eventRangeLabel spells out both ends", () => {
  const [event] = Model.parseEvents(JSON.stringify([timedEvent]))
  const from = Model.formatTime(new Date(Date.parse("2026-09-14T16:30:00Z")), true)
  const to = Model.formatTime(new Date(Date.parse("2026-09-14T17:00:00Z")), true)
  assert.equal(Model.eventRangeLabel(event, true), from + " – " + to)
  const [trip] = Model.parseEvents(JSON.stringify([allDayTrip]))
  assert.equal(Model.eventRangeLabel(trip, true), "All day")
})

test("calendarLabel shortens a subscribed address to its local part", () => {
  assert.equal(Model.calendarLabel("josh.fabean@bluedroplabs.com"), "josh.fabean")
  assert.equal(Model.calendarLabel("Personal"), "Personal")
  assert.equal(Model.calendarLabel("Josh @ Work"), "Josh @ Work")
})

test("calendarColor maps HEY's names and falls back for the rest", () => {
  assert.equal(Model.calendarColor("purple", "#fallback"), "#8b6fc4")
  assert.equal(Model.calendarColor("PURPLE", "#fallback"), "#8b6fc4")
  assert.equal(Model.calendarColor("", "#fallback"), "#fallback")
  assert.equal(Model.calendarColor("chartreuse", "#fallback"), "#fallback")
})

// ---------------------------------------------------------------------------
// Commands
// ---------------------------------------------------------------------------

test("weekCommand passes the date and filter as arguments, never as syntax", () => {
  const command = Model.weekCommand("2026-09-14")
  assert.equal(command[0], "bash")
  assert.equal(command[1], "-c")
  assert.match(command[2], /^timeout -k \d+ \d+ hey event week "\$1"/)
  assert.match(command[2], /head -c \d+$/)
  assert.equal(command[4], "2026-09-14")
  assert.equal(command[5], Model.weekJqProjection)
})

test("weekCommand keeps a hostile date out of the shell", () => {
  const command = Model.weekCommand('$(touch /tmp/pwned); "')
  // It lands in argv, not in the script.
  assert.equal(command[4], '$(touch /tmp/pwned); "')
  assert.equal(command[2].indexOf("pwned"), -1)
})

test("normalizedRefreshInterval clamps to something a bar can live with", () => {
  assert.equal(Model.normalizedRefreshInterval(300), 300)
  assert.equal(Model.normalizedRefreshInterval(5), 300)
  assert.equal(Model.normalizedRefreshInterval("abc"), 300)
  assert.equal(Model.normalizedRefreshInterval(99999), 3600)
  assert.equal(Model.normalizedRefreshInterval(60), 60)
})

test("the bar format ring walks and wraps without repeating", () => {
  const ring = Model.formatRing("dddd HH:mm", Model.barFormats(false))
  assert.equal(new Set(ring).size, ring.length)
  let seen = "dddd HH:mm"
  for (let i = 0; i < ring.length; i++) seen = Model.nextFormat(ring, seen)
  assert.equal(seen, "dddd HH:mm")
})

test("the ring is the stock clock's, so the bar cycles like the bar it replaces", () => {
  assert.deepEqual(Model.barFormats(false).slice(0, 4),
    ["dddd HH:mm", "dddd h:mm AP", "HH:mm", "h:mm AP"])
})

test("a hand-written format joins the ring rather than being lost", () => {
  const ring = Model.formatRing("yyyy/MM/dd", Model.barFormats(false))
  assert.ok(ring.indexOf("yyyy/MM/dd") !== -1)
})

// ---------------------------------------------------------------------------
// Calendar grid
// ---------------------------------------------------------------------------

test("monthGrid is always six rows of seven", () => {
  const weeks = Model.monthGrid(2026, 1, 1, "2026-02-10", {})
  assert.equal(weeks.length, 6)
  for (const week of weeks) assert.equal(week.days.length, 7)
})

test("monthGrid carries event counts onto its days", () => {
  const counts = { "2026-09-14": 3 }
  const weeks = Model.monthGrid(2026, 8, 1, "2026-09-04", counts)
  const day = weeks.flatMap(w => w.days).find(d => d.key === "2026-09-14")
  assert.equal(day.events, 3)
  const empty = weeks.flatMap(w => w.days).find(d => d.key === "2026-09-15")
  assert.equal(empty.events, 0)
})

test("eventCounts counts every day a span touches", () => {
  const events = Model.parseEvents(JSON.stringify([allDayTrip, allDaySingle]))
  const counts = Model.eventCounts(events)
  assert.equal(counts["2026-09-13"], 1)
  assert.equal(counts["2026-09-15"], 1)
  assert.equal(counts["2026-09-16"], undefined)
  assert.equal(counts["2026-09-30"], 1)
})

test("isoWeek matches the ISO-8601 definition at the year boundary", () => {
  assert.equal(Model.isoWeek(2026, 0, 1), 1)
  assert.equal(Model.isoWeek(2025, 11, 29), 1)
  assert.equal(Model.isoWeek(2026, 11, 31), 53)
})

test("week start normalizes names, numbers and nonsense", () => {
  assert.equal(Model.normalizedWeekStart("monday", 0), 1)
  assert.equal(Model.normalizedWeekStart("sun", 1), 0)
  assert.equal(Model.normalizedWeekStart(null, 0), 0)
  assert.equal(Model.normalizedWeekStart("banana", 1), 1)
  assert.equal(Model.toggledWeekStart(1), 0)
  assert.equal(Model.toggledWeekStart(0), 1)
})

test("year progress runs 0 to just under 100", () => {
  assert.equal(Model.yearProgressPercent(2026, 0, 1), 0)
  assert.equal(Model.yearProgressPercent(2026, 11, 31), 100)
  assert.ok(Model.yearProgress(2026, 5, 15) > 0.4)
})

// ---------------------------------------------------------------------------

let failed = 0
for (const [name, fn] of tests) {
  try {
    fn()
    console.log("  ok   " + name)
  } catch (error) {
    failed++
    console.log("  FAIL " + name)
    console.log("       " + String(error.message).split("\n").join("\n       "))
  }
}
console.log("")
console.log(`${tests.length - failed}/${tests.length} passing  (TZ=${process.env.TZ || "system"})`)
process.exit(failed === 0 ? 0 : 1)
