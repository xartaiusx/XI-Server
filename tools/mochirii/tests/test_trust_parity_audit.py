from __future__ import annotations

import datetime as dt
import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path

MODULE_PATH = Path(__file__).resolve().parents[1] / "trust_parity_audit.py"
SPEC = importlib.util.spec_from_file_location("trust_parity_audit", MODULE_PATH)
assert SPEC and SPEC.loader
audit = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = audit
SPEC.loader.exec_module(audit)

FIXTURE_ROOT = Path(__file__).resolve().parent / "fixtures" / "trust_parity"
NOW = 2_000_000_000
COMMIT = "a" * 40
PLAYER = "Twills"


def bool_text(value: bool) -> str:
    return "true" if value else "false"


def evidence_line(fields: dict[str, object]) -> str:
    return "\t".join(f"{key}={value}" for key, value in fields.items())


def build_session(
    mode: str,
    *,
    combat: bool = False,
    diagnostic: bool = False,
    progression_only: bool = False,
    truncated: bool = False,
    closed: bool = False,
    campaign_extravaganza: int = 3,
    campaign_expo: int = 1,
    start_epoch: int = NOW - 100,
) -> list[str]:
    contract = audit.MODE_CONTRACTS[mode]
    roster = contract["roster"]
    trust_ids = [trust_id for trust_id, _ in roster]
    trust_names = [name for _, name in roster]
    extension = mode == audit.MODE_ALLIANCE
    first = contract["party_trust_counts"][0]
    second = first + contract["party_trust_counts"][1]
    party_rosters = (roster[:first], roster[first:second], roster[second:])
    session_id = f"Twills-1234-{start_epoch}-1"
    rows: list[str] = []

    def append(
        record_type: str,
        event: str,
        state: str,
        **extra: object,
    ) -> None:
        sequence = len(rows) + 1
        epoch = start_epoch + sequence
        fields: dict[str, object] = {
            "schema_version": 2,
            "record_type": record_type,
            "session_id": session_id,
            "server_commit": COMMIT,
            "sequence": sequence,
            "timestamp_epoch": epoch,
            "timestamp_utc": dt.datetime.fromtimestamp(epoch, dt.timezone.utc).strftime(
                "%Y-%m-%dT%H:%M:%SZ"
            ),
            "owner": PLAYER,
            "owner_id": 1234,
            "evidence_mode": mode,
            "topology": contract["topology"],
            "state": state,
            "generation": 1,
            "zone": 100,
            "trust_engage_type": (
                0 if record_type == "session_end" else contract["trust_engage_type"]
            ),
            "event": event,
        }
        if record_type != "combat":
            fields["log_truncated"] = "false"
        fields.update(extra)
        rows.append(evidence_line(fields))

    append(
        "session_begin",
        "session_begin",
        "idle",
        entitlement=1,
        actual_gm=5,
        visible_gm=0,
        authorized="true",
        alliance_active="false",
        authorization_predicate_available="true",
        feature_enabled="true",
        max_parties=3,
        expected_count=len(roster),
        expected_trust_ids=",".join(str(value) for value in trust_ids),
        expected_trust_names=",".join(trust_names),
        expected_party1_count=contract["party_trust_counts"][0],
        expected_party2_count=contract["party_trust_counts"][1],
        expected_party3_count=contract["party_trust_counts"][2],
        expected_party1_trusts=",".join(name for _, name in party_rosters[0]) or "none",
        expected_party2_trusts=",".join(name for _, name in party_rosters[1]) or "none",
        expected_party3_trusts=",".join(name for _, name in party_rosters[2]) or "none",
        expected_party1_trust_ids=",".join(str(value) for value, _ in party_rosters[0])
        or "none",
        expected_party2_trust_ids=",".join(str(value) for value, _ in party_rosters[1])
        or "none",
        expected_party3_trust_ids=",".join(str(value) for value, _ in party_rosters[2])
        or "none",
        aep_setting="true",
        aep_effective="true",
        unity_setting="true",
        unity_effective=bool_text(extension),
        campaign_extravaganza_setting=campaign_extravaganza,
        campaign_expo_setting=campaign_expo,
        campaign_extravaganza_effective="false",
        campaign_expo_effective=bool_text(extension and campaign_expo != 0),
        campaign_effective=bool_text(extension and campaign_expo != 0),
        combat_summoning_setting="false",
        combat_summoning_effective="false",
        defensive_setting="true",
        defensive_effective=bool_text(extension),
        shared_target_setting="true",
        shared_target_effective=bool_text(extension),
        role_enmity_setting="true",
        role_enmity_effective=bool_text(extension),
        combat_rest_setting="true",
        combat_rest_effective=bool_text(extension),
        qa_extension=bool_text(extension),
        qa_watermark=(
            "MOCHIRII EXTENSION — NOT RETAIL ACCEPTANCE" if extension else "none"
        ),
        log_truncated="false",
    )
    idle_roster_fields = {
        "expected_count": len(roster),
        "expected_trust_ids": ",".join(str(value) for value in trust_ids),
        "active_count": 0,
        "active_trust_ids": "none",
        "active_trust_names": "none",
        "real_pc_count": 1,
        "party1_count": 1,
        "party2_count": 0,
        "party3_count": 0,
        "duplicate_count": 0,
        "unexpected_count": 0,
        "order_match": "false",
        "exact_match": "false",
    }
    append("roster", "preflight", "idle", **idle_roster_fields)
    append("roster", "cleared", "idle", **idle_roster_fields)
    append(
        "session_state",
        "spawning",
        "spawning",
        alliance_active=bool_text(extension),
    )

    if diagnostic:
        append(
            "diagnostic",
            "combat_diag",
            "spawning",
            trust=roster[0][1],
            trust_id=roster[0][0],
            focus_target_targid=0,
            focus_reason=0,
            role_enmity_action=0,
            role_enmity_target_targid=0,
            trust_rest_mode=0,
            trust_rest_start_reason=0,
        )

    for attached_count, (trust_id, trust_name) in enumerate(roster, 1):
        append(
            "logger",
            "logger_attached",
            "spawning",
            trust_id=trust_id,
            trust_name=trust_name,
            attach_reason="synthetic-test",
            attached_count=attached_count,
        )
        append(
            "combat",
            "progression_bonus",
            "spawning",
            trust=trust_name,
            trust_id=trust_id,
            aep_hp_rank=1,
            aep_mp_rank=1,
            aep_stat_rank=1,
            aep_combat_rank=1,
            aep_magic_rank=1,
            unity_parity_rank=1,
            unity_parity_stat_bonus=10 if extension else 0,
        )

    ready_roster_fields = {
        "expected_count": len(roster),
        "expected_trust_ids": ",".join(str(value) for value in trust_ids),
        "active_count": len(roster),
        "active_trust_ids": ",".join(str(value) for value in trust_ids),
        "active_trust_names": ",".join(trust_names),
        "real_pc_count": 1,
        "party1_count": contract["party_counts"][0],
        "party2_count": contract["party_counts"][1],
        "party3_count": contract["party_counts"][2],
        "duplicate_count": 0,
        "unexpected_count": 0,
        "order_match": "true",
        "exact_match": "true",
    }
    append(
        "roster",
        "summon_complete",
        "ready",
        **ready_roster_fields,
    )
    append(
        "session_state",
        "ready",
        "ready",
        alliance_active=bool_text(extension),
    )
    begin_fields = dict(token.split("=", 1) for token in rows[0].split("\t"))
    checkpoint_fields = {
        key: begin_fields[key]
        for key in audit.SESSION_BEGIN_FIELDS
        if key in begin_fields
    }
    checkpoint_fields.update(ready_roster_fields)
    checkpoint_fields.update(
        {
            "alliance_active": bool_text(extension),
            "attached_count": len(roster),
            "pending_timers": 1,
            "combat_acceptance": "not_run",
            "log_truncated": "false",
        }
    )
    append(
        "checkpoint",
        "summon_complete",
        "ready",
        **checkpoint_fields,
    )

    if progression_only:
        # The exact per-Trust progression rows above are deliberately the only
        # record_type=combat rows in this fixture.
        pass
    if combat:
        action_context = {
            "action_uid": "synthetic-action-1",
            "decision": "executed",
            "rejection_reason": "none",
            "outcome": "packet_emitted",
            "trust": "valaineral",
            "trust_id": 910,
            "trust_entity_id": 500,
            "trust_mp": 100,
            "source": "synthetic",
            "action_category": 1,
            "action_category_name": "BasicAttack",
            "action_id": 1,
            "action_recast_ms": 0,
            "focus_target_targid": 321 if extension else 0,
            "focus_reason": 1 if extension else 0,
            "role_enmity_action": 1 if extension else 0,
            "role_enmity_target_targid": 321 if extension else 0,
            "gambit_target": 1,
            "gambit_reaction": 1,
            "gambit_select": 1,
            "distance_to_current_target": "2.0",
            "distance_to_primary_target": "2.0",
            "action_range": "2.0",
            "distance_to_master": "1.0",
            "actor_x": "1.0",
            "actor_y": "2.0",
            "actor_z": "3.0",
            "master_x": "0.0",
            "master_y": "0.0",
            "master_z": "0.0",
            "current_target_x": "3.0",
            "current_target_y": "2.0",
            "current_target_z": "3.0",
            "primary_target_x": "3.0",
            "primary_target_y": "2.0",
            "primary_target_z": "3.0",
            "primary_target_objtype": 4,
            "enmity_ce": 10,
            "enmity_ve": 20,
            "enmity_total": 30,
            "packet_actor_id": 500,
        }
        append(
            "combat",
            "action_packet",
            "ready",
            **action_context,
            target_count=1,
            result_count=1,
            total_param=25,
        )
        result_context = dict(action_context)
        result_context["outcome"] = "hit"
        append(
            "combat",
            "action_result",
            "ready",
            **result_context,
            packet_raw_target_id=600,
            packet_target_resolution="entity",
            target_index=0,
            result_index=0,
            result_resolution=1,
            result_resolution_name="hit",
            result_param=25,
            message_id=1,
            message_name="attack_hit",
            packet_target_objtype=4,
            packet_target_x="3.0",
            packet_target_y="2.0",
            packet_target_z="3.0",
            distance_to_packet_target="2.0",
        )
    if truncated:
        append(
            "logger",
            "log_truncated",
            "ready",
            log_truncated="true",
            reason="session_size_limit",
        )
    if closed:
        append(
            "roster",
            "cleared",
            "idle",
            trust_engage_type=0,
            reason="synthetic-test",
            **idle_roster_fields,
        )
        append(
            "session_state",
            "idle",
            "idle",
            trust_engage_type=0,
            reason="synthetic-test",
        )
        append(
            "session_end",
            "session_end",
            "idle",
            completion="cleared",
            reason="synthetic-test",
            pending_timers=0,
            final_pending_timers=0,
            log_truncated="false",
            **idle_roster_fields,
        )
    return rows


