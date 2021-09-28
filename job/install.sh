#!/bin/bash

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

mkdir -p ${DEPLOY_LOCAL_WORKDIR}
mkdir -p ${TOOLS_HOST_DIR}

# Custom settings
. ${ROOT_DIR}/config.sh

# Import Function 
. ${ROOT_DIR}/common.sh

start_time=$SECONDS

echo $KUBECONFIG > /root/.kube/config


## config ##
echo "Instana db host ${INSTANA_DB_HOST} "
NFS_HOST=${INSTANA_DB_HOST}
NFS_PATH="/mnt/nfs_share"
INSTANA_HOST=$(cat /root/instana/conf/settings.hcl | grep base_domain | awk -F '"' '{print $2}')
INSTANA_SALES_KEY=$(cat /root/instana/conf/settings.hcl | grep sales_key | awk -F '"' '{print $2}')
PASSWORD=$(cat /root/instana/conf/settings.hcl | grep admin_password | awk -F '"' '{print $2}')
WORKDIR="/root/instana"

INSTANA_VERSION=${INSTANA_VERSION:-205-2}
INSTANA_KUBECTL_PLUGIN_VERSION=${INSTANA_VERSION:-205-0}

## Copy settings.hcl from mount point to work directory
cp ${WORKDIR}/conf/settings.hcl ${WORKDIR}/settings.hcl

# start install #

install-nfs-provisioner

#install-instana-console

install-kubectl-instana-plugin

generate-instana-license

install-instana

kubectl apply -f networking.yaml

print-summary-k8

print-elapsed