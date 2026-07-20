#!/usr/bin/env bash
# Creates a Hetzner k3s cluster named rts-<run-id> based on the repo's
# hetzner-k3s_cluster_config.yaml, then applies the Reclaim the Stack node
# role labels. Kubeconfig ends up in agent/runs/<run-id>/kubeconfig.
#
# Usage: agent/create-cluster.sh <run-id>

source "$(dirname "$0")/common.sh"

RUN_ID="${1:?Usage: create-cluster.sh <run-id>}"

generate_cluster_config "$RUN_ID"
hetzner-k3s create --config "$(run_dir "$RUN_ID")/cluster_config.yaml"

export KUBECONFIG="$(run_dir "$RUN_ID")/kubeconfig"

# Kubelets may not self-assign node-role.kubernetes.io labels, so the pool
# labels in the cluster config don't work -- label the nodes here instead.
kubectl get nodes -o name | grep -- '-workers-' |
  xargs -I{} kubectl label --overwrite {} node-role.kubernetes.io/worker=
kubectl get nodes -o name | grep -- '-databases-' |
  xargs -I{} kubectl label --overwrite {} node-role.kubernetes.io/database=

kubectl get nodes -o wide

echo
echo "Cluster $(cluster_name "$RUN_ID") is up. To use it:"
echo "export KUBECONFIG=$KUBECONFIG"
