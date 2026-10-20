# CodeQL extraction and security acceptance

CodeQL findings and extraction coverage are separate gates. A successful workflow,
an empty API `warning`, or zero rated high findings does not prove complete source
analysis or absence of unrated quality findings. No alert is suppressed by this
coverage policy.

For both compiler-traced acceptance lanes, a failed-extractor invocation is a
failure regardless of its notification level. The native numeric compiler/fatal
metric and all existing error diagnostics remain mandatory. Known native
extractor assertion and nonzero-exit messages in extraction warnings are checked
before the report's display truncation; ordinary discretionary warnings remain
visible without being reclassified. A database-create exit of zero, or even a
zero diagnostic metric, is not proof that a crashed extractor produced an AST.
Required source and API coverage must also pass. This is a fail-closed supplement,
not a claim to recognize every possible future extractor failure message.

The Glaze9.0.0 compatibility candidate pins the same official
[release revision](https://github.com/stephenberry/glaze/commit/d78832c82289c61a9315bfbc35332cec9f4e93ca)
and uses a separate revision/patch-content-bound CPM cache; old caches remain
untouched. Its patch names the invented context/iterator/endpoint template
parameters at three declaration/definition pairs. Context and iterator still
forward, the endpoint stays by value, and `noexcept`, inline decorations and all
parsing bodies remain unchanged. JSON's options predicate remains before the
context concept in the single leading conjunction, preserving the
[associated constraint order](https://eel.is/c++draft/temp.constr.decl).
This is a local compatibility evaluation, not a claimed upstream fix. Local
MSVC19.51 native success and failed local CodeQL experiments do not establish
the approved hosted MSVC19.44 result: its exact raw-zero/AST/source/API acceptance
and every other lane remain required. Native regression coverage exercises all
three forms, forwarding, truncation/depth limits and bounded streaming skips.

The same content-bound patch explicitly binds the three validated-number
predicates to the existing `bool(uint8_t) noexcept` overload, preserving the
definition-context lookup when later Glaze headers add `is_digit(char)`. Only
those bindings change; numeric advancement, bounds and error paths do not.
The public Sol container-detection customization marks `as_returns_t<T>` as
non-container: the pinned wrapper privately stores its payload and exposes
`value()`, while its existing dedicated pusher returns multiple Lua values.
Ordinary containers keep their existing traits. See the
[supported trait customization](https://sol2.readthedocs.io/en/latest/containers.html#container-detection).
Three StatusEffect schema annotations spell their existing signed-64 zero
alternative as `int64{0}`; runtime fields/defaults, schema bounds and packet
layouts are unchanged.

Native GCC14 and Clang22 baseline/candidate diagnostics compare all 256
predicate bytes and bounded numeric cases, both Sol include orders with an
isolated Lua state, and byte-identical actual StatusEffect schema JSON.
Focused native regressions retain those contracts. These comparisons establish
native equivalence only, not successful CodeQL extraction. Every hosted lane,
the 40 Linux recovery paths, Windows four-source/eight-API/four-C-body proofs,
zero compiler/fatal errors and zero failed extractor invocations remain required.

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
- A fifth, separately named Windows2022/MSVC14.44 manual category traces only
  `xi_connect` and `xi_profile` plus their common dependencies. The pinned setup
  action selects the explicit VS2022 Enterprise path, MSVC14.44 library/toolset
  and Windows SDK10.0.26100.0
  environment; a bounded native preflight rejects missing/wrong compilers,
  developer environments, toolsets or x64 targets without fallback. Both C/C++
  compiler paths resolve to the selected toolset's real `cl.exe`, not clang-cl,
  MinGW or a simulated extractor dialect. Before any first-party native build,
  the generated CMake compiler contexts and compilation database must prove the
  exact native compiler path, MSVC19.44 identity and Windows x64/LLP64 target.
  Every first-party C++ command requires the sole exact `/std:c++23preview`
  standard option and the existing `/W4`, `/WX`, `/permissive-` policy, with
  `/Zc:__cplusplus` for truthful language macros. Reject conflicting standards,
  warning/conformance overrides and fabricated compiler or language predefines.
  The global reporting enable is set once. Per-command inspection permits
  repeated identical standalone enables because [spdlog1.17.0 adds its own](https://github.com/gabime/spdlog/blob/v1.17.0/CMakeLists.txt#L298-L300)
  after [CMake's global flags](https://cmake.org/cmake/help/v3.31/variable/CMAKE_LANG_FLAGS.html).
  Missing, disabling, malformed or grouped reporting options fail closed in
  dependency commands as well as first-party commands. Actual Windows
  [Windows argument decoding](https://learn.microsoft.com/en-us/windows/win32/api/shellapi/nf-shellapi-commandlinetoargvw)
  uses typed System32-only bindings and exactly one `LocalFree`, not POSIX
  tokenization. The supported CMake command grammar rejects
  adjacent/unmatched quotes, controls, oversized UTF-16 input, response files and
  `/link`; it is not a universal CRT-parser equivalence claim. Mandatory native
  Windows regression cases compare adversarial tokens with real UCRT argv
  delivery against the [CRT rules](https://learn.microsoft.com/en-us/cpp/c-language/parsing-c-command-line-arguments),
  including escaped quotes and literal apostrophes. Compiler/reporting mismatches identify bounded
  source/driver context without printing full commands or environments.
  First-party conformance checks also reject a disabling `twoPhase-` member
  inside [comma-separated `/Zc` options](https://learn.microsoft.com/en-us/cpp/build/reference/zc-conformance),
  regardless of whether it precedes or follows the required conformance flags.
  This compiler-contract change was explicitly approved after the pinned
  Clang20.1.8 trace failed; it does not relax any extraction or security gate.
  The ordinary native MSVC build configuration remains unchanged.
  CMake3.31.6's [MSVC module](https://github.com/Kitware/CMake/blob/v3.31.6/Modules/Compiler/MSVC-CXX.cmake#L30-L36)
  maps C++23 to `-std:c++latest`, which also enables post-C++23 features. The
  CI-only, guarded [`CMAKE_PROJECT_server_INCLUDE` hook](https://cmake.org/cmake/help/v3.31/variable/CMAKE_PROJECT_PROJECT-NAME_INCLUDE.html)
  replaces both stock C++23 option mappings after language initialization;
  other compilers/build lanes never load it. Generated command inspection
  verifies the actual option rather than trusting `CMAKE_CXX_STANDARD=23`.
  The lane initializes tracing without a C++ frontend override, then builds the
  four pinned bcrypt C inputs in that same database. Their native commands may
  not force C++ mode or fabricate compiler predefines. Unique object outputs
  must be absent before this build and present afterward, with an unchanged
  compilation database. Only then does the lane enable C++23 for schema and
  server compilation; no C input is moved outside tracing or excluded.
  The raw gate also requires exactly one `windows-bcrypt-c-bodies` metric of
  four: distinct pinned-source files with actual function bodies and traced
  compilations. Header declarations, duplicate compilations, and no-build
  extraction cannot satisfy this additional gate. Existing four-source,
  eight-API, numeric-zero and failed-extractor gates remain mandatory.
  Only this Windows lane supplies `--ms_c++23` through the pinned extractor's
  supported `frontend_options` transport. The native compiler's exact
  `/std:c++23preview` switch is otherwise unrecognized by CodeQL2.27.2; generic
  `--c++23` does not restore `_MSVC_LANG` and therefore changes ASIO feature
  selection. The [MSVC-specific language option](https://edgcpp.org/doc/ext_intf/#language-dialect-options)
  preserves the naturally detected Microsoft compiler/version and its C++23
  feature set, rather than forcing Microsoft emulation onto another compiler.
  Native macro undefinitions, fabricated feature values, replacement standard
  headers and diagnostic suppressions are not used.
  Windows system-library linkage continues to follow `WIN32`, preserving the
  same timer/debug/network imports and CMake's normal default libraries.
  The bounded native probe includes the actual `common/macros.h` first and
  verifies CRT aliases against `_stricmp`, `off_t`/`_off_t`, Windows x64/LLP64,
  native compiler/language identity, alternative tokens, definition-context
  two-phase lookup, defaulted comparison and C++23/STL features. It also covers
  the complete-but-no-`value` tuple-size structured-binding rule. A separate
  C++20 negative control rejects the C++23/STL feature test, so a mode label
  alone cannot establish the selected features. `/permissive-` enables
  conforming two-phase lookup; an extra positive `/Zc:twoPhase` is omitted,
  and ignored driver options are not accepted
  merely because `/WX` leaves the compiler exit code zero. See Microsoft's
  [standard-mode](https://learn.microsoft.com/en-us/cpp/build/reference/std-specify-language-standard-version?view=msvc-170)
  and [two-phase lookup](https://learn.microsoft.com/en-us/cpp/build/reference/zc-twophase?view=msvc-170)
  contracts. No production object from these probes is reused. Their success
  does not establish extractor compatibility: only the unchanged raw coverage,
  numeric zero compiler/fatal-error and eight-family API gates accept CodeQL.
  Generated-header steps and the
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

Both later clang-cl20.1.8 spellings (`-clang:-std=c++23` and
`/std:c++23preview`) passed native compilation but produced the same failed
extraction: 12,127 compiler errors and zero of the eight private-file API
families. The second also passed the native C++23 macro/library proof. These
are retained diagnostic results, not acceptance; aggregate extractor language
telemetry does not establish the mode of every translation unit. The GNU
frontend candidate keeps the same compiler version, Windows ABI, SDK/toolset
and exact C++23 mode while avoiding the CL-driver argument-translation path.

The first GNU-frontend Windows trace then failed native compilation on two
deprecated `strcmpi` calls in authentication, before SARIF existed. The existing
comparison portability block now maps both Windows aliases to Microsoft's
documented equivalent preferred [`_stricmp`](https://learn.microsoft.com/en-us/cpp/c-runtime-library/reference/strcmpi?view=msvc-170).
It includes `<cstring>` before defining aliases, preventing a macro from
rewriting the UCRT's own deprecated declarations. POSIX aliases remain
`strcasecmp`; null-terminated, locale-sensitive comparison and authentication
decisions are unchanged. No warning suppression or replacement comparison
algorithm is introduced. Actual native Windows proof remains required.

The subsequent d6c GNU-frontend trace passed native compilation, queries, all
four required Windows source files and all eight API families, but retained
525 native compiler errors and 21 aborted-invocation notifications. That raw
gate failure remains preserved and is not accepted. A controlled, pinned
CodeQL2.27.2/Clang20.1.8 real-header reproduction isolated alternative-token
handling and extractor-only system-header `__STDC__` state: the native numeric
error query fell from six to three with `--alternative_tokens`, then to zero
with the real native `-U__STDC__`; the exact environment transport also passed.
Native macro and preprocessed output were identical before/after undefinition,
including the real CRT types and ABI. These diagnostic checks used local
MSVC14.51 headers, not the required CI14.44 toolset. They do not prove that all
ASIO substitution diagnostics or the complete trace are corrected. Fresh exact
CI14.44 raw extraction must still pass every unchanged acceptance gate; neither
the reproduction nor a successful native build permits deployment. A separate
definition-context overload probe passes both native compilation and extraction
with `--dep_name`; this narrow documented option avoids the wider semantic
changes of switching Microsoft emulation modes. Its exact newline-separated
environment transport was also reproduced with zero compiler/fatal records.
The [extractor-options interface](https://docs.github.com/en/code-security/reference/code-scanning/codeql/codeql-cli/extractor-options)
and the exact pinned extractor schema provide the option transport; EDG's
[frontend documentation](https://edgcpp.org/doc/ext_intf/)
defines `--alternative_tokens`. LLVM20.1.8's
[native preprocessor initialization](https://github.com/llvm/llvm-project/blob/llvmorg-20.1.8/clang/lib/Frontend/InitPreprocessor.cpp)
defines the MSVC-compatible absence being preserved. No dependency version,
standard, runtime behavior, query or coverage denominator changes here.

The complete385e GNU-frontend trace then passed native compiler/header/language
proof, traced compilation/linking and query execution, with all four required
Windows sources and eight API families. It still failed the unchanged raw gate:
542 compiler errors, 197 extraction-warning groups and17 aborted-invocation
notifications. The earlier token, CRT-offset, ambiguous query cleanup and
missing ASIO work-result diagnostics were absent, but Glaze structured-binding
and constrained-declaration, ASIO executor-trait, JSON iterator and cpptrace
diagnostics remained. No single microprobe explains all groups, and native build
success does not establish source analysis. These failed artifacts remain
diagnostic-only and do not permit a merge or deployment.

Source-bound minimal probes reproduced a native-valid CWG2386 aggregate binding
that CodeQL2.27.2 rejects, including with independently verified public17.14 STL
headers. This defect-report rule requires a complete tuple-size class **with a
`value` member** before choosing tuple-protocol decomposition; absence of that
member permits aggregate binding. See [CWG2386](https://cplusplus.github.io/CWG/issues/2386.html).
Neither speculative SFINAE/language switches nor changing compiler spelling
verified a faithful correction in that Clang evaluation. CodeQL2.27.2 was the latest stable release at
evaluation; its [support matrix](https://codeql.github.com/docs/codeql-overview/supported-languages-and-frameworks/)
lists VS2022 and explicitly qualifies C++23 support as beta. The approved
real-MSVC evaluation traces the actual compiler's semantics instead of forcing
Microsoft emulation onto a Clang build. Local VS18/14.51 probes, if successful,
remain diagnostic-only; exact CI14.44 raw results and every retained gate must
pass before acceptance.

Real-MSVC local diagnostics distinguish native compiler acceptance from scanner
behavior. On the installed VS18/14.51 compiler, native C++23-preview compilation
and strict CRT/ABI/feature proofs pass. Natural CodeQL tracing fails to recognize
the preview flag; generic C++23 selection still omits `_MSVC_LANG`. The precise
`--ms_c++23` option yields zero numeric compiler/fatal errors for source-bound
valid structured-binding and real-header/CRT probes, without defining compiler
macros manually. These are not exact VS2022/14.44 or full-project acceptance.
A deliberately invalid tuple-value control is rejected by the native compiler
but accepted by this extractor; that failed diagnostic control is retained,
not reported as a pass or semantic-conformance proof. CodeQL is not a substitute
for the mandatory strict native build. Actual dependency feature branches and
all fresh coverage/API/error gates still require separate verification.

ASIO remains at the verified 1.38.0 source commit
`03cf5f86a780dd102f1cdd3a59d1244d12143e46`, with only the maintainer's
[non-invocable work-result correction](https://github.com/chriskohlhoff/asio/commit/f71a59e0673c4c4b3c936225ac36baabb3ba8db7)
backported. The empty primary template and `void_t` specialization preserve
valid callable results while making invalid substitution fail cleanly. The
existing CPM patch mechanism keys a separate source cache by revision and
patch content, preserving the unpatched cache. No newer mutex, scheduler,
executor layout or unrelated ASIO changes are imported. A registered native
regression checks value/void/non-callable substitution and queued, exactly-once
type-erased execution, increasing the complete native case count from 110 to
111. Local reproduction removed the ASIO diagnostics; fresh full CI extraction
and native regression execution remain required and are not implied by that
diagnostic result.

The first supported-toolchain candidate passed native compiler/SDK preflight but
failed CMake generation before CodeQL initialization: fmt12.2.0 auto-enabled its
optional module for clang-cl, while CMake3.31.6 has no MSVC-frontend Clang module
scanner. The pinned dependency now explicitly sets `FMT_MODULE OFF`. Mochirii
uses fmt's headers and `fmt::fmt`, not module imports; both remain unchanged.
This disables an unused dependency target, not CodeQL source scanning, query
suites, compiler diagnostics or first-party coverage requirements.

The pinned efsw revision's Windows failed-watch cleanup deletes the allocated
watcher, not its null borrowed parent. A repository-owned one-line patch is
applied through native CPM `PATCHES`; the revision and patch-content digest
derive a separate cache key, preserving prior caches and preventing stale patch
reuse. Both are unchanged when its tab-free tracked template is rendered through native
`configure_file(@ONLY NEWLINE_STYLE LF)`. The rendered patch is byte-identical
to the previously validated patch; both container staging images explicitly
install `patch` as a build-only dependency. No sanity-check exemption is needed.
The full Linux no-PCH trace also requires PacketCap's direct `fmt/chrono.h`
include for its existing timestamp formatter; no format or capture behavior changes.
The PR schema job consumes an external devtools image, so it independently
installs the same native `patch` build prerequisite when absent; rebuilding this
repository's Dockerfile alone cannot update that external image. Windows clang-cl
also requires the crash reason's already-empty optional `detail` member to be
explicitly initialized under the retained warnings-as-errors policy. This does
not alter crash-report contents or suppress a diagnostic.
The data records also explicitly default their previously empty optional/sequence
members (`Hide`, `Holes`, `Route`, `Members`) at declaration. This preserves their
existing empty states when an aggregate omits them, retains aggregate layout and
the separate wire-schema contract, and satisfies the same strict Windows warning
without changing compiler flags or expanding every aggregate call site.
Profile call sites likewise explicitly retain their already-zero reserved fields,
arrays and checksums, and empty optional/callback members. Packed protocol type
definitions are unchanged. All 16 profile translation units pass the same strict
missing-member diagnostic without precompiled headers after the focused fix.
Fault injection of the exact pinned function bodies with mock Windows
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
[named-project include timing](https://cmake.org/cmake/help/v3.31/command/project.html#code-injection),
[fmt12.2 optional module contract](https://github.com/fmtlib/fmt/blob/12.2.0/CMakeLists.txt#L47-L79),
[CMake3.31 Clang frontend module support](https://github.com/Kitware/CMake/blob/v3.31.6/Modules/Compiler/Clang-CXX.cmake#L29-L67),
[Glaze9 MSVC interface contract](https://github.com/stephenberry/glaze/blob/v9.0.0/CMakeLists.txt#L21-L41).
