# Local data

The app stores timer state, preferences and session history in a local SQLite database. No account is required.

| Record | Contents |
| --- | --- |
| Focus session | ID, start and finish time, intended duration, active elapsed duration, completion or abandonment |
| Active timer | Timer kind and phase, intended duration, elapsed time before the current run, recovery anchors |
| Saved preset | ID, timer kind, label and duration; focus presets include break durations |
| Stopwatch lap | Stopwatch ID, order, total elapsed time and split duration |
| Installed pack | Pack ID, selected version, manifest schema, storage location and size |
| Preferences | Theme, duration defaults, alerts, sound, haptics and animation settings |

Write the completed session and clear or advance the active focus state in one transaction. Summaries query history rather than store a second copy of the totals. Preserve the intended duration separately from active elapsed time.

Active timer checkpoints can carry Android elapsed-realtime and boot-count samples. When both samples are from the same boot, elapsed realtime supplies the recovery interval. After a device restart or on platforms without those samples, recovery uses UTC wall time and clamps negative elapsed intervals to zero.

Add a new migration when the schema changes. Test upgrades against earlier schema snapshots. Validate an imported backup before writing records and apply the accepted import in one transaction.
