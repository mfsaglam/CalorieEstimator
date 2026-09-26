#!/usr/bin/env python3
"""Run one hard-bounded CalorieEstimator live-evaluation child process.

The child test accepts at most five case IDs and checkpoints JSONL before and
after every case. This supervisor never retries. It terminates the entire child
process group if one case stops making progress or the batch reaches five
minutes, because FoundationModels cancellation is not assumed to be reliable.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import selectors
import signal
import subprocess
import sys
import time
import uuid
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
REPORT = ROOT / "Data/Reports/database_evaluation.json"
LIVE_DIR = ROOT / "Data/Reports/live_batches"
XCODE_DEVELOPER_DIR = Path("/Applications/Xcode-beta.app/Contents/Developer")


def timestamp() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat()


def append_and_sync(path: Path, event: dict) -> None:
    with path.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(event, ensure_ascii=False, sort_keys=True) + "\n")
        handle.flush()
        os.fsync(handle.fileno())


def terminate_process_group(process: subprocess.Popen[str]) -> None:
    if process.poll() is not None:
        return
    try:
        os.killpg(process.pid, signal.SIGTERM)
        process.wait(timeout=3)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        process.wait(timeout=5)
    except ProcessLookupError:
        pass


def read_new_events(path: Path, offset: int) -> tuple[list[dict], int]:
    if not path.exists():
        return [], offset
    with path.open("r", encoding="utf-8") as handle:
        handle.seek(offset)
        events = []
        for line in handle:
            try:
                events.append(json.loads(line))
            except json.JSONDecodeError:
                # A flushed newline-delimited record is expected. Preserve the
                # offset before an incomplete final line for the next poll.
                break
        return events, handle.tell()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("case_ids", nargs="+", help="One to five benchmark IDs; each is executed exactly once.")
    parser.add_argument("--batch-id", default=None)
    parser.add_argument("--case-timeout-seconds", type=int, default=75)
    parser.add_argument("--batch-timeout-seconds", type=int, default=300)
    args = parser.parse_args()

    if not 1 <= len(args.case_ids) <= 5 or len(set(args.case_ids)) != len(args.case_ids):
        parser.error("provide 1-5 unique case IDs")
    if not 1 <= args.case_timeout_seconds < 300:
        parser.error("case timeout must be between 1 and 299 seconds")
    if not 1 <= args.batch_timeout_seconds <= 300:
        parser.error("batch timeout must be between 1 and 300 seconds")

    report = json.loads(REPORT.read_text(encoding="utf-8"))
    known_ids = {case["id"] for case in report["benchmark"]["cases"]}
    unknown = [case_id for case_id in args.case_ids if case_id not in known_ids]
    if unknown:
        parser.error(f"unknown benchmark IDs: {', '.join(unknown)}")

    batch_id = args.batch_id or f"batch-{uuid.uuid4().hex[:12]}"
    LIVE_DIR.mkdir(parents=True, exist_ok=True)
    output = LIVE_DIR / f"{batch_id}.jsonl"
    if output.exists():
        parser.error(f"refusing to overwrite existing batch output: {output}")

    environment = os.environ.copy()
    environment.update({
        "RUN_DATABASE_LIVE_EVALUATION": "1",
        "LIVE_EVALUATION_CASE_IDS": ",".join(args.case_ids),
        "LIVE_EVALUATION_BATCH_ID": batch_id,
        "LIVE_EVALUATION_OUTPUT": str(output),
        "DEVELOPER_DIR": str(XCODE_DEVELOPER_DIR),
        "CLANG_MODULE_CACHE_PATH": "/tmp/calorieestimator-clang-cache",
        "SWIFTPM_MODULECACHE_OVERRIDE": "/tmp/calorieestimator-swift-cache",
    })
    command = [
        "xcrun", "swift", "test", "--disable-sandbox",
        "--filter", "DatabaseLiveEvaluationTests/runBoundedBenchmark",
    ]
    process = subprocess.Popen(
        command,
        cwd=ROOT,
        env=environment,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
        start_new_session=True,
    )
    selector = selectors.DefaultSelector()
    assert process.stdout is not None
    selector.register(process.stdout, selectors.EVENT_READ)

    batch_started = time.monotonic()
    current_case: str | None = None
    current_case_started: float | None = None
    event_offset = 0
    abort_reason: str | None = None

    try:
        while process.poll() is None:
            for key, _ in selector.select(timeout=0.25):
                line = key.fileobj.readline()
                if line:
                    print(line, end="", flush=True)

            events, event_offset = read_new_events(output, event_offset)
            for event in events:
                kind = event.get("event")
                case_id = event.get("case_id")
                if kind == "START":
                    current_case = case_id
                    current_case_started = time.monotonic()
                    print(f"START {case_id} {event.get('timestamp')}", flush=True)
                elif kind in {"DONE", "TIMEOUT"}:
                    print(
                        f"DONE {case_id} elapsed_ms={event.get('elapsed_milliseconds')} "
                        f"status={'timeout' if kind == 'TIMEOUT' else event.get('reason', 'done')}",
                        flush=True,
                    )
                    current_case = None
                    current_case_started = None

            now = time.monotonic()
            if now - batch_started >= args.batch_timeout_seconds:
                abort_reason = f"hard batch timeout after {args.batch_timeout_seconds}s"
                break
            if current_case_started is not None and now - current_case_started >= args.case_timeout_seconds:
                abort_reason = f"hard case timeout after {args.case_timeout_seconds}s; cancellation not assumed reliable"
                break

        if abort_reason is not None:
            append_and_sync(output, {
                "event": "BATCH_ABORT",
                "batch_id": batch_id,
                "case_id": current_case,
                "timestamp": timestamp(),
                "reason": abort_reason,
            })
            print(f"DONE {current_case or 'batch'} status=aborted reason={abort_reason}", flush=True)
            terminate_process_group(process)
            return 124

        # Drain any final child output without waiting beyond normal process exit.
        remainder = process.stdout.read()
        if remainder:
            print(remainder, end="", flush=True)
        return process.returncode or 0
    finally:
        selector.close()
        if process.poll() is None:
            terminate_process_group(process)


if __name__ == "__main__":
    raise SystemExit(main())
