# Third-party notices

## Omarchy

This plugin is a derivative of Omarchy's built-in Clock widget (`omarchy.clock`),
and reproduces parts of it so that the calendar behaves exactly as the one it
replaces.

Reproduced, with modifications:

- `Model.js` — the calendar-grid half: week-start normalization, ISO week
  numbers, the six-row month grid, and the year and life-expectancy meters.
  `monthGrid` additionally carries per-day event counts.
- `Panel.qml` — the hero date, year and memento-mori rails, month grid and
  month navigation. The agenda section below the grid is new.
- `BarWidget.qml` — the bar label, its format ring, and the panel lifecycle
  contract. The calendar icon and the HEY fetch are new.

Omarchy is copyright (c) 37signals and is distributed under the MIT License.
Upstream: https://github.com/basecamp/omarchy

## HEY CLI

This plugin invokes the `hey` command-line tool as an external process. It
neither bundles nor redistributes any part of it.

Upstream: https://github.com/basecamp/hey-cli
