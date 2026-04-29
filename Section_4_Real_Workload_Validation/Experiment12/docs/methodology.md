# Methodology — Experiment 12: DeathStarBench Baseline

## Traffic Generation

Tool: **wrk2** (open-loop, Poisson arrivals)

Traffic originates from:
- wrk2 pods on the dedicated `load-gen` node
- `cpuset`-isolated to dedicated cores (avoids kube-system interference)

This ensures:
- No external network noise pollutes the measurement
- Load generator resource usage does not affect worker node CPU budgets
- True open-loop semantics — each request is issued independently of prior responses

---

## Workload: DeathStarBench Social-Network

### Social Graph Initialization

Before every repetition, the MongoDB social graph is initialized with the `socfb-Reed98` Facebook ego-network dataset:

```bash
python3 scripts/init_social_graph.py \
  --graph=socfb-Reed98 \
  --ip=${NGINX_IP} \
  --port=8080
```

- 963 users, 18,812 edges
- Realistic follower-graph density
- Exercises fanout-heavy reads (`read-home-timeline`) and write fan-in (`compose-post`)
- **Must be re-run between every repetition** to reset DB state for reproducibility

---

## Phases

### 1. Saturation Sweep (One-Time Pre-Run)

```bash
# Sweep each endpoint independently, 50→600 RPS, 60s per step
for RPS in 50 100 150 200 250 300 350 400 450 500 550 600; do
  ../wrk2/wrk -D exp -t 4 -c 50 -d 60s -L \
    -s configs/wrk2/compose-post.lua \
    http://${NGINX_IP}:8080/wrk2-api/post/compose -R ${RPS}
  sleep 30
done
```

Goal: identify the P99 knee. Confirm operating points are at 60–70% of saturation.

---

### 2. Warmup (Per Repetition)

```bash
# 60 seconds, all 3 endpoints, at target RPS — discarded from analysis
../wrk2/wrk -D exp -t 2 -c 50 -d 60s \
  -s configs/wrk2/compose-post.lua \
  http://${NGINX_IP}:8080/wrk2-api/post/compose -R 200 &

../wrk2/wrk -D exp -t 2 -c 50 -d 60s \
  -s configs/wrk2/read-home-timeline.lua \
  http://${NGINX_IP}:8080/wrk2-api/home-timeline/read -R 300 &

../wrk2/wrk -D exp -t 2 -c 50 -d 60s \
  -s configs/wrk2/read-user-timeline.lua \
  http://${NGINX_IP}:8080/wrk2-api/user-timeline/read -R 300 &

wait
```

Metrics recorded: None (discarded).

Purpose: JIT compilation, TCP connection pool warm-up, Redis cache warm-up, MongoDB index loading into memory.

---

### 3. Measurement Run (Per Repetition)

```bash
# 180 seconds, all 3 endpoints simultaneously
../wrk2/wrk -D exp -t 2 -c 50 -d 180s -L \
  -s configs/wrk2/compose-post.lua \
  http://${NGINX_IP}:8080/wrk2-api/post/compose -R 200 \
  > data/raw/run_NNN/compose-post.txt &

../wrk2/wrk -D exp -t 2 -c 50 -d 180s -L \
  -s configs/wrk2/read-home-timeline.lua \
  http://${NGINX_IP}:8080/wrk2-api/home-timeline/read -R 300 \
  > data/raw/run_NNN/home-timeline.txt &

../wrk2/wrk -D exp -t 2 -c 50 -d 180s -L \
  -s configs/wrk2/read-user-timeline.lua \
  http://${NGINX_IP}:8080/wrk2-api/user-timeline/read -R 300 \
  > data/raw/run_NNN/user-timeline.txt &

wait
```

**wrk2 flags explained:**
- `-D exp` — Exponential inter-arrival times (Poisson process, open-loop, no coordinated omission)
- `-t 2` — 2 threads (matches available cpuset on load-gen node)
- `-c 50` — 50 connections (sized for open-loop semantics at these RPS)
- `-d 180s` — 180 second measurement window
- `-L` — Output full latency histogram (required for P99.99 extraction)

---

### 4. Background Metric Collection (During Measurement)

