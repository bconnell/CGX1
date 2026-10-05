import unittest
import subprocess
import tempfile
from pathlib import Path

from scripts.validate_evidence import (
    content_fingerprint,
    validate_architecture_claims,
    source_fingerprint,
    validate_current_claims,
    validate_hosted_candidates,
    validate_live_workflow_runs,
    validate_legacy_local_records,
    validate_matrix_evidence,
    validate_matrix_transitions,
    validate_transition,
)


EVIDENCE_COLUMNS = [
    "contract", "reference_model", "executable_tests", "rtl", "rtl_simulation",
    "subsystem_integration", "cu_integration", "gpu_integration",
    "software_toolchain_integration", "synthesis", "timing", "area", "power",
    "physical_implementation", "silicon_measurement",
]
MATURITY_STATES = ["not_started", "specified", "implemented", "validated", "partial"]


def make_matrix(evidence, evidence_refs=None):
    row = {stage: "not_started" for stage in EVIDENCE_COLUMNS}
    row.update(evidence)
    return {
        "schema_version": 2,
        "evidence_ledger": "design/cgx1_validation_evidence.json",
        "status_values": MATURITY_STATES,
        "status_descriptions": {state: state for state in MATURITY_STATES},
        "evidence_columns": EVIDENCE_COLUMNS,
        "subsystems": [
            {
                "id": "resident-composition",
                "evidence": row,
                "evidence_refs": evidence_refs or {},
            }
        ],
    }


