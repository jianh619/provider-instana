####################
# Utility functions
####################

CYAN="\033[0;36m"
NORMAL="\033[0m"
RED="\033[0;31m"

function info {
  echo -e "${CYAN}INFO  ${NORMAL}$@" >&2
}

function error {
  echo -e "${RED}ERROR ${NORMAL}$@" >&2
}

function wait-ns {
  local ns=$1
  echo -n "Waiting for namespace $ns ready "
  retries=100
  until [[ $retries == 0 ]]; do
    echo -n "."
    local result=$(${KUBECTL} --kubeconfig ${KUBECONFIG} get ns $ns -o name 2>/dev/null)
    if [[ $result == "namespace/$ns" ]]; then
      echo " Done"
      break
    fi
    sleep 1
    retries=$((retries - 1))
  done
  [[ $retries == 0 ]] && echo
}

function wait-deployment {
  local object=$1
  local ns=$2
  echo -n "Waiting for deployment $object in $ns namespace ready "
  retries=600
  until [[ $retries == 0 ]]; do
    echo -n "."
    local result=$(${KUBECTL} --kubeconfig ${KUBECONFIG} get deploy $object -n $ns -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
    if [[ $result == 1 ]]; then
      echo " Done"
      break
    fi
    sleep 1
    retries=$((retries - 1))
  done
  [[ $retries == 0 ]] && echo
}

function add-apt-source {
  local source_list="$1"
  local source_item="$2"
  local apt_key="$3"
  local grep_text="${source_item/[/\\[}"
  grep_text="${grep_text/]/\\]}"
  touch /etc/apt/sources.list.d/${source_list}
  if ! cat /etc/apt/sources.list.d/${source_list} | grep -q "${grep_text}"; then
    echo "${source_item}" >> /etc/apt/sources.list.d/${source_list}
    wget -qO - ${apt_key} | apt-key add -
  fi
}

function install-apt-package {
  local required_pkg="$1"
  local pkg_version="$2"
  local arg="${required_pkg}"
  if [[ -n ${pkg_version} ]]; then
    arg="${required_pkg}=${pkg_version}"
  fi

  local pkg_ok=$(dpkg-query -W --showformat='${Status} [${Version}]\n' ${required_pkg} | grep "install ok installed")
  if [[ -z ${pkg_ok} ]]; then
    apt-get update
    apt-get --yes install ${arg}
  else
    if [[ -n ${pkg_version} ]]; then
      apt-get --yes install ${arg} --allow-downgrades
    else
      echo "${required_pkg} detected."
    fi
  fi
}

function install-helm-release {

  local helm_repository_name=$1;  shift
  local helm_repository_url=$1;   shift
  local helm_release_name=$1;     shift
  local helm_release_namespace=$1;shift
  local helm_chart_name=$1;       shift
  local helm_chart_ref="${helm_repository_name}/${helm_chart_name}"
  
  info "Installing helm ${helm_release_name} from  ..."


  echo "helm is"+${HELM}
  # Update helm repo
  if ! "${HELM}" repo list -o yaml | grep -i "Name:\s*${helm_repository_name}\s*$" >/dev/null; then
    ${HELM} repo add "${helm_repository_name}" "${helm_repository_url}"
  fi
  ${HELM} repo update

  # Create namespace if not exists
  ${KUBECTL} --kubeconfig ${KUBECONFIG} get ns "${helm_release_namespace}" >/dev/null 2>&1 || \
    ${KUBECTL} --kubeconfig ${KUBECONFIG} create ns "${helm_release_namespace}"

  # Install helm release
  ${HELM} upgrade --install "${helm_release_name}" --namespace "${helm_release_namespace}" --kubeconfig "${KUBECONFIG}" \
    "${helm_chart_ref}" $@ 2>/dev/null

  wait-deployment ${helm_chart_name} ${helm_release_namespace}
}

####################
# Preflight check
####################

function preflight-check {
  if ! command -v docker >/dev/null 2>&1; then
    error "docker not installed, exit."
    exit 1
  fi

  if [[ -z $INSTANA_DOWNLOAD_KEY ]]; then
    error "INSTANA_DOWNLOAD_KEY must not be empty, exit."
    exit 1
  fi

  if [[ -z $INSTANA_SALES_KEY ]]; then
    error "INSTANA_SALES_KEY must not be empty, exit."
    exit 1
  fi
}

####################
# Install kind
####################

KIND=${TOOLS_HOST_DIR}/kind-${KIND_VERSION}

function install-kind {
  info "Installing kind ${KIND_VERSION} ..."

  if [[ ! -f ${KIND} ]]; then
    curl -fsSLo ${KIND} https://github.com/kubernetes-sigs/kind/releases/download/${KIND_VERSION}/kind-${SAFEHOSTPLATFORM} || exit -1
    chmod +x ${KIND}
  else
    echo "kind ${KIND_VERSION} detected."
  fi

  info "Installing kind ${KIND_VERSION} ... OK"
}


####################
# Install java
####################

JAVA=${TOOLS_HOST_DIR}/jdk-${JAVA_VERSION}

function install-java {
  info "Installing java ${JAVA_VERSION} ..."

  if [[ ! -f ${JAVA} ]]; then
    info "https://download.java.net/java/ga/jdk${JAVA_VERSION}/openjdk-${JAVA_VERSION}_linux-x64_bin.tar.gz"
    curl https://download.java.net/java/ga/jdk11/openjdk-11_linux-x64_bin.tar.gz | tar -xz -C ${TOOLS_HOST_DIR}   
  else
    echo "java ${JAVA_VERSION} detected."
  fi

  info "Installing java ${JAVA_VERSION} ... OK"
}

####################
# Install kubectl
####################

KUBECTL=${TOOLS_HOST_DIR}/kubectl-${KUBECTL_VERSION}

function install-kubectl {
  info "Installing kubectl ${KUBECTL_VERSION} ..."

  if [[ ! -f ${KUBECTL} ]]; then
    curl -fsSLo ${KUBECTL} https://storage.googleapis.com/kubernetes-release/release/${KUBECTL_VERSION}/bin/${HOSTOS}/${SAFEHOSTARCH}/kubectl || exit -1
    chmod +x ${KUBECTL}
  else
    echo "kubectl ${KUBECTL_VERSION} detected."
  fi

  info "Installing kubectl ${KUBECTL_VERSION} ... OK"
}

####################
# Install helm
####################

HELM3=${TOOLS_HOST_DIR}/helm-${HELM3_VERSION}
HELM=${HELM3}

function install-helm {
  info "Installing helm3 ${HELM3_VERSION} ..."

  if [[ ! -f ${HELM3} ]]; then
    mkdir -p ${TOOLS_HOST_DIR}/tmp-helm3
    curl -fsSL https://get.helm.sh/helm-${HELM3_VERSION}-${SAFEHOSTPLATFORM}.tar.gz | tar -xz -C ${TOOLS_HOST_DIR}/tmp-helm3
    mv ${TOOLS_HOST_DIR}/tmp-helm3/${SAFEHOSTPLATFORM}/helm ${HELM3}
    rm -fr ${TOOLS_HOST_DIR}/tmp-helm3
  else
    echo "helm3 ${HELM3_VERSION} detected."
  fi

  info "Installing helm3 ${HELM3_VERSION} ... OK"
}

####################
# Launch kind
####################

# The cluster information
DEPLOY_LOCAL_KUBECONFIG=${DEPLOY_LOCAL_WORKDIR}/kubeconfig
KIND_CLUSTER_NAME=instana-demo
KUBECONFIG=${HOME}/.kube/config

function kind-up {
  info "kind up ..."

  if [[ $1 == --reg ]]; then
    KIND_CONFIG_FILE=${ROOT_DIR}/kind-reg.yaml
  else
    KIND_CONFIG_FILE=${ROOT_DIR}/kind.yaml
  fi

  ${KIND} get kubeconfig --name ${KIND_CLUSTER_NAME} >/dev/null 2>&1 || ${KIND} create cluster --name=${KIND_CLUSTER_NAME} --kubeconfig="${KUBECONFIG}" --config="${KIND_CONFIG_FILE}"
  ${KIND} get kubeconfig --name ${KIND_CLUSTER_NAME} > ${DEPLOY_LOCAL_KUBECONFIG}
  ${KUBECTL} --kubeconfig ${KUBECONFIG} config use-context kind-${KIND_CLUSTER_NAME}

  if [[ $1 == --reg ]]; then
    # Document the local registry
    wait-ns kube-public

    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: local-registry-hosting
  namespace: kube-public
data:
  localRegistryHosting.v1: |
    host: "localhost:${REG_PORT}"
    help: "https://kind.sigs.k8s.io/docs/user/local-registry/"
EOF

    # Connect the registry to the cluster network
    docker network connect "kind" "${REG_NAME}" || true
  fi

  info "kind up ... OK"
}

function kind-down {
  info "kind down ..."

  ${KIND} delete cluster --name=${KIND_CLUSTER_NAME}

  info "kind down ... OK"
}

####################
# Install NFS
####################

NFS_PATH="/mnt/nfs_share"

function install-nfs {
  info "Installing nfs-kernel-server ..."

  install-apt-package "nfs-kernel-server"

  info "Installing nfs-kernel-server ... OK"

  info "Setting up nfs share ..."

  echo "Create root NFS directory"
  mkdir -p ${NFS_PATH}
  chown nobody:nogroup ${NFS_PATH} # No-one is owner
  chmod 777 ${NFS_PATH}            # Everyone can modify files

  echo "Define access for NFS clients in export file /etc/exports"
  if ! cat /etc/exports | grep -q "${NFS_PATH}"; then
    echo "${NFS_PATH} *(rw,sync,no_root_squash,no_all_squash,no_subtree_check)" >> /etc/exports

    echo "Make the nfs share available to clients"
    exportfs -a                         # Making the file share available
    systemctl restart nfs-kernel-server # Restarting the NFS kernel
  fi

  info "Setting up nfs share ... OK"
}

####################
# Install Instana Console
####################

function install-instana-console {
  info "Installing Instana console ${INSTANA_CONSOLE_VERSION} ..."

  add-apt-source "instana-product.list" \
    "deb [arch=amd64] https://self-hosted.instana.io/apt generic main" \
    "https://self-hosted.instana.io/signing_key.gpg"

  install-apt-package "instana-console" ${INSTANA_CONSOLE_VERSION}

  info "Installing Instana console ${INSTANA_CONSOLE_VERSION} ... OK"
}

####################
# Install Instana DB
####################

function install-instana-db {
  info "Installing Instana DB ${INSTANA_CONSOLE_VERSION} ..."

  mkdir -p /mnt/metrics     # cassandra data dir
  mkdir -p /mnt/traces      # clickhouse data dir
  mkdir -p /mnt/data        # elastic, cockroachdb and kafka data dir
  mkdir -p /mnt/log         # log dir for db's

  echo "Installing Instana DB using the provided settings ..."
  cat ${ROOT_DIR}/conf/settings-db.hcl.tpl | \
    sed -e "s|@@INSTANA_DOWNLOAD_KEY|${INSTANA_DOWNLOAD_KEY}|g; \
      s|@@INSTANA_DB_HOST|${INSTANA_DB_HOST}|g;" > ${DEPLOY_LOCAL_WORKDIR}/settings-db.hcl

  instana datastores init --file ${DEPLOY_LOCAL_WORKDIR}/settings-db.hcl --force

  info "Installing Instana DB ${INSTANA_CONSOLE_VERSION} ... OK"
}

####################
# Install NFS provisioner
####################

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

  add-apt-source "instana-product.list" \
    "deb [arch=amd64] https://self-hosted.instana.io/apt generic main" \
    "https://self-hosted.instana.io/signing_key.gpg"

  install-apt-package "instana-kubectl" ${INSTANA_KUBECTL_PLUGIN_VERSION}

  info "Installing Instana kubectl plugin ${INSTANA_KUBECTL_PLUGIN_VERSION} ... OK"
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
    echo "$lic_text" > ${DEPLOY_LOCAL_WORKDIR}/license
    rm -f license 
  fi

  info "Generating Instana license ... OK"
}

