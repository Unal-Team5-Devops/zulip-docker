import json
import logging
import os
from pathlib import Path
import socket
import struct
import threading
import time
from urllib.request import urlopen

import psycopg
import redis
from prometheus_client import Counter, Gauge, Histogram, start_http_server

logging.basicConfig(level=logging.INFO, format='%(asctime)s %(levelname)s %(message)s')
BUCKETS = (.005, .01, .025, .05, .1, .25, .5, 1, 2, 5, 10, 30, 90)
requests = Counter('zulip_http_requests_total', 'Completed HTTP requests at the gateway', ['route', 'status_class'])
duration = Histogram('zulip_http_request_duration_seconds', 'Gateway request duration excluding long polling', ['route', 'status_class'], buckets=BUCKETS)
parsed = Counter('zulip_access_log_lines_total', 'Access log parse results', ['result'])
last_log = Gauge('zulip_access_log_last_timestamp_seconds', 'Time of last processed access log')
probe_up = Gauge('zulip_dependency_up', 'Successful dependency round trip', ['dependency'])
probe_duration = Histogram('zulip_dependency_probe_duration_seconds', 'Synthetic dependency round trip, not application query latency', ['dependency'], buckets=BUCKETS)
pg_connections = Gauge('zulip_postgres_connections', 'Current database connections')
pg_limit = Gauge('zulip_postgres_max_connections', 'Configured PostgreSQL connection limit')
pg_stats = Gauge('zulip_postgres_stat_total', 'Cumulative PostgreSQL database counters', ['operation'])
pg_size = Gauge('zulip_postgres_database_bytes', 'Database disk footprint')
redis_stats = Gauge('zulip_redis_stat', 'Redis INFO values', ['metric'])
mem_stats = Gauge('zulip_memcached_stat', 'Memcached binary STATS values', ['metric'])
active = Gauge('zulip_gateway_connections', 'NGINX connections', ['state'])
started = Gauge('zulip_collector_start_time_seconds', 'Collector start time')
started.set(time.time())
for route in ('web', 'api'):
    for status in ('2xx', '3xx', '4xx', '5xx'):
        requests.labels(route, status)
        duration.labels(route, status)

def secret(name):
    return Path('/run/secrets/zulip__' + name + '_password').read_text().strip()

def route_for(uri):
    if uri.startswith(('/static/', '/user_uploads/', '/json/events', '/api/v1/events')):
        return None
    return 'api' if uri.startswith(('/api/', '/json/')) else 'web'

def tail():
    path = Path('/logs/access.json')
    while not path.exists():
        time.sleep(1)
    with path.open() as stream:
        stream.seek(0, 2)
        while True:
            line = stream.readline()
            if not line:
                if path.stat().st_size < stream.tell():
                    stream.seek(0)
                time.sleep(.1)
                continue
            try:
                item = json.loads(line)
                route = route_for(item['uri'])
                if route:
                    status = str(item['status'] // 100) + 'xx'
                    if status not in ('2xx', '3xx', '4xx', '5xx'):
                        status = '5xx'
                    requests.labels(route, status).inc()
                    duration.labels(route, status).observe(item['duration'])
                parsed.labels('ok').inc()
                last_log.set(time.time())
            except (ValueError, KeyError, TypeError):
                parsed.labels('error').inc()

def postgres_probe():
    with psycopg.connect(host=os.getenv('POSTGRES_HOST', 'database'), dbname='zulip', user='zulip', password=secret('postgres'), connect_timeout=3, options='-c statement_timeout=3000') as conn:
        with conn.cursor() as cur:
            cur.execute('SELECT count(*) FROM pg_stat_activity')
            pg_connections.set(cur.fetchone()[0])
            cur.execute('SHOW max_connections')
            pg_limit.set(int(cur.fetchone()[0]))
            cur.execute("SELECT xact_commit, xact_rollback, blks_read, blks_hit, deadlocks, pg_database_size(datname) FROM pg_stat_database WHERE datname = current_database()")
            row = cur.fetchone()
            for name, value in zip(('commit', 'rollback', 'blocks_read', 'blocks_hit', 'deadlocks'), row[:5]):
                pg_stats.labels(name).set(value)
            pg_size.set(row[5])

def redis_probe():
    with redis.Redis(host=os.getenv('REDIS_HOST', 'redis'), password=secret('redis'), socket_timeout=3, socket_connect_timeout=3) as client:
        for key, value in client.info().items():
            if key in ('used_memory', 'maxmemory', 'total_commands_processed', 'rejected_connections', 'connected_clients', 'keyspace_hits', 'keyspace_misses', 'evicted_keys', 'total_error_replies'):
                redis_stats.labels(key).set(float(value))

def read_exact(sock, length):
    result = b''
    while len(result) < length:
        chunk = sock.recv(length - len(result))
        if not chunk:
            raise ConnectionError('Memcached closed connection')
        result += chunk
    return result

def mem_packet(sock, opcode, key=b'', value=b''):
    body = key + value
    sock.sendall(struct.pack('>BBHBBHIIQ', 0x80, opcode, len(key), 0, 0, 0, len(body), 0, 0) + body)

def mem_response(sock):
    magic, opcode, keylen, extra, datatype, status, size, opaque, cas = struct.unpack('>BBHBBHIIQ', read_exact(sock, 24))
    data = read_exact(sock, size)
    if status:
        raise ConnectionError('Memcached authentication or STATS failed')
    return data[extra:extra + keylen], data[extra + keylen:]

def memcached_probe():
    with socket.create_connection((os.getenv('MEMCACHED_HOST', 'memcached'), 11211), timeout=3) as sock:
        mem_packet(sock, 0x21, b'PLAIN', b'\x00zulip\x00' + secret('memcached').encode())
        mem_response(sock)
        mem_packet(sock, 0x10)
        while True:
            key, value = mem_response(sock)
            if not key:
                break
            if key.decode() in ('bytes', 'limit_maxbytes', 'curr_connections', 'cmd_get', 'cmd_set', 'get_hits', 'get_misses', 'evictions'):
                mem_stats.labels(key.decode()).set(float(value))

def rabbitmq_probe():
    with urlopen(os.getenv('RABBITMQ_METRICS', 'http://rabbitmq:15692/metrics'), timeout=3) as response:
        if response.status != 200:
            raise ConnectionError('RabbitMQ metrics endpoint unavailable')
        response.read()

def gateway_probe():
    with urlopen('http://gateway:8081/status', timeout=3) as response:
        lines = response.read().decode().splitlines()
        active.labels('active').set(int(lines[0].split()[-1]))
        fields = lines[3].split()
        for name, value in zip(('reading', 'writing', 'waiting'), (fields[1], fields[3], fields[5])):
            active.labels(name).set(int(value))

def poll(name, function):
    while True:
        start = time.monotonic()
        try:
            function()
            probe_up.labels(name).set(1)
        except Exception as exc:
            probe_up.labels(name).set(0)
            logging.warning('%s probe failed: %s', name, type(exc).__name__)
        probe_duration.labels(name).observe(time.monotonic() - start)
        time.sleep(10)

if __name__ == '__main__':
    start_http_server(9105)
    threading.Thread(target=tail, daemon=True).start()
    for name, function in [('postgres', postgres_probe), ('redis', redis_probe), ('memcached', memcached_probe), ('rabbitmq', rabbitmq_probe), ('gateway', gateway_probe)]:
        threading.Thread(target=poll, args=(name, function), daemon=True).start()
    threading.Event().wait()
