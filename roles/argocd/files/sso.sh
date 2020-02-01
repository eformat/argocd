#!/bin/bash

NAMESPACE="${1}"

oc -n ${NAMESPACE} patch deployment argocd-dex-server \
  -p '{"spec": {"template": {"spec": {"containers": [{"name": "dex","image": "quay.io/ablock/dex:openshift-connector"}]}}}}'

API=$(oc whoami --show-server)
TOKEN=$(oc serviceaccounts get-token argocd-dex-server -n ${NAMESPACE})
HOST=$(oc get route argocd -n ${NAMESPACE} --template='{{ .spec.host }}')
oc -n ${NAMESPACE} annotate sa/argocd-dex-server serviceaccounts.openshift.io/oauth-redirecturi.argocd=https://$HOST/api/dex/callback --overwrite

oc delete cm argocd-cm -n ${NAMESPACE}

oc create -n ${NAMESPACE} -f - <<EOF
apiVersion: v1
data:
  dex.config: |
    connectors:
      # OpenShift
      - type: openshift
        id: openshift
        name: OpenShift
        config:
          issuer: ${API}
          clientID: system:serviceaccount:${NAMESPACE}:argocd-dex-server
          clientSecret: ${TOKEN}
          redirectURI: https://${HOST}/api/dex/callback
          insecureCA: true
  resource.customizations: |
    apps.openshift.io/DeploymentConfig:
      ignoreDifferences: |
        jsonPointers:
        - /spec/template/spec/containers/0/image
        - /spec/triggers/1/imageChangeParams/lastTriggeredImage
    build.openshift.io/BuildConfig:
      ignoreDifferences: |
        jsonPointers:
        - /spec/triggers
        - /status
    org.eclipse.che/CheCluster:
      ignoreDifferences: |
        jsonPointers:
        - /spec
  url: https://${HOST}
kind: ConfigMap
metadata:
  labels:
    app.kubernetes.io/name: argocd-cm
    app.kubernetes.io/part-of: argocd
  name: argocd-cm
  namespace: ${NAMESPACE}
EOF

oc delete cm argocd-rbac-cm -n ${NAMESPACE}

oc create -n ${NAMESPACE} -f - <<EOF
apiVersion: v1
data:
  policy.default: role:admin
kind: ConfigMap
metadata:
  labels:
    app.kubernetes.io/name: argocd-rbac-cm
    app.kubernetes.io/part-of: argocd
  name: argocd-rbac-cm
  namespace: ${NAMESPACE}
EOF

oc -n ${NAMESPACE} delete pod -l app.kubernetes.io/name=argocd-server --wait=true