####################
# Install Instana
####################

function install-instana {
  info "Installing Instana ${INSTANA_VERSION} ..."

  echo "Creating self-signed certificate ..."
  if [[ ! -f ${DEPLOY_LOCAL_WORKDIR}/tls.key || ! -f ${DEPLOY_LOCAL_WORKDIR}/tls.crt ]]; then
    openssl req -x509 -newkey rsa:2048 -keyout ${DEPLOY_LOCAL_WORKDIR}/tls.key -out ${DEPLOY_LOCAL_WORKDIR}/tls.crt -days 365 -nodes -subj "/CN=*.${INSTANA_FQDN}"
  else
    echo "Self-signed certificate detected"
  fi

  echo "Generating dhparams ..."
  if [[ ! -f ${DEPLOY_LOCAL_WORKDIR}/dhparams.pem ]]; then
    openssl dhparam -out ${DEPLOY_LOCAL_WORKDIR}/dhparams.pem 1024
  else
    echo "dhparams detected"
  fi

  echo "setting path" ${INSTANA_SETTINGS_PATH}

  if [[ ! -f ${INSTANA_SETTINGS_PATH}/settings.hcl ]]; then
    INSTANA_DB_HOSTIP="$(host ${INSTANA_DB_HOST} | awk '/has.*address/{print $NF; exit}')"
    INSTANA_LICENSE=${DEPLOY_LOCAL_WORKDIR}/license
    INSTANA_SETTINGS=${ROOT_DIR}/conf/settings.hcl.tpl
    if [[ $1 == --reg ]]; then
      INSTANA_SETTINGS=${ROOT_DIR}/conf/settings-reg.hcl.tpl
    fi
    cat ${INSTANA_SETTINGS} | \
      sed -e "s|@@INSTANA_DOWNLOAD_KEY|${INSTANA_DOWNLOAD_KEY}|g; \
        s|@@INSTANA_SALES_KEY|${INSTANA_SALES_KEY}|g; \
        s|@@INSTANA_LICENSE|${INSTANA_LICENSE}|g; \
        s|@@INSTANA_FQDN|${INSTANA_FQDN}|g; \
        s|@@INSTANA_DB_HOSTIP|${INSTANA_DB_HOSTIP}|g; \
        s|@@ROOT_DIR|${ROOT_DIR}|g; \
        s|@@DEPLOY_LOCAL_WORKDIR|${DEPLOY_LOCAL_WORKDIR}|g;" > ${DEPLOY_LOCAL_WORKDIR}/settings.hcl
    ${KUBECTL} instana apply --yes --settings-file ${DEPLOY_LOCAL_WORKDIR}/settings.hcl
  else
    echo "Applying Instana using provided settings "
    cp ${INSTANA_SETTINGS_PATH}/settings.hcl ${DEPLOY_LOCAL_WORKDIR}/
    ${KUBECTL} instana apply --yes --settings-file ${DEPLOY_LOCAL_WORKDIR}/settings.hcl
  fi
  wait-ns instana-core

  wait-deployment acceptor instana-core
  wait-deployment ingress-core instana-core
  wait-deployment ingress instana-units

  info "Installing Instana ${INSTANA_VERSION} ... OK"
}

