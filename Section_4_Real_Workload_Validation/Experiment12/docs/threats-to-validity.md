# Threats to Validity — Experiment 12: DeathStarBench Baseline

## Internal Validity

### MongoDB Write-Ahead Log (WAL) Variance
DSB's MongoDB instances use WAL, which creates periodic I/O spikes that add noise to per-run latency.

**Mitigation:**
- Re-initialize the database between every repetition (fresh state → identical WAL behavior)
- 5 repetitions with median reporting reduces WAL-induced variance
- Flag and discard runs where P50 CV > 5%

### Redis Eviction Randomness
Redis LRU eviction policy is non-deterministic; cache hit rates vary between runs.

**Mitigation:**
- Re-run `init_social_graph.py` before every repetition to warm the follow-graph cache
- 60-second warmup ensures Redis is in a stable cache-hit state before measurement begins

### Background Kubernetes System Processes
kube-proxy, CNI plugin, log collectors, and metrics-server run on all nodes and consume CPU.

**Mitigation:**
- wrk2 is `cpuset`-isolated on the load-gen node, not sharing cores with kube system pods
- Victim-tier and mid-tier services are not co-located with kube-system workloads on their respective nodes
- Run `kubectl top pod -A` before each experiment to verify no unexpected system pods on worker-0

### JIT / Cold-Start Effects
Go and Java runtimes (used by some DSB services) have JIT compilation warm-up periods that inflate early latency.

**Mitigation:**
- 60-second warmup phase discarded from all measurements
- Warmup uses identical RPS as measurement phase to bring all services to operating temperature

---

## External Validity

### Hardware Generalizability
Results are collected on 4 vCPU / 8 GB RAM managed Kubernetes nodes (actual cluster). The paper's design assumed 2 vCPU nodes. The interference mechanism (shared ztunnel task queue) is hardware-independent, but the magnitude of interference and the saturation operating point are hardware-specific.

**Mitigation:**
- Saturation sweep (`run-saturation-sweep.sh`) identifies the actual knee for this hardware
- Operating point (200/300/300 RPS) is calibrated to 60–70% of saturation on the actual cluster, not the paper's assumed point
- All comparisons (Exp 13, 14) use the same hardware, so relative interference ratios are valid

### Istio Version Sensitivity
Behavior of Istio Ambient's ztunnel may change across versions. Results are specific to ztunnel 1.23.x.

**Mitigation:**
- `data/metadata/software-versions.txt` records exact versions (ztunnel commit hash, Istio chart version)
- Reproducibility requires pinning to same Istio/ztunnel version

### DeathStarBench Version Sensitivity
DSB's Social-Network microservices and Helm chart evolve. Service call paths may change between versions.

**Mitigation:**
- Pin DSB to a specific git commit hash recorded in `data/metadata/git-commit.txt`
- Use the official social-network Helm chart (no local modifications)

### Single Cluster / No Multi-Cluster
This experiment uses a single 3-node cluster. Results may not generalize to multi-cluster deployments where cross-node ztunnel performance differs.

**Mitigation:**
- The interference mechanism is node-local (same ztunnel instance), so single-node results are sufficient to demonstrate the effect
- Out of scope for this experiment: cross-node ztunnel contention

---

## Measurement Bias

### Open-Loop vs. Real Traffic Patterns
wrk2 with `-D exp` generates Poisson arrivals, which approximates but does not perfectly match real production traffic (which may have burstier patterns, larger payloads, different connection rates).

**Mitigation:**
- Poisson is the standard arrival model in queuing theory and the model used by all comparison papers (Rajomon, Sinan, FIRM)
- Experiment 13 includes a burst-mode trial that explicitly tests bursty patterns

### Coordinated Omission (Addressed by wrk2)
Closed-loop load generators (e.g., `ab`, plain `curl` loops) underestimate tail latency by hiding slow responses behind think time. wrk2 with `-D exp` eliminates this.

**Mitigation:**
- `-D exp` flag is mandatory; never remove it
- Never use `hey` or `ab` as a drop-in replacement for P99.99 measurements

### Jaeger Overhead
Jaeger's all-in-one deployment on `worker-1` consumes CPU and memory (est. 0.3–0.5 vCPU at 100% sampling + 500 RPS total throughput).

**Mitigation:**
- Jaeger is deployed on `worker-1`, not `worker-0` — it does not consume victim-tier CPU budget
- Jaeger's own latency (exporter calls) adds a small overhead to every service span; this is uniform and identical across all repetitions, so it does not bias relative comparisons
- Memory limit set to avoid OOM: 4 GB heap for Jaeger all-in-one

### wrk2 Thread Count Limitation
`-t 2` (2 threads) is used to match the cpuset allocation on the load-gen node. At very high target RPS, wrk2 may not sustain the target rate if the load-gen node becomes saturated.

**Mitigation:**
- The saturation sweep monitors both server-side P99 AND wrk2's reported actual RPS; if actual < target by > 5%, the node is saturated and cannot sustain that rate
- At 200/300/300 RPS with 2 threads, load-gen CPU usage is expected to be < 30% of the 4-vCPU budget (safe margin)

---

## Configuration Bias

### nodeAffinity Enforcement
nodeAffinity rules force co-location of victim-tier services on `worker-0`. This does not reflect real-world deployments where operators use anti-affinity for application coupling, not for proxy isolation.

**This is intentional, not a bias.** The paper's argument is that ambient mode's isolation guarantee is broken even when operators follow normal Kubernetes best practices. nodeAffinity is the exact mechanism operators would use to co-locate related services on the same node for network performance — with the unintended consequence of sharing the ztunnel.

### Fixed Replica Count
All services run with 1 replica. Real deployments have multiple replicas with HPA.

**Mitigation:**
- 1 replica per service is sufficient to demonstrate the interference mechanism
- Multiple replicas would distribute traffic across nodes, reducing the per-ztunnel load and making interference less visible — not more
- Experiment scope: demonstrate the mechanism, not characterize production scale behavior

---

## Tool Limitations

- **wrk2** reports latency from the client's perspective; it does not capture internal proxy queueing delay (that requires eBPF, as in Exp 4)
- **Jaeger** adds tracing overhead to every service call; at 100% sampling this is measurable but small (< 100 μs per span export call)
- **`/proc` CPU polling** is sampled at 1-second intervals; sub-second CPU spikes are not captured
- **`kubectl top`** relies on the Metrics API, which aggregates over 15-second windows — too coarse for tail latency correlation; used only for sanity checking, not for paper figures

---

## Conclusion

Despite these limitations, Experiment 12's setup provides a **rigorous, DSB-community-standard baseline** for DSB Social-Network under Istio Ambient Mode. The combination of:

- wrk2 open-loop load generation (no coordinated omission)
- 5 repetitions with fresh DB initialization (controls variance)
- Split-node placement matching the paper's threat model
- Jaeger tracing for per-hop latency attribution

...establishes a defensible baseline against which Experiments 13 and 14 can demonstrate the interference effect and recovery time under real microservice workloads.
