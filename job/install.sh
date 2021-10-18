#!/bin/bash

#set -x

# OS and arch settings
HOSTOS=$(uname -s | tr '[:upper:]' '[:lower:]')
HOSTARCH=$(uname -m)
SAFEHOSTARCH=${HOSTARCH}
if [[ ${HOSTOS} == darwin ]]; then
  SAFEHOSTARCH=amd64
fi
if [[ ${HOSTARCH} == x86_64 ]]; then
  SAFEHOSTARCH=amd64
fi
HOST_PLATFORM=${HOSTOS}_${HOSTARCH}
SAFEHOSTPLATFORM=${HOSTOS}-${SAFEHOSTARCH}

# Directory settings
ROOT_DIR=$(cd -P $(dirname $0) >/dev/null 2>&1 && pwd)
WORK_DIR=${ROOT_DIR}/.work
DEPLOY_LOCAL_WORKDIR=${WORK_DIR}/local/localdev
CACHE_DIR=${ROOT_DIR}/.cache
TOOLS_DIR=${CACHE_DIR}/tools
TOOLS_HOST_DIR=${TOOLS_DIR}/${HOST_PLATFORM}
INSTANA_SETTINGS_PATH="/root/instana/conf"

mkdir -p ${DEPLOY_LOCAL_WORKDIR}
mkdir -p ${TOOLS_HOST_DIR}

# Custom settings
. ${ROOT_DIR}/config.sh

# Import Function 
. ${ROOT_DIR}/common.sh

start_time=$SECONDS

#echo $KUBECONFIG > /root/.kube/config


## config ##
INSTANA_SALES_KEY=$(cat /root/instana/conf/settings.hcl | grep sales_key | awk -F '"' '{print $2}')


# start install #
install-kubectl
install-helm
install-nfs-provisioner

install-instana-console

install-kubectl-instana-plugin
generate-instana-license

install-instana $@

kubectl apply -f networking.yaml

print-summary-k8

print-elapsed
