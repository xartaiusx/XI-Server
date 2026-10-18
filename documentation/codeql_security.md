# CodeQL extraction and security acceptance

CodeQL findings and extraction coverage are separate gates. A successful workflow,
an empty API `warning`, or zero rated high findings does not prove complete source
analysis or absence of unrated quality findings. No alert is suppressed by this
coverage policy.

## Preserved analysis contracts

- Keep `security-extended` and `security-and-quality`, the existing `ext/**` and
  `build/**` exclusions, and no-build C++/Python categories. Existing category and
  required-check names remain stable. The compiler-traced C++ lane reuses the
  exact historical `:analyze/language:cpp` category to reconcile its retained
  alerts without replacing broad current no-build discovery. A separate cheap
  Python lane refreshes `:analyze/language:python`. No category is hidden or
  deleted; native `--sarif-category` generation preserves matching semantics.
- Both Linux C++ categories use the existing Ubuntu26.04/GCC15 CI toolchain. Configure
  CMake and generate enum/IPC/dependency headers before initialization. Native
  schema validation builds common/data libraries and runs only after tracer
  initialization in both manual lanes, so no first-party bootstrap object is
  reused untraced. No-build analysis needs no native schema executable. The traced
  category then compiles all six native targets with a fresh Debug build, no
  PCH/IPO/compiler cache, and the existing custom/era/example modules plus the
  optional packet-capture source. That module is enabled **only in ephemeral CI**;
  this workflow never starts a server or enables live packet capture.
- A fifth, separately named Windows2022/clang-cl20.1.8 manual category traces only
  `xi_connect` and `xi_profile` plus their common dependencies. The pinned setup
  action selects the explicit VS2022 Enterprise path, MSVC14.44 library/toolset
  and Windows SDK10.0.26100.0
  environment; a bounded native preflight rejects missing/wrong compilers,
  developer environments, toolsets or x64 targets without fallback. Both C/C++
  compiler paths are explicit. Before any native build/tracing, the generated
  CMake compiler contexts must prove Clang20.1.8/MSVC frontend/exact paths and
  every first-party C++ compilation command must use `-clang:-std=c++23`, never
  `c++latest`/C++26. CMake3.31.6 supplies that native standard flag for clang-cl17+.
  The normal native MSVC Build lane is unchanged. Generated-header steps and the
  fresh uncached/no-PCH Debug context remain. Existing four categories/check names and full
  query suites are unchanged. The shared local coverage pack is added to every
  C++ lane with the native `+` query input so it cannot replace configured
  security/quality queries.
- Checkout does not persist credentials. Permissions remain actions/contents
  read and security-events write; no privileged PR event or secrets are added.
- `CODEQL_ACTION_FILE_COVERAGE_ON_PRS=true` keeps native file baselines on PRs.
  The pinned action otherwise omits them on PRs to improve performance.
- Save raw pre-filter SARIF and the deterministic coverage report in a unique
  exact-source-SHA artifact, even when the gate fails. GitHub's analysis REST API
  returns only a SARIF subset, not this baseline inventory. Retain runtime/private
  downloads outside Git.

`tools/mochirii/codeql_coverage.py` consumes native baseline and
`successfully-extracted-files` diagnostic notifications. Alert locations and
files merely present in a source archive are **not** evidence of extraction.
Missing/malformed metadata, source/category mismatch, failed invocation, zero
baseline/extraction, unsafe paths, missing required translation units, and traced
compiler/error diagnostics fail closed. File coverage does not prove every
conditional platform branch or successful parsing of every expression.
The pinned action's modern baseline IDs are `cli/expected-extracted-files/c`
and `/cpp` (C/C++), and `cli/expected-extracted-files/python`; legacy language-specific
baseline IDs remain accepted. Tests cover both native formats without treating
another language's baseline as coverage.
Raw pre-upload SARIF can omit `versionControlProvenance`; the CLI independently
verifies checkout `HEAD` against the requested source SHA, which is `GITHUB_SHA`
in CI. Any SARIF provenance present must match. PR scans therefore bind to the
checked-out synthetic merge commit, not merely the PR head. Raw SARIF is never
rewritten to fabricate provenance.

