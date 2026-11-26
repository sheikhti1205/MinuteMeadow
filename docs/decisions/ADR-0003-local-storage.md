# 0003: Local storage

Status: Accepted

Use SQLite via Drift for session history and state that must be written together. Use simple preferences for independent settings such as theme. Keep imported pack assets in app-owned storage and verify them before switching the installed version.

A cloud store would require connectivity and an account for core features. A collection of preference keys would make history queries and migration more difficult. SQLite adds migration work, which belongs in the storage layer rather than the screens.