####################
# Setup network
####################

function setup-network {
  info "Setting up Instana networking ..."

  echo "Exposing Instana networking ..."
  ${KUBECTL} --kubeconfig ${KUBECONFIG} apply -f ${ROOT_DIR}/conf/networking.yaml
  
}

function setup-apache {
  echo "Installing apache ..."
  install-apt-package "apache2"

  echo "Configuring apache for Instana ..."
  cat ${ROOT_DIR}/conf/instana-ssl.conf.tpl | \
    sed -e "s|@@INSTANA_FQDN|${INSTANA_FQDN}|g; \
      s|@@DEPLOY_LOCAL_WORKDIR|${DEPLOY_LOCAL_WORKDIR}|g;" > /etc/apache2/sites-available/instana-ssl.conf
  a2ensite instana-ssl

  a2enmod proxy
  a2enmod proxy_http
  a2enmod ssl

  service apache2 restart

  info "Setting up Instana networking ... OK"
}

####################
# Pull and load images
####################

function pull-images {
  info "Pulling images ..."
  
  instana datastores images pull --key ${INSTANA_DOWNLOAD_KEY}

  echo
  echo "Pulling additional operator images ..."
 
  REQUIRED_IMAGES+=( `${KUBECTL} instana images` ) 

  docker login containers.instana.io -u _ -p $INSTANA_DOWNLOAD_KEY 2>/dev/null

  for i in ${REQUIRED_IMAGES[@]+"${REQUIRED_IMAGES[@]}"}; do
    echo "Pulling image: ${i}"
    if echo "${i}" | grep ":master\s*$" >/dev/null || echo "${i}" | grep ":latest\s*$" >/dev/null || \
      ! docker inspect --type=image "${i}" >/dev/null 2>&1; then
      docker pull "${i}"
    fi
  done

  info "Pulling images ... OK"
}

