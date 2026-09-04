import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

// One event in the agenda: a time, a calendar-colored rule, a title, and the
// calendar it came from.
//
// The rule down the left is doing the work a colored dot usually does badly.
// A dot at this size is a few pixels of hue and reads as noise in a list; a
// hairline the height of the row reads as a category, and a stack of them
// reads as which calendar the day belongs to without anyone having to look
// up a legend.
Item {
  id: root

  property var event: null
  property bool hour24: false
  property bool past: false
  property bool now: false
  property color foreground: Color.foreground
  // The hover tint and the mark on an event under way are different jobs:
  // one is the panel's own accent, the other is the bar's attention color.
  property color accent: Color.accent
  property color nowColor: Color.urgent
  property string fontFamily: Style.font.family
  property real timeColumnWidth: Style.space(64)

  signal activated()

  readonly property string timeText: Model.eventTimeLabel(event, hour24)
  readonly property string calendarText: event ? Model.calendarLabel(event.calendar) : ""
  readonly property color railColor: event ? Model.calendarColor(event.color, accent) : accent
  readonly property bool declined: event && String(event.status) === "declined"
  readonly property bool hasLink: event && (event.joinUrl !== "" || event.url !== "")

  // Past and declined are the same visual idea — this is not asking anything
  // of you — so they fade the same way rather than inventing a second style.
  readonly property real contentOpacity: (past || declined) ? 0.45 : 1.0

  implicitWidth: parent ? parent.width : Style.space(400)
  implicitHeight: Math.max(Style.space(26), titleText.implicitHeight + Style.space(8))

  Rectangle {
    anchors.fill: parent
    radius: Style.cornerRadius
    color: rowMouse.containsMouse
      ? Style.hoverFillFor(root.foreground, root.accent)
      : "transparent"
  }

  Row {
    id: contentRow
    anchors.fill: parent
    anchors.leftMargin: Style.space(6)
    anchors.rightMargin: Style.space(6)
    spacing: Style.space(8)
    opacity: root.contentOpacity

    Text {
      textFormat: Text.PlainText
      width: root.timeColumnWidth
      height: parent.height
      horizontalAlignment: Text.AlignRight
      verticalAlignment: Text.AlignVCenter
      text: root.timeText
      color: root.now ? root.nowColor : Qt.darker(root.foreground, 1.45)
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      font.bold: root.now
    }

    Rectangle {
      width: Style.spacing.hairline * 2
      height: parent.height - Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      radius: width / 2
      color: root.railColor
    }

    Text {
      id: titleText
      textFormat: Text.PlainText
      // Whatever the time column, the rail and the calendar label leave.
      width: Math.max(Style.space(40), parent.width - root.timeColumnWidth
        - calendarLabel.width - Style.space(8) * 3 - Style.spacing.hairline * 2)
      height: parent.height
      verticalAlignment: Text.AlignVCenter
      text: root.event ? root.event.title : ""
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      font.bold: root.now
      font.strikeout: root.declined
      elide: Text.ElideRight
    }

    Text {
      id: calendarLabel
      textFormat: Text.PlainText
      height: parent.height
      verticalAlignment: Text.AlignVCenter
      horizontalAlignment: Text.AlignRight
      text: root.calendarText
      color: Qt.darker(root.foreground, 1.9)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  MouseArea {
    id: rowMouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: root.hasLink ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: root.activated()

    PanelToolTip {
      visible: rowMouse.containsMouse && root.event !== null
      fontFamily: root.fontFamily
      text: {
        if (!root.event) return ""
        var lines = [Model.eventRangeLabel(root.event, root.hour24) + " · " + root.event.title]
        if (root.event.calendar !== "") lines.push(root.event.calendar)
        if (root.event.location !== "") lines.push(root.event.location)
        if (root.event.joinUrl !== "") lines.push(root.event.joinTitle || "Join")
        else if (root.event.url !== "") lines.push("Open in HEY")
        return lines.join("\n")
      }
    }
  }
}
