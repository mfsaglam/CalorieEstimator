#!/usr/bin/env python3
"""Merge supervised JSONL live batches into the deterministic evaluation report."""

from __future__ import annotations

import collections
import json
import statistics
from pathlib import Path
from typing import Any

from evaluate_food_database import JSON_PATH, MD_PATH, render_markdown


ROOT = Path(__file__).resolve().parents[1]
LIVE_DIR = ROOT / "Data/Reports/live_batches"

BATCH_PLAN = {
    "pilot-5-case-20260926": ["base-01", "base-16", "mod-02", "mod-13", "base-43"],
    "remaining-01": ["base-02", "base-03", "base-04", "base-05", "base-06"],
    "remaining-02": ["base-07", "base-08", "base-09", "base-10", "base-11"],
    "remaining-03": ["base-12", "base-13", "base-14", "base-15", "base-17"],
    "remaining-04": ["base-18", "base-19", "base-20", "base-21", "base-22"],
    "remaining-05": ["base-23", "base-24", "base-25", "base-26", "base-27"],
    "remaining-06": ["base-28", "base-29", "base-30", "base-31", "base-32"],
    "remaining-07": ["base-33", "base-34", "base-35", "base-36", "base-37"],
    "remaining-08": ["base-38", "base-39", "base-40", "base-41", "base-42"],
    "remaining-09": ["base-44", "base-45", "mod-01", "mod-03", "mod-04"],
    "remaining-10": ["mod-05", "mod-06", "mod-07", "mod-08", "mod-09"],
    "remaining-11": ["mod-10", "mod-11", "mod-12", "mod-14"],
}

NON_LATIN_LANGUAGES = {"ar", "hi", "ja", "ko", "ru", "zh"}


def percent(numerator: int, denominator: int) -> float | None:
    return round(100 * numerator / denominator, 2) if denominator else None


def percentile(values: list[int], p: float) -> float | None:
    if not values:
        return None
    ordered = sorted(values)
    position = (len(ordered) - 1) * p
    lower = int(position)
    upper = min(lower + 1, len(ordered) - 1)
    fraction = position - lower
    return ordered[lower] + (ordered[upper] - ordered[lower]) * fraction


def load_events(path: Path) -> list[dict[str, Any]]:
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


def execution_status(result: dict[str, Any]) -> str:
    failure = result.get("timeout_or_failure")
    if not failure:
        return "success"
    if failure == "Response may contain sensitive or unsafe content":
        return "safety_refusal"
    if "modelTimedOut" in failure or "timed out" in failure.lower():
        return "timeout"
    return "failure"


def grouped_results(cases: list[dict[str, Any]], key) -> list[dict[str, Any]]:
    groups: dict[str, list[dict[str, Any]]] = collections.defaultdict(list)
    for case in cases:
        groups[key(case)].append(case)
    output = []
    for label, values in sorted(groups.items()):
        output.append({
            "group": label,
            "cases": len(values),
            "successful": sum(item["execution_status"] == "success" for item in values),
            "recipe_hits": sum(bool(item.get("recipe_hit")) for item in values),
            "failures_timeouts_refusals": sum(item["execution_status"] in {"failure", "timeout", "safety_refusal"} for item in values),
            "not_executed": sum(item["execution_status"] == "not_executed_batch_terminated" for item in values),
        })
    return output


