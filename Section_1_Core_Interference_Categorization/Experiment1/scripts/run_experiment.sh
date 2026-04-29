#!/bin/bash

set -e

RUNS=5

echo "Starting experiment with $RUNS runs..."

for i in $(seq 1 $RUNS); do
  echo "-----------------------------"
  echo "Run $i"
  echo "-----------------------------"

  ./scripts/setup.sh
  sleep 10

  ./scripts/run_once.sh

  ./scripts/cleanup.sh
  sleep 5
done

echo "All runs completed."