Every C++ report requires exactly one native numeric row from
`.github/codeql/security-coverage/CompilerErrorsTotal.ql`. Its global count includes
the pinned native `CompilerError` (severity4) and `CompilerCatastrophe` (severity5)
classes. Missing, duplicate, noninteger, boolean or negative totals fail closed;
missing execution evidence is never converted to zero. Both manual lanes require
an actual zero, while no-build discovery retains positive totals for review
without changing its breadth. The original grouped compiler-error telemetry is
preserved separately as `compiler_error_groups_sum`; `compiler_errors` is the
explicit native total, or null when unavailable. Suppressible discretionary
diagnostics (severity3), warnings and notes remain visible and reviewable; a zero
error/fatal count is not proof of complete parsing or security cleanliness.
The numeric-only query returns one row even when its count is zero. The native
CLI exports summary metrics into `run.properties.metricResults`; actual zero
serialization and query execution must still be verified in the fresh candidate
raw SARIF. Fixture tests or resolved-query/rule metadata cannot substitute for it.

The focused Windows gate additionally requires one native metric row from
`.github/codeql/security-coverage/WindowsPrivateFileCalls.ql`, with value8.
The metric counts distinct required call-target names **inside the extracted
`certificateHelpers::openExclusivePrivateFile` AST in `cert_helpers.h`**:
SDDL conversion, exclusive `CreateFileW`, volume ACL support, `CloseHandle`,
`LocalFree`, `_open_osfhandle`, `_fdopen`, and descriptor-close failure handling
with `_close`. Missing/duplicate/malformed metrics, fewer than eight families,
missing login/profile/Windows-common source extraction, or compiler/error
diagnostics fail closed. This is branch extraction evidence, not a claim that
every runtime failure path has executed. The local query pack pins
`codeql/cpp-all`12.2.0, matching the inspected CodeQL2.27.2 query sources; native
pack resolution, query compilation, explicit compiler-error zero and the Windows
metric must be proved by the actual candidate run, not mocked SARIF or source
review.

The shared pack runs on all C++ lanes, but Linux does not require its Windows
metric to be8. The focused Windows lane does not apply the Linux40-unit recovery
minimum, since it intentionally does not build
map/search/world/tests; it still reports its complete native baseline and every
missing file without exclusions or a reduced denominator. File inventories
across categories and this specific positive API metric are separate evidence.

The report retains every missing baseline path and separates the existing
vendor/generated denominator from first-party counts. It also reports diagnostic
messages and finding counts by rule, SARIF level, security-vs-quality taxonomy and
numeric security-severity band. An absent security score is `unrated`, never an
invented zero/low score. The coverage gate does not dismiss findings or declare
all warnings reviewed.

## Source-bound initial inventory

Analysis1975798551, main `02c7f2f7729161b1fd3e9588bc28f7c1c652b02a`,
CodeQL2.27.2/cpp-queries1.9.1: C++1249/1312 and C155/162. Its exact analysis-only
CSV contains1474 rows,70 unextracted paths (40 `.cpp`,30 `.h`), all first-party,
with blank failure-reason cells. The authenticated global status page aggregates
older configurations; do not substitute those aggregate totals.
The source-bound open inventory is577 findings. A separate137 open historical
records last analyzed at771f6b7 remain under the pre-build-mode categories,
including21 rated findings; those must be reconciled against current code and
fresh final-main scans. Their old locations/severities are not current source
proof, and omission from a new category cannot close their review obligations.

The40 translation units are the explicit minimum regression-recovery set in
`CPP_RECOVERY_PATHS`. They include production database/session/network/Lua/Trust/
inventory/profile/search code, five test translation units, and optional
`modules/tools/packetcap/packetcap.cpp`. All40 must be extracted in the manual
category; future missing files remain visible rather than shrinking a denominator.

The30 headers are not a blanket exemption:

- Six Windows resource-ID headers: `res/connectserver.h`, `mapserver.h`,
  `profileserver.h`, `searchserver.h`, `testserver.h`, `worldserver.h`. They contain
  icon/resource-editor constants, not executable server logic. Keep their missing
  status explicit; Windows native resource compilation is separate evidence.
- Fifteen S2C layouts: `0x005_packetcontrol.h`, `0x006_naraku.h`, `0x012_gm.h`,
  `0x013_gmcommand.h`, `0x02e_openmogmenu.h`, `0x03b_eventmes.h`,
  `0x060_musicvolume.h`, `0x096_myroom_enter.h`, `0x097_myroom_exit.h`,
  `0x0ab_feat_data.h`, `0x0b7_gmscitem.h`, `0x0de_group_solicit_no.h`,
  `0x0e2_group_list2.h`, `0x0e6_ballista.h`, `0x117_equipset_res.h` under
  `src/map/packets/s2c/`. Fourteen have no source `#include` reference at02c;
  `0x02e_openmogmenu.h` is included by `lua_base_entity.cpp` and is a real gap.
  Unreferenced declarations are not vendor files and must not be filtered away.
- `src/common/pch.h` is the disabled-in-CI include aggregator; the headers it
  includes must still be analyzed through their actual translation units.
- Remaining real contracts: `src/common/engine.h`, `src/common/rng/null.h`,
  `src/map/enums/chat_message_area.h`, `src/map/items/exdata/storage_slip.h`,
  `src/map/packets/c2s/0x085_shop_sell_set.h`,
  `src/map/ximesh/transformation_matrix.h`, `src/test/mock_socket.h`,
  `src/test/reporters/ctrf_types.h`.

The original database contains GCC14 headers and extensive parser diagnostics:
missing generated `xi::StatusEffect`/`xi::Weather`, unresolved `sol::object`,
logging symbols, and `std::to_underlying`. Therefore, upgrading a runner alone is
not proven sufficient; generated headers and actual traced compiler context are
required. No-build extraction intentionally hides some recoverable warnings.

## Required review and remaining platform proof

The deployment gate is risk-based, not a requirement to erase every style note.
Review each current and historical instance against current source and preserve
its disposition in private runtime evidence. Confirmed security/correctness
defects must be fixed and verified; non-security quality debt may remain open
with an explicit rationale. Unrated is not low risk. New findings from recovered
code require the same review before merge/deployment.

The initial714-record review (577 current,137 historical) identified real missing
ability/Feint-effect null checks and unsized scheduler FOURCC string reads.
Focused native/Lua regressions accompany those fixes. The review also hardened
native DB credential transport, protected runtime tables/source exports,
linked-setting preservation, launcher report privacy and Python error handling.
Source review alone is not acceptance of those changes.

Retained quality debt includes genuine one-case switches, long-switch/
documentation/complexity concerns, placeholder logging/cleanup branches,
established short names and harmless binding/interface cleanup. Existing
value-taking checksum/ownership constructors and RAII/module registration are
intentional contracts, not speculative performance fixes. Template/coroutine/
macro and switch extraction discrepancies remain candidates until current traced
results corroborate them; never remove active validation to silence those notes.
No alert dismissal, suppression, core exclusion or denominator reduction is
part of this gate.

The earlier d297 Windows2025 job actually used the VS2026 image20261007.264.1
and MSVC14.51, outside CodeQL's documented Microsoft-extension range (VS2022).
Its native build and Windows API metric8 passed, but34 compiler errors and17
aborted extractor invocations failed the gate. Those results are diagnostic,
not security acceptance. Clang-cl20.1.8 lies within both CodeQL's documented
Clang range and Glaze9's tested Clang18+ range; C++23 extraction is still beta,
so fresh native zero-error/Windows8 proof is mandatory, not inferred from this
toolchain change. The Glaze interface facade also retains upstream's three
real-MSVC-only C++ conformance options; clang-cl never inherits those options.
Only `/MP` is restricted to the real MSVC driver; warnings-as-errors are retained.

