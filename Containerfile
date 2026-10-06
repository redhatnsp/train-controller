FROM registry.access.redhat.com/ubi9/ubi:9.3

RUN dnf update -y \
 && dnf install -y --setopt=install_weak_deps=false nodejs npm \
 && dnf install -y git make gcc g++ \
 && dnf clean -y all \
 && mkdir /opt/app

WORKDIR /opt/app
COPY *.js package*.json ./
COPY src/ ./src/

RUN npm install \
 && chmod -R go+rwX .

ENTRYPOINT [ "/usr/bin/node" ]
CMD [ "index.js" ]