REG_NAME='kind-registry'
REG_PORT='5000'

function setup-registry {
  info "Setting up registry ..."

  echo "Creating registry container unless it already exists ..."
  running="$(docker inspect -f '{{.State.Running}}' "${REG_NAME}" 2>/dev/null || true)"
  if [ "${running}" != 'true' ]; then
    docker run \
      -d --restart=always -p "127.0.0.1:${REG_PORT}:5000" --name "${REG_NAME}" \
      registry:2
  fi

  REQUIRED_IMAGES+=( $(instana images version) )

  for image in ${REQUIRED_IMAGES[@]+"${REQUIRED_IMAGES[@]}"}; do
    local registry=${image%%/*}
    local repository=${image#*/}
    local target_image="localhost:5000/${repository}"

    echo "${image} ➞ ${target_image}"
    docker tag $image $target_image
    docker push $target_image
    # docker rmi $target_image
  done

  info "Setting up registry ... OK"
}

####################
# Print summary after install
####################

function print-summary-db {
  cat << EOF

👏 Congratulations! The Single-hosted Instana Database Layer is available!
It installed following tools and applitions:
- Single-hosted Instana Database Layer (Build ${INSTANA_CONSOLE_VERSION})
- The command-line tool instana-console (Build ${INSTANA_CONSOLE_VERSION})

EOF
}

