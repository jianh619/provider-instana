From ubuntu:20.04

ARG KUBECTL_VERSION=v1.17.11
ENV KUBECTL_VERSION $KUBECTL_VERSION

ARG HELM_VERSION=v3.5.3
ENV HELM_VERSION $HELM_VERSION

RUN mkdir -p /root/instana; \
    mkdir -p /root/.kube; \
    mkdir -p /root/instana/tmp-helm3; \
    apt-get update; \
    apt-get install wget curl -y; \
    apt-get install -y gnupg2; \
    curl -fsSLo /usr/local/bin/kubectl https://storage.googleapis.com/kubernetes-release/release/$KUBECTL_VERSION/bin/linux/amd64/kubectl && \
    chmod +x /usr/local/bin/kubectl; \
    curl -fsSL https://get.helm.sh/helm-$HELM_VERSION-linux-amd64.tar.gz | tar -xz -C /root/instana/tmp-helm3 && \
    mv /root/instana/tmp-helm3/linux-amd64/helm /usr/local/bin/helm && \
    chmod +x /usr/local/bin/helm && \
    rm -rf /root/instana/tmp-helm3

COPY job/conf /root/instana/
<<<<<<< HEAD
COPY job/install.sh job/config.sh job/common.sh /root/instana/
=======
COPY job/install.sh /root/instana
>>>>>>> 59753c8897937fe81010339bf88498ed022d0cc4

WORKDIR /root/instana

CMD ["/root/instana/install.sh"]
<<<<<<< HEAD

=======
>>>>>>> 59753c8897937fe81010339bf88498ed022d0cc4
