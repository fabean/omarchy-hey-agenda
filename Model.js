// Pure data and date math for the HEY Agenda widget and its panel.
//
// Everything here is Qt-free so it can be unit tested under node (tests/run);
// the QML owns month and weekday naming through Qt.locale(), and the panel
// owns every pixel.
//
// The calendar-grid half of this file (week starts, ISO weeks, the month grid,
// the year and life meters) is Omarchy's own clock model, MIT licensed and
// reproduced so this widget keeps the stock calendar's behaviour exactly.
// See THIRD_PARTY_NOTICES.md.

var MS_PER_DAY = 86400000

// ---------------------------------------------------------------------------
// HEY CLI
// ---------------------------------------------------------------------------

// One week per call. `hey event week` is HEY's own expansion of the week a
// date falls in — repeating series already unrolled into the days they land
// on — which is the same set the app draws, so today's agenda is a filter of
// the week rather than a second request.
var weekJqProjection = ".data | map({"
  + "id: .id,"
  + " occurrence_id: (.occurrence_id // \"\"),"
  + " title: (.title // .summary // \"(untitled)\"),"
  + " all_day: (.all_day // false),"
  + " starts_at: (.starts_at // \"\"),"
  + " ends_at: (.ends_at // \"\"),"
  + " location: (.location // \"\"),"
  + " calendar: (.calendar.name // \"Personal\"),"
  + " color: (.calendar.color // \"\"),"
  + " join_url: (.join_link.url // \"\"),"
  + " join_title: (.join_link.title // \"\"),"
  + " url: (.edit_url // \"\"),"
  + " status: (.attendance_status // \"\")"
  + "})"

var cliTimeoutSeconds = 20
var cliKillGraceSeconds = 3
var cliOutputByteLimit = 1024 * 1024
var maximumEventCount = 500

// `timeout` bounds a CLI that never answers and `head -c` bounds one that
// answers forever, so neither can wedge or balloon the shared shell process.
// The date and the filter are passed as arguments rather than interpolated,
// so nothing built here can be read as shell syntax.
var weekScript = "timeout -k " + cliKillGraceSeconds + " " + cliTimeoutSeconds
  + " hey event week \"$1\" --json --all --jq \"$2\" 2>/dev/null"
  + " | head -c " + (cliOutputByteLimit + 1)

function weekCommand(dayKey) {
  return ["bash", "-c", weekScript, "hey-agenda", String(dayKey || ""), weekJqProjection]
}

// A version probe doubles as the "is it installed and signed in?" check: an
// unauthenticated CLI still answers `--version`, but the week call above then
// comes back empty, which is what the panel reports.
function versionCommand() {
  return ["bash", "-c", "timeout 5 hey --version 2>/dev/null | head -c 200", "hey-agenda"]
}

// ---------------------------------------------------------------------------
// Parsing
// ---------------------------------------------------------------------------

function boundedString(value, limit) {
  var text = String(value === undefined || value === null ? "" : value)
  return text.length > limit ? text.substr(0, limit) : text
}

// The CLI is trusted to be the CLI, but the calendars behind it are not: an
// event title, location or calendar name is text somebody else wrote, so
// every string that reaches a binding is length-capped here and rendered as
// PlainText there.
function normalizeEvent(raw) {
  if (!raw || typeof raw !== "object") return null

  var startsAt = boundedString(raw.starts_at, 64)
  if (startsAt === "") return null

  var allDay = raw.all_day === true
  return {
    id: boundedString(raw.occurrence_id, 96) || boundedString(raw.id, 32),
    seriesId: boundedString(raw.id, 32),
    title: boundedString(raw.title, 256) || "(untitled)",
    allDay: allDay,
    startsAt: startsAt,
    endsAt: boundedString(raw.ends_at, 64) || startsAt,
    location: boundedString(raw.location, 256),
    calendar: boundedString(raw.calendar, 128),
    color: boundedString(raw.color, 32),
    joinUrl: safeUrl(raw.join_url),
    joinTitle: boundedString(raw.join_title, 64),
    url: safeUrl(raw.url),
    status: boundedString(raw.status, 32),
    // Resolved once, here, so nothing downstream has to remember that an
    // all-day event is a floating date rather than an instant.
    startMs: allDay ? null : parseInstant(startsAt),
    endMs: allDay ? null : parseInstant(raw.ends_at || startsAt)
  }
}