function print-summary-k8 {
  cat << EOF

👏 Congratulations! The Self-hosted Instana on Kubernetes is available!
It launched a kind cluster, installed following tools and applitions:
- kind ${KIND_VERSION}
- kubectl ${KUBECTL_VERSION}
- helm ${HELM3_VERSION}
- The kubectl plugin instana (Build ${INSTANA_KUBECTL_PLUGIN_VERSION})
- Self-hosted Instana on Kubernetes (Build ${INSTANA_VERSION})

To access Instana UI, open https://${INSTANA_FQDN} in browser.
- username: admin@instana.local
- password: passw0rd

For tools you want to run anywhere, create links in a directory defined in your PATH, e.g:
ln -s -f ${KUBECTL} /usr/local/bin/kubectl
ln -s -f ${KIND} /usr/local/bin/kind
ln -s -f ${HELM} /usr/local/bin/helm

EOF
}

function install-agent {
  AGENT=${TOOLS_HOST_DIR}/setup_agent.sh
  info "Installing instana agent ..."
  curl -o ${AGENT} https://setup.instana.io/agent && chmod 700 ${AGENT} && sudo JAVA_HOME=${JAVA} ${AGENT} -a ${INSTANA_DOWNLOAD_KEY} -t dynamic -e ${INSTANA_FQDN}:443 -y -s

  info "Installing instana agent ... OK"
}

function print-elapsed {
  elapsed_time=$(($SECONDS - $start_time))
  echo "Total elapsed time: $elapsed_time seconds"
}

####################
# Clean Instana DB
####################

function clean-instana-db {
  info "Cleaning Instana DB ..."

  local db_layer=(
    instana-cockroachdb
    instana-elastic
    instana-cassandra
    instana-kafka
    instana-clickhouse
    instana-zookeeper
  )

  for db in ${db_layer[@]}; do
    if docker container inspect $db >/dev/null 2>&1; then
      echo "Stopping container $db ..."
      docker stop $db
      echo "Removing container $db ..."
      docker rm $db
    fi
  done

  echo "Deleting db data ..."
  rm -r /mnt/metrics/* 2>/dev/null
  rm -r /mnt/traces/* 2>/dev/null
  rm -r /mnt/data/* 2>/dev/null
  rm -r /mnt/log/* 2>/dev/null

  info "Cleaning Instana DB ... OK"
}

####################
# Print help
####################

function print-help {
  cat << EOF
The Opinionated Sandbox for Self-hosted Instana on Kubernetes

Help you install the single-hosted Instana database layer on one machine and the
self-hosted Instana for Kubernetes in a KIND cluster on another machine.

Usage: $0 [up|down] [db|nfs|reg|k8] [flags]

Examples:
  # Bring up single-hosted Instana database layer on your machine
  $0 up db
  # Bring up NFS service on your machine
  $0 up nfs
  # Bring up a local registry on your machine
  $0 up reg
  # Bring up self-hosted Instana for Kubernetes on a KIND cluster on your machine
  $0 up k8
  # Bring up self-hosted Instana for Kubernetes on a KIND cluster on your machine and use local registry
  $0 up k8 --reg
  # Take down single-hosted Instana database layer on your machine
  $0 down db
  # Take down self-hosted Instana for Kubernetes on your machine
  $0 down k8
EOF
}
