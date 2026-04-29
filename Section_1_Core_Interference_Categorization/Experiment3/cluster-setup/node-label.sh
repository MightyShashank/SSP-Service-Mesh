#!/bin/bash

NODE_NAME=ssp-worker-1

echo "[INFO] Labeling node for co-location..."
kubectl label node $NODE_NAME exp=mesh --overwrite

# This above command will label the node with "exp=mesh". (Since kube scheduler used labels to decide where should I place this pod) The --overwrite flag allows it to overwrite any existing label with the same key. 
# You can verify the labeling by running:
# kubectl get nodes --show-labels