// Only ever handed to a browser launcher, so anything that is not plainly a
// web URL is dropped rather than passed along.
function safeUrl(value) {
  var text = boundedString(value, 2048).replace(/^\s+|\s+$/g, "")
  return /^https:\/\/[^\s"'<>\\]+$/.test(text) ? text : ""
}

function parseInstant(value) {
  var ms = Date.parse(String(value || ""))
  return isFinite(ms) ? ms : null
}

function parseEvents(raw) {
  var text = String(raw === undefined || raw === null ? "" : raw).replace(/^\s+|\s+$/g, "")
  if (text === "" || text.length > cliOutputByteLimit) return null

  var parsed
  try {
    parsed = JSON.parse(text)
  } catch (e) {
    return null
  }
  if (!Array.isArray(parsed)) return null

  var events = []
  for (var i = 0; i < parsed.length && events.length < maximumEventCount; i++) {
    var event = normalizeEvent(parsed[i])
    if (event) events.push(event)
  }
  return events
}

// ---------------------------------------------------------------------------
// Days
// ---------------------------------------------------------------------------

function pad2(value) {
  var n = Number(value)
  return (n < 10 ? "0" : "") + n
}

function dateKey(year, month, day) {
  return year + "-" + pad2(Number(month) + 1) + "-" + pad2(day)
}

function keyForDate(date) {
  return dateKey(date.getFullYear(), date.getMonth(), date.getDate())
}

function dateFromKey(key) {
  var parts = String(key || "").split("-")
  return new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]))
}

function addDays(key, delta) {
  var date = dateFromKey(key)
  date.setDate(date.getDate() + delta)
  return keyForDate(date)
}

// The days an event occupies, in local terms.
//
// A timed event is an instant, so its day is whatever day that instant falls
// on here — an 8pm UTC start is tomorrow in Tokyo and today in New York, and
// both are right. An all-day event is not an instant at all: HEY stores it as
// a midnight-UTC pair, and reading that as a moment would slide "today" onto
// yesterday for everyone west of Greenwich. So its dates are taken from the
// text and never converted.
//
// Multi-day all-day events end exclusively — HEY writes a three-day trip as
// the 13th through the 16th — while a single-day one repeats its own date.
// Both shapes have to land on exactly the days the app draws.
function eventDayKeys(event) {
  if (!event) return []

  if (!event.allDay) {
    if (event.startMs === null) return []
    return [keyForDate(new Date(event.startMs))]
  }

  var startKey = String(event.startsAt).substr(0, 10)
  var endKey = String(event.endsAt).substr(0, 10)
  if (!/^\d{4}-\d{2}-\d{2}$/.test(startKey)) return []
  if (!/^\d{4}-\d{2}-\d{2}$/.test(endKey) || endKey <= startKey) return [startKey]

  var keys = []
  var cursor = startKey
  // Bounded so a corrupt or absurd end date cannot spin here.
  while (cursor < endKey && keys.length < 90) {
    keys.push(cursor)
    cursor = addDays(cursor, 1)
  }
  return keys.length > 0 ? keys : [startKey]
}

// All-day events first, then by start time, then by title so two events at
// the same minute keep a stable order between refreshes.
function compareEvents(a, b) {
  if (a.allDay !== b.allDay) return a.allDay ? -1 : 1
  if (!a.allDay) {
    var delta = (a.startMs || 0) - (b.startMs || 0)
    if (delta !== 0) return delta
  }
  return a.title < b.title ? -1 : (a.title > b.title ? 1 : 0)
}

function eventsForDay(events, dayKey) {
  var key = String(dayKey || "")
  var out = []
  var list = Array.isArray(events) ? events : []
  for (var i = 0; i < list.length; i++) {
    if (eventDayKeys(list[i]).indexOf(key) !== -1) out.push(list[i])
  }
  return out.sort(compareEvents)
}

// The week as a list of days rather than a map, so the panel can repeat over
// it directly. Empty days are kept: a blank Thursday is information, and
// dropping it would make the week jump around as events come and go.
function weekDays(events, firstDayKey, todayKey) {
  var days = []
  for (var i = 0; i < 7; i++) {
    var key = addDays(firstDayKey, i)
    var dayEvents = eventsForDay(events, key)
    days.push({
      key: key,
      date: dateFromKey(key),
      today: key === String(todayKey || ""),
      past: key < String(todayKey || ""),
      events: dayEvents,
      count: dayEvents.length
    })
  }
  return days
}

