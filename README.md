# XI Server

Retail-inspired FFXI server enhancements, kept public-safe and source-reviewable.

<p>
<a href="https://github.com/xartaiusx/XI-Server/actions/workflows/build.yml?query=branch%3Aretail-inspired%2Fenhancements"><img alt="Builds: retail-inspired/enhancements" src="https://github.com/xartaiusx/XI-Server/actions/workflows/build.yml/badge.svg?branch=retail-inspired/enhancements"></a>
<a href="https://github.com/xartaiusx/XI-Server/actions/workflows/codeql_analysis.yml?query=branch%3Aretail-inspired%2Fenhancements"><img alt="CodeQL: retail-inspired/enhancements" src="https://github.com/xartaiusx/XI-Server/actions/workflows/codeql_analysis.yml/badge.svg?branch=retail-inspired/enhancements"></a>
<a href="https://www.gnu.org/licenses/gpl-3.0"><img alt="License: GPLv3" src="https://img.shields.io/badge/License-GPLv3-blue.svg"></a>
</p>

## Purpose

This repository is a public source lane for a FFXI server fork focused on retail-inspired enhancements.

The goal is not to claim perfect retail parity. The goal is to make source-backed gameplay improvements that follow the spirit of retail FFXI where credible evidence exists, while clearly separating those public changes from private local tooling, diagnostics, runtime state, and operator workflow.

## Branch Model

`retail-inspired/enhancements` is the single long-lived public branch for reviewed FFXI behavior enhancements that may differ from strict retail but are intended to feel retail-consistent.

Short-lived pull request branches may be used for review and should be deleted after merge. Private local tooling and experiments are not published here. Public content should not include local account details, local character details, GM helper commands, runtime logs, client files, private documentation, database dumps, or machine-specific configuration.

## Current Checks

The badges above point to this repository's own published GitHub Actions workflow status.

Use them as the quick visitor-facing health check:

- Builds should be green before treating the source baseline as currently healthy.
- CodeQL should be green before treating the public branch as clean from the configured static-analysis perspective.

Local-only validation may be broader than the public badges, but private runtime checks are not documented here unless they are safe and useful for public contributors. Additional public checks should only be shown here once they are configured and passing cleanly for the public branch.

## Enhancement Standard

Public gameplay changes should be small, source-reviewable, and easy to compare against the current codebase.

Preferred evidence order:

1. Current checked-out source, SQL, migrations, and runtime behavior.
2. Official FFXI or Square Enix update notes.
3. Retail captures, event dumps, packet observations, or in-client proof when official notes omit exact details.
4. Community references as secondary guidance only, verified against source or runtime evidence before implementation.

When exact retail behavior is uncertain, changes should be described as retail-inspired rather than retail-identical.

## Public Scope

Good public changes include:

- gameplay behavior fixes with clear source evidence
- SQL or script corrections that can be reviewed independently
- narrow enhancements that preserve the retail feel of FFXI
- documentation that helps explain public source behavior

Do not publish:

- secrets, passwords, hashes, tokens, or temporary credentials
- local runtime configuration or generated compose overrides
- local operator scripts, private task notes, or diagnostic commands
- client files, launcher binaries, Wine or Proton prefixes, mod archives, or extracted assets
- database dumps, backups, raw captures with private data, or runtime logs

## Development Notes

This project uses Docker Compose for local runtime validation. Public code changes should remain buildable and reviewable without requiring private machine state.

For source-level changes, prefer the smallest pull request that proves the behavior. Keep unrelated refactors, local quality-of-life tooling, and experimental server customization out of public history until they have a clear public purpose and evidence trail.

## License

This project is distributed under the GNU GPL v3 license. See [LICENSE](LICENSE).

## Credits

This fork builds on GPL-licensed open-source server emulator work and the long-running efforts of its contributors. Public changes here should preserve that spirit: source-visible, reviewable, and useful to people who care about FFXI behavior.
