ARG UBI_IMAGE=registry.access.redhat.com/ubi7/ubi-minimal:latest
ARG GO_IMAGE=rancher/hardened-build-base:v1.13.15b4
FROM ${UBI_IMAGE} as ubi
FROM ${GO_IMAGE} as builder
# setup required packages
RUN set -x \
 && apk --no-cache add \
    file \
    gcc \
    git \
    make
# setup the build
ARG ARCH="amd64"
ARG K3S_ROOT_VERSION="v0.6.0-rc3"
ADD https://github.com/rancher/k3s-root/releases/download/${K3S_ROOT_VERSION}/k3s-root-xtables-${ARCH}.tar /opt/xtables/k3s-root-xtables.tar
RUN tar xvf /opt/xtables/k3s-root-xtables.tar -C /opt/xtables
ARG TAG="v1.18.8"
ARG PKG="github.com/kubernetes/kubernetes"
ARG SRC="github.com/kubernetes/kubernetes"
RUN git clone --depth=1 https://${SRC}.git $GOPATH/src/${PKG}
WORKDIR $GOPATH/src/${PKG}
RUN git fetch --all --tags --prune
RUN git checkout tags/${TAG} -b ${TAG}
RUN echo 'GO_BUILD_FLAGS=" \
         -gcflags=-trimpath=/go/src \
         "' \
    >> ./go-build-static
RUN echo 'GO_LDFLAGS=" \
         -X k8s.io/component-base/version.gitVersion=${TAG} \
         -X k8s.io/component-base/version.gitCommit=$(git rev-parse HEAD) \
         -X k8s.io/component-base/version.gitTreeState=clean \
         -X k8s.io/component-base/version.buildDate=$(date -u +%Y-%m-%dT%H:%M:%SZ) \
         -linkmode=external -extldflags \"-static -Wl,--fatal-warnings\""' \
    >> ./go-build-static
RUN echo 'go build ${GO_BUILD_FLAGS} -ldflags "${GO_LDFLAGS}" "${@}"' \
    >> ./go-build-static
## build statically linked executables
RUN sh -ex ./go-build-static -o bin/kube-proxy ./cmd/kube-proxy
# assert statically linked executables
RUN echo '[ -e $1 ] && (file $1 | grep -E "executable, x86-64, .*, statically linked")' \
    >> ./assert-static
RUN sh -ex ./assert-static bin/kube-proxy
RUN ./bin/kube-proxy --version
# assert goboring symbols
RUN echo '[ -e $1 ] && (go tool nm $1 | grep Cfunc__goboring > .boring; if [ $(wc -l <.boring) -eq 0 ]; then exit 1; fi)' \
    >> ./assert-boring
RUN sh -ex ./assert-boring bin/kube-proxy
# install (with strip) to /usr/local/bin
RUN install -s bin/* /usr/local/bin

FROM ubi
RUN microdnf update -y     && \
    microdnf install -y which \
    conntrack-tools        && \ 
    rm -rf /var/cache/yum
COPY --from=builder /opt/xtables/bin/* /usr/sbin/
COPY --from=builder /usr/local/bin/ /usr/local/bin/

