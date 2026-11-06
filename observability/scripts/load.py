import argparse
from collections import Counter
from concurrent.futures import ThreadPoolExecutor
import json
import ssl
import socket
import time
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

original_getaddrinfo = socket.getaddrinfo


def resolve_localhost(host, *args, **kwargs):
    if isinstance(host, str) and host.endswith('.localhost'):
        host = '127.0.0.1'
    return original_getaddrinfo(host, *args, **kwargs)


socket.getaddrinfo = resolve_localhost

parser = argparse.ArgumentParser()
parser.add_argument(
    '--url', default='https://zulip.localhost:8080/api/v1/server_settings')
parser.add_argument('--seconds', type=int, default=180)
parser.add_argument('--rps', type=float, default=5)
parser.add_argument('--output')
args = parser.parse_args()
if args.seconds <= 0 or not 0 < args.rps <= 100:
    parser.error('seconds debe ser positivo y rps debe estar entre 0 y 100')
context = ssl._create_unverified_context()


def request_one(_):
    start = time.monotonic()
    try:
        with urlopen(Request(args.url, headers={'User-Agent': 'zulip-workshop-load/1.0'}), timeout=10, context=context) as response:
            response.read()
            status = response.status
    except HTTPError as exc:
        status = exc.code
    except (URLError, TimeoutError, OSError):
        status = 0
    return status, time.monotonic() - start


started = time.time()
results = []
with ThreadPoolExecutor(max_workers=20) as executor:
    pending = []
    deadline = time.monotonic() + args.seconds
    next_request = time.monotonic()
    while time.monotonic() < deadline:
        pending.append(executor.submit(request_one, None))
        next_request += 1 / args.rps
        time.sleep(max(0, next_request - time.monotonic()))
    results = [future.result() for future in pending]
latencies = sorted(value for _, value in results)
report = {'started_unix': started, 'finished_unix': time.time(), 'url': args.url, 'configured_rps': args.rps, 'requests': len(
    results), 'statuses': dict(Counter(str(code) for code, _ in results)), 'p95_seconds': latencies[max(0, int(.95 * len(latencies)) - 1)]}
print(json.dumps(report, indent=2))
if args.output:
    from pathlib import Path
    Path(args.output).write_text(json.dumps(report, indent=2) + '\n')
