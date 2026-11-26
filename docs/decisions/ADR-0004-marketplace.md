# 0004: Bundled catalogue before remote distribution

Status: Accepted

Use a versioned local catalogue behind a repository interface. A development build can use a separate fixture catalogue. Production accepts an empty registry.

A backend would add deployment and account work before there are packs to distribute. A future static registry can use the same catalogue interface. Installed packs remain available offline even when no registry is reachable.
