#!/bin/bash
set -e
set -o pipefail

# Add user to k8s using service account, no RBAC (must create RBAC after this script)
if [[ -z "$1" ]] || [[ -z "$2" ]]; then
 echo "usage: $0 <service_account_name> <namespace>"
 exit 1
fi

SERVICE_ACCOUNT_NAME=$1
NAMESPACE="$2"

TARGET_FOLDER="/tmp/kube"
mkdir -p $TARGET_FOLDER
KUBECFG_FILE_NAME="/tmp/kube/k8s-${SERVICE_ACCOUNT_NAME}-${NAMESPACE}-conf"

echo -e "\\nService account and namespace config will be written to ${KUBECFG_FILE_NAME}"

echo -e "\\nCreating a service account in ${NAMESPACE}: ${SERVICE_ACCOUNT_NAME}"
kubectl create sa "${SERVICE_ACCOUNT_NAME}" --namespace "${NAMESPACE}"

echo -e "\\nGetting secret of service account ${SERVICE_ACCOUNT_NAME} on ${NAMESPACE}"
SECRET_NAME=$(kubectl get sa "${SERVICE_ACCOUNT_NAME}" --namespace "${NAMESPACE}" -o json | grep -o '"name": ".*-token-.*"' | sed -e 's/"name": "//' -e 's/"//')
echo $SECRET_NAME

echo -e -n "\\nExtracting ca.crt from secret..."
kubectl get secret "${SECRET_NAME}" --namespace "${NAMESPACE}" -o json | grep -o '"ca.crt":.*' | sed -e 's/"ca.crt": "//' -e 's/",//' | base64 -D > "${TARGET_FOLDER}/ca.crt"

echo -e -n "\\nGetting user token from secret..."
USER_TOKEN=$(kubectl get secret "${SECRET_NAME}" --namespace "${NAMESPACE}" -o json | grep -o '"token":.*' | sed -e 's/"token": "//' -e 's/"//' | base64 -D)
echo $USER_TOKEN

context=$(kubectl config current-context)
echo -e "\\nSetting current context to: $context"

CLUSTER_NAME=$(kubectl config get-contexts "$context" | awk '{print $3}' | tail -n 1)
echo "Cluster name: ${CLUSTER_NAME}"

ENDPOINT=$(kubectl config view -o jsonpath="{.clusters[?(@.name == \"${CLUSTER_NAME}\")].cluster.server}")
echo "Endpoint: ${ENDPOINT}"

# Set up the config
echo -e "\\nPreparing k8s-${SERVICE_ACCOUNT_NAME}-${NAMESPACE}-conf"
echo -n "Setting a cluster entry in kubeconfig..."
kubectl config set-cluster "${CLUSTER_NAME}" \
    --kubeconfig="${KUBECFG_FILE_NAME}" \
    --server="${ENDPOINT}" \
    --certificate-authority="${TARGET_FOLDER}/ca.crt" \
    --embed-certs=true

echo -n "Setting token credentials entry in kubeconfig..."
kubectl config set-credentials \
    "${SERVICE_ACCOUNT_NAME}-${NAMESPACE}-${CLUSTER_NAME}" \
    --kubeconfig="${KUBECFG_FILE_NAME}" \
    --token="${USER_TOKEN}"

echo -n "Setting a context entry in kubeconfig..."
kubectl config set-context \
    "${SERVICE_ACCOUNT_NAME}-${NAMESPACE}-${CLUSTER_NAME}" \
    --kubeconfig="${KUBECFG_FILE_NAME}" \
    --cluster="${CLUSTER_NAME}" \
    --user="${SERVICE_ACCOUNT_NAME}-${NAMESPACE}-${CLUSTER_NAME}" \
    --namespace="${NAMESPACE}"

echo -n "Setting the current-context in the kubeconfig file..."
kubectl config use-context "${SERVICE_ACCOUNT_NAME}-${NAMESPACE}-${CLUSTER_NAME}" \
    --kubeconfig="${KUBECFG_FILE_NAME}"

