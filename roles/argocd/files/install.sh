#!/bin/bash

#set -x

NAMESPACE="${1}"
ARGO_IMAGE_VERSION="${2}"
DEX_IMAGE_VERSION="${3}"
REDIS_IMAGE_VERSION="${4}"

TMPDIR=$(mktemp -d)
cd ${TMPDIR}
curl -sLO https://raw.githubusercontent.com/argoproj/argo-cd/v${ARGO_IMAGE_VERSION}/manifests/install.yaml

sed -i -e "s|namespace: argocd|namespace: ${NAMESPACE}|g" ${TMPDIR}/install.yaml
sed -i -e "s|image: argoproj/argocd:.*$|image: argoproj/argocd:v${ARGO_IMAGE_VERSION}|g" ${TMPDIR}/install.yaml
sed -i -e "s|image: quay.io/dexidp/dex:.*$|image: quay.io/dexidp/dex:v${DEX_IMAGE_VERSION}|g" ${TMPDIR}/install.yaml
sed -i -e "s|image: redis:.*$|image: redis:${REDIS_IMAGE_VERSION}|g" ${TMPDIR}/install.yaml

oc apply -n ${NAMESPACE} -f ${TMPDIR}/install.yaml

rm -rf ${TMPDIR}