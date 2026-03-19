# Threats to Validity

## Internal Validity

- Background cluster processes may introduce noise
- CPU contention outside ztunnel may affect results

Mitigation:
- Dedicated node used
- Minimal background workload

---

## External Validity

- Results may vary across:
  - Different hardware
  - Different cluster sizes
  - Different Istio versions

---

## Measurement Bias

- Fortio measurements depend on client-side resource availability
- Network stack variability may affect results

Mitigation:
- Client runs on same node
- Fixed QPS (controlled load generation)
- Multiple runs averaged

---

## Configuration Bias

- NodeSelector forces co-location
- May not reflect real-world deployments

---

## Tool Limitations

- Fortio operates from a client perspective and does not capture full internal dataplane behavior
- Limited direct visibility into internal queueing and scheduling inside ztunnel
- Requires external observability (Prometheus/Grafana) for system-level insights

---

## Conclusion

Despite limitations, the setup provides a **controlled, QPS-driven environment** to isolate dataplane contention effects and study tail latency behavior under multi-service load.