#### ztunnel CPU per-thread

Polled every 1 second from worker-0 via SSH:

```bash
ZTUNNEL_PID=$(kubectl exec -n istio-system ${ZTUNNEL_POD} -- cat /proc/1/status | grep ^Pid | awk '{print $2}')

while true; do
  for TID in $(ls /proc/${ZTUNNEL_PID}/task/); do
    cat /proc/${ZTUNNEL_PID}/task/${TID}/stat
  done
  echo "---"
  sleep 1
done
```

#### ztunnel RSS

Polled every 5 seconds:

```bash
while true; do
  echo "=== $(date) ==="
  cat /proc/${ZTUNNEL_PID}/smaps_rollup | grep Rss
  sleep 5
done
```

#### Jaeger Traces (Post-Run Collection)

```bash
# Collect all compose-post traces via Jaeger HTTP API
curl "http://${JAEGER_IP}:16686/api/traces?service=compose-post&limit=10000" \
  > data/raw/run_NNN/jaeger-traces.json
```

Sampling rate: **100%** during baseline (Exp 12). Documents every request's per-hop span.

---

## Metrics Collected

### Application-Level (wrk2)

- Latency percentiles: P50, P75, P90, P95, P99, P99.9, P99.99
- Throughput: actual requests/second achieved
- Error rate: HTTP errors + connection failures (%)

### System-Level

- ztunnel CPU utilization: per-thread, per-second (from `/proc`)
- ztunnel RSS: from `/smaps_rollup`
- Node CPU: `kubectl top node`
- Pod CPU: `kubectl top pod`

### Distributed Tracing (Jaeger)

- Per-hop span latency for `compose-post` call chain
- Allows isolating which service hop contributes to tail latency
- Used to produce the Jaeger flame chart (paper Figure 3)

---

## Repetition Protocol

- **5 independent repetitions** per experiment configuration
- Between repetitions: full DSB teardown + redeploy + social graph re-init
- Results: median across 5 runs for all percentiles
- 95% Confidence Interval: bootstrap resampling (N = 10,000 samples)
- Validity gate: coefficient of variation (CV) < 5% on P50; failing runs flagged and repeated

Bootstrap CI calculation:
```python
import numpy as np

def bootstrap_ci(data, stat=np.median, n_boot=10000, ci=95):
    boot_stats = [stat(np.random.choice(data, len(data), replace=True))
                  for _ in range(n_boot)]
    lo = np.percentile(boot_stats, (100 - ci) / 2)
    hi = np.percentile(boot_stats, 100 - (100 - ci) / 2)
    return lo, hi
```

---

## Controls

- **Fixed replicas**: 1 replica per service (no HPA / autoscaling)
- **No autoscaling**: disabled cluster-wide
- **No background workloads**: no other user workloads on the cluster
- **Node placement enforced**: nodeAffinity rules prevent scheduler drift
- **Same namespace**: ambient mesh enabled via `istio.io/dataplane-mode: ambient`
- **Fixed DB state**: social graph re-initialized identically before every repetition
- **Jaeger memory limit**: `--memory.max-traces=500000` to prevent OOM on worker-1

---

## Key Advantage of wrk2 over Fortio

Unlike Fortio's closed-loop connection model, wrk2 with `-D exp` uses:

- **Open-loop Poisson arrivals**: requests are issued on a schedule independent of response times
- **No coordinated omission**: if the server is slow, later requests are still issued on schedule
- **Accurate tail latency**: slow responses count as slow — they are not hidden by "wait for previous response" behavior

This is industry standard for microservice latency benchmarking (used by Rajomon, Sinan, FIRM, Topfull).

---

## Prometheus Queries (Supplemental)

```promql
# ztunnel CPU usage (supplemental — primary is /proc)
rate(container_cpu_usage_seconds_total{pod=~"ztunnel.*"}[1m])

# Request latency via Istio metrics
histogram_quantile(0.99,
  rate(istio_request_duration_milliseconds_bucket[1m])
)

# Request throughput
rate(istio_requests_total[1m])

# Network throughput on worker-0
rate(container_network_transmit_bytes_total{pod=~"social-graph.*|user-service.*"}[1m])
```
