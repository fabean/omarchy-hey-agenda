# HEY Agenda for Omarchy

The stock Omarchy calendar, with your [HEY](https://hey.com) agenda under it.

The bar label is the ordinary clock — same formats, same right-click ring, same date and time. A calendar icon appears in front of it when something is starting within the next 15 minutes, and stays there until the event is over. That is the entire bar change: no titles, no countdown, no color. The panel answers "what?" for anyone the icon makes curious.

Clicking the label opens the familiar calendar popup — hero date, year meter, month grid with ISO week numbers — now with a dot under every day that holds events, and today's agenda below the grid. One button expands the agenda to the whole week.

## Requirements

- Omarchy with the Quattro shell plugin system
- The [HEY CLI](https://github.com/basecamp/hey-cli) **1.4.0 or newer**, on `PATH` and signed in (`hey setup`)
- A HEY account with calendars
- An Omarchy-compatible Nerd Font for the calendar icon

The plugin reads `hey event week`, which is HEY's own expansion of the week — repeating series already unrolled into the days they fall on, across every calendar switched on in HEY. It covers the same events the app draws, so there is nothing to configure about which calendars to include.

## Install

Review the source before installing. Omarchy plugins run as unsandboxed code inside the long-running shell process.

```bash
omarchy plugin add https://github.com/fabean/omarchy-hey-agenda.git --enable
```

The widget goes in the center section by default. If it was installed without `--enable`:

```bash
omarchy plugin enable io.github.fabean.hey-agenda --section center
```

### Replacing the stock Clock

This widget is a drop-in for `omarchy.clock`. Disable the stock one so you do not carry two clocks:

```bash
omarchy plugin disable omarchy.clock
```

Omarchy pins one center widget to the exact middle of the bar and flanks the others around it, so that revealing hover-only widgets does not shove the whole center section sideways. That pin is `bar.centerAnchor` in `~/.config/omarchy/shell.json`, and out of the box it names the stock clock. Point it at this widget instead:

```jsonc
{
  "bar": {
    "centerAnchor": "io.github.fabean.hey-agenda"
  }
}
```

Without this, the center section is centered as a group and the bar shifts when hidden widgets appear.

## Use

**Bar**

- Left-click opens or closes the calendar and agenda.
- Right-click cycles the date format, exactly as the stock clock does. The choice is written to `shell.json`, so it survives a restart.
- Middle-click refreshes from HEY.
- Hover names the next event and how far away it is.

**Panel**

- The month grid steps with the chevrons, the scroll wheel, the arrow keys, or `[` and `]` (`{` and `}` for years). `T` or clicking the hero date returns to today.
- A dot under a day means that day holds events. It is one dot, not a count — the grid answers "is there anything?", the agenda answers "what?".
- The calendar button expands the agenda from today to the whole week, grouped by day, empty days included. `E` does the same.
- `R` or the refresh button re-reads from HEY. Opening the panel also refreshes.
- Clicking an event opens its meeting link if it has one, and its HEY page otherwise.
- Clicking the `W` heading switches the week between starting Monday and Sunday.
- Double-clicking the year bar sets a birth year, for anyone who wants the memento mori rail the stock clock hides there too.

Events that have ended are dimmed, and so are ones you have declined. An event under way is marked in the bar's attention color.

## Settings

Configured per widget in `shell.json`, or through Omarchy's widget settings UI.

| Key | Default | Meaning |
| --- | --- | --- |
| `alertLeadMinutes` | `15` | How far ahead the calendar icon appears. It stays lit until the event ends. `0` turns it off. All-day events never trigger it. |
| `format` | `dddd HH:mm` | Bar date format, same syntax as the stock Clock. |
| `timeFormat` | `auto` | Event times in the agenda: `auto` follows the system locale, or force `12` / `24`. |
| `refreshIntervalSec` | `300` | How often to re-read HEY. Clamped to 30–3600. |
| `dimPast` | `true` | Dim events that have already ended. |

The panel also stores `weekStartDay`, `birthYear` and `lifeExpectancy`, which are written by the controls that set them.

## Notes

- **An event on two calendars appears twice.** If you subscribe to the same calendar from two accounts, HEY returns both, and the plugin shows both — with their calendar names, so you can tell which is which. Hiding one would hide a real fact about your calendars.
- **All-day events are floating dates.** They are placed on the day they name, never converted through your timezone, so a bill due on the 30th does not slide onto the 29th. Multi-day ones end exclusively, the way HEY stores them.
- **Failures are never shown as an empty day.** A missing CLI, a signed-out session and a dead network all produce the same empty answer, so the panel says what went wrong instead of showing an afternoon that looks clear.

## Develop

```bash
omarchy plugin validate .
tests/run                      # Model.js unit tests, run in four timezones
```

`Model.js` holds every piece of date and agenda math and is Qt-free, so it runs under plain node. The timezone-sensitive parts — all-day placement, multi-day spans, which local day an instant belongs to — are the reason `tests/run` runs the suite under UTC, Los Angeles, Tokyo and Kiritimati rather than only where you happen to be.

For local testing, copy the repository into `~/.config/omarchy/plugins/io.github.fabean.hey-agenda` and restart the shell with `omarchy-restart-shell`.

Lint the QML against the installed shell:

```bash
mkdir -p /tmp/qmlroot && ln -sfn "$OMARCHY_PATH/shell" /tmp/qmlroot/qs
qmllint -I /tmp/qmlroot BarWidget.qml Panel.qml AgendaRow.qml
```

## Update

```bash
omarchy plugin update io.github.fabean.hey-agenda
```

## Remove

```bash
omarchy plugin remove io.github.fabean.hey-agenda
```

Removal deletes the plugin checkout and drops the widget from the bar. It does not touch the HEY CLI, your HEY session, or any calendar data. If you pointed `bar.centerAnchor` at this widget, set it back to `omarchy.clock`.

## License

[MIT](LICENSE). Portions of the calendar are Omarchy's own, also MIT — see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