The pinned efsw revision's Windows failed-watch cleanup deletes the allocated
watcher, not its null borrowed parent. A repository-owned one-line patch is
applied through native CPM `PATCHES`; the revision and patch-content digest
derive a separate cache key, preserving prior caches and preventing stale patch
reuse. Fault injection of the exact pinned function bodies with mock Windows
APIs reproduced all three original failure leaks and verified corrected cleanup
plus unchanged success ownership. That is native Linux source-level proof, not
native Windows API or heap measurement; fresh Windows builds remain required.

Profile presence registration now removes a newly inserted or newly published
session if status lookup or friend announcement throws before returning the
cleanup ID. A previously registered session is retained if an exception occurs
before replacement publication. Four native fault-injection cases cover initial
lookup, announcement, successful replacement/stale sign-off and failed replacement
recovery using unopened sessions and an in-memory database. Normal coroutine
frame lifetime is not itself a demonstrated dangling-pointer defect; the fixed
exception path is a separate ownership failure.

1. Run the targeted coverage/policy tests, then fresh no-build, full Linux traced
   and focused Windows traced scans on one immutable candidate. Inspect raw
   diagnostics, recover all40 Linux units, require an explicit native compiler-error
   zero in both manual lanes, and require the Windows AST metric8.
2. Review remaining header gaps individually and compare the union of current
   categories; never claim100% by dropping baseline files or treating a source
   archive as extraction. If critical Windows-only implementation remains outside
   analyzed preprocessor branches, do not claim those covered merely because the
   new private-file metric passes. Six resource constant headers alone do
   not justify three additional expensive full-platform scan builds.
3. Reconcile every finding against current fully extracted code. Preserve real
   fixes/tests; do not dismiss none-mode findings merely because manual differs.
   Security and unrated quality acceptance are explicit review decisions.
4. Protected PR review/merge and final-main scans are distinct from local build,
   restored-DB simulation, deployment and native Windower verification. This
   workflow changes no runtime, credentials, services, client or Twills entitlement.

Primary contracts:
[compiled build modes](https://docs.github.com/en/code-security/reference/code-scanning/codeql/build-options-for-compiled-languages),
[raw file baseline](https://docs.github.com/en/code-security/tutorials/customize-code-scanning/analyze-code),
[REST SARIF subset](https://docs.github.com/en/rest/code-scanning/code-scanning),
[pinned PR baseline control](https://github.com/github/codeql-action/blob/6f2ac81f5cd81fe351a197ba0b00d91d03cd2aee/src/init.ts#L304),
[pinned native metric shape](https://github.com/github/codeql/blob/a7057b836bf29767461026718b14d20790b9085f/cpp/ql/src/Summary/LinesOfCode.ql),
[pinned native diagnostic classes](https://github.com/github/codeql/blob/a7057b836bf29767461026718b14d20790b9085f/cpp/ql/lib/semmle/code/cpp/Diagnostics.qll),
[native summary-metric export](https://codeql.github.com/docs/codeql-overview/codeql-changelog/codeql-cli-2.5.3/),
[native extracted-file query](https://github.com/github/codeql/blob/main/cpp/ql/src/Diagnostics/ExtractedFiles.ql),
[no-build diagnostic behavior](https://github.com/github/codeql/blob/main/cpp/ql/src/Diagnostics/ExtractionWarnings.ql),
[supported compiler/language ranges](https://codeql.github.com/docs/codeql-overview/supported-languages-and-frameworks/),
[Windows2022 runner image](https://github.com/actions/runner-images/blob/main/images/windows/Windows2022-Readme.md),
[pinned developer-environment inputs](https://github.com/TheMrMilchmann/setup-msvc-dev/blob/368ef7d1ee4d1171b31d4a7f67f4d954f903f5a9/action.yaml),
[native CMake clang-cl C++23 selection](https://github.com/Kitware/CMake/blob/v3.31.6/Modules/Compiler/Clang.cmake#L230-L238),
[Glaze9 MSVC interface contract](https://github.com/stephenberry/glaze/blob/v9.0.0/CMakeLists.txt#L21-L41).
