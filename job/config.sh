# The version of kind
KIND_VERSION=${KIND_VERSION:-v0.11.1}
# The version of kubectl
KUBECTL_VERSION=${KUBECTL_VERSION:-v1.17.11}
# The version of helm
HELM3_VERSION=${HELM3_VERSION:-v3.5.3}
# The version of java
JAVA_VERSION=${JAVA_VERSION:-11}

###################
# Instana settings
###################

# Your Instana download key
INSTANA_DOWNLOAD_KEY="${INSTANA_DOWNLOAD_KEY:-}"
# Your Instana sales key
INSTANA_SALES_KEY="${INSTANA_SALES_KEY:-}"
# The version of Instana
INSTANA_VERSION=${INSTANA_VERSION:-207-8}
INSTANA_CONSOLE_VERSION=${INSTANA_VERSION:-207-8}
INSTANA_KUBECTL_PLUGIN_VERSION=${INSTANA_VERSION:-207-8}
# Your Instana hostname
INSTANA_FQDN=${INSTANA_FQDN:-$(hostname)}
# Your Instana db hostname
INSTANA_DB_HOST=${INSTANA_DB_HOST:-$(hostname)}
# Your NFS hostname
NFS_HOST=${NFS_HOST:-$INSTANA_DB_HOST}

