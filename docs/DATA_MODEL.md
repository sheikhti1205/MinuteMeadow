# Local data

These are the planned storage boundaries. The startup preview does not create a database.

| Record | Contents |
| --- | --- |
| Focus session | ID, start and finish time, intended duration, active elapsed duration, completion or abandonment |
| Active timer | Timer kind and phase, intended duration, elapsed time before the current run, recovery anchors |
| Saved preset | ID, timer kind, label and duration; focus presets include break durations |
| Stopwatch lap | Stopwatch ID, order, total elapsed time and split duration |
| Installed pack | Pack ID, selected version, manifest schema, storage location and size |
| Preferences | Theme, duration defaults, alerts, sound, haptics and animation settings |

Write the completed session and clear or advance the active focus state in one transaction. Summaries query history rather than store a second copy of the totals. Preserve the intended duration separately from active elapsed time.

Add a new migration when the schema changes. Test upgrades against earlier schema snapshots. Validate an imported backup before writing records and apply the accepted import in one transaction.