def main() -> None:
    report = json.loads(JSON_PATH.read_text(encoding="utf-8"))
    benchmark_cases = report["benchmark"]["cases"]
    benchmark_by_id = {case["id"]: case for case in benchmark_cases}
    results_by_id: dict[str, dict[str, Any]] = {}
    batches = []
    watchdog_terminations = 0
    hard_batch_terminations = 0
    internal_timeout_batch_stops = 0

    for batch_id, planned_ids in BATCH_PLAN.items():
        path = LIVE_DIR / f"{batch_id}.jsonl"
        events = load_events(path)
        result_events = [event for event in events if event.get("result")]
        termination_event = next((event for event in events if event["event"] == "BATCH_ABORT"), None)
        timeout_event = next((event for event in events if event["event"] == "TIMEOUT"), None)
        if termination_event:
            reason = termination_event.get("reason", "")
            if "hard batch timeout" in reason:
                hard_batch_terminations += 1
            else:
                watchdog_terminations += 1
        if timeout_event:
            internal_timeout_batch_stops += 1

        completed_ids = []
        for event in result_events:
            result = dict(event["result"])
            case_id = result["id"]
            completed_ids.append(case_id)
            result["execution_status"] = execution_status(result)
            result["batch_id"] = batch_id
            result["checkpoint_event"] = event["event"]
            # The old counter predicted zero for an explicit-weight case that
            # missed its localized alias and entered FoundationModels. A model
            # timeout proves that the first request was made.
            if result["execution_status"] in {"timeout", "safety_refusal", "failure"} and result.get("foundationmodels_requests", 0) == 0:
                result["foundationmodels_requests"] = 1
            results_by_id[case_id] = result

        stopped_at = (termination_event or timeout_event or {}).get("case_id")
        terminated = termination_event is not None or timeout_event is not None
        for case_id in planned_ids:
            if case_id in results_by_id:
                continue
            benchmark = benchmark_by_id[case_id]
            results_by_id[case_id] = {
                "id": case_id,
                "input": benchmark["input"],
                "lookup": benchmark.get("lookup"),
                "language": benchmark["language"],
                "category": benchmark["category"],
                "cohort": benchmark["cohort"],
                "route": benchmark["route"],
                "expected_recipe_id": benchmark.get("expected_recipe_id"),
                "actual_recipe_id": None,
                "recipe_hit": False,
                "provenance": None,
                "confidence": None,
                "ingredients": None,
                "total_grams": None,
                "calories": None,
                "fallback_stage": "batchTerminated",
                "modifier_expected": benchmark.get("expected_modifier"),
                "modifier_actual": None,
                "modifier_correct": None,
                "timeout_or_failure": f"not executed because batch {batch_id} terminated at {stopped_at}",
                "invariants": None,
                "plausibility": None,
                "plausibility_reasons": [],
                "foundationmodels_requests": 0,
                "elapsed_milliseconds": None,
                "execution_status": "not_executed_batch_terminated" if terminated else "missing_result",
                "batch_id": batch_id,
                "checkpoint_event": None,
            }
        batches.append({
            "batch_id": batch_id,
            "planned_case_ids": planned_ids,
            "completed_case_ids": completed_ids,
            "terminated": terminated,
            "stopped_at_case_id": stopped_at,
            "watchdog_termination": termination_event is not None and "hard batch timeout" not in termination_event.get("reason", ""),
            "hard_batch_timeout": termination_event is not None and "hard batch timeout" in termination_event.get("reason", ""),
            "internal_model_timeout_stop": timeout_event is not None,
            "artifact": str(path.relative_to(ROOT)),
        })

    missing = sorted(set(benchmark_by_id) - set(results_by_id))
    unexpected = sorted(set(results_by_id) - set(benchmark_by_id))
    if missing or unexpected:
        raise RuntimeError(f"live merge mismatch: missing={missing}, unexpected={unexpected}")

    cases = [{**benchmark_by_id[case_id], **results_by_id[case_id]} for case_id in benchmark_by_id]
    total = len(cases)
    successful = [case for case in cases if case["execution_status"] == "success"]
    executed = [case for case in cases if case["execution_status"] != "not_executed_batch_terminated"]
    expected_recipe = [case for case in cases if case.get("expected_recipe_id")]
    recipe_hits = [case for case in cases if case.get("recipe_hit")]
    provenance_counts = collections.Counter(case.get("provenance") for case in cases if case.get("provenance"))
    status_counts = collections.Counter(case["execution_status"] for case in cases)
    mass_cases = [case for case in successful if case.get("invariants", {}).get("mass_conserved") is not None]
    mass_passes = [case for case in mass_cases if case["invariants"]["mass_conserved"]]
    modifier_successes = [case for case in successful if case.get("expected_modifier")]
    modifier_correct = [case for case in modifier_successes if case.get("modifier_correct")]
    product_modifier_cases = [case for case in modifier_successes if case["id"] != "mod-13"]
    product_modifier_correct = [case for case in product_modifier_cases if case.get("modifier_correct")]
    latencies = [int(case["elapsed_milliseconds"]) for case in executed if case.get("elapsed_milliseconds") is not None]
    foundation_requests = sum(int(case.get("foundationmodels_requests") or 0) for case in cases)

    failure_reasons = collections.Counter()
    for case in cases:
        if case["execution_status"] == "timeout":
            failure_reasons["FoundationModels parse timed out"] += 1
        elif case["execution_status"] == "safety_refusal":
            failure_reasons[case["timeout_or_failure"]] += 1
        elif case["execution_status"] == "not_executed_batch_terminated":
            failure_reasons["not executed after an earlier case terminated its batch"] += 1
        elif case.get("provenance") == "localNutrition":
            failure_reasons["recipe miss resolved by local nutrition"] += 1

    by_language = grouped_results(cases, lambda case: case["language"])
    for item in by_language:
        item["language"] = item.pop("group")
        item["modifier_correct"] = sum(
            case.get("modifier_correct") is True for case in cases if case["language"] == item["language"]
        )
    by_cohort = grouped_results(cases, lambda case: case["cohort"])
    for item in by_cohort:
        item["cohort"] = item.pop("group")
    by_script = grouped_results(cases, lambda case: "non-Latin" if case["language"] in NON_LATIN_LANGUAGES else "Latin")
    for item in by_script:
        item["script"] = item.pop("group")

    imported_successes = [case for case in successful if case["cohort"] == "imported_usda" and case.get("recipe_hit")]
    ten_best_imported = [{
        "id": case["id"],
        "input": case["input"],
        "actual_recipe_id": case.get("actual_recipe_id"),
        "calories": case.get("calories"),
        "total_grams": case.get("total_grams"),
        "elapsed_milliseconds": case.get("elapsed_milliseconds"),
    } for case in imported_successes[:10]]

    execution_failures = status_counts["failure"] + status_counts["timeout"] + status_counts["safety_refusal"]
    non_successes = total - len(successful)
    aggregate = {
        "total_benchmark_cases": total,
        "executed_case_count": len(executed),
        "successfully_completed_cases": len(successful),
        "trusted_recipe_expected_cases": len(expected_recipe),
        "trusted_recipe_hits": len(recipe_hits),
        "trusted_recipe_hit_rate_percent": percent(len(recipe_hits), len(expected_recipe)),
        "localRecipe_rate_percent": percent(provenance_counts["localRecipe"], total),
        "localNutrition_rate_percent": percent(provenance_counts["localNutrition"], total),
        "modelAssistedRecipe_rate_percent": percent(provenance_counts["modelAssistedRecipe"], total),
        "modelNutrition_rate_percent": percent(provenance_counts["modelNutrition"], total),
        "failure_timeout_safety_refusal_count": execution_failures,
        "failure_timeout_safety_refusal_rate_percent": percent(execution_failures, total),
        "failure_timeout_rate_percent": percent(execution_failures, total),
        "not_executed_batch_terminated_count": status_counts["not_executed_batch_terminated"],
        "not_executed_batch_terminated_rate_percent": percent(status_counts["not_executed_batch_terminated"], total),
        "overall_non_success_count": non_successes,
        "overall_non_success_rate_percent": percent(non_successes, total),
        "mass_conservation_pass_count": len(mass_passes),
        "mass_conservation_eligible_count": len(mass_cases),
        "mass_conservation_pass_rate_percent": percent(len(mass_passes), len(mass_cases)),
        "modifier_correct_count": len(modifier_correct),
        "modifier_successfully_evaluated_count": len(modifier_successes),
        "modifier_accuracy_percent": percent(len(modifier_correct), len(modifier_successes)),
        "modifier_product_semantics_correct_count": len(product_modifier_correct),
        "modifier_product_semantics_evaluable_count": len(product_modifier_cases),
        "modifier_product_semantics_accuracy_percent": percent(len(product_modifier_correct), len(product_modifier_cases)),
        "average_case_latency_ms": round(statistics.mean(latencies), 2),
        "median_case_latency_ms": round(statistics.median(latencies), 2),
        "p95_case_latency_ms": round(percentile(latencies, .95) or 0, 2),
        "foundationmodels_request_count": foundation_requests,
        "watchdog_terminations": watchdog_terminations,
        "batch_hard_timeout_terminations": hard_batch_terminations,
        "internal_model_timeout_batch_stops": internal_timeout_batch_stops,
    }

    live = {
        "execution_policy": {
            "maximum_cases_per_process": 5,
            "one_execution_per_input": True,
            "retries": 0,
            "silent_case_timeout_seconds": 75,
            "hard_batch_timeout_seconds": 300,
        },
        "executed_case_count": len(executed),
        "foundationmodels_request_count": foundation_requests,
        "aggregate_metrics": aggregate,
        "provenance_breakdown": dict(provenance_counts),
        "execution_status_breakdown": dict(status_counts),
        "by_language": by_language,
        "by_cohort": by_cohort,
        "by_script": by_script,
        "latency_ms": {
            "average": aggregate["average_case_latency_ms"],
            "median": aggregate["median_case_latency_ms"],
            "p95": aggregate["p95_case_latency_ms"],
            "sample_size": len(latencies),
        },
        "fallback_reasons": [{"reason": reason, "count": count} for reason, count in failure_reasons.most_common()],
        "batch_results": batches,
        "raw_results": cases,
        "ten_best_imported": ten_best_imported,
        "special_analysis": {
            "mod_13_cheeseburger": {
                "input": "200g cheeseburger with 25g extra cheese",
                "benchmark_expected_final_grams": 225,
                "actual_final_grams": 200,
                "classification": "evaluation-spec issue",
                "documented_semantics": "The stated meal mass is final unless the user clearly says the modifier is additional outside the base quantity. The existing finalMeal path reserves explicit ingredient grams inside the final mass.",
                "determination": "200g final meal including the 25g explicit cheese increase",
                "evidence": "The result contains 46g cheese: approximately 21g base cheese from the remaining 175g plus the explicit 25g increase, while total mass remains 200g.",
            },
            "base_43_tofu_scramble": {
                "input": "200g tofu scramble",
                "classification": "fallback/model-availability failure",
                "exact_error": "Response may contain sensitive or unsafe content",
                "prompt_workaround_attempted": False,
            },
        },
    }
    report["live_evaluation"] = live
    report["recommended_next_actions"] = [
        "Add a non-destructive canonicality/reusability gate plus family grouping for near-duplicate FNDDS variants, keeping survey records available without treating all of them as canonical dishes.",
        "Add reviewed multilingual aliases for the top 100–250 IngredientIDs; top-250 coverage reaches 83.32% of ingredient occurrences and 46.24% of complete trusted recipes.",
        "Audit Unicode normalization and exact alias resolution across major non-Latin scripts; the Hindi biryani alias missed deterministic resolution and fell into a model timeout.",
        "Make FoundationModels cancellation hard-bounded at a process boundary and reduce the four sequential requests used for known-recipe modifiers; four cases stopped at the internal timeout and p95 latency was about 63.6 seconds.",
        "Formalize quantity-scope wording in benchmark specifications and regression fixtures so final-meal versus base-plus-addition expectations cannot be ambiguous, as demonstrated by mod-13.",
    ]
    JSON_PATH.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    MD_PATH.write_text(render_markdown(report), encoding="utf-8")
    print(f"Merged {len(BATCH_PLAN)} batches and {total} benchmark outcomes")
    print(f"Wrote {JSON_PATH}")
    print(f"Wrote {MD_PATH}")


if __name__ == "__main__":
    main()
