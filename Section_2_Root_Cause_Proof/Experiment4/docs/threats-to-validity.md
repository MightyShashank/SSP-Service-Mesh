# Threats to Validity

## Internal Validity

- Background cluster processes may introduce noise
- CPU contention outside ztunnel may affect results
- eBPF probe overhead may add latency (though measured at <5μs)

Mitigation:
- Dedicated node used
- Minimal background workload
- Probe overhead measured and documented (<0.1% of request latency)

---

## External Validity

- Results may vary across:
  - Different hardware
  - Different cluster sizes
  - Different Istio/ztunnel versions
  - Different kernel versions (eBPF support varies)
  - Different bpftrace versions

---

## Measurement Bias

- Fortio measurements depend on client-side resource availability
- eBPF timestamps use monotonic clock (reliable, but limited to single-host)
- Network stack variability may affect results

Mitigation:
- Client runs on same node
- Fixed QPS (controlled load generation)
- Multiple runs averaged
- Monotonic clock eliminates NTP drift concerns

---

## eBPF-Specific Threats

### Symbol Availability
- ztunnel binary may be stripped (no debug symbols)
- This limits uprobe-based instrumentation
- Fallback to kprobe-only decomposition captures fewer pipeline stages

Mitigation:
- Auto-detection of symbol availability
- Kprobe fallback still captures T_network and T_proxy_total
- Scheduling delay from sched tracepoints provides proxy queue approximation

### Clock Precision
- bpftrace `nsecs` uses `ktime_get_ns()` (nanosecond monotonic clock)
- Cross-probe clock skew is not an issue (single host)

### Probe Interference
- Attaching too many probes simultaneously may introduce latency
- kprobe on hot functions (tcp_rcv_established) fires very frequently

Mitigation:
- PID filtering reduces probe frequency to ztunnel traffic only
- Total probe overhead measured < 0.1% of request latency

---

## Configuration Bias

- NodeSelector forces co-location
- May not reflect real-world deployments
- svc-B load levels (0–1000 RPS) may not represent production scale

---

## Tool Limitations

- bpftrace 0.14.0 lacks some features (e.g., for-each map iteration)
- bpftrace map output format requires post-processing
- Fortio operates from client perspective (complementary to eBPF data)

---

## Conclusion

Despite limitations, the eBPF-based approach provides the strongest available evidence for **localizing latency to proxy-internal queueing**. The combination of kernel probes, scheduler tracepoints, and application-level measurement (Fortio) creates a multi-layered validation that no single tool could achieve. The fallback strategies ensure the experiment produces meaningful results even when ideal conditions (debug symbols) are not met.