// HEY draws its weeks Monday-first, and `hey event week` answers the same
// span, so the agenda's week is Monday-based no matter where the month grid
// above it starts its rows.
function weekStartKey(dayKey) {
  var date = dateFromKey(dayKey)
  var weekday = (date.getDay() + 6) % 7
  return addDays(dayKey, -weekday)
}

// ---------------------------------------------------------------------------
// Now
// ---------------------------------------------------------------------------

function hasEnded(event, nowMs) {
  if (!event || event.allDay) return false
  var end = event.endMs === null ? event.startMs : event.endMs
  return end !== null && end <= nowMs
}

function isNow(event, nowMs) {
  if (!event || event.allDay || event.startMs === null) return false
  var end = event.endMs === null ? event.startMs : event.endMs
  return event.startMs <= nowMs && nowMs < end
}

// What the bar is for: the thing you are in, or the thing you are about to be
// in. A meeting already under way beats one that starts later, because the
// question the bar answers at 10:05 is "what am I in?" and not "what is next?".
//
// Falls back to an all-day event only when there is no timed one left, so a
// birthday does not sit in the bar all day over a standup in ten minutes.
function currentOrNextEvent(events, nowMs) {
  var list = Array.isArray(events) ? events : []
  var upcoming = null
  var allDay = null

  for (var i = 0; i < list.length; i++) {
    var event = list[i]
    if (event.allDay) {
      if (!allDay) allDay = event
      continue
    }
    if (isNow(event, nowMs)) return event
    if (event.startMs !== null && event.startMs > nowMs) {
      if (!upcoming || event.startMs < upcoming.startMs) upcoming = event
    }
  }
  return upcoming || allDay
}

// ---------------------------------------------------------------------------
// Formatting
// ---------------------------------------------------------------------------

// Compact by design: this goes in a bar slot next to everything else, so
// "4:30p" earns its width where "4:30 PM" does not.
function formatTime(date, hour24) {
  if (!date) return ""
  var hours = date.getHours()
  var minutes = pad2(date.getMinutes())
  if (hour24) return pad2(hours) + ":" + minutes
  var suffix = hours < 12 ? "a" : "p"
  var hour12 = hours % 12
  if (hour12 === 0) hour12 = 12
  return hour12 + ":" + minutes + suffix
}

function eventTimeLabel(event, hour24) {
  if (!event) return ""
  if (event.allDay) return "all day"
  if (event.startMs === null) return ""
  return formatTime(new Date(event.startMs), hour24)
}

function eventRangeLabel(event, hour24) {
  if (!event) return ""
  if (event.allDay) return "All day"
  if (event.startMs === null) return ""
  var start = formatTime(new Date(event.startMs), hour24)
  if (event.endMs === null || event.endMs <= event.startMs) return start
  return start + " – " + formatTime(new Date(event.endMs), hour24)
}

function truncate(text, limit) {
  var value = String(text === undefined || text === null ? "" : text)
  if (value.length <= limit) return value
  // Cut at a word boundary when one is close enough that the ellipsis reads
  // as a trimmed title rather than a chopped one.
  var cut = value.substr(0, limit - 1)
  var space = cut.lastIndexOf(" ")
  if (space >= limit - 10) cut = cut.substr(0, space)
  return cut.replace(/[\s,;:.-]+$/, "") + "…"
}

var barTitleLimit = 32

// How close is close enough to be worth a mark in the bar.
var defaultAlertLeadMinutes = 15

function normalizedAlertLead(value) {
  var minutes = Math.round(Number(value))
  if (!isFinite(minutes) || minutes < 0) return defaultAlertLeadMinutes
  return Math.min(240, minutes)
}

