#!/bin/bash

<<<<<<< HEAD
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
=======


CYAN="\033[0;36m"
NORMAL="\033[0m"
RED="\033[0;31m"

####################
# Utility functions
####################

function info {
  echo -e "${CYAN}INFO  ${NORMAL}$@" >&2
}

function error {
  echo -e "${RED}ERROR ${NORMAL}$@" >&2
}


function wait-deployment {
  local object=$1
  local ns=$2
  echo -n "Waiting for deployment $object in $ns namespace ready "
  retries=600
  until [[ $retries == 0 ]]; do
    echo -n "."
    local result=$(kubectl get deploy $object -n $ns -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
    if [[ $result == 1 ]]; then
      echo " Done"
      break
    fi
    sleep 1
    retries=$((retries - 1))
  done
  [[ $retries == 0 ]] && echo
}

function wait-ns {
  local ns=$1
  echo -n "Waiting for namespace $ns ready "
  retries=100
  until [[ $retries == 0 ]]; do
    echo -n "."
    local result=$(kubectl get ns $ns -o name 2>/dev/null)
    if [[ $result == "namespace/$ns" ]]; then
      echo " Done"
      break
    fi
    sleep 1
    retries=$((retries - 1))
  done
  [[ $retries == 0 ]] && echo
}

####################
# Install NFS provisioner
####################

function install-helm-release {
  local helm_repository_name=$1;  shift
  local helm_repository_url=$1;   shift
  local helm_release_name=$1;     shift
  local helm_release_namespace=$1;shift
  local helm_chart_name=$1;       shift
  local helm_chart_ref="${helm_repository_name}/${helm_chart_name}"

  # Update helm repo
  if ! helm repo list -o yaml | grep -i "Name:\s*${helm_repository_name}\s*$" >/dev/null; then
    helm repo add "${helm_repository_name}" "${helm_repository_url}"
  fi
  helm repo update

  # Create namespace if not exists
  kubectl get ns "${helm_release_namespace}" >/dev/null 2>&1 || \
    kubectl create ns "${helm_release_namespace}"

  # Install helm release
  helm upgrade --install "${helm_release_name}" --namespace "${helm_release_namespace}" \
    "${helm_chart_ref}" $@ 2>/dev/null

  wait-deployment ${helm_chart_name} ${helm_release_namespace}
}

function install-nfs-provisioner {
  info "Installing NFS provisioner ..."

  local helm_repository_name="nfs-subdir-external-provisioner"
  local helm_repository_url="https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner"
  local helm_release_name="nfs-subdir-external-provisioner"
  local helm_release_namespace="default"
  local helm_chart_name="nfs-subdir-external-provisioner"

  install-helm-release \
    ${helm_repository_name} ${helm_repository_url} \
    ${helm_release_name} ${helm_release_namespace} ${helm_chart_name} \
    --set nfs.server=${NFS_HOST} --set nfs.path=${NFS_PATH}

  info "Installing NFS provisioner ... OK"
}

####################
# Install Instana kubectl plugin
####################

function install-kubectl-instana-plugin {
  info "Installing Instana kubectl plugin ${INSTANA_KUBECTL_PLUGIN_VERSION} ..."

  echo "deb [arch=amd64] https://self-hosted.instana.io/apt generic main" > /etc/apt/sources.list.d/instana-product.list
  wget -qO - "https://self-hosted.instana.io/signing_key.gpg" | apt-key add -
  apt-get update
  apt-get install instana-kubectl=${INSTANA_KUBECTL_PLUGIN_VERSION} -y

  info "Installing Instana kubectl plugin ${INSTANA_KUBECTL_PLUGIN_VERSION} ... OK"
}

####################
# Install Instana Console
####################

function install-instana-console {
  info "Installing Instana console ${INSTANA_VERSION} ..."

  echo "deb [arch=amd64] https://self-hosted.instana.io/apt generic main" > /etc/apt/sources.list.d/instana-product.list
  wget -qO - "https://self-hosted.instana.io/signing_key.gpg" | apt-key add -
  apt-get update
  apt-get install instana-console=${INSTANA_VERSION} -y

  info "Installing Instana console ${INSTANA_VERSION} ... OK"
}

####################
# Generate Instana license
####################

function generate-instana-license {
  info "Generating Instana license ..."

  instana license download --key=${INSTANA_SALES_KEY}

  if [[ -f license ]]; then
    local lic_text="$(cat license)"
    lic_text="${lic_text%\]}"
    lic_text="${lic_text#\[}"
    lic_text="${lic_text%\"}"
    lic_text="${lic_text#\"}"
    echo "$lic_text" > ${WORKDIR}/license
  fi

  info "Generating Instana license ... OK"
}

####################
# Install Instana
####################

function install-instana {
  info "Installing Instana ${INSTANA_VERSION} ..."

  echo "Creating self-signed certificate ..."
  openssl req -x509 -newkey rsa:2048 -keyout ${WORKDIR}/tls.key -out ${WORKDIR}/tls.crt -days 365 -nodes -subj "/CN=*.${INSTANA_HOST}"

  echo "Generating dhparams ..."
  openssl dhparam -out ${WORKDIR}/dhparams.pem 1024

  kubectl instana apply --yes --settings-file ${WORKDIR}/settings.hcl

  wait-ns instana-core

echo "Creating persistent volume claim ..."
  cat << EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: spans-volume-claim
  namespace: instana-core
spec:
  storageClassName: nfs-client
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 10Gi
EOF

  wait-deployment acceptor instana-core
  wait-deployment ingress-core instana-core
  wait-deployment ingress instana-units

  info "Installing Instana ${INSTANA_VERSION} ... OK"

}

function print-summary-k8 {
  cat << EOF

👏 Congratulations! The Self-hosted Instana on Kubernetes is available!

To access Instana UI, open https://${INSTANA_HOST} in browser.
- username: admin@instana.local
- password: ${PASSWORD}


EOF
}

function print-elapsed {
  elapsed_time=$(($SECONDS - $start_time))
  echo "Total elapsed time: $elapsed_time seconds"
}


################### Main ####################


#        preflight-check
#        install-kind
#        install-kubectl
#        install-helm
#        kind-up $@
#        install-nfs-provisioner
#        install-instana-console
#        install-kubectl-instana-plugin
#        generate-instana-license
#        install-instana $@
#        setup-network
#        print-summary-k8
#        print-elapsed

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
>>>>>>> 59753c8897937fe81010339bf88498ed022d0cc4

kubectl apply -f networking.yaml

print-summary-k8

<<<<<<< HEAD
print-elapsed
=======
print-elapsed
>>>>>>> 59753c8897937fe81010339bf88498ed022d0cc4
