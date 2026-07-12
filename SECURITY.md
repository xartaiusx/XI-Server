# Security Policy

## Supported Branch

Mochirii accepts security fixes on the `main` branch.

## Reporting A Vulnerability

Please do not open a public issue for a security vulnerability, exploit path,
credential leak, or private server abuse vector.

Use GitHub private vulnerability reporting if it is enabled for this repository.
If it is not available, contact the repository owner through GitHub before
sharing reproduction details publicly.

Useful reports include:

- the affected commit or file path;
- exact reproduction steps;
- the expected impact;
- any server logs or client screenshots needed to understand the issue, with
  secrets and account credentials removed.

## Public Repository Boundaries

Do not commit passwords, database backups, client files, mod archives, runtime
logs, Windower screenshots, private keys, or local machine secrets. Runtime
evidence belongs under `C:\Github Repo's\FFXI\Runtime`, outside this
repository.

Active Mochirii credentials belong only under
`C:\Github Repo's\FFXI\FFXI Creds`. Repo and runtime consumers may link to that
store, but must not copy credential values into tracked files or evidence.

This project does not operate a public bug bounty program.
