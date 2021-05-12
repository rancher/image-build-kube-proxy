ARG UBI_IMAGE=registry.access.redhat.com/ubi7/ubi-minimal:latest
ARG GO_IMAGE=rancher/hardened-build-base:v1.16.4b7
FROM ${UBI_IMAGE} as ubi
FROM ${GO_IMAGE} as builder
# setup required packages
RUN set -x \
 && apk --no-cache add \
    file \
    gcc \
    tar \
    git \
    make
# setup the build
ARG ARCH="amd64"
ARG K3S_ROOT_VERSION="v0.8.1"
ADD https://github.com/k3s-io/k3s-root/releases/download/${K3S_ROOT_VERSION}/k3s-root-${ARCH}.tar /opt/k3s-root/k3s-root.tar
RUN tar xvf /opt/k3s-root/k3s-root.tar -C /opt/k3s-root --wildcards --strip-components=2 './bin/aux/*tables*'
RUN tar xvf /opt/k3s-root/k3s-root.tar -C /opt/k3s-root './bin/ipset'
ARG TAG="v1.21.1"
ARG PKG="github.com/kubernetes/kubernetes"
ARG SRC="github.com/kubernetes/kubernetes"
ARG MAJOR
ARG MINOR
RUN git clone --depth=1 https://${SRC}.git $GOPATH/src/${PKG}
WORKDIR $GOPATH/src/${PKG}
RUN git fetch --all --tags --prune
RUN git checkout tags/${TAG} -b ${TAG}
RUN GO_LDFLAGS="-linkmode=external \
    -X k8s.io/client-go/pkg/version.gitMajor=${MAJOR} \
    -X k8s.io/client-go/pkg/version.gitMinor=${MINOR} \
    -X k8s.io/component-base/version.gitMajor=${MAJOR} \
    -X k8s.io/component-base/version.gitMinor=${MINOR} \
    -X k8s.io/component-base/version.gitVersion=${TAG} \
    -X k8s.io/component-base/version.gitCommit=$(git rev-parse HEAD) \
    -X k8s.io/component-base/version.gitTreeState=clean \
    -X k8s.io/component-base/version.buildDate=$(date -u +%Y-%m-%dT%H:%M:%SZ) \
    " go-build-static.sh -mod=vendor -gcflags=-trimpath=${GOPATH}/src -o bin/kube-proxy ./cmd/kube-proxy
RUN go-assert-static.sh bin/*
RUN go-assert-boring.sh bin/*
# install (with strip) to /usr/local/bin
RUN install -s bin/* /usr/local/bin
RUN kube-proxy --version

FROM ubi
RUN microdnf update -y     && \
    microdnf install -y which \
    conntrack-tools        && \ 
    rm -rf /var/cache/yum
COPY --from=builder /opt/k3s-root/aux/ /usr/sbin/
COPY --from=builder /opt/k3s-root/bin/ /bin/
COPY --from=builder /usr/local/bin/ /usr/local/bin/

