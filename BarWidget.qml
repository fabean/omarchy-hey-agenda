import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// The bar label, and the owner of everything the panel reads.
//
// The label is the stock Omarchy clock, unchanged: the same formats, the same
// right-click ring, the same date and time. The bar is where you look to find
// out what time it is, and a widget that kept substituting a meeting title for
// the clock would be answering a question nobody asked it.
//
// The one addition is a calendar glyph in front of the time when something is
// close. That is the whole signal — no title, no countdown, no color — and
// the panel underneath answers "what?" for anyone it makes curious.
//
// One `hey event week` call feeds both halves: HEY has already unrolled the
// week's repeating series into the days they land on, so today's agenda is a
// filter of the week rather than a second request. Panel.qml draws it.
BarWidget {
  id: root
  moduleName: "io.github.fabean.hey-agenda"

  property date displayDate: clock.date

  // ---- Settings
  readonly property string configuredFormat: vertical
    ? setting("verticalFormat", "HH\n—\nmm")
    : setting("format", "dddd HH:mm")
  readonly property int alertLeadMinutes: Model.normalizedAlertLead(setting("alertLeadMinutes", 15))
  readonly property string timeFormat: String(setting("timeFormat", "auto"))
  readonly property int refreshIntervalSec: Model.normalizedRefreshInterval(setting("refreshIntervalSec", 300))
  readonly property bool dimPast: setting("dimPast", true) === true

  // "auto" is the one setting that has to ask the system: whether a place
  // writes half past four as 16:30 or 4:30p is a regional convention, not a
  // preference, so it is read off the locale unless someone says otherwise.
  readonly property bool hour24: timeFormat === "24"
    ? true
    : (timeFormat === "12" ? false : String(Qt.locale().timeFormat(Locale.ShortFormat)).indexOf("AP") === -1)

  readonly property var formatRing: Model.formatRing(configuredFormat, Model.barFormats(vertical))

  // ---- Event state, owned here and read by the panel.
  property var events: []
  property bool loading: false
  // Distinguishes "nothing on today" from "we have not looked yet", which are
  // the same empty list but very different things to put on screen.
  property bool loaded: false
  property string lastError: ""
  property string loadedWeekKey: ""

  readonly property string todayKey: Model.keyForDate(displayDate)
  readonly property var todayEvents: Model.eventsForDay(events, todayKey)
  readonly property var nextEvent: Model.currentOrNextEvent(todayEvents, displayDate.getTime())
  readonly property var counts: Model.eventCounts(events)

  // The one thing the events change about the bar.
  readonly property var alertEvent: Model.imminentEvent(todayEvents, displayDate.getTime(), alertLeadMinutes)
  readonly property bool alerting: alertEvent !== null

  // 'ww' is substituted before Qt sees it — Qt has no ISO week specifier of
  // its own — exactly as the stock clock does it.
  readonly property string dateText: Qt.formatDateTime(displayDate,
    String(configuredFormat).replace(/ww/g, Model.isoWeekLiteral(
      displayDate.getFullYear(), displayDate.getMonth(), displayDate.getDate())))

  readonly property string calendarGlyph: "󰃭"
  readonly property string displayText: alerting ? calendarGlyph + "  " + dateText : dateText

  // Vertical bars stack one line per icon slot, so the glyph takes a line of
  // its own rather than being crammed onto the hour.
  readonly property var verticalLines: alerting
    ? [calendarGlyph].concat(dateText.split("\n"))
    : dateText.split("\n")

  // ---- Fetching
  function refresh() {
    displayDate = new Date()
    fetchWeek(Model.weekStartKey(Model.keyForDate(displayDate)))
  }

  function fetchWeek(weekKey) {
    if (weekProcess.running) return
    root.loading = true
    weekProcess.command = Model.weekCommand(weekKey)
    root.loadedWeekKey = weekKey
    weekProcess.running = true
  }

  function applyWeek(exitCode, stdout) {
    root.loading = false
    var parsed = Model.parseEvents(stdout)
    if (parsed === null) {
      // An empty answer is the shape every failure takes here — the CLI is
      // missing, or signed out, or the network is gone — so the panel says
      // what to do about it rather than showing a day that looks clear.
      root.lastError = exitCode === 0
        ? "No answer from the HEY CLI."
        : "The HEY CLI exited with status " + exitCode + "."
      root.loaded = true
      return
    }
    root.lastError = ""
    root.events = parsed
    root.loaded = true
  }

  // ---- Bar label formats. Cycling writes back to shell.json, so the label
  //      the bar shows is the label the config holds.
  function cycleFormat() {
    var current = String(configuredFormat)
    var next = Model.nextFormat(formatRing, current)
    if (next === "" || next === current) return

    var entry = { id: root.moduleName }
    for (var key in root.settings) if (key !== "id") entry[key] = root.settings[key]
    entry[vertical ? "verticalFormat" : "format"] = next

    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  // ---- Panel. Shape contract for shell.summon/hide/toggle routing:
  //      Bar.findPanelWidget requires open/close/opened on the bar-widget root.
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function togglePanel() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  function toggleWeekStart() {
    if (panelLoader.item) panelLoader.item.toggleWeekStart()
  }

  function toggleWeekView() {
    if (panelLoader.item) panelLoader.item.toggleWeekView()
  }

  readonly property real openPanelIndicatorWidth: button.labelWidth
  readonly property real openPanelIndicatorHeight: Math.max(Style.space(10), Math.round(Style.bar.iconSlot * 0.55))

  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Component.onCompleted: refresh()

  SystemClock {
    id: clock
    precision: SystemClock.Minutes
    onDateChanged: {
      var wasKey = root.todayKey
      root.displayDate = date
      // Midnight moved the day, and probably the week with it.
      if (Model.keyForDate(date) !== wasKey) root.refresh()
    }
  }

  Timer {
    id: refreshTimer
    interval: root.refreshIntervalSec * 1000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  Process {
    id: weekProcess
    running: false
    command: []
    stdout: StdioCollector {
      onStreamFinished: root.applyWeek(weekProcess.exitCode, text)
    }
    onExited: function(exitCode) {
      // A process that dies before its stream finishes never reaches the
      // collector, so the spinner would stay up forever without this.
      if (root.loading) root.applyWeek(exitCode, "")
    }
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  IpcHandler {
    target: "io.github.fabean.hey-agenda"

    function refresh(): void { root.refresh() }
    function cycleFormat(): void { root.cycleFormat() }
    function toggleWeekStart(): void { root.toggleWeekStart() }
    function toggleWeek(): void { root.toggleWeekView() }
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.togglePanel() }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.vertical ? "" : root.displayText
    labelVisible: !root.vertical
    hasVisualContent: root.vertical ? root.verticalLines.length > 0 : text !== ""
    fixedHeight: root.vertical ? root.verticalLines.length * Style.bar.iconSlot : -1
    horizontalMargin: 8.75
    verticalPadding: 8.75
    // The glyph says "something is close"; hovering says what, and when.
    tooltipText: {
      if (root.lastError !== "") return "HEY Agenda — " + root.lastError
      if (!root.loaded) return "HEY Agenda"
      if (root.alerting) {
        var minutes = Model.minutesUntil(root.alertEvent, root.displayDate.getTime())
        var when = minutes <= 0 ? "Now" : "In " + minutes + " min"
        return when + " · " + root.alertEvent.title
      }
      if (root.nextEvent) return "Next: " + Model.eventRangeLabel(root.nextEvent, root.hour24)
        + " · " + root.nextEvent.title
      return "Nothing left today"
    }

    onPressed: function(b) {
      if (b === Qt.RightButton) root.cycleFormat()
      else if (b === Qt.MiddleButton) root.refresh()
      else root.togglePanel()
    }

    Column {
      visible: root.vertical
      anchors.fill: parent

      Repeater {
        model: root.verticalLines

        OpticalGlyph {
          required property string modelData
          width: button.width
          height: Style.bar.iconSlot
          text: modelData
          fontFamily: button.fontFamily
          fontSize: modelData.length > 3 ? button.fontSize * 0.9 : button.fontSize
          color: button.foreground
        }
      }
    }
  }
}
