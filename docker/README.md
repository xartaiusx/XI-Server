# Mochirii Docker Notes

The current Mochirii development workflow uses the local Windows runtime and
desktop shortcuts documented in `documentation/client_mod_admin_plan.md`:

- `Start Mochirii Server.lnk`
- `Start Mochirii Server (Local QA).lnk`
- `Stop Mochirii Server.lnk`

Docker is not the active runtime path for the current server state. If Docker is
reintroduced later, prefer building a local Mochirii image from this checkout and
document the exact image tag, settings files, module mounts, and migration steps
here before using it for QA.