def write_log(path: Path, rows: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(rows) + "\n", encoding="utf-8")


def validate(
    path: Path,
    *,
    readiness_only: bool,
    expected_commit: str = COMMIT,
    live_path: Path | None = None,
) -> tuple[dict[str, object], int]:
    parsed = audit.parse_evidence(path)
    return audit.validate_evidence(
        parsed,
        player=PLAYER,
        expected_commit=expected_commit,
        readiness_only=readiness_only,
        max_age_seconds=1800,
        now_epoch=NOW,
        live_path=live_path or path,
    )


class TrustParityAuditTests(unittest.TestCase):
    def test_emitter_lifecycle_uses_idle_prepare_then_authoritative_projection(self) -> None:
        for mode in (audit.MODE_RETAIL, audit.MODE_ALLIANCE):
            with self.subTest(mode=mode):
                rows = build_session(mode)
                parsed_rows = [
                    dict(token.split("=", 1) for token in row.split("\t"))
                    for row in rows
                ]
                self.assertEqual(
                    [
                        (row["record_type"], row["event"], row["state"])
                        for row in parsed_rows[:4]
                    ],
                    [
                        ("session_begin", "session_begin", "idle"),
                        ("roster", "preflight", "idle"),
                        ("roster", "cleared", "idle"),
                        ("session_state", "spawning", "spawning"),
                    ],
                )
                self.assertEqual(parsed_rows[0]["alliance_active"], "false")
                expected_active = "true" if mode == audit.MODE_ALLIANCE else "false"
                self.assertEqual(parsed_rows[3]["alliance_active"], expected_active)
                ready = next(
                    row
                    for row in parsed_rows
                    if row["record_type"] == "session_state"
                    and row["event"] == "ready"
                )
                self.assertEqual(ready["alliance_active"], expected_active)
                self.assertEqual(parsed_rows[0]["combat_summoning_setting"], "false")
                self.assertEqual(parsed_rows[0]["combat_summoning_effective"], "false")

    def test_missing_and_empty_logs_fail_nonzero(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for path in (root / "missing.tsv", root / "empty.tsv"):
                if path.name == "empty.tsv":
                    path.write_bytes(b"")
                with self.subTest(path=path.name):
                    report, exit_code = validate(path, readiness_only=True)
                    self.assertEqual(exit_code, 1)
                    self.assertEqual(report["status"], "fail")
                    self.assertEqual(report["combat_acceptance"], "not_run")

    def test_legacy_fixtures_are_descriptive_only_and_fail(self) -> None:
        for name in ("legacy-header-only.tsv", "legacy-progression-only.tsv"):
            with self.subTest(name=name):
                report, exit_code = validate(FIXTURE_ROOT / name, readiness_only=True)
                self.assertEqual(exit_code, 1)
                self.assertEqual(report["combat_acceptance"], "not_run")
                self.assertTrue(report["legacy"]["descriptive_only"])
                self.assertIn(
                    "legacy_schema_no_session_contract",
                    {issue["code"] for issue in report["issues"]},
                )

    def test_duplicate_key_fixture_fails_strict_parsing(self) -> None:
        report, exit_code = validate(
            FIXTURE_ROOT / "malformed-duplicate-key.tsv", readiness_only=True
        )
        self.assertEqual(exit_code, 1)
        self.assertIn("duplicate_key", {issue["code"] for issue in report["issues"]})

    def test_exact_retail_readiness_writes_json_and_markdown(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            live = root / "runtime/logs/trust_actions/live/Twills.log"
            write_log(live, build_session(audit.MODE_RETAIL))
            result = audit.generate_report(
                root / "repo",
                root / "runtime",
                PLAYER,
                readiness_only=True,
                now_epoch=NOW,
                expected_commit=COMMIT,
            )
            self.assertEqual(result.exit_code, 0)
            self.assertEqual(result.report["status"], "pass")
            self.assertEqual(result.report["combat_acceptance"], "not_run")
            self.assertEqual(result.report["lane_acceptance"], "not_run")
            self.assertEqual(result.report["parity_acceptance"], "not_run")
            self.assertTrue(result.json_path and result.json_path.exists())
            self.assertTrue(result.markdown_path and result.markdown_path.exists())
            payload = json.loads(result.json_path.read_text(encoding="utf-8"))
            self.assertEqual(payload["evidence_mode"], audit.MODE_RETAIL)
            markdown = result.markdown_path.read_text(encoding="utf-8")
            self.assertIn("READINESS ONLY — NO COMBAT ACCEPTANCE", markdown)
            repeated = audit.generate_report(
                root / "repo",
                root / "runtime",
                PLAYER,
                readiness_only=True,
                now_epoch=NOW,
                expected_commit=COMMIT,
            )
            self.assertNotEqual(repeated.json_path, result.json_path)
            self.assertNotEqual(repeated.markdown_path, result.markdown_path)

    def test_exact_alliance_readiness_is_extension_not_retail(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "Twills.log"
            write_log(path, build_session(audit.MODE_ALLIANCE))
            report, exit_code = validate(path, readiness_only=True)
            self.assertEqual(exit_code, 0)
            self.assertEqual(report["lane_classification"], "mochirii_extension")
            self.assertEqual(report["retail_acceptance"], "not_run")
            self.assertIn(
                "MOCHIRII EXTENSION — NOT RETAIL ACCEPTANCE", report["banners"]
            )

    def test_retail_readiness_rejects_applied_unity_stat_bonus(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "Twills.log"
            rows = build_session(audit.MODE_RETAIL)
            for index, row in enumerate(rows):
                if "event=progression_bonus" in row:
                    rows[index] = row.replace(
                        "unity_parity_stat_bonus=0",
                        "unity_parity_stat_bonus=10",
                    )
                    break
            write_log(path, rows)
            report, exit_code = validate(path, readiness_only=True)
            self.assertEqual(exit_code, 1)
            self.assertIn(
                "mode_isolation_failure",
                {issue["code"] for issue in report["issues"]},
            )

    def test_alliance_readiness_allows_disabled_raw_campaigns(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "Twills.log"
            write_log(
                path,
                build_session(
                    audit.MODE_ALLIANCE,
                    campaign_extravaganza=0,
                    campaign_expo=0,
                ),
            )
            report, exit_code = validate(path, readiness_only=True)
            self.assertEqual(exit_code, 0)
            self.assertEqual(report["status"], "pass")

    def test_readiness_rejects_any_combat_rows(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "Twills.log"
            write_log(path, build_session(audit.MODE_RETAIL, combat=True))
            report, exit_code = validate(path, readiness_only=True)
            self.assertEqual(exit_code, 1)
            self.assertEqual(report["combat_acceptance"], "not_run")
            self.assertIn(
                "unexpected_combat_evidence",
                {issue["code"] for issue in report["issues"]},
            )

    def test_listener_diagnostics_do_not_claim_combat_actions(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "Twills.log"
            write_log(path, build_session(audit.MODE_RETAIL, diagnostic=True))
            report, exit_code = validate(path, readiness_only=True)
            self.assertEqual(exit_code, 0)
            self.assertEqual(report["combat_acceptance"], "not_run")

    def test_retail_rejects_qa_only_diagnostic_state(self) -> None:
        mutations = (
            ("focus_reason=0", "focus_reason=1"),
            ("role_enmity_action=0", "role_enmity_action=1"),
            ("trust_rest_mode=0", "trust_rest_mode=2"),
            ("trust_rest_start_reason=0", "trust_rest_start_reason=4"),
        )
        for original, replacement in mutations:
            with self.subTest(field=replacement.split("=", 1)[0]):
                with tempfile.TemporaryDirectory() as temporary:
                    path = Path(temporary) / "Twills.log"
                    rows = build_session(audit.MODE_RETAIL, diagnostic=True)
                    for index, row in enumerate(rows):
                        if "record_type=diagnostic" in row:
                            rows[index] = row.replace(original, replacement)
                            break
                    write_log(path, rows)
                    report, exit_code = validate(path, readiness_only=True)
                    self.assertEqual(exit_code, 1)
                    self.assertIn(
                        "mode_isolation_failure",
                        {issue["code"] for issue in report["issues"]},
                    )

    def test_action_context_requires_focus_and_role_target_identity(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            path = root / "archive/session.log"
            rows = build_session(audit.MODE_RETAIL, combat=True, closed=True)
            for index, row in enumerate(rows):
                if "event=action_packet" in row:
                    rows[index] = row.replace("\tfocus_target_targid=0", "")
                    break
            write_log(path, rows)
            report, exit_code = validate(
                path,
                readiness_only=False,
                live_path=root / "live/Twills.log",
            )
            self.assertEqual(exit_code, 1)
            self.assertIn(
                "missing_required_fields",
                {issue["code"] for issue in report["issues"]},
            )

    def test_action_context_rejects_malformed_numeric_values(self) -> None:
        mutations = (
            ("trust_mp=100", "trust_mp=banana", "invalid_integer"),
            (
                "distance_to_current_target=2.0",
                "distance_to_current_target=nan",
                "invalid_number",
            ),
        )
        for original, replacement, expected_code in mutations:
            with self.subTest(field=replacement.split("=", 1)[0]):
                with tempfile.TemporaryDirectory() as temporary:
                    root = Path(temporary)
                    path = root / "archive/session.log"
                    rows = build_session(audit.MODE_RETAIL, combat=True, closed=True)
                    for index, row in enumerate(rows):
                        if "event=action_packet" in row:
                            rows[index] = row.replace(original, replacement)
                            break
                    write_log(path, rows)
                    report, exit_code = validate(
                        path,
                        readiness_only=False,
                        live_path=root / "live/Twills.log",
                    )
                    self.assertEqual(exit_code, 1)
                    self.assertIn(
                        expected_code,
                        {issue["code"] for issue in report["issues"]},
                    )

    def test_incomplete_action_record_type_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "Twills.log"
            rows = build_session(audit.MODE_RETAIL, diagnostic=True)
            rows[4] = rows[4].replace(
                "record_type=diagnostic", "record_type=action"
            )
            write_log(path, rows)
            report, exit_code = validate(path, readiness_only=True)
            self.assertEqual(exit_code, 1)
            self.assertIn(
                "unknown_record_type", {issue["code"] for issue in report["issues"]}
            )

    def test_progression_only_cannot_satisfy_combat(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "Twills.log"
            write_log(path, build_session(audit.MODE_RETAIL, progression_only=True))
            report, exit_code = validate(path, readiness_only=False)
            self.assertEqual(exit_code, 1)
            self.assertEqual(report["combat_acceptance"], "fail")
            self.assertIn(
                "insufficient_combat_evidence",
                {issue["code"] for issue in report["issues"]},
            )

    def test_active_combat_prefix_cannot_satisfy_acceptance(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "Twills.log"
            write_log(path, build_session(audit.MODE_RETAIL, combat=True))
            report, exit_code = validate(path, readiness_only=False)
            self.assertEqual(exit_code, 1)
            self.assertEqual(report["combat_acceptance"], "fail")
            self.assertIn(
                "combat_session_not_closed",
                {issue["code"] for issue in report["issues"]},
            )

    def test_explicit_truncation_marker_fails_closed(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "Twills.log"
            write_log(path, build_session(audit.MODE_RETAIL, truncated=True))
            report, exit_code = validate(path, readiness_only=True)
            self.assertEqual(exit_code, 1)
            self.assertIn(
                "log_truncated", {issue["code"] for issue in report["issues"]}
            )

    def test_closed_combat_with_truncation_marker_fails_closed(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            path = root / "archive/session.log"
            write_log(
                path,
                build_session(
                    audit.MODE_RETAIL,
                    combat=True,
                    truncated=True,
                    closed=True,
                ),
            )
            report, exit_code = validate(
                path,
                readiness_only=False,
                live_path=root / "live/Twills.log",
            )
            self.assertEqual(exit_code, 1)
            self.assertEqual(report["combat_acceptance"], "fail")
            self.assertIn(
                "log_truncated", {issue["code"] for issue in report["issues"]}
            )

    def test_correlated_hostile_packet_and_result_pass_combat(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            path = root / "archive/session.log"
            write_log(path, build_session(audit.MODE_RETAIL, combat=True, closed=True))
            report, exit_code = validate(
                path,
                readiness_only=False,
                live_path=root / "live/Twills.log",
            )
            self.assertEqual(exit_code, 0)
            self.assertEqual(report["combat_acceptance"], "pass")
            self.assertEqual(report["lane_acceptance"], "pass")
            self.assertEqual(report["parity_acceptance"], "not_run")
            self.assertEqual(report["retail_acceptance"], "pass")
            self.assertIn(
                "SINGLE-LANE COMBAT EVIDENCE — NO CROSS-LANE PARITY ACCEPTANCE",
                report["banners"],
            )

    def test_correlated_negative_action_result_params_pass_combat(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            path = root / "archive/session.log"
            rows = build_session(audit.MODE_RETAIL, combat=True, closed=True)
            rows = [
                row.replace("total_param=25", "total_param=-25").replace(
                    "result_param=25", "result_param=-25"
                )
                for row in rows
            ]
            write_log(path, rows)
            report, exit_code = validate(
                path,
                readiness_only=False,
                live_path=root / "live/Twills.log",
            )
            self.assertEqual(exit_code, 0)
            self.assertEqual(report["combat_acceptance"], "pass")

    def test_terminal_cleanup_must_prove_zero_roster_and_timers(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            path = root / "archive/session.log"
            rows = build_session(audit.MODE_RETAIL, combat=True, closed=True)
            rows[-1] = rows[-1].replace("active_count=0", "active_count=1")
            write_log(path, rows)
            report, exit_code = validate(
                path,
                readiness_only=False,
                live_path=root / "live/Twills.log",
            )
            self.assertEqual(exit_code, 1)
            self.assertIn(
                "terminal_cleanup_mismatch",
                {issue["code"] for issue in report["issues"]},
            )

    def test_mixed_modes_and_sequence_gap_fail(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "Twills.log"
            rows = build_session(audit.MODE_RETAIL)
            rows[-1] = (
                rows[-1]
                .replace(
                    "evidence_mode=retail_control",
                    "evidence_mode=twills_full_alliance_qa",
                )
                .replace(f"sequence={len(rows)}", "sequence=99")
            )
            write_log(path, rows)
            report, exit_code = validate(path, readiness_only=True)
            codes = {issue["code"] for issue in report["issues"]}
            self.assertEqual(exit_code, 1)
            self.assertIn("mixed_modes", codes)
            self.assertIn("invalid_sequence", codes)

    def test_authoritative_state_reentry_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "Twills.log"
            rows = build_session(audit.MODE_RETAIL)
            ready_row = next(
                row
                for row in rows
                if "record_type=session_state" in row and "event=ready" in row
            )
            repeated_spawning = ready_row.replace(
                "event=ready", "event=spawning"
            ).replace("state=ready", "state=spawning")
            checkpoint_index = next(
                index
                for index, row in enumerate(rows)
                if "record_type=checkpoint" in row and "event=summon_complete" in row
            )
            rows[checkpoint_index:checkpoint_index] = [repeated_spawning, ready_row]
            for sequence, row in enumerate(rows, 1):
                tokens = row.split("\t")
                tokens = [
                    f"sequence={sequence}" if token.startswith("sequence=") else token
                    for token in tokens
                ]
                rows[sequence - 1] = "\t".join(tokens)

            write_log(path, rows)
            report, exit_code = validate(path, readiness_only=True)
            self.assertEqual(exit_code, 1)
            self.assertIn(
                "invalid_state_sequence",
                {issue["code"] for issue in report["issues"]},
            )

    def test_stale_wrong_commit_and_roster_contamination_fail(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "Twills.log"
            rows = build_session(audit.MODE_RETAIL, start_epoch=NOW - 10_000)
            rows = [
                row.replace(
                    "active_trust_ids=910,980,914,1013,1019",
                    "active_trust_ids=910,980,914,1013,1002",
                )
                for row in rows
            ]
            write_log(path, rows)
            report, exit_code = validate(
                path, readiness_only=True, expected_commit="b" * 40
            )
            codes = {issue["code"] for issue in report["issues"]}
            self.assertEqual(exit_code, 1)
            self.assertIn("stale_evidence", codes)
            self.assertIn("server_commit_mismatch", codes)
            self.assertIn("roster_active_mismatch", codes)

    def test_powershell_entrypoint_is_thin_and_propagates_exit_code(self) -> None:
        wrapper = MODULE_PATH.with_suffix(".ps1").read_text(encoding="utf-8")
        self.assertIn("wsl.exe @auditArgs", wrapper)
        self.assertIn("exit $LASTEXITCODE", wrapper)
        self.assertIn("/home/xartyzx/projects/FFXI-Runtime", wrapper)
        self.assertNotIn("Set-Content", wrapper)


if __name__ == "__main__":
    unittest.main()
