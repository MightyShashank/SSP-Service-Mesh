# Grafana dashboards — placeholder directory.
# Pre-built dashboards for ztunnel and DSB metrics.
# Not required for Experiment 12 script execution;
# provided for convenience during manual debugging.
#
# To import dashboards:
#   1. Deploy Grafana (helm install grafana grafana/grafana)
#   2. Add Prometheus as a data source
#   3. Import JSON files from this directory
#
# Suggested dashboards:
#   - ztunnel-overview.json: CPU, RSS, connection count
#   - dsb-latency.json: Request latency per endpoint
#   - node-resources.json: Node CPU/memory from kube metrics
