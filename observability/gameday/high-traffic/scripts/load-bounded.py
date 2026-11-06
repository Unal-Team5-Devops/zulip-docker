"""Bounded, reusable-connection HTTP load for the local high-traffic GameDay."""

import argparse
from collections import Counter
import http.client
import json
import math
from pathlib import Path
from queue import Full, Queue
import ssl
import threading
import time


parser = argparse.ArgumentParser()
parser.add_argument('--seconds', type=int, required=True)
parser.add_argument('--rps', type=int, required=True)
parser.add_argument('--workers', type=int, default=256)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
if not 5 <= args.seconds <= 120:
    parser.error('seconds debe estar entre 5 y 120')
if not 1 <= args.rps <= 3000:
    parser.error('rps debe estar entre 1 y 3000')
if not 1 <= args.workers <= 256:
    parser.error('workers debe estar entre 1 y 256')

context = ssl._create_unverified_context()
tasks = Queue(maxsize=args.workers * 2)
results = []
results_lock = threading.Lock()


def percentile(values, fraction):
    if not values:
        return None
    ordered = sorted(values)
    return ordered[max(0, math.ceil(fraction * len(ordered)) - 1)]


def worker():
    connection = None
    while True:
        due = tasks.get()
        if due is None:
            tasks.task_done()
            break
        start = time.monotonic()
        error_type = None
        try:
            if connection is None:
                connection = http.client.HTTPSConnection(
                    '127.0.0.1', 8080, timeout=10, context=context)
            connection.request(
                'GET', '/login/',
                headers={'Host': 'zulip.localhost:8080',
                         'User-Agent': 'zulip-gameday-high-traffic/1.0'})
            response = connection.getresponse()
            response.read()
            status = response.status
        except Exception as exc:
            status = 0
            error_type = type(exc).__name__
            if connection is not None:
                connection.close()
            connection = None
        finished = time.monotonic()
        with results_lock:
            results.append((status, finished - start, start - due, finished, error_type))
        tasks.task_done()
    if connection is not None:
        connection.close()


threads = [threading.Thread(target=worker, daemon=True) for _ in range(args.workers)]
for thread in threads:
    thread.start()

started_unix = time.time()
started = time.monotonic()
deadline = started + args.seconds
interval = 1 / args.rps
next_due = started
offered = 0
dropped = 0
while True:
    now = time.monotonic()
    if now >= deadline:
        break
    if now < next_due:
        time.sleep(min(next_due - now, 0.005))
        continue
    offered += 1
    try:
        tasks.put_nowait(next_due)
    except Full:
        dropped += 1
    next_due += interval

scheduled_end = time.monotonic()
for _ in threads:
    tasks.put(None)
tasks.join()
for thread in threads:
    thread.join()
finished = time.monotonic()

statuses = Counter(str(status) for status, _, _, _, _ in results)
errors = Counter(error for _, _, _, _, error in results if error)
report = {
    'started_unix': started_unix,
    'finished_unix': time.time(),
    'url': 'https://zulip.localhost:8080/login/',
    'configured_rps': args.rps,
    'configured_seconds': args.seconds,
    'workers': args.workers,
    'queue_capacity': args.workers * 2,
    'expected_requests': args.rps * args.seconds,
    'offered': offered,
    'offered_rps': offered / args.seconds,
    'dropped_before_send': dropped,
    'requests': len(results),
    'statuses': dict(statuses),
    'client_error_types': dict(errors),
    'actual_rps': len(results) / (finished - started),
    'completed_during_window_rps': sum(
        1 for _, _, _, end, _ in results if end <= scheduled_end) / args.seconds,
    'drain_seconds': finished - scheduled_end,
    'p95_seconds': percentile([duration for _, duration, _, _, _ in results], 0.95),
    'p95_queue_seconds': percentile([wait for _, _, wait, _, _ in results], 0.95),
}
args.output.parent.mkdir(parents=True, exist_ok=True)
args.output.write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
print(json.dumps(report, indent=2))