// The event the bar is warning about, or null when there is nothing close.
//
// An event already under way counts. It is not "coming up" by the plain
// meaning of the words, but an indicator that switches off at the exact
// moment the meeting starts is telling you the opposite of what you need,
// so the mark stays lit until the thing is actually over.
//
// All-day events never trigger it. A birthday is not something you are late
// for, and a mark that sat lit from midnight would stop meaning anything.
function imminentEvent(events, nowMs, leadMinutes) {
  var lead = normalizedAlertLead(leadMinutes)
  if (lead <= 0) return null

  var horizon = nowMs + lead * 60000
  var list = Array.isArray(events) ? events : []
  var soonest = null

  for (var i = 0; i < list.length; i++) {
    var event = list[i]
    if (event.allDay || event.startMs === null) continue
    if (isNow(event, nowMs)) return event
    if (event.startMs > nowMs && event.startMs <= horizon) {
      if (!soonest || event.startMs < soonest.startMs) soonest = event
    }
  }
  return soonest
}

// Whole minutes until it starts, for the tooltip. Negative once it is under
// way, which the caller reads as "now" rather than as a countdown.
function minutesUntil(event, nowMs) {
  if (!event || event.allDay || event.startMs === null) return 0
  return Math.round((event.startMs - nowMs) / 60000)
}

// ---------------------------------------------------------------------------
// Calendar colors
// ---------------------------------------------------------------------------

// HEY names its calendar colors rather than giving hex, so the dots are
// matched to HEY's own palette. Anything unnamed falls through to the theme's
// accent, which keeps a calendar the plugin has never heard of from becoming
// invisible.
var calendarColors = {
  "black": "#3b4045",
  "blue": "#3b82c4",
  "brown": "#8b6a4b",
  "green": "#3f9d5a",
  "orange": "#d8802f",
  "pink": "#d264a0",
  "purple": "#8b6fc4",
  "red": "#c4544f",
  "teal": "#3f9d9d",
  "yellow": "#d4a72c"
}

function calendarColor(name, fallback) {
  var key = String(name || "").toLowerCase().replace(/^\s+|\s+$/g, "")
  return calendarColors[key] || fallback
}

// External calendars come through as the address they were subscribed from,
// which is a long thing to hang off the right of every row. The local part
// carries the whole distinction between one account and another.
function calendarLabel(name) {
  var text = String(name || "").replace(/^\s+|\s+$/g, "")
  var at = text.indexOf("@")
  if (at > 0 && text.indexOf(" ") === -1) text = text.substr(0, at)
  return truncate(text, 22)
}

// ---------------------------------------------------------------------------
// Bar label formats
// ---------------------------------------------------------------------------

// Right-clicking the widget walks these and writes the result to shell.json,
// so the label the bar shows and the format the config holds stay the same
// thing. Shorter than the stock clock's ring: this label is usually giving
// way to an event, so the date shapes that earn a slot are the compact ones.
// The stock Omarchy clock's ring, verbatim: this bar is that bar, and a
// widget that cycled through different shapes than the one it replaces would
// be a worse clock for no reason. Each locale-shaped time preset is followed
// by its 12-hour twin, so the walk from 24-hour to AM/PM is one right click.
var BAR_FORMATS = [
  "dddd HH:mm",
  "dddd h:mm AP",
  "HH:mm",
  "h:mm AP",
  "ddd d MMM HH:mm",
  "ddd d MMM h:mm AP",
  "d MMMM 'W'ww yyyy",
  "yyyy-MM-dd HH:mm"
]

var VERTICAL_BAR_FORMATS = [
  "HH\n—\nmm",
  "h\n—\nmm\nAP",
  "dd\nMMM\n'W'ww\n''yy",
  "HH\nmm"
]

function barFormats(vertical) {
  return vertical ? VERTICAL_BAR_FORMATS.slice() : BAR_FORMATS.slice()
}

function formatRing(configured, presets) {
  var ring = []
  var candidates = (presets || []).concat([configured])
  for (var i = 0; i < candidates.length; i++) {
    var format = String(candidates[i] === undefined || candidates[i] === null ? "" : candidates[i])
    if (format === "" || ring.indexOf(format) !== -1) continue
    ring.push(format)
  }
  return ring.length > 0 ? ring : ["dddd HH:mm"]
}

function nextFormat(ring, current) {
  if (!ring || ring.length === 0) return ""
  var index = ring.indexOf(String(current === undefined || current === null ? "" : current))
  return ring[(index + 1) % ring.length]
}

function normalizedRefreshInterval(value) {
  var seconds = Math.round(Number(value))
  if (!isFinite(seconds) || seconds < 30) return 300
  return Math.min(3600, seconds)
}

