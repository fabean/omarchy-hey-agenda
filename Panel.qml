import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model

// The stock Omarchy calendar popup — hero date, year meter, month grid with
// ISO week numbers — with the day's HEY agenda under it.
//
// The grid stays a read-out rather than a picker, exactly as it is upstream:
// today is the only marked day, and the only thing that moves is which month
// is on screen. What it gains is a dot under any day holding events, so the
// month says something about the month rather than only about the date.
//
// Under the grid, the agenda. It opens on today, and the "Week" toggle
// expands it to the whole week grouped by day — the same events, at the range
// you asked about. BarWidget.qml owns the fetch and hands the events down.
Panel {
  id: root
  moduleName: "io.github.fabean.hey-agenda"
  ipcTarget: "io.github.fabean.hey-agenda"
  manageIpc: false

  property var anchorItem: null

  // The bar tracks the widget mounted in its slot — BarWidget.qml — not this
  // nested panel, so everything the bar identifies a panel by has to be that
  // widget.
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  // ---- Everything the host owns, read through one guard so the panel still
  //      renders when it is instantiated bare.
  readonly property var events: hostWidget && hostWidget.events ? hostWidget.events : []
  readonly property var counts: hostWidget && hostWidget.counts ? hostWidget.counts : ({})
  readonly property bool loading: hostWidget ? hostWidget.loading === true : false
  readonly property bool loaded: hostWidget ? hostWidget.loaded === true : false
  readonly property string lastError: hostWidget ? String(hostWidget.lastError || "") : ""
  readonly property bool hour24: hostWidget ? hostWidget.hour24 === true : false
  readonly property bool dimPast: hostWidget ? hostWidget.dimPast === true : true

  // ---- Today. SystemClock keeps this honest across midnight.
  property date today: new Date()
  readonly property string todayKey: Model.keyForDate(today)
  readonly property real nowMs: today.getTime()

  property int viewYear: today.getFullYear()
  property int viewMonth: today.getMonth()

  readonly property date viewDate: new Date(viewYear, viewMonth, 1)
  readonly property bool viewingCurrentMonth: viewYear === today.getFullYear() && viewMonth === today.getMonth()

  // ---- Agenda range. Day is the default because the day is the question;
  //      the week is the follow-up.
  property bool weekView: false

  readonly property string weekFirstKey: Model.weekStartKey(todayKey)
  readonly property var todayEvents: Model.eventsForDay(events, todayKey)
  readonly property var weekDays: Model.weekDays(events, weekFirstKey, todayKey)
  readonly property int weekCount: events.length

  readonly property string weekRangeLabel: {
    var first = Model.dateFromKey(weekFirstKey)
    var last = Model.dateFromKey(Model.addDays(weekFirstKey, 6))
    return first.getMonth() === last.getMonth()
      ? Qt.formatDate(first, "d") + "–" + Qt.formatDate(last, "d MMM")
      : Qt.formatDate(first, "d MMM") + " – " + Qt.formatDate(last, "d MMM")
  }

  readonly property real yearDone: Model.yearProgress(today.getFullYear(), today.getMonth(), today.getDate())
  readonly property int yearDonePercent: Model.yearProgressPercent(today.getFullYear(), today.getMonth(), today.getDate())

  readonly property int birthYear: Model.parseBirthYear(setting("birthYear", 0), today.getFullYear())
  readonly property int age: Model.ageFromBirthYear(birthYear, today.getFullYear())
  readonly property int lifeExpectancy: Model.parseLifeExpectancy(setting("lifeExpectancy", 0))
  readonly property real lifeDone: Model.lifeProgress(age, lifeExpectancy)
  readonly property int lifeDonePercent: Model.lifeProgressPercent(age, lifeExpectancy)
  property bool editingLife: false

  readonly property int weekStart: Model.normalizedWeekStart(setting("weekStartDay", null), Qt.locale().firstDayOfWeek)
  readonly property var labelLocale: Qt.locale("en_US")
  readonly property string nextWeekStartLabel: labelLocale.dayName(Model.toggledWeekStart(weekStart), Locale.LongFormat)
  readonly property var weekdays: Model.weekdayOrder(weekStart)
  readonly property var weeks: Model.monthGrid(viewYear, viewMonth, weekStart, todayKey, counts)

  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property color accentColor: Color.accent
  // What the bar uses to say "look at this", which is exactly what an event
  // already under way is saying.
  readonly property color nowColor: bar ? bar.urgent : Color.urgent
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property int cellWidth: Style.space(52)
  readonly property int cellHeight: Style.space(34)
  readonly property int cellSpacing: Style.space(2)
  readonly property int weekColumnWidth: Style.space(32)
  readonly property int gutterWidth: Style.space(14)

  function open() {
    refresh()
    root.controller.show()
    Qt.callLater(function() {
      if (root.opened) setCenterHoverRevealSuppressed(true)
    })
  }

  function close() {
    setCenterHoverRevealSuppressed(false)
    if (root.editingLife) root.cancelEditingLife()
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function setCenterHoverRevealSuppressed(value) {
    if (root.bar && "centerHoverRevealSuppressed" in root.bar)
      root.bar.centerHoverRevealSuppressed = value
  }

  // Opening is also a reason to re-read: the panel is usually opened because
  // something is about to happen, and a five-minute-old answer is the wrong
  // one to greet that with.
  function refresh() {
    root.today = new Date()
    root.goToToday()
    if (root.hostWidget && typeof root.hostWidget.refresh === "function") root.hostWidget.refresh()
  }

  function toggleWeekView() {
    root.weekView = !root.weekView
  }

  // Join link first, HEY second. Someone clicking a meeting two minutes
  // before it starts wants the room, not the event's edit page.
  function openEvent(event) {
    if (!event) return
    var url = event.joinUrl !== "" ? event.joinUrl : event.url
    if (url === "") return
    Quickshell.execDetached(["xdg-open", url])
    root.close()
  }

  function goToToday() {
    root.viewYear = today.getFullYear()
    root.viewMonth = today.getMonth()
  }

  function moveMonth(delta) {
    var next = Model.stepMonth(viewYear, viewMonth, delta)
    root.viewYear = next.year
    root.viewMonth = next.month
  }

  function moveYear(delta) {
    moveMonth(delta * 12)
  }

  function persistSettings(values) {
    var entry = { id: root.moduleName }
    for (var existing in root.settings) if (existing !== "id") entry[existing] = root.settings[existing]
    for (var key in values) entry[key] = values[key]

    root.settings = entry
    if (root.hostWidget && "settings" in root.hostWidget) root.hostWidget.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function setWeekStart(day) {
    var next = Model.normalizedWeekStart(day, root.weekStart)
    if (next === root.weekStart) return
    persistSettings({ weekStartDay: Model.weekStartSettingName(next) })
  }

  function startEditingLife() {
    root.editingLife = true
    Qt.callLater(function() {
      bornField.text = root.birthYear > 0 ? String(root.birthYear) : ""
      expectancyField.text = String(root.lifeExpectancy)
      bornField.selectAll()
      bornField.forceActiveFocus()
    })
  }

  function cancelEditingLife() {
    root.editingLife = false
    Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
  }

  function handleLifeKey(event, other) {
    if (event.key === Qt.Key_Escape) {
      root.cancelEditingLife()
      event.accepted = true
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      root.commitLife()
      event.accepted = true
    } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
      other.selectAll()
      other.forceActiveFocus()
      event.accepted = true
    }
  }

  function clearLife() {
    if (root.birthYear <= 0) return
    persistSettings({ birthYear: 0 })
  }

  function commitLife() {
    var born = Model.parseBirthYear(bornField.text, today.getFullYear())
    var span = Model.parseLifeExpectancy(expectancyField.text)
    if (born !== root.birthYear || span !== root.lifeExpectancy)
      persistSettings({ birthYear: born, lifeExpectancy: span })
    cancelEditingLife()
  }

  function toggleWeekStart() {
    setWeekStart(Model.toggledWeekStart(root.weekStart))
  }

  function weekdayLabel(weekday) {
    return String(labelLocale.dayName(weekday, Locale.ShortFormat)).toUpperCase()
  }

  SystemClock {
    id: clock
    precision: SystemClock.Minutes
    onDateChanged: {
      // Tracked every minute, not only across midnight: the agenda dims what
      // has ended and marks what is under way, and both go stale on the
      // minute rather than on the day.
      var rolled = Model.keyForDate(clock.date) !== String(root.todayKey)
      var followToday = root.viewingCurrentMonth
      root.today = clock.date
      if (rolled && followToday) root.goToToday()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(560))
    contentHeight: panel.fittedContentHeight(calendarColumn.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.editingLife
      onMoveRequested: function(dx, dy) {
        if (dx !== 0) root.moveMonth(dx)
        if (dy !== 0) root.moveYear(dy)
      }
      onActivateRequested: root.goToToday()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "[") root.moveMonth(-1)
        else if (t === "]") root.moveMonth(1)
        else if (t === "{") root.moveYear(-1)
        else if (t === "}") root.moveYear(1)
        else if (t === "t" || t === "T") root.goToToday()
        else if (t === "w" || t === "W") root.toggleWeekStart()
        else if (t === "e" || t === "E") root.toggleWeekView()
        else if (t === "r" || t === "R") root.refresh()
      }

      Flickable {
        id: calendarScroll
        anchors.fill: parent
        contentWidth: calendarColumn.width
        contentHeight: calendarColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height || contentWidth > width

        Column {
          id: calendarColumn
          width: Math.max(calendarScroll.width, gridColumn.width)
          spacing: Style.space(8)

          // ---- Hero: today, centered, and the way home once the view has
          //      stepped away from it.
          Item {
            width: parent.width
            height: heroRow.height

            Row {
              id: heroRow
              anchors.horizontalCenter: parent.horizontalCenter
              spacing: Style.space(22)

              Text {
                anchors.baseline: heroDate.baseline
                text: "󰃭"
                color: heroMouse.containsMouse
                  ? Style.hoverStateColor(root.contentForeground, Color.accent)
                  : root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: 48
              }

              Text {
                id: heroDate
                textFormat: Text.PlainText
                anchors.verticalCenter: parent.verticalCenter
                text: Qt.formatDate(root.today, "MMMM d")
                color: heroMouse.containsMouse
                  ? Style.hoverStateColor(root.contentForeground, Color.accent)
                  : root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: 52
                font.bold: true
              }
            }

            MouseArea {
              id: heroMouse
              x: heroRow.x
              y: heroRow.y
              width: heroRow.width
              height: heroRow.height
              enabled: !root.viewingCurrentMonth
              hoverEnabled: enabled
              cursorShape: Qt.PointingHandCursor
              onClicked: root.goToToday()

              PanelToolTip {
                visible: heroMouse.containsMouse
                text: "Back to today"
                fontFamily: root.contentFontFamily
              }
            }
          }

          // ---- Year progress, doubling as the rule under the hero.
          Item {
            width: parent.width
            height: yearBlock.y + yearBlock.height

            Item {
              id: yearBlock
              y: Style.space(6)
              anchors.horizontalCenter: parent.horizontalCenter
              width: gridColumn.width
              height: Math.max(yearLabel.implicitHeight, Style.space(10))

              TapHandler {
                enabled: !root.editingLife
                onDoubleTapped: root.startEditingLife()
              }

              Row {
                visible: root.editingLife
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(10)

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: "BORN"
                  color: Qt.darker(root.contentForeground, 1.5)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.letterSpacing: 1
                }

                TextField {
                  id: bornField
                  width: Style.space(70)
                  anchors.verticalCenter: parent.verticalCenter
                  placeholderText: "year"
                  foreground: root.contentForeground
                  font.family: root.contentFontFamily
                  inputMethodHints: Qt.ImhDigitsOnly

                  Keys.onPressed: function(event) { root.handleLifeKey(event, expectancyField) }
                }

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  leftPadding: Style.space(6)
                  text: "LIVE TO"
                  color: Qt.darker(root.contentForeground, 1.5)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.letterSpacing: 1
                }

                TextField {
                  id: expectancyField
                  width: Style.space(60)
                  anchors.verticalCenter: parent.verticalCenter
                  placeholderText: "90"
                  foreground: root.contentForeground
                  font.family: root.contentFontFamily
                  inputMethodHints: Qt.ImhDigitsOnly

                  Keys.onPressed: function(event) { root.handleLifeKey(event, bornField) }
                }
              }

              Text {
                id: yearLabel
                textFormat: Text.PlainText
                visible: !root.editingLife
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: root.today.getFullYear()
                color: Qt.darker(root.contentForeground, 1.5)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.bodySmall
                font.letterSpacing: 1
              }

              Text {
                id: yearPercent
                textFormat: Text.PlainText
                visible: !root.editingLife
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: root.yearDonePercent + "%"
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.bodySmall
              }

              Rectangle {
                id: yearTrack
                visible: !root.editingLife
                anchors.left: yearLabel.right
                anchors.right: yearPercent.left
                anchors.leftMargin: Style.space(12)
                anchors.rightMargin: Style.space(12)
                anchors.verticalCenter: parent.verticalCenter
                height: Style.space(6)
                radius: Style.cornerRadius > 0 ? height / 2 : 0
                color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.12)

                Rectangle {
                  width: Math.round(parent.width * root.yearDone)
                  height: parent.height
                  radius: parent.radius
                  color: Style.selectedStateColor(root.contentForeground, Color.accent)

                  Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                }
              }
            }
          }

          // ---- Memento mori, for anyone who goes looking.
          Item {
            visible: root.birthYear > 0
            width: parent.width
            height: visible ? lifeBlock.height : 0

            Item {
              id: lifeBlock
              anchors.horizontalCenter: parent.horizontalCenter
              width: gridColumn.width
              height: Math.max(lifeLabel.implicitHeight, Style.space(10))

              Text {
                id: lifeLabel
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "LIFE"
                color: Qt.darker(root.contentForeground, 1.5)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.bodySmall
                font.letterSpacing: 1
              }

              Text {
                id: lifePercent
                textFormat: Text.PlainText
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: root.lifeDonePercent + "%"
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.bodySmall
              }

              Rectangle {
                anchors.left: lifeLabel.right
                anchors.right: lifePercent.left
                anchors.leftMargin: Style.space(12)
                anchors.rightMargin: Style.space(12)
                anchors.verticalCenter: parent.verticalCenter
                height: Style.space(6)
                radius: Style.cornerRadius > 0 ? height / 2 : 0
                color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.12)

                Rectangle {
                  width: Math.round(parent.width * root.lifeDone)
                  height: parent.height
                  radius: parent.radius
                  color: Style.selectedStateColor(root.contentForeground, Color.accent)

                  Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                }
              }

              TapHandler {
                onDoubleTapped: root.clearLife()
              }

              MouseArea {
                id: lifeMouse
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.NoButton

                PanelToolTip {
                  visible: lifeMouse.containsMouse
                  text: "Memento Mori"
                  fontFamily: root.contentFontFamily
                }
              }
            }
          }

          // ---- Month grid.
          Item {
            width: parent.width
            height: gridColumn.y + gridColumn.height

            WheelHandler {
              onWheel: function(event) {
                if (event.angleDelta.y === 0) return
                root.moveMonth(event.angleDelta.y > 0 ? -1 : 1)
              }
            }

            Column {
              id: gridColumn
              y: Style.space(18)
              anchors.horizontalCenter: parent.horizontalCenter
              spacing: Style.space(3)

              Row {
                id: headerRow
                spacing: root.cellSpacing

                Rectangle {
                  width: root.weekColumnWidth
                  height: Style.space(16)
                  radius: Style.cornerRadius
                  color: weekStartMouse.containsMouse
                    ? Style.hoverFillFor(root.contentForeground, Color.accent)
                    : "transparent"

                  Text {
                    anchors.centerIn: parent
                    text: "W"
                    color: weekStartMouse.containsMouse
                      ? Style.hoverStateColor(root.contentForeground, Color.accent)
                      : Qt.darker(root.contentForeground, 1.9)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                    font.letterSpacing: 1
                    font.bold: true
                  }

                  MouseArea {
                    id: weekStartMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.toggleWeekStart()
                  }

                  PanelToolTip {
                    visible: weekStartMouse.containsMouse
                    text: "Start weeks on " + root.nextWeekStartLabel
                    fontFamily: root.contentFontFamily
                  }
                }

                Item {
                  width: root.gutterWidth
                  height: Style.space(16)
                }

                Repeater {
                  model: root.weekdays

                  Text {
                    textFormat: Text.PlainText
                    required property var modelData
                    width: root.cellWidth
                    height: Style.space(16)
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: root.weekdayLabel(modelData)
                    color: Qt.darker(root.contentForeground, 1.5)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                    font.letterSpacing: 1
                    font.bold: true
                  }
                }
              }

              Repeater {
                model: root.weeks

                Row {
                  required property var modelData
                  spacing: root.cellSpacing

                  Text {
                    textFormat: Text.PlainText
                    width: root.weekColumnWidth
                    height: root.cellHeight
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: modelData.week
                    color: Qt.darker(root.contentForeground, 1.9)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                  }

                  Item {
                    width: root.gutterWidth
                    height: root.cellHeight
                  }

                  Repeater {
                    model: modelData.days

                    Rectangle {
                      required property var modelData

                      width: root.cellWidth
                      height: root.cellHeight
                      radius: Style.cornerRadius
                      color: "transparent"
                      border.width: modelData.today ? Style.spacing.hairline : 0
                      border.color: Style.normalBorderFor(root.contentForeground, Color.accent)

                      Text {
                        textFormat: Text.PlainText
                        anchors.centerIn: parent
                        // Nudged up by half the dot's lane so the number stays
                        // optically centred in the cell whether or not the day
                        // carries one.
                        anchors.verticalCenterOffset: -Style.space(2)
                        text: modelData.day
                        color: modelData.inMonth
                          ? (modelData.weekend ? Qt.darker(root.contentForeground, 1.45) : root.contentForeground)
                          : Qt.darker(root.contentForeground, 2.2)
                        font.family: root.contentFontFamily
                        font.pixelSize: Style.font.body
                        font.bold: modelData.today
                      }

                      // One dot for a day with anything on it. Not a count:
                      // a row of dots turns the grid into a chart, and the
                      // question the grid answers is "is there anything?" —
                      // the agenda below answers "what?".
                      Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: Style.space(4)
                        width: Style.space(3)
                        height: width
                        radius: width / 2
                        visible: modelData.events > 0
                        opacity: modelData.inMonth ? 0.85 : 0.35
                        color: Style.selectedStateColor(root.contentForeground, Color.accent)
                      }
                    }
                  }
                }
              }
            }

            Rectangle {
              x: gridColumn.x + root.weekColumnWidth + root.cellSpacing + Math.round((root.gutterWidth - width) / 2)
              y: gridColumn.y + headerRow.height + gridColumn.spacing
              width: Style.spacing.hairline
              height: gridColumn.height - headerRow.height - gridColumn.spacing
              color: root.contentForeground
              opacity: 0.1
            }
          }

          // ---- Month stepping.
          Item {
            width: parent.width
            height: monthNav.height

            Item {
              id: monthNav
              anchors.horizontalCenter: parent.horizontalCenter
              width: gridColumn.width
              height: monthLabel.implicitHeight + Style.space(10)

              Text {
                id: monthLabel
                textFormat: Text.PlainText
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(130)
                horizontalAlignment: Text.AlignHCenter
                text: Qt.formatDate(root.viewDate, "MMMM yyyy").toUpperCase()
                color: Qt.darker(root.contentForeground, 1.4)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.body
                font.letterSpacing: 1
              }

              PanelActionButton {
                anchors.left: parent.left
                anchors.leftMargin: -Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                iconText: "󰅁"
                tooltipText: "Previous month"
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
                onClicked: root.moveMonth(-1)
              }

              PanelActionButton {
                anchors.right: parent.right
                anchors.rightMargin: -Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                iconText: "󰅂"
                tooltipText: "Next month"
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
                onClicked: root.moveMonth(1)
              }
            }
          }

          // ---- Agenda. Everything below the rule is HEY.
          Item {
            width: parent.width
            height: agendaColumn.y + agendaColumn.implicitHeight

            Column {
              id: agendaColumn
              y: Style.space(6)
              anchors.horizontalCenter: parent.horizontalCenter
              width: gridColumn.width
              spacing: Style.space(6)

              PanelSeparator {
                width: parent.width
                foreground: root.contentForeground
              }

              // Header: what range is on screen, and the controls that change
              // it. The range label carries the count, because "TODAY · 3" is
              // the whole answer for anyone who only came to check.
              Item {
                width: parent.width
                height: Math.max(rangeLabel.implicitHeight, weekToggle.height) + Style.space(6)

                PanelSectionHeader {
                  id: rangeLabel
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  foreground: root.contentForeground
                  fontFamily: root.contentFontFamily
                  text: root.weekView
                    ? "THIS WEEK · " + root.weekRangeLabel
                    : (root.todayEvents.length > 0 ? "TODAY · " + root.todayEvents.length : "TODAY")
                }

                Row {
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(2)

                  PanelActionButton {
                    id: refreshButton
                    anchors.verticalCenter: parent.verticalCenter
                    iconText: root.loading ? "󰔟" : "󰑐"
                    tooltipText: root.loading ? "Refreshing…" : "Refresh from HEY"
                    foreground: root.contentForeground
                    fontFamily: root.contentFontFamily
                    fontSize: Style.font.iconSmall
                    enabled: !root.loading
                    onClicked: root.refresh()
                  }

                  PanelActionButton {
                    id: weekToggle
                    anchors.verticalCenter: parent.verticalCenter
                    iconText: root.weekView ? "󰃭" : "󰸗"
                    tooltipText: root.weekView ? "Show today" : "Show the week"
                    foreground: root.contentForeground
                    hoverColor: root.contentForeground
                    fontFamily: root.contentFontFamily
                    fontSize: Style.font.iconSmall
                    bordered: root.weekView
                    hasCursor: root.weekView
                    onClicked: root.toggleWeekView()
                  }
                }
              }

              // ---- Day view.
              Column {
                width: parent.width
                spacing: Style.spacing.xxs
                visible: !root.weekView

                Repeater {
                  model: root.weekView ? [] : root.todayEvents

                  AgendaRow {
                    required property var modelData
                    width: agendaColumn.width
                    event: modelData
                    hour24: root.hour24
                    past: root.dimPast && Model.hasEnded(modelData, root.nowMs)
                    now: Model.isNow(modelData, root.nowMs)
                    foreground: root.contentForeground
                    accent: root.accentColor
                    nowColor: root.nowColor
                    fontFamily: root.contentFontFamily
                    onActivated: root.openEvent(modelData)
                  }
                }
              }

              // ---- Week view: seven days, empty ones kept. A blank Thursday
              //      is information, and dropping it would make the week
              //      reshuffle as events come and go.
              Column {
                width: parent.width
                spacing: Style.space(4)
                visible: root.weekView

                Repeater {
                  model: root.weekView ? root.weekDays : []

                  Column {
                    id: dayGroup
                    // Named, because the row Repeater below nests a second
                    // modelData inside this one. Unqualified, "modelData"
                    // there would mean whichever scope QML reached first.
                    required property var modelData
                    readonly property var day: dayGroup.modelData

                    width: agendaColumn.width
                    spacing: Style.spacing.xxs

                    Item {
                      width: parent.width
                      height: dayHeading.implicitHeight + Style.space(4)

                      Text {
                        id: dayHeading
                        textFormat: Text.PlainText
                        anchors.left: parent.left
                        anchors.bottom: parent.bottom
                        text: Qt.formatDate(dayGroup.day.date, "ddd d").toUpperCase()
                        color: dayGroup.day.today
                          ? root.contentForeground
                          : Qt.darker(root.contentForeground, dayGroup.day.past ? 2.2 : 1.7)
                        font.family: root.contentFontFamily
                        font.pixelSize: Style.font.caption
                        font.letterSpacing: 1
                        font.bold: dayGroup.day.today
                      }

                      // Today's row gets a rule out to the edge — the only
                      // marker in the week, matching the single outlined cell
                      // in the grid above.
                      Rectangle {
                        visible: dayGroup.day.today
                        anchors.left: dayHeading.right
                        anchors.leftMargin: Style.space(8)
                        anchors.right: parent.right
                        anchors.verticalCenter: dayHeading.verticalCenter
                        anchors.verticalCenterOffset: 1
                        height: Style.spacing.hairline
                        color: Style.selectedStateColor(root.contentForeground, Color.accent)
                        opacity: 0.5
                      }
                    }

                    Repeater {
                      model: dayGroup.day.events

                      AgendaRow {
                        required property var modelData
                        width: agendaColumn.width
                        event: modelData
                        hour24: root.hour24
                        past: root.dimPast && Model.hasEnded(modelData, root.nowMs)
                        now: Model.isNow(modelData, root.nowMs)
                        foreground: root.contentForeground
                        accent: root.accentColor
                        fontFamily: root.contentFontFamily
                        onActivated: root.openEvent(modelData)
                      }
                    }

                    Text {
                      textFormat: Text.PlainText
                      visible: dayGroup.day.count === 0
                      leftPadding: Style.space(6)
                      height: visible ? Style.space(18) : 0
                      verticalAlignment: Text.AlignVCenter
                      text: "—"
                      color: Qt.darker(root.contentForeground, 2.4)
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.bodySmall
                    }
                  }
                }
              }

              // ---- The empty and broken states. An empty day and an
              //      unreachable CLI are the same empty list, and saying so
              //      is the difference between a clear afternoon and a
              //      widget that quietly stopped working.
              Item {
                width: parent.width
                height: visible ? Style.space(34) : 0
                visible: root.lastError !== ""
                  || (!root.loaded && !root.loading)
                  || (root.loaded && root.lastError === ""
                      && (root.weekView ? root.weekCount === 0 : root.todayEvents.length === 0))

                Text {
                  textFormat: Text.PlainText
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(6)
                  anchors.verticalCenter: parent.verticalCenter
                  width: parent.width - Style.space(12)
                  wrapMode: Text.WordWrap
                  elide: Text.ElideRight
                  text: {
                    if (root.lastError !== "")
                      return root.lastError + " Check that the HEY CLI is installed and signed in — run `hey setup`."
                    if (!root.loaded) return "Reading your HEY calendars…"
                    return root.weekView ? "Nothing on this week." : "Nothing on today."
                  }
                  color: Qt.darker(root.contentForeground, root.lastError !== "" ? 1.3 : 1.9)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                }
              }
            }
          }
        }
      }
    }
  }
}