class ContentFingerprintTests(unittest.TestCase):
    def test_fingerprint_ignores_only_the_evidence_ledger(self):
        source = {"README.md": b"CGX1\n", "design/evidence.json": b"old", "src/a.cpp": b"int a;\n"}
        changed_ledger = {**source, "design/evidence.json": b"new"}

        first = content_fingerprint(source, {"design/evidence.json"})
        second = content_fingerprint(changed_ledger, {"design/evidence.json"})
        self.assertEqual(first, second)
        self.assertNotEqual(first, content_fingerprint({**source, "src/a.cpp": b"int b;\n"}, {"design/evidence.json"}))

    def test_git_candidate_identity_tracks_source_but_ignores_ledger_edits(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            subprocess.run(["git", "init", "-q"], cwd=root, check=True)
            subprocess.run(["git", "config", "user.name", "CGX1 Test"], cwd=root, check=True)
            subprocess.run(["git", "config", "user.email", "cgx1-test@example.invalid"], cwd=root, check=True)
            (root / "README.md").write_text("before\n", encoding="utf-8")
            (root / "design").mkdir()
            (root / "design/evidence.json").write_text("first record\n", encoding="utf-8")
            subprocess.run(["git", "add", "README.md", "design/evidence.json"], cwd=root, check=True)
            subprocess.run(["git", "commit", "-qm", "fixture"], cwd=root, check=True)

            committed = source_fingerprint(root, "HEAD", ["design/evidence.json"])
            (root / "README.md").write_text("after\n", encoding="utf-8")
            working = source_fingerprint(root, None, ["design/evidence.json"])
            (root / "design/evidence.json").write_text("updated record\n", encoding="utf-8")
            working_after_ledger_update = source_fingerprint(root, None, ["design/evidence.json"])

        self.assertNotEqual(committed, working)
        self.assertEqual(working, working_after_ledger_update)


class HostedCandidateTests(unittest.TestCase):
    def test_hosted_runs_must_match_the_recorded_candidate(self):
        commit = "a" * 40
        other = "b" * 40
        ledger = {
            "schema_version": 1,
            "candidates": [
                {
                    "commit": commit,
                    "source_fingerprint": "f" * 64,
                    "workflow_runs": [
                        {
                            "workflow": "RTL CI",
                            "run_id": 12345678901,
                            "head_sha": other,
                            "status": "completed",
                            "conclusion": "success",
                        },
                        {"workflow": "Windows CI", "run_id": 12345678902, "head_sha": commit, "status": "completed", "conclusion": "success"},
                    ],
                }
            ],
        }

        findings = validate_hosted_candidates(ledger, {commit: "f" * 64})

        self.assertTrue(any("head SHA" in finding for finding in findings), findings)

    def test_hosted_candidate_source_identity_must_match_the_commit_tree(self):
        commit = "a" * 40
        ledger = {
            "schema_version": 1,
            "candidates": [{"commit": commit, "source_fingerprint": "0" * 64, "workflow_runs": []}],
        }

        findings = validate_hosted_candidates(ledger, {commit: "f" * 64})

        self.assertTrue(any("source fingerprint" in finding for finding in findings), findings)

    def test_exact_successful_run_is_accepted(self):
        commit = "c" * 40
        ledger = {
            "schema_version": 1,
            "candidates": [
                {
                    "commit": commit,
                    "source_fingerprint": "f" * 64,
                    "workflow_runs": [
                        {
                            "workflow": "RTL CI",
                            "run_id": 12345678901,
                            "head_sha": commit,
                            "status": "completed",
                            "conclusion": "success",
                        },
                        {
                            "workflow": "Windows CI",
                            "run_id": 12345678902,
                            "head_sha": commit,
                            "status": "completed",
                            "conclusion": "success",
                        },
                    ],
                }
            ],
        }

        self.assertEqual(validate_hosted_candidates(ledger, {commit: "f" * 64}), [])

    def test_candidate_workflow_policy_preserves_legacy_and_requires_new_lanes(self):
        legacy_commit = "d" * 40
        current_commit = "e" * 40
        workflows = ["RTL CI", "Windows CI", "Linux Sanitizers", "RTL Tools CI"]
        def run_records(commit, names):
            return [
                {"workflow": name, "run_id": index + (10 if commit == legacy_commit else 20),
                 "head_sha": commit, "status": "completed", "conclusion": "success"}
                for index, name in enumerate(names)
            ]

        legacy = {
            "commit": legacy_commit,
            "source_fingerprint": "f" * 64,
            "required_hosted_workflows": ["RTL CI", "Windows CI"],
            "workflow_runs": run_records(legacy_commit, ["RTL CI", "Windows CI"]),
        }
        current = {
            "commit": current_commit,
            "source_fingerprint": "f" * 64,
            "required_hosted_workflows": workflows,
            "workflow_runs": run_records(current_commit, workflows[:-1]),
        }
        ledger = {"schema_version": 1, "required_hosted_workflows": workflows,
                  "candidates": [legacy, current]}

        findings = validate_hosted_candidates(
            ledger, {legacy_commit: "f" * 64, current_commit: "f" * 64}
        )

        self.assertTrue(any("RTL Tools CI" in finding for finding in findings), findings)

    def test_live_run_result_must_match_the_evidence_ledger(self):
        commit = "c" * 40
        ledger = {
            "candidates": [
                {
                    "commit": commit,
                    "workflow_runs": [
                        {"workflow": "RTL CI", "run_id": 12345678901, "head_sha": commit, "status": "completed", "conclusion": "success"}
                    ],
                }
            ]
        }
        live = [{"databaseId": 12345678901, "workflowName": "RTL CI", "headSha": "d" * 40, "status": "completed", "conclusion": "failure"}]

        findings = validate_live_workflow_runs(ledger, live)

        self.assertEqual(len(findings), 2)
        self.assertTrue(any("headSha" in finding for finding in findings), findings)
        self.assertTrue(any("conclusion" in finding for finding in findings), findings)

    def test_local_only_validation_does_not_require_hosted_ci(self):
        record = {
            "id": "historical-local-only",
            "evidence_class": "local_only",
            "base_commit": "a" * 40,
            "legacy_source_fingerprint": "f" * 64,
            "fingerprint_scope": "legacy changed-file content identity",
            "hosted_ci": "not_run",
            "current_candidate": False,
        }

        self.assertEqual(validate_legacy_local_records([record]), [])


class MatrixEvidenceTests(unittest.TestCase):
    def test_validated_rtl_must_reference_executed_simulation(self):
        matrix = make_matrix(
            {"rtl_simulation": "validated"},
            {"rtl_simulation": ["rtl:compile-only-top"]},
        )
        catalog = {"rtl:compile-only-top": {"class": "compile_only"}}

        findings = validate_matrix_evidence(matrix, catalog)

        self.assertTrue(any("not executed" in finding or "compile-only" in finding for finding in findings), findings)

    def test_validated_state_requires_concrete_reference(self):
        matrix = make_matrix({"executable_tests": "validated"})

        findings = validate_matrix_evidence(matrix, {})

        self.assertTrue(any("requires concrete evidence references" in finding for finding in findings), findings)

    def test_validated_rtl_with_executed_reference_is_accepted(self):
        matrix = make_matrix(
            {"rtl_simulation": "validated"},
            {"rtl_simulation": ["rtl:executed-top"]},
        )

        self.assertEqual(validate_matrix_evidence(matrix, {"rtl:executed-top": {"class": "simulated"}}), [])

    def test_partial_rtl_state_can_name_compile_only_composition(self):
        matrix = make_matrix(
            {"rtl_simulation": "partial"},
            {"rtl_simulation": ["rtl:compile-only-top"]},
        )

        self.assertEqual(validate_matrix_evidence(matrix, {"rtl:compile-only-top": {"class": "compile_only"}}), [])

    def test_matrix_obligation_prevents_validated_state_hiding_compile_only_top(self):
        matrix = make_matrix(
            {"rtl_simulation": "validated"},
            {"rtl_simulation": ["rtl:executed-top"]},
        )
        catalog = {
            "rtl:executed-top": {"class": "simulated"},
            "rtl:compile-only-top": {
                "class": "compile_only",
                "blocks_validation_for": "resident-composition",
            },
        }

        findings = validate_matrix_evidence(matrix, catalog)

        self.assertTrue(any("must remain partial" in finding for finding in findings), findings)


class MaturityTransitionTests(unittest.TestCase):
    def test_evidence_correction_can_downgrade_validated_to_partial(self):
        self.assertEqual(validate_transition("validated", "partial"), [])

    def test_unstarted_subsystem_cannot_jump_directly_to_validated(self):
        self.assertTrue(validate_transition("not_started", "validated"))

    def test_matrix_comparison_checks_every_evidence_column(self):
        previous = {
            "evidence_columns": ["reference_model", "rtl_simulation"],
            "subsystems": [{"id": "sample", "evidence": {"reference_model": "specified", "rtl_simulation": "not_started"}}],
        }
        current = {
            "evidence_columns": ["reference_model", "rtl_simulation"],
            "subsystems": [{"id": "sample", "evidence": {"reference_model": "validated", "rtl_simulation": "validated"}}],
        }

        findings = validate_matrix_transitions(previous, current)

        self.assertEqual(len(findings), 2)

    def test_matrix_comparison_rejects_removing_an_existing_subsystem(self):
        previous = {"evidence_columns": [], "subsystems": [{"id": "kept", "evidence": {}}]}
        current = {"evidence_columns": [], "subsystems": []}

        findings = validate_matrix_transitions(previous, current)

        self.assertTrue(any("cannot be removed" in finding for finding in findings), findings)


class CurrentClaimTests(unittest.TestCase):
    def test_superseded_sha_in_current_candidate_claim_is_rejected(self):
        active = "a" * 40
        stale = "b" * 40

        findings = validate_current_claims([("docs/STATUS.md", f"Current candidate: {stale}")], active)

        self.assertTrue(any("superseded" in finding for finding in findings), findings)

    def test_historical_sha_without_current_claim_is_not_rejected(self):
        active = "a" * 40
        historical = "b" * 40

        self.assertEqual(validate_current_claims([("docs/VALIDATION.md", f"Historical candidate {historical}")], active), [])


class ArchitectureClaimTests(unittest.TestCase):
    def _architecture(self):
        return {
            "execution_model": {
                "register_state_authority": {
                    "vector": {"logical_registers_per_wave": 256, "storage_implemented": True, "cu_capacity_accounting": True},
                    "scalar": {"logical_registers_per_wave": 128, "storage_implemented": False, "cu_capacity_accounting": True, "class": "capacity_accounting_only"},
                    "predicate": {"logical_registers_per_wave": 16, "storage_implemented": False, "cu_capacity_accounting": True, "class": "capacity_accounting_only"},
                },
                "control": {"simulation_exercised": True},
            },
            "simulation_evidence": {"execution_model.control.simulation_exercised": ["rtl:control"]},
            "matrix_engine": {"pooled_vgpr_rtl": {"resident_int8_vector_composition_simulation_exercised": False, "resident_int8_vector_composition_validation": "compile_only"}},
        }

    def test_simulation_flags_require_executed_rtl_evidence(self):
        architecture = self._architecture()
        architecture["simulation_evidence"]["execution_model.control.simulation_exercised"] = ["rtl:compile"]
        catalog = {"rtl:compile": {"class": "compile_only", "stages": ["rtl_simulation"]}}

        findings = validate_architecture_claims(architecture, catalog)

        self.assertTrue(any("not simulated" in finding for finding in findings), findings)

    def test_scalar_and_predicate_capacity_are_not_misreported_as_stored_state(self):
        architecture = self._architecture()
        architecture["execution_model"]["register_state_authority"]["scalar"]["storage_implemented"] = True

        findings = validate_architecture_claims(architecture, {"rtl:control": {"class": "simulated", "stages": ["rtl_simulation"]}})

        self.assertTrue(any("capacity accounting only" in finding for finding in findings), findings)

    def test_revision_specific_ci_metadata_is_rejected_from_architecture(self):
        architecture = self._architecture()
        architecture["power_management"] = {"validated_revision": "a" * 40}

        findings = validate_architecture_claims(architecture, {"rtl:control": {"class": "simulated", "stages": ["rtl_simulation"]}})

        self.assertTrue(any("belongs in the validation evidence ledger" in finding for finding in findings), findings)


if __name__ == "__main__":
    unittest.main()