// ---------------------------------------------------------------------------
// Calendar grid — Omarchy's clock model, MIT. See THIRD_PARTY_NOTICES.md.
// ---------------------------------------------------------------------------

var WEEKDAY_NAMES = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]

function isoWeekLiteral(year, month, day) {
  return pad2(isoWeek(year, month, day))
}

function coerceWeekStart(value) {
  if (value === undefined || value === null) return null
  if (typeof value === "number")
    return isFinite(value) ? ((Math.round(value) % 7) + 7) % 7 : null

  var text = String(value).replace(/^\s+|\s+$/g, "").toLowerCase()
  if (text === "") return null

  for (var i = 0; i < WEEKDAY_NAMES.length; i++)
    if (WEEKDAY_NAMES[i] === text || WEEKDAY_NAMES[i].substr(0, 3) === text) return i

  var parsed = parseInt(text, 10)
  return isFinite(parsed) ? ((parsed % 7) + 7) % 7 : null
}

function normalizedWeekStart(value, fallback) {
  var configured = coerceWeekStart(value)
  if (configured !== null) return configured
  var fallbackStart = coerceWeekStart(fallback)
  return fallbackStart === null ? 1 : fallbackStart
}

function weekStartSettingName(index) {
  return WEEKDAY_NAMES[normalizedWeekStart(index, 1)]
}

function toggledWeekStart(index) {
  return normalizedWeekStart(index, 1) === 1 ? 0 : 1
}

function weekdayOrder(weekStart) {
  var start = normalizedWeekStart(weekStart, 1)
  var out = []
  for (var i = 0; i < 7; i++) out.push((start + i) % 7)
  return out
}

// ISO-8601 week number: the week owning the Thursday of that date's
// Monday-based week.
function isoWeek(year, month, day) {
  var date = new Date(Date.UTC(year, month, day))
  var weekday = date.getUTCDay() || 7
  date.setUTCDate(date.getUTCDate() + 4 - weekday)
  var yearStart = new Date(Date.UTC(date.getUTCFullYear(), 0, 1))
  return Math.ceil(((date.getTime() - yearStart.getTime()) / MS_PER_DAY + 1) / 7)
}

function dayOfYear(year, month, day) {
  return Math.round((Date.UTC(year, month, day) - Date.UTC(year, 0, 1)) / MS_PER_DAY) + 1
}

function daysInYear(year) {
  return dayOfYear(year, 11, 31)
}

function yearProgress(year, month, day) {
  var total = daysInYear(year)
  if (total <= 0) return 0
  return Math.max(0, Math.min(1, (dayOfYear(year, month, day) - 1) / total))
}

function yearProgressPercent(year, month, day) {
  return Math.round(yearProgress(year, month, day) * 100)
}

var DEFAULT_LIFE_EXPECTANCY = 90

function parseBirthYear(value, currentYear) {
  var now = Math.round(Number(currentYear))
  if (!isFinite(now)) return 0
  var text = String(value === undefined || value === null ? "" : value).replace(/^\s+|\s+$/g, "")
  if (!/^\d{4}$/.test(text)) return 0
  var year = parseInt(text, 10)
  if (!isFinite(year) || year > now || year < now - 120) return 0
  return year
}

function ageFromBirthYear(birthYear, currentYear) {
  var born = parseBirthYear(birthYear, currentYear)
  if (born <= 0) return 0
  return Math.round(Number(currentYear)) - born
}

function parseAge(value) {
  var text = String(value === undefined || value === null ? "" : value).replace(/^\s+|\s+$/g, "")
  if (!/^\d+$/.test(text)) return 0
  var years = parseInt(text, 10)
  if (!isFinite(years) || years <= 0 || years > 120) return 0
  return years
}

function parseLifeExpectancy(value) {
  var text = String(value === undefined || value === null ? "" : value).replace(/^\s+|\s+$/g, "")
  if (!/^\d+$/.test(text)) return DEFAULT_LIFE_EXPECTANCY
  var years = parseInt(text, 10)
  if (!isFinite(years) || years <= 0 || years > 150) return DEFAULT_LIFE_EXPECTANCY
  return years
}

function lifeProgress(age, expectancy) {
  var years = parseAge(age)
  var span = parseLifeExpectancy(expectancy)
  if (years <= 0 || span <= 0) return 0
  return Math.max(0, Math.min(1, years / span))
}

