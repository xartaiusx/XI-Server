# Database client security

`tools/mysql_client.py` is the shared native MariaDB/MySQL client transport for
`tools/dbtool.py` and `tools/ci/startup_checks.py`. It does not provision
credentials, authorize a database migration, or replace encrypted backup and
restore verification.

## Native client contract

Call `run_mysql(executable, arguments, *, host, user, port, password,
options_file=None, timeout=600, capture_output=True)` rather than constructing a
password-bearing command line. Host, user, port, and password are serialized
into one `[client]` option block of at most 16 KiB, with each string field
bounded to 4 KiB before escaping. Values are quoted and escaped; NUL and
unsupported inputs fail closed. The executable receives
`--defaults-file=<descriptor-or-private-path>` as its first option, not
`--defaults-extra-file`. Ambient option files and include directives are not
part of this contract. See the [MariaDB client option
reference](https://mariadb.com/docs/server/clients-and-utilities/mariadb-client/mariadb-command-line-client).

Passwords must not appear in child arguments, shell commands, inherited
password-bearing environment variables, diagnostics, or reports. The wrapper
uses a bounded native subprocess without a shell and closes transport handles
on success, failure, or timeout. The in-process `mariadb.connect()` API remains
separate from this CLI transport.

Connection overrides, `--print-defaults`, help/debug/verbose, and client logging
switches are rejected. Native failures keep
their nonzero return code but never forward native error text or SQL, which may
contain private connection details. Windows/macOS fixture paths are not secret
values and are the only extra transport input permitted in the child argv.
Only an optional public database identifier and an optional `-e`/`--execute`
query are allowed. A sole `--version` is permitted for a connection-free native
parser check. No abbreviated, combined, debug, or other client switches are
accepted; the CLI execution wrapper also rejects dump executables.

| Platform | Transport | Required privacy proof |
| --- | --- | --- |
| Linux, including the canonical WSL server | Anonymous `memfd`; no named option file is created | Mode `0600` before writing, close-on-exec, only the selected descriptor passed to the child |
| Windows | Explicit, existing private option file | File and immediate parent: current-token ownership and protected, non-null owner-only DACL; mode bits are insufficient |
| macOS | Explicit, existing private option file | File and immediate parent: current-user ownership, owner-only mode, and no extended ACL entries |

Linux always uses the memory descriptor. Windows/macOS select the existing
file using `options_file` or the path-only `MOCHIRII_MYSQL_OPTIONS_FILE`
environment variable. There is no password-argument, password-environment,
temporary-file, or automatically created credential-file fallback. An
unsupported platform or unavailable privacy check must stop before launching
the client.

## Existing private files

The supplied file must match `serialize_options(host, user, port, password)`
byte-for-byte: one `[client]` group with the expected connection fields.
Additional groups, comments, include directives, unrelated options, oversized
content, and mismatched values are rejected. Do not display the serialized
content, invoke `--print-defaults`, or copy a credential file into the checkout
or runtime to satisfy this check.

On Windows, a shared static PowerShell validator checks only metadata, never
values. The owner must be the current token user;
the DACL must be protected and contain only explicit allow entries for that
same SID. Inherited, deny, object, unsupported, or other-principal entries are
not accepted. The file must not be a directory or reparse-point leaf. The same
ownership/DACL check applies to its immediate parent, which must be a real
directory rather than a reparse-point leaf. The pathname hierarchy must remain
stable and quiescent throughout the call. An unprivileged identity cannot replace
the private file or parent; same-user/privileged changes are outside this boundary.
No credential-bearing output or script interpolation is used. See Microsoft's
[Get-Acl contract](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.security/get-acl).

On macOS, check the opened file and its immediate parent for current-user
ownership, owner-only permissions, and absence of extended ACL entries. Reject
symlink/nonregular files and symlink/nondirectory parents. Mode `0600` alone is
not proof. For an already validated descriptor, only `acl_get_fd_np()` returning
NULL with freshly captured `ENOENT` is accepted as no ACL; other NULL results
fail closed. A valid non-null ACL must have no entries. Darwin entry lookup
returns `0` when an entry exists, unlike Linux. Apple's [ACL
header](https://github.com/apple-oss-distributions/Libc/blob/71bbe350ab79eef58113991d817ccc6165061a64/include/sys/acl.h#L91-L112)
and [entry
implementation](https://github.com/apple-oss-distributions/Libc/blob/71bbe350ab79eef58113991d817ccc6165061a64/posix1e/acl_entry.c#L108-L137)
define the iteration contract. The no-ACL result follows its [descriptor
reader](https://github.com/apple-oss-distributions/Libc/blob/71bbe350ab79eef58113991d817ccc6165061a64/posix1e/acl_file.c#L66-L84)
and [missing-property
handling](https://github.com/apple-oss-distributions/Libc/blob/71bbe350ab79eef58113991d817ccc6165061a64/gen/filesec.c#L141-L154).

These checks protect against other unprivileged identities. They do not
isolate credentials from a compromised current account, administrator/root,
SYSTEM, or concurrent privileged ACL/ancestor changes. A retained handle is
not a general race-free pathname guarantee.

## Canonical WSL controls

The existing `prepare-mariadb-client-config.sh` name is retained as an execution
wrapper, not a copy/path-producing helper. `--check` validates before service
changes; native invocations parse the existing source into bounded process
memory, then use the same anonymous `0600` memfd transport. The accepted source
syntax is one `[client]` group, optional comments, and only `host`, `port`,
`user`, and `password`, with no duplicates or include directives. Missing host
and port mean the local endpoint; controls require loopback and port `3306`.
The normalizer keeps all connection options in memory, never in argv.

The one canonical Windows-backed `Server/mariadb-client.cnf` source has a narrow
DrvFS privacy contract: validate metadata on that exact known Windows path
before reading it, reject a directory/reparse-point leaf or null DACL, and
require owner and every allow ACE to be limited to the current Windows user,
SYSTEM, or Administrators. Trusted-only inherited ACEs are accepted; mode `777`
on DrvFS is not used as privacy proof. The Windows hierarchy must remain stable
under privileged control; its immediate parent must also have trusted ownership
and no unprivileged write/delete-child/permission-changing grant. The read-only
preflight returns only a boolean or
generic failure; never print ACL identities, file values, or hashes. This
exception does not apply to arbitrary paths, which still require effective
POSIX ownership and owner-only permissions. Credentials and ACLs are unchanged.

`open-mariadb-wsl.sh --start-db-only` requires all six services stopped/disabled,
starts only MariaDB, and checks the XI-stopped/DB-running/manual expectation.
Failure rolls back the partial DB start. The normal desktop database console
uses that same gate before opening its bounded native prompt. The full-server
start retains its six-service/eight-port fail-closed lifecycle and preflights
the credential source without creating or deleting any credential copies.

Historical capture/restore scripts are not deployment approval: the old capture
path has separate credential handling and key generation. It is not silently
made safe by this wrapper and must not run without separate review and authority.

## Backup and linked-setting policy

`dbtool`'s plaintext SQL backup path is blocked. Keep `auto_backup=0`; a
configured automatic backup must not silently degrade to an unprotected dump
or silently skip a required backup. The separately reviewed canonical
encrypted capture/restore workflow is the backup route. No new encryption,
key-generation, or credential-provisioning subsystem is introduced here.

Single-table and bulk source-data exports share the existing `player_data`
protection list: account, character, runtime, and other protected tables cannot
be written into Git's SQL sources, including case variants. Export names must
be unquoted SQL identifiers of at most 64 characters and name an existing
regular, non-symlink `sql/<table>.sql` file. The source must declare that same
table; triggers and non-table SQL are rejected. These checks run before any
cursor query or output write. Public static-table value/comment formatting is
unchanged. This source-maintenance path is not a backup or a private-data export
route, and errors never print database values.
The same central list also preserves existing runtime rows during ordinary
content updates, including account sessions, party/alliance membership, login
trust tokens, chat/GM audit data, and character recasts. Missing protected tables
still follow the existing first-setup/import path; this is not a prefix-based
production denylist and does not exclude static fishing or other content tables.

`auto_update_client=false` must preserve `settings/login.lua` even when the
upstream client version differs. An explicitly requested version update may
rewrite an ordinary file, but must never replace a linked login setting,
rewrite its credential target, or create a `.bak` copy. Reject a required
linked-setting rewrite in preflight before SQL mutations. Do not lower
`VER_LOCK` or treat preserving the setting as client-compatibility proof.

Before any separately authorized live migration, require a fresh encrypted
backup and isolated restore proof, an unchanged durable Twills baseline, and
the canonical DB-only/manual-start lifecycle gate. Historical restore
manifests are references, not current recovery instructions. Run the reviewed
migration twice for idempotency and recheck durable state. Keep credentials,
private backups, reports, and logs outside Git. See
[portable restore policy](portable_restore.md).

## Verification and stop boundary

Run the synthetic regression suite from the canonical checkout:

```bash
python3 -m unittest tools.mochirii.tests.test_mysql_client_security tools.mochirii.tests.test_server_control_credentials
git diff --check
```

Tests must cover serialization/injection bounds, absence of password-bearing
arguments/environment, descriptor cleanup and timeout, strict existing-file
privacy/content rejection, blocked plaintext backups, and linked-setting
preservation before SQL mutation. Native Windows/macOS checks require their
own runners; Linux mocks do not establish native ACL behavior. CI alone may
create public synthetic option fixtures under a private `runner.temp`
directory. Never run that fixture provisioning against workstation credentials.

Windows validation intentionally has no cross-call cache: ordinary file stat
metadata is not a reliable ACL-version token. Canonical Linux dbtool imports use
memfd directly and pay no Windows process cost; each canonical control execution
revalidates its source's Windows metadata once. Native Windows option-file calls
perform their metadata check before every client invocation.

Passing source, synthetic, and hosted checks does not prove a live migration,
backup restore, client login/zoning, or Trust readiness. Those remain separate
authorized gates with canonical desktop/runtime controls and native Windower
evidence. Preserve Twills' permanent 17-Trust QA entitlement; retail control
remains one player plus five Trusts. Finish noncombat readiness with the client
closed and all six services stopped/disabled, then stop before combat.
