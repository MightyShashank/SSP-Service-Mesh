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

- wrk measurements depend on client performance
- Network stack variability may affect results

Mitigation:
- Client runs on same node
- Multiple runs averaged

---

## Configuration Bias

- NodeSelector forces co-location
- May not reflect real-world deployments

---

## Tool Limitations

- wrk does not capture full system behavior
- Limited visibility into internal queueing

---

## Conclusion

Despite limitations, setup provides a **controlled environment** to isolate dataplane contention effects.