function lifeProgressPercent(age, expectancy) {
  return Math.round(lifeProgress(age, expectancy) * 100)
}

// Always six rows of seven days, so the popup is exactly as tall in February
// as it is in August. `counts` maps a day key to how many events it holds, so
// the grid can carry an event dot without knowing what an event is.
function monthGrid(year, month, weekStart, todayKey, counts) {
  var start = normalizedWeekStart(weekStart, 1)
  var leading = (new Date(year, month, 1).getDay() - start + 7) % 7
  var cursor = new Date(year, month, 1 - leading)
  var today = String(todayKey || "")
  var byDay = counts || {}
  var weeks = []

  for (var w = 0; w < 6; w++) {
    var days = []
    var thursday = null
    for (var d = 0; d < 7; d++) {
      var cellYear = cursor.getFullYear()
      var cellMonth = cursor.getMonth()
      var cellDay = cursor.getDate()
      var weekday = cursor.getDay()
      var key = dateKey(cellYear, cellMonth, cellDay)
      if (weekday === 4) thursday = { year: cellYear, month: cellMonth, day: cellDay }
      days.push({
        key: key,
        year: cellYear,
        month: cellMonth,
        day: cellDay,
        weekday: weekday,
        inMonth: cellMonth === month && cellYear === year,
        weekend: weekday === 0 || weekday === 6,
        today: key === today,
        events: Number(byDay[key] || 0)
      })
      cursor.setDate(cursor.getDate() + 1)
    }
    var anchor = thursday || days[0]
    weeks.push({
      week: isoWeek(anchor.year, anchor.month, anchor.day),
      days: days
    })
  }
  return weeks
}

function stepMonth(year, month, delta) {
  var target = new Date(year, Number(month) + Number(delta), 1)
  return { year: target.getFullYear(), month: target.getMonth() }
}

// Event counts per day key, for the month grid's dots.
function eventCounts(events) {
  var counts = {}
  var list = Array.isArray(events) ? events : []
  for (var i = 0; i < list.length; i++) {
    var keys = eventDayKeys(list[i])
    for (var k = 0; k < keys.length; k++) counts[keys[k]] = (counts[keys[k]] || 0) + 1
  }
  return counts
}

if (typeof module !== "undefined") {
  module.exports = {
    weekCommand: weekCommand,
    versionCommand: versionCommand,
    weekJqProjection: weekJqProjection,
    parseEvents: parseEvents,
    normalizeEvent: normalizeEvent,
    safeUrl: safeUrl,
    boundedString: boundedString,
    eventDayKeys: eventDayKeys,
    eventsForDay: eventsForDay,
    weekDays: weekDays,
    weekStartKey: weekStartKey,
    hasEnded: hasEnded,
    isNow: isNow,
    currentOrNextEvent: currentOrNextEvent,
    formatTime: formatTime,
    eventTimeLabel: eventTimeLabel,
    eventRangeLabel: eventRangeLabel,
    truncate: truncate,
    imminentEvent: imminentEvent,
    minutesUntil: minutesUntil,
    normalizedAlertLead: normalizedAlertLead,
    calendarColor: calendarColor,
    calendarLabel: calendarLabel,
    barFormats: barFormats,
    formatRing: formatRing,
    nextFormat: nextFormat,
    normalizedRefreshInterval: normalizedRefreshInterval,
    dateKey: dateKey,
    keyForDate: keyForDate,
    dateFromKey: dateFromKey,
    addDays: addDays,
    normalizedWeekStart: normalizedWeekStart,
    weekStartSettingName: weekStartSettingName,
    toggledWeekStart: toggledWeekStart,
    weekdayOrder: weekdayOrder,
    isoWeek: isoWeek,
    isoWeekLiteral: isoWeekLiteral,
    dayOfYear: dayOfYear,
    daysInYear: daysInYear,
    yearProgress: yearProgress,
    yearProgressPercent: yearProgressPercent,
    parseAge: parseAge,
    parseBirthYear: parseBirthYear,
    ageFromBirthYear: ageFromBirthYear,
    parseLifeExpectancy: parseLifeExpectancy,
    lifeProgress: lifeProgress,
    lifeProgressPercent: lifeProgressPercent,
    monthGrid: monthGrid,
    stepMonth: stepMonth,
    eventCounts: eventCounts
  }
}
