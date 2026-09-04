### Repository URL

https://github.com/fabean/omarchy-hey-agenda

### Category

Productivity

### Tags

Bar, Quickshell

### Suggest a missing tag

Calendar

### Maintainer notes

A drop-in replacement for the built-in Clock widget that adds a HEY agenda to
the calendar popup. The bar label is the stock clock; the only addition is a
calendar icon shown when an event starts within a configurable lead time
(default 15 minutes).

Requires the HEY CLI 1.4.0 or newer on PATH and signed in, plus an
Omarchy-compatible Nerd Font. The plugin runs `hey event week` on a timer
(default every 5 minutes, 30–3600s configurable) and on panel open. The call is
wrapped in `timeout` and `head -c` so a hung or runaway CLI cannot stall or
balloon the shell process; the date and jq filter are passed as argv, never
interpolated into the script. Event text from calendars is length-capped and
rendered as PlainText, and only https URLs are ever handed to `xdg-open`.

The calendar half is derived from Omarchy's own MIT-licensed Clock widget; this
is recorded in THIRD_PARTY_NOTICES.md.

### Submission checklist

- [x] The repository is public and contains installation and removal instructions.
- [x] I have documented the plugin license and any external dependencies.
- [x] I confirm that I own or have permission to submit this plugin and its preview assets.
- [x] The plugin does not overwrite user configuration without explicit consent.
- [x] I understand that approval is for listing and is not a security review.
