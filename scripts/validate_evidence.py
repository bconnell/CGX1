#!/usr/bin/env python3
"""Validate CGX1 candidate identity and completeness-matrix evidence claims."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path, PurePosixPath
from typing import Iterable, Mapping

try:
    from scripts.validation_paths import PathTranslationError, resolve_root_argument
except ModuleNotFoundError:
    from validation_paths import PathTranslationError, resolve_root_argument


COMMIT_RE = re.compile(r"^[0-9a-f]{40}$")
FINGERPRINT_RE = re.compile(r"^[0-9a-f]{64}$")
ALLOWED_TRANSITIONS = {
    "not_started": {"not_started", "specified", "implemented", "partial"},
    "specified": {"specified", "implemented", "partial"},
    "implemented": {"implemented", "validated", "partial"},
    "partial": {"partial", "implemented", "validated"},
    "validated": {"validated", "partial"},
}
RTL_SIMULATION_CLASSES = {"simulated"}
LEGACY_REQUIRED_HOSTED_WORKFLOWS = ["RTL CI", "Windows CI"]
REQUIRED_EVIDENCE_COLUMNS = [
    "contract", "reference_model", "executable_tests", "rtl", "rtl_simulation",
    "subsystem_integration", "cu_integration", "gpu_integration",
    "software_toolchain_integration", "synthesis", "timing", "area", "power",
    "physical_implementation", "silicon_measurement",
]


def content_fingerprint(
    files: Mapping[str, bytes], excluded_paths: Iterable[str] = ()
) -> str:
    """Hash sorted path/content records; the evidence ledger can exclude itself."""
    excluded = {PurePosixPath(path.replace("\\", "/")).as_posix() for path in excluded_paths}
    records = []
    for raw_path, contents in files.items():
        path = PurePosixPath(raw_path.replace("\\", "/")).as_posix()
        if path in excluded:
            continue
        content_sha = hashlib.sha256(contents).hexdigest()
        records.append((path, f"{path}:{content_sha}"))
    records.sort(key=lambda item: item[0].encode("utf-8"))
    payload = "\n".join(record for _, record in records).encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


def _git(root: Path, *args: str) -> bytes:
    root = root.resolve()
    result = subprocess.run(
        ["git", "-c", f"safe.directory={root}", "-C", str(root), *args],
        cwd=root, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )
    return result.stdout


def _git_blobs(root: Path, object_ids: Iterable[str]) -> dict[str, bytes]:
    unique_ids = sorted(set(object_ids))
    if not unique_ids:
        return {}
    result = subprocess.run(
        ["git", "-c", f"safe.directory={root}", "-C", str(root), "cat-file", "--batch"],
        cwd=root,
        input=("\n".join(unique_ids) + "\n").encode("ascii"),
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    output = result.stdout
    offset = 0
    blobs: dict[str, bytes] = {}
    while offset < len(output):
        header_end = output.find(b"\n", offset)
        if header_end < 0:
            raise ValueError("git cat-file --batch returned a truncated header")
        object_id, object_type, size_bytes = output[offset:header_end].split(b" ", 2)
        size = int(size_bytes)
        offset = header_end + 1
        payload_end = offset + size
        if payload_end >= len(output) or output[payload_end:payload_end + 1] != b"\n":
            raise ValueError("git cat-file --batch returned a truncated object")
        if object_type != b"blob":
            raise ValueError(f"expected blob {object_id.decode('ascii')}, got {object_type!r}")
        blobs[object_id.decode("ascii")] = output[offset:payload_end]
        offset = payload_end + 1
    return blobs


def source_fingerprint(
    root: Path, revision: str | None = None, excluded_paths: Iterable[str] = ()
) -> str:
    """Fingerprint a committed tree or the tracked plus non-ignored working tree."""
    files: dict[str, bytes] = {}
    if revision is None:
        tracked = _git(root, "ls-files", "--cached", "-z").split(b"\0")
        untracked = _git(root, "ls-files", "--others", "--exclude-standard", "-z").split(b"\0")
        for raw_path in set(tracked + untracked):
            if not raw_path:
                continue
            path = raw_path.decode("utf-8", errors="surrogateescape")
            file_path = root / Path(path)
            if file_path.is_file():
                files[path.replace("\\", "/")] = file_path.read_bytes()
    else:
        tree = _git(root, "ls-tree", "-r", "-z", "--full-tree", revision)
        tree_records = []
        blob_ids = []
        for record in tree.split(b"\0"):
            if not record:
                continue
            metadata, raw_path = record.split(b"\t", 1)
            mode, object_type, object_id = metadata.split(b" ", 2)
            if object_type != b"blob" or mode == b"160000":
                continue
            path = raw_path.decode("utf-8", errors="surrogateescape")
            object_id_text = object_id.decode("ascii")
            tree_records.append((path.replace("\\", "/"), object_id_text))
            blob_ids.append(object_id_text)
        blobs = _git_blobs(root, blob_ids)
        for path, object_id in tree_records:
            files[path] = blobs[object_id]
    return content_fingerprint(files, excluded_paths)


def validate_transition(previous: str, current: str) -> list[str]:
    if previous not in ALLOWED_TRANSITIONS:
        return [f"unknown previous evidence state {previous!r}"]
    if current not in ALLOWED_TRANSITIONS:
        return [f"unknown current evidence state {current!r}"]
    if current not in ALLOWED_TRANSITIONS[previous]:
        return [f"illegal evidence transition {previous!r} -> {current!r}"]
    return []


def validate_matrix_evidence(
    matrix: dict, evidence_catalog: Mapping[str, dict]
) -> list[str]:
    findings: list[str] = []
    if matrix.get("schema_version") != 2:
        findings.append("completeness matrix schema_version must be 2")
    if "validated_candidate" in matrix or "local_working_tree_candidate" in matrix:
        findings.append("candidate-specific metadata must live in the evidence ledger, not the matrix")
    if matrix.get("evidence_ledger") != "design/cgx1_validation_evidence.json":
        findings.append("matrix evidence_ledger must name design/cgx1_validation_evidence.json")

    states = matrix.get("status_values")
    columns = matrix.get("evidence_columns")
    rows = matrix.get("subsystems")
    if not isinstance(states, list) or set(states) != set(ALLOWED_TRANSITIONS):
        findings.append("matrix status_values must enumerate the five supported maturity states")
    if not isinstance(columns, list) or not isinstance(rows, list):
        findings.append("matrix evidence_columns and subsystems must be arrays")
        return findings
    if columns != REQUIRED_EVIDENCE_COLUMNS:
        findings.append("matrix evidence_columns do not match the supported completeness schema")
    descriptions = matrix.get("status_descriptions")
    if not isinstance(descriptions, dict) or set(descriptions) != set(ALLOWED_TRANSITIONS):
        findings.append("matrix status_descriptions must define every supported maturity state")

    seen_ids: set[str] = set()
    rows_by_id: dict[str, dict] = {}
    for row in rows:
        subsystem_id = row.get("id")
        prefix = f"subsystem {subsystem_id!r}"
        if not isinstance(subsystem_id, str) or not subsystem_id:
            findings.append("every subsystem requires a non-empty id")
            continue
        if subsystem_id in seen_ids:
            findings.append(f"duplicate subsystem id {subsystem_id!r}")
        seen_ids.add(subsystem_id)
        rows_by_id[subsystem_id] = row

        evidence = row.get("evidence")
        if not isinstance(evidence, dict) or set(evidence) != set(columns):
            findings.append(f"{prefix} evidence keys must exactly match evidence_columns")
            continue
        refs_by_stage = row.get("evidence_refs", {})
        if not isinstance(refs_by_stage, dict):
            findings.append(f"{prefix} evidence_refs must be an object")
            refs_by_stage = {}

        for stage in columns:
            state = evidence.get(stage)
            if state not in ALLOWED_TRANSITIONS:
                findings.append(f"{prefix} has invalid {stage} state {state!r}")
                continue
            refs = refs_by_stage.get(stage, [])
            if state == "validated" and (not isinstance(refs, list) or not refs):
                findings.append(f"{prefix} {stage}=validated requires concrete evidence references")
                continue
            if not isinstance(refs, list):
                findings.append(f"{prefix} {stage} evidence references must be an array")
                continue
            for reference in refs:
                if not isinstance(reference, str) or reference not in evidence_catalog:
                    findings.append(f"{prefix} {stage} references unknown evidence {reference!r}")
                    continue
                evidence_item = evidence_catalog[reference]
                declared_stages = evidence_item.get("stages")
                if declared_stages is not None and stage not in declared_stages:
                    findings.append(
                        f"{prefix} {stage} reference {reference!r} is not classified for that evidence stage"
                    )
                expected_classes = {
                    "reference_model": {"executable_test"},
                    "executable_tests": {"executable_test"},
                    "rtl": {"rtl_implementation"},
                    "rtl_simulation": RTL_SIMULATION_CLASSES,
                    "subsystem_integration": {"integration_test", "simulated"},
                    "cu_integration": {"cu_integration", "simulated"},
                    "gpu_integration": {"gpu_integration"},
                    "software_toolchain_integration": {"software_toolchain"},
                    "synthesis": {"synthesis"},
                    "timing": {"timing"},
                    "area": {"area"},
                    "power": {"power"},
                    "physical_implementation": {"physical_implementation"},
                    "silicon_measurement": {"silicon_measurement"},
                }
                accepted_classes = expected_classes.get(stage)
                if state == "validated" and accepted_classes and evidence_item.get("class") not in accepted_classes:
                    findings.append(
                        f"{prefix} {stage} reference {reference!r} has evidence class "
                        f"{evidence_item.get('class')!r}, expected one of {sorted(accepted_classes)}"
                    )
                if (
                    stage == "rtl_simulation"
                    and state == "validated"
                    and evidence_item.get("class") not in RTL_SIMULATION_CLASSES
                ):
                    findings.append(
                        f"{prefix} RTL simulation reference {reference!r} was not executed; "
                        f"classification is {evidence_item.get('class')!r}"
                    )
    for reference, evidence_item in evidence_catalog.items():
        owner = evidence_item.get("blocks_validation_for") if isinstance(evidence_item, dict) else None
        owner_row = rows_by_id.get(owner)
        if owner_row is not None and owner_row.get("evidence", {}).get("rtl_simulation") == "validated":
            findings.append(
                f"subsystem {owner!r} rtl_simulation must remain partial while required "
                f"composition {reference!r} is compile-only"
            )
    serialized = json.dumps(matrix, ensure_ascii=False)
    if re.search(r"\b\d+(?:\.\d+)?\s*%", serialized):
        findings.append("completeness matrix must not represent project progress with percentages")
    return findings


def validate_matrix_transitions(previous: dict, current: dict) -> list[str]:
    findings: list[str] = []
    previous_rows = {row.get("id"): row for row in previous.get("subsystems", [])}
    current_ids = {row.get("id") for row in current.get("subsystems", [])}
    for removed_id in previous_rows.keys() - current_ids:
        findings.append(f"subsystem {removed_id!r} cannot be removed from the completeness matrix")
    columns = current.get("evidence_columns", [])
    for row in current.get("subsystems", []):
        subsystem_id = row.get("id")
        prior = previous_rows.get(subsystem_id)
        prior_evidence = prior.get("evidence", {}) if prior else {}
        current_evidence = row.get("evidence", {})
        for stage in columns:
            old_state = prior_evidence.get(stage, "not_started")
            new_state = current_evidence.get(stage, "not_started")
            findings.extend(
                f"subsystem {subsystem_id!r} {stage}: {finding}"
                for finding in validate_transition(old_state, new_state)
            )
    return findings


def validate_hosted_candidates(
    ledger: dict, source_fingerprints: Mapping[str, str]
) -> list[str]:
    findings: list[str] = []
    if ledger.get("schema_version") != 1:
        findings.append("evidence ledger schema_version must be 1")
    candidates = ledger.get("candidates")
    if not isinstance(candidates, list):
        return findings + ["evidence ledger candidates must be an array"]
    default_required = ledger.get("required_hosted_workflows", LEGACY_REQUIRED_HOSTED_WORKFLOWS)
    if (not isinstance(default_required, list) or not default_required
            or any(not isinstance(workflow, str) or not workflow.strip() for workflow in default_required)):
        findings.append("evidence ledger required_hosted_workflows must be a non-empty string array")
        default_required = LEGACY_REQUIRED_HOSTED_WORKFLOWS

    seen_commits: set[str] = set()
    seen_runs: set[int] = set()
    for candidate in candidates:
        commit = candidate.get("commit")
        if not isinstance(commit, str) or not COMMIT_RE.fullmatch(commit):
            findings.append(f"candidate commit must be a full lowercase 40-character SHA: {commit!r}")
            continue
        if commit in seen_commits:
            findings.append(f"duplicate evidence candidate commit {commit}")
        seen_commits.add(commit)
        fingerprint = candidate.get("source_fingerprint")
        if not isinstance(fingerprint, str) or not FINGERPRINT_RE.fullmatch(fingerprint):
            findings.append(f"candidate {commit} has an invalid source fingerprint")
        elif commit not in source_fingerprints:
            findings.append(f"candidate {commit} source fingerprint cannot be verified from Git")
        elif source_fingerprints[commit] != fingerprint:
            findings.append(f"candidate {commit} source fingerprint does not match the committed tree")

        runs = candidate.get("workflow_runs", [])
        if not isinstance(runs, list):
            findings.append(f"candidate {commit} workflow_runs must be an array")
            continue
        required = candidate.get("required_hosted_workflows", default_required)
        if (not isinstance(required, list) or not required
                or any(not isinstance(workflow, str) or not workflow.strip() for workflow in required)):
            findings.append(f"candidate {commit} required_hosted_workflows must be a non-empty string array")
            required = LEGACY_REQUIRED_HOSTED_WORKFLOWS
        successful_workflows = {
            run.get("workflow") for run in runs
            if isinstance(run, dict) and run.get("head_sha") == commit
            and run.get("status") == "completed" and run.get("conclusion") == "success"
        }
        missing_workflows = sorted(set(required) - successful_workflows)
        if missing_workflows:
            findings.append(
                f"hosted candidate {commit} lacks exact successful required workflow(s): "
                + ", ".join(missing_workflows)
            )
        for run in runs:
            run_id = run.get("run_id")
            if not isinstance(run_id, int) or run_id <= 0:
                findings.append(f"candidate {commit} has an invalid workflow run id {run_id!r}")
            elif run_id in seen_runs:
                findings.append(f"workflow run id {run_id} is recorded more than once")
            else:
                seen_runs.add(run_id)
            if run.get("head_sha") != commit:
                findings.append(
                    f"candidate {commit} workflow run {run_id!r} head SHA {run.get('head_sha')!r} "
                    "does not match the recorded candidate"
                )
            if run.get("status") != "completed" or run.get("conclusion") != "success":
                findings.append(
                    f"candidate {commit} workflow run {run_id!r} is not completed successfully"
                )
            if not isinstance(run.get("workflow"), str) or not run["workflow"].strip():
                findings.append(f"candidate {commit} workflow run {run_id!r} requires a workflow name")
    return findings


def validate_legacy_local_records(records: Iterable[dict]) -> list[str]:
    findings: list[str] = []
    for index, record in enumerate(records):
        label = record.get("id", f"legacy local record {index}")
        if record.get("evidence_class") != "local_only":
            findings.append(f"{label} must preserve its local_only evidence class")
        if record.get("hosted_ci") != "not_run":
            findings.append(f"{label} local-only record must not claim hosted CI evidence")
        if record.get("current_candidate") is not False:
            findings.append(f"{label} must be explicitly classified as historical, not current")
        if not isinstance(record.get("base_commit"), str) or not COMMIT_RE.fullmatch(record["base_commit"]):
            findings.append(f"{label} requires its full base commit identity")
        if not isinstance(record.get("legacy_source_fingerprint"), str) or not FINGERPRINT_RE.fullmatch(record["legacy_source_fingerprint"]):
            findings.append(f"{label} requires its legacy fingerprint to remain auditable")
        if not isinstance(record.get("fingerprint_scope"), str) or not record["fingerprint_scope"].strip():
            findings.append(f"{label} requires the original fingerprint scope")
    return findings


def validate_architecture_claims(
    architecture: dict, evidence_catalog: Mapping[str, dict]
) -> list[str]:
    findings: list[str] = []
    simulation_evidence = architecture.get("simulation_evidence", {})
    true_flags: set[str] = set()
    forbidden_temporal_fields = {
        "validated_revision",
        "hosted_rtl_ci_run",
        "hosted_windows_ci_run",
    }

    def visit(value: object, path: str = "") -> None:
        if isinstance(value, dict):
            for key, child in value.items():
                child_path = f"{path}.{key}" if path else key
                if key in forbidden_temporal_fields or (key.startswith("local_") and key.endswith("_passed")):
                    findings.append(
                        f"architecture field {child_path!r} is revision-specific and belongs in the validation evidence ledger"
                    )
                if (key == "simulation_exercised" or key.endswith("_simulation_exercised")) and child is True:
                    true_flags.add(child_path)
                    references = simulation_evidence.get(child_path) if isinstance(simulation_evidence, dict) else None
                    if not isinstance(references, list) or not references:
                        findings.append(f"architecture simulation flag {child_path!r} requires executed RTL evidence")
                    else:
                        for reference in references:
                            item = evidence_catalog.get(reference)
                            if item is None or item.get("class") != "simulated":
                                findings.append(
                                    f"architecture simulation flag {child_path!r} references {reference!r}, which was not simulated"
                                )
                visit(child, child_path)
        elif isinstance(value, list):
            for index, child in enumerate(value):
                visit(child, f"{path}[{index}]")

    visit(architecture)
    if isinstance(simulation_evidence, dict):
        for path in simulation_evidence:
            if path not in true_flags:
                findings.append(f"architecture simulation evidence {path!r} does not match an active true flag")

    execution = architecture.get("execution_model", {})
    authority = execution.get("register_state_authority", {}) if isinstance(execution, dict) else {}
    vector = authority.get("vector", {})
    scalar = authority.get("scalar", {})
    predicate = authority.get("predicate", {})
    if vector.get("storage_implemented") is not True or vector.get("cu_capacity_accounting") is not True:
        findings.append("vector VGPR state must distinguish implemented storage from CU capacity accounting")
    for name, expected_count in (("scalar", execution.get("scalar_registers_per_wave")), ("predicate", execution.get("predicate_registers_per_wave"))):
        item = authority.get(name, {})
        if (
            item.get("storage_implemented") is not False
            or item.get("cu_capacity_accounting") is not True
            or item.get("class") != "capacity_accounting_only"
            or item.get("logical_registers_per_wave") != expected_count
        ):
            findings.append(
                f"{name} register state must be classified as capacity accounting only, with no allocated storage claim"
            )
    if predicate is None or scalar is None:
        findings.append("scalar and predicate register authority records are required")

    pooled = architecture.get("matrix_engine", {}).get("pooled_vgpr_rtl", {})
    if (
        pooled.get("resident_int8_vector_composition_simulation_exercised") is not False
        or pooled.get("resident_int8_vector_composition_validation") != "compile_only"
    ):
        findings.append("pooled resident INT8 plus ordinary-vector composition must remain explicitly compile-only")
    return findings


def validate_current_claims(
    documents: Iterable[tuple[str, str]], candidate_commit: str
) -> list[str]:
    findings: list[str] = []
    for path, text in documents:
        for line_number, line in enumerate(text.splitlines(), start=1):
            claims = re.split(
                r"(?:(?<=[.!?])\s+(?=[\"'“‘(\[]*[A-Z0-9`])|;\s+)", line,
            )
            for claim in claims:
                lower = claim.lower()
                if "current" not in lower or "candidate" not in lower:
                    continue
                for sha in re.findall(r"(?<![0-9a-f])[0-9a-f]{40}(?![0-9a-f])", lower):
                    if sha != candidate_commit.lower():
                        findings.append(
                            f"{path}:{line_number}: current candidate points to superseded SHA {sha}"
                        )
    return findings


def validate_live_workflow_runs(ledger: dict, live_runs: Iterable[dict]) -> list[str]:
    live_by_id = {run.get("databaseId"): run for run in live_runs if isinstance(run, dict)}
    findings: list[str] = []
    for candidate in ledger.get("candidates", []):
        commit = candidate.get("commit")
        for recorded in candidate.get("workflow_runs", []):
            live = live_by_id.get(recorded.get("run_id"))
            if live is None:
                findings.append(f"hosted workflow run {recorded.get('run_id')!r} is missing from the live GitHub run list")
                continue
            comparisons = (
                ("workflowName", "workflow"),
                ("headSha", "head_sha"),
                ("status", "status"),
                ("conclusion", "conclusion"),
            )
            for live_key, recorded_key in comparisons:
                if live.get(live_key) != recorded.get(recorded_key):
                    findings.append(
                        f"hosted workflow run {recorded.get('run_id')} {live_key}={live.get(live_key)!r} "
                        f"does not match recorded {recorded_key}={recorded.get(recorded_key)!r} for {commit}"
                    )
    return findings


def _load_json(path: Path) -> dict:
    with path.open("r", encoding="utf-8-sig") as handle:
        value = json.load(handle)
    if not isinstance(value, dict):
        raise ValueError(f"expected a JSON object in {path}")
    return value


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", help="repository root in this shell's path syntax")
    parser.add_argument("--matrix", default="design/cgx1_completeness_matrix.json")
    parser.add_argument("--ledger", default="design/cgx1_validation_evidence.json")
    parser.add_argument("--candidate", default="HEAD", help="commit used for the committed candidate identity")
    parser.add_argument("--base-matrix", help="optional Git revision used to check legal status transitions")
    parser.add_argument("--verify-hosted-runs", action="store_true", help="reconcile ledger run records with GitHub Actions")
    parser.add_argument("--check-remote", action="store_true", help="query the configured completeness branch and report divergence")
    args = parser.parse_args(argv)

    try:
        root = resolve_root_argument(args.root, script_file=__file__)
    except PathTranslationError as error:
        parser.error(str(error))
    ledger_path = Path(args.ledger)
    matrix = _load_json(root / args.matrix)
    ledger = _load_json(root / ledger_path)
    architecture = _load_json(root / "design/cgx1_architecture.json")
    excluded = [ledger_path.as_posix()]

    evidence_catalog = ledger.get("evidence_catalog", {})
    findings = validate_matrix_evidence(matrix, evidence_catalog)
    findings.extend(validate_architecture_claims(architecture, evidence_catalog))
    if ledger.get("fingerprint_algorithm") != "sha256-path-content-records-v1":
        findings.append("evidence ledger fingerprint_algorithm is unsupported")
    if ledger.get("fingerprint_excluded_paths") != [ledger_path.as_posix()]:
        findings.append("evidence ledger must exclude only itself from source identity")
    candidate_fingerprint = source_fingerprint(root, args.candidate, excluded)
    working_fingerprint = source_fingerprint(root, None, excluded)
    fingerprints = {}
    for candidate in ledger.get("candidates", []):
        commit = candidate.get("commit")
        if isinstance(commit, str) and COMMIT_RE.fullmatch(commit):
            try:
                fingerprints[commit] = source_fingerprint(root, commit, excluded)
            except subprocess.CalledProcessError as error:
                findings.append(f"candidate {commit} tree cannot be read from Git: {error}")
    findings.extend(validate_hosted_candidates(ledger, fingerprints))
    findings.extend(validate_legacy_local_records(ledger.get("legacy_local_records", [])))

    documents = []
    for relative in ledger.get("current_claim_documents", []):
        path = root / relative
        if not path.is_file():
            findings.append(f"current-claim document does not exist: {relative}")
            continue
        documents.append((relative, path.read_text(encoding="utf-8-sig")))
    head = _git(root, "rev-parse", args.candidate).decode("ascii").strip()
    findings.extend(validate_current_claims(documents, head))

    if args.base_matrix:
        previous = json.loads(_git(root, "show", f"{args.base_matrix}:{args.matrix}").decode("utf-8-sig"))
        findings.extend(validate_matrix_transitions(previous, matrix))

    live_runs = None
    if args.verify_hosted_runs:
        try:
            result = subprocess.run(
                ["gh", "run", "list", "--repo", "bconnell/CGX1", "--limit", "100", "--json",
                 "databaseId,workflowName,status,conclusion,headSha"],
                cwd=root,
                check=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=30,
            )
            live_runs = json.loads(result.stdout)
            findings.extend(validate_live_workflow_runs(ledger, live_runs))
        except (OSError, subprocess.SubprocessError, json.JSONDecodeError) as error:
            findings.append(f"GitHub Actions run evidence could not be reconciled: {error}")

    remote_status = None
    if args.check_remote:
        try:
            remote_url = _git(root, "remote", "get-url", "origin").decode("utf-8").strip()
            normalized_url = remote_url.removesuffix(".git").lower()
            if normalized_url not in {"https://github.com/bconnell/cgx1", "git@github.com:bconnell/cgx1"}:
                findings.append(f"origin remote does not resolve to bconnell/CGX1: {remote_url}")
            else:
                remote_output = subprocess.run(
                    ["git", "-c", f"safe.directory={root}", "-C", str(root),
                     "ls-remote", "origin", "refs/heads/codex/cgx1-completeness"],
                    cwd=root,
                    check=True,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                    timeout=30,
                ).stdout.strip()
                remote_sha = remote_output.split()[0] if remote_output else None
                if remote_sha is None or not COMMIT_RE.fullmatch(remote_sha):
                    findings.append("remote completeness branch could not be resolved")
                else:
                    counts = _git(root, "rev-list", "--left-right", "--count", f"{remote_sha}...{args.candidate}").decode("ascii").split()
                    remote_status = {"sha": remote_sha, "ahead": int(counts[1]), "behind": int(counts[0])}
        except (OSError, subprocess.SubprocessError, IndexError, ValueError) as error:
            findings.append(f"remote completeness candidate could not be reconciled: {error}")

    if findings:
        for finding in findings:
            print(f"[fail] {finding}", file=sys.stderr)
        return 1
    print(f"[pass] completeness evidence schema and ledger checks passed")
    print(f"[candidate] commit={head} committed_source_fingerprint={candidate_fingerprint}")
    print(f"[working] source_fingerprint={working_fingerprint}")
    if remote_status is not None:
        print(f"[remote] branch=codex/cgx1-completeness sha={remote_status['sha']} ahead={remote_status['ahead']} behind={remote_status['behind']}")
    for candidate in ledger.get("candidates", []):
        runs = ",".join(str(run.get("run_id")) for run in candidate.get("workflow_runs", [])) or "none"
        print(f"[hosted evidence] historical_commit={candidate.get('commit')} fingerprint={candidate.get('source_fingerprint')} runs={runs}")
    print(f"[evidence] historical hosted candidates={len(ledger.get('candidates', []))}; exact run checks={'live' if live_runs is not None else 'ledger-only'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
