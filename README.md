# argocd

Latest Release
- https://github.com/argoproj/argo-cd/releases

### Install from ansible
```
ansible-playbook -i inventory install.yml -e argocd_install=true --vault-password-file=~/.vault_pass.txt
```

#### Install from template
```
oc new-project argocd --display-name="ArgoCD" --description="ArgoCD"
oc apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/v1.8.1/manifests/install.yaml
sudo curl -L  https://github.com/argoproj/argo-cd/releases/download/v1.8.1/argocd-linux-amd64 -o /usr/local/bin/argocd
sudo chmod +x /usr/local/bin/argocd
oc port-forward svc/argocd-server -n argocd 4443:443 &
```

There is also a nemspaced install version (see below for more details):
```
oc apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/v1.8.1/manifests/namespace-install.yaml
```

Login locally (or setup SSO below)
```
PSWD=$(oc get pods -n argocd -l app.kubernetes.io/name=argocd-server -o name | cut -d'/' -f 2)
argocd login localhost:4443 --insecure --username admin --password $PSWD
argocd account update-password --insecure
argocd relogin
```

#### Install from operator

`Note`: Operator is not latest version and has issues with git, sso (use template for now for fully working solution)

- https://argocd-operator.readthedocs.io/en/latest/guides/install-openshift/

```
#oc create -f https://raw.githubusercontent.com/argoproj-labs/argocd-operator/master/deploy/service_account.yaml
#oc create -f https://raw.githubusercontent.com/argoproj-labs/argocd-operator/master/deploy/role.yaml
#oc create -f https://raw.githubusercontent.com/argoproj-labs/argocd-operator/master/deploy/role_binding.yaml

#oc create -f https://raw.githubusercontent.com/argoproj-labs/argocd-operator/master/deploy/argo-cd/argoproj.io_applications_crd.yaml
#oc create -f https://raw.githubusercontent.com/argoproj-labs/argocd-operator/master/deploy/argo-cd/argoproj.io_appprojects_crd.yaml
#oc create -f https://raw.githubusercontent.com/argoproj-labs/argocd-operator/master/deploy/crds/argoproj.io_argocds_crd.yaml
#oc create -f https://raw.githubusercontent.com/argoproj-labs/argocd-operator/master/deploy/crds/argoproj.io_argocdexports_crd.yaml

#oc create -n openshift-marketplace -f https://raw.githubusercontent.com/argoproj-labs/argocd-operator/master/deploy/catalog_source.yaml
#oc get pods -n openshift-marketplace -l olm.catalogSource=argocd-catalog

oc new-project argocd --display-name="ArgoCD" --description="ArgoCD"
oc adm policy add-cluster-role-to-user cluster-admin -z argocd-application-controller -n argocd

oc create -f https://raw.githubusercontent.com/argoproj-labs/argocd-operator/master/deploy/operator_group.yaml

cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: argocd-operator
spec:
  channel: alpha
  installPlanApproval: Automatic
  name: argocd-operator
  source: community-operators
  sourceNamespace: openshift-marketplace
  startingCSV: argocd-operator.v0.0.5
EOF

oc get installplan --all-namespaces

cat <<EOF | oc apply -f-
apiVersion: argoproj.io/v1alpha1
kind: ArgoCD
metadata:
  name: argocd
  labels:
    app: argocd
spec:
  dex:
    config: ""
    image: quay.io/redhat-cop/dex:v2.22.0-openshift
    openShiftOAuth: true
    version: "openshift-connector"
  ha:
    enabled: false
  grafana:
    enabled: false
    route: true
    size: 1
  prometheus:
    enabled: false
    route: true
    size: 1
  rbac:
    defaultPolicy: role:admin
  repositories: |
    - url: https://github.com/rht-labs/ubiquitous-journey.git
    - type: helm
      url: https://rht-labs.github.io/helm-charts
      name: rht-labs
  insecure: false
  server:
    route: true
  service:
    type: ClusterIP
  statusBadgeEnabled: true
  usersAnonymousEnabled: false
  version: v1.5.4
EOF
```

### Deleting argocd project

If the project hangs when deleting - check CRD's

```
oc get applications.argoproj.io --all-namespaces
oc patch applications.argoproj.io jenkins -n argocd --type='json' -p='[{"op": "replace", "path": "/metadata/finalizers", "value":[]}]'
oc patch applications.argoproj.io welcome -n argocd --type='json' -p='[{"op": "replace", "path": "/metadata/finalizers", "value":[]}]'
```

#### SSO

- https://blog.openshift.com/openshift-authentication-integration-with-argocd/

Create Route
```
oc create route passthrough argocd --service=argocd-server --port=https --insecure-policy=Redirect
```

Hacks
```
oc patch deployment argocd-dex-server \
  -p '{"spec": {"template": {"spec": {"containers": [{"name": "dex","image": "quay.io/redhat-cop/dex:v2.22.0-openshift"}]}}}}'

-- if using operator
-- https://github.com/jmckind/argocd-operator/pull/40/files
oc edit deployment argocd-server

    spec:
      containers:
      - command:
        - argocd-server
        - --dex-server
        - 'http://argocd-dex-server:5556'

--
API=$(oc whoami --show-server)
TOKEN=$(oc serviceaccounts get-token argocd-dex-server -n argocd)
HOST=$(oc get route argocd -n argocd --template='{{ .spec.host }}')
oc annotate sa/argocd-dex-server serviceaccounts.openshift.io/oauth-redirecturi.argocd=https://$HOST/api/dex/callback --overwrite

oc edit cm argocd-cm -n argocd

cat <<EOF > ~/tmp/argocd-cm.yaml
data:
  url: https://$HOST
  dex.config: |
    connectors:
      # OpenShift
      - type: openshift
        id: openshift
        name: OpenShift
        config:
          issuer: $API
          clientID: system:serviceaccount:argocd:argocd-dex-server
          clientSecret: $TOKEN
          redirectURI: https://$HOST/api/dex/callback
          insecureCA: true
EOF
```

Add default policy as `role:admin`
```
-- https://github.com/argoproj/argo-cd/blob/master/docs/operator-manual/argocd-rbac-cm.yaml

oc edit cm argocd-rbac-cm

data:
  policy.default: role:admin
  accounts.admin: apiKey
```

Restart server pod if not operator
```
oc delete pod -l app.kubernetes.io/name=argocd-server
```

Login sso
```
argocd login $HOST:443 --sso --insecure --username admin
argocd login --grpc-web $HOST
```

TIP: argocd route - `CERT INVALID ERROR` - in google chrome type 'thisisunsafe' to skip

#### Configure ArgoCD Sync

Ignore openshift differences that dont sync.

```
-- ignore first image in sync for deployment config
oc edit cm argocd-cm -n argocd

data:
  resource.customizations: |
    apps.openshift.io/DeploymentConfig:
      ignoreDifferences: |
        jsonPointers:
        - /spec/template/spec/containers/0/image
        - /spec/triggers/0/imageChangeParams/lastTriggeredImage
        - /spec/triggers/1/imageChangeParams/lastTriggeredImage
        - /spec/triggers/2/imageChangeParams/lastTriggeredImage
    build.openshift.io/BuildConfig:
      ignoreDifferences: |
        jsonPointers:
        - /spec/triggers
        - /status
    org.eclipse.che/CheCluster:
      ignoreDifferences: |
        jsonPointers:
        - /spec

oc delete pod -l app.kubernetes.io/name=argocd-server -n argocd
```

### Extraneous ignores

```
-- argocd ignore extraneous
https://argoproj.github.io/argo-cd/user-guide/compare-options/#ignoring-resources-that-are-extraneous

metadata:
  annotations:
    argocd.argoproj.io/compare-options: IgnoreExtraneous

-- https://argoproj.github.io/argo-cd/user-guide/sync-options/

metadata:
  annotations:
    argocd.argoproj.io/sync-options: Prune=false
hub
metadata:
  annotations:
    argocd.argoproj.io/sync-options: Validate=false
```

### Sync Projects / Namespaces First

```
metadata:
  name: my-project
  annotations:
    argocd.argoproj.io/sync-wave: "-1"
```

### Sealed Secrets

- https://github.com/bitnami-labs/sealed-secrets

`bitnami sealed-secrets`
```
argocd repo add https://github.com/eformat/argocd.git
argocd app create sealed-secrets \
  --repo https://github.com/eformat/argocd.git \
  --path sealed-secrets \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace kube-system \
  --revision master \
  --sync-policy automated

argocd app get sealed-secrets
argocd app sync sealed-secrets --prune
#
argocd app delete sealed-secrets
```

Backup cluster secret - Not safe for git !
```
oc get secret -n kube-system -l sealedsecrets.bitnami.com/sealed-secrets-key=active -o yaml > sealed-secret-master.key
```
(new cluster) Replace new secret install with existing key
```
# decrypt master for sealed secrets
ansible-vault decrypt sealed-secret-master.key --vault-password-file=~/.vault_pass.txt
# edit secret name
pod=$(oc -n kube-system get secret -l sealedsecrets.bitnami.com/sealed-secrets-key=active -o name)
sed -i -e "s|name:.*|name: ${pod##secret/}|" sealed-secret-master.key
oc replace -f sealed-secret-master.key
# restart sealedsecret controller pod
oc delete pod -n kube-system -l name=sealed-secrets-controller
```

`kubeseal` Client for generating secrets
```
release=$(curl --silent "https://api.github.com/repos/bitnami-labs/sealed-secrets/releases/latest" | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p')
GOOS=$(go env GOOS)
GOARCH=$(go env GOARCH)
wget https://github.com/bitnami-labs/sealed-secrets/releases/download/$release/kubeseal-$GOOS-$GOARCH
sudo install -m 755 kubeseal-$GOOS-$GOARCH /usr/local/bin/kubeseal
```

Test
```
oc new-project foobar
oc create secret generic mysecret --dry-run --from-literal=foo=bar -o yaml > ~/tmp/mysecret.yml
kubeseal < ~/tmp/mysecret.yml > ~/tmp/mysealedsecret.yml
oc apply -f ~/tmp/mysealedsecret.yml # This file is safe for git!
# Profit
oc get secret mysecret -o yaml
oc get sealedsecret.bitnami.com/mysecret -o yaml
```

### Cluster Configuration

Pre-requisites: install `sealed-secrets`

`cluster-foo`
```
argocd repo add https://github.com/eformat/argocd.git
argocd app create cluster-foo \
  --repo https://github.com/eformat/argocd.git \
  --path clusters/cluster-foo \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace openshift-config \
  --revision master \
  --sync-policy automated

argocd app get cluster-foo
argocd app sync cluster-foo --prune
#
argocd app delete cluster-foo
```

`cluster-bar`
```
argocd repo add https://github.com/eformat/argocd.git
argocd app create cluster-bar \
  --repo https://github.com/eformat/argocd.git \
  --path clusters/cluster-bar \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace openshift-config \
  --revision master \
  --sync-policy automated

argocd app get cluster-bar
argocd app sync cluster-bar --prune
#
argocd app delete cluster-bar
```

`cluster-hivec`
```
argocd repo add https://github.com/eformat/argocd.git
argocd app create cluster-hivec \
  --repo https://github.com/eformat/argocd.git \
  --path clusters/cluster-hivec \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace openshift-config \
  --revision master \
  --sync-policy automated

argocd app get cluster-hivec
argocd app sync cluster-hivec --prune
#
argocd app delete cluster-hivec
```

```
# FIXME move to bitnami sealed secret
# from keycloak ocp-console client
oc create secret generic idp-secret --from-literal=clientSecret=<ocp-console keycloak client secret> -n openshift-config
```

### Infrastructure Applications

`amq-streams operator`
```
argocd repo add https://github.com/eformat/argocd.git
argocd app create amq-streams \
  --repo https://github.com/eformat/argocd.git \
  --path amq-streams \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace amq-streams \
  --revision master \
  --sync-policy automated

argocd app get amq-streams
argocd app sync amq-streams --prune
#
argocd app delete amq-streams
```

`nexus operator`
```
argocd repo add https://github.com/eformat/argocd.git
argocd app create nexus \
  --repo https://github.com/eformat/argocd.git \
  --path nexus \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace nexus \
  --revision master \
  --sync-policy automated

argocd app get nexus
argocd app sync nexus --prune
#
argocd app delete nexus
```

`tekton`
```
argocd repo add https://github.com/eformat/argocd.git
argocd app create tekton \
  --repo https://github.com/eformat/argocd.git \
  --path tekton \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace openshift-operators \
  --revision master \
  --sync-policy automated

argocd app get tekton
argocd app sync tekton --prune
#
argocd app delete tekton
```

`crw`
```
argocd repo add https://github.com/eformat/argocd.git
argocd app create crw \
  --repo https://github.com/eformat/argocd.git \
  --path crw/base \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace crw \
  --revision master \
  --sync-policy automated

argocd app get crw
argocd app sync crw --prune
#
argocd app delete crw

# delete may hang
oc patch checluster.org.eclipse.che codeready-workspaces -n crw --type='json' -p='[{"op": "replace", "path": "/metadata/finalizers", "value":[]}]'
```

`keycloak`
```
argocd repo add https://github.com/eformat/argocd.git
argocd app create keycloak \
  --repo https://github.com/eformat/argocd.git \
  --path keycloak \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace keycloak \
  --revision master \
  --sync-policy automated

argocd app get keycloak
argocd app sync keycloak --prune
#
argocd app delete keycloak

# FIXME reecnrypt route has private key, so keep separate for now
~/git/keycloak-utils/keycloak-route.sh
```

`jenkins`
```
argocd repo add https://github.com/eformat/charts.git
argocd app create jenkins \
  --repo https://github.com/eformat/charts.git \
  --path jenkins \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace jenkins \
  --revision master \
  --sync-policy automated

argocd app get jenkins
argocd app sync jenkins --prune
#
argocd app delete jenkins
```

`my-jenkins`
```
argocd repo add https://github.com/eformat/my-jenkins-chart.git
argocd app create jenkins \
  --repo https://github.com/eformat/my-jenkins-chart.git \
  --path . \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace jenkins \
  --revision master \
  --sync-policy automated

argocd app get jenkins
argocd app sync jenkins --prune
#
argocd app delete jenkins
```

`pact-broker`
```
argocd repo add https://github.com/eformat/charts.git
argocd app create pact-broker \
  --repo https://github.com/eformat/charts.git \
  --path pact-broker \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace pact-broker \
  --revision master \
  --sync-policy automated

argocd app get pact-broker
argocd app sync pact-broker --prune
#
argocd app delete pact-broker
```

### Applications

`quarkus-coffe-demo`
```
argocd repo add https://github.com/eformat/argocd.git
argocd app create quarkus-coffeeshop-demo \
  --repo https://github.com/eformat/argocd.git \
  --path quarkus-coffeeshop-demo \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace quarkus-coffee \
  --revision master

#  --sync-policy automated

argocd app get quarkus-coffeeshop-demo
argocd app sync quarkus-coffeeshop-demo --prune
#
argocd app delete quarkus-coffeeshop-demo
```

Build image using tekton (not part of argo)
```
oc -n quarkus-coffee create serviceaccount pipeline
oc -n quarkus-coffee adm policy add-scc-to-user privileged -z pipeline
oc -n quarkus-coffee adm policy add-role-to-user edit -z pipeline

cat <<EOF | oc create -n quarkus-coffee -f -
apiVersion: tekton.dev/v1alpha1
kind: PipelineRun
metadata:
  generateName: quarkus-coffeeshop-demo-deploy-pipelinerun-
  annotations:
    argocd.argoproj.io/sync-options: Prune=false
    argocd.argoproj.io/compare-options: IgnoreExtraneous
spec:
  timeout: '30m'
  pipelineRef:
    name: deploy-pipeline
  serviceAccountName: 'pipeline'
  resources:
  - name: app-git
    resourceRef:
      name: quarkus-coffeeshop-git
  - name: app-image
    resourceRef:
      name: quarkus-coffeeshop-image
EOF
```

`welcome`
```
argocd repo add https://github.com/eformat/welcome.git
argocd app create welcome \
  --repo https://github.com/eformat/welcome.git \
  --path argocd/overlays/cluster1 \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace welcome \
  --revision master \
  --sync-policy automated

argocd app get welcome
argocd app sync welcome --prune
#
argocd app delete welcome
```

### ArgoCD Multicluster

"one app per cluster, multiple destinations not possible"

- https://github.com/argoproj/argo-cd/issues/1673

Use cases:
- A single app that has owns resources in different clusters.
- A single app that is deployed identically (or with small variations) in different clusters.

Posts:
- https://www.katacoda.com/openshift/courses/introduction/gitops-multicluster
- https://itnext.io/multicluster-scheduler-argo-workflows-across-kubernetes-clusters-ea98016499ca

```bash
-- add clusters from kubeconfig
argocd cluster add default/api-foo-eformat-me:6443/kube:admin
argocd cluster add default/api-hivec-sandbox1604-opentlc-com:6443/admin

-- list
argocd cluster list

-- add application repo
argocd repo add http://github.com/eformat/welcome.git
argocd repo list

-- can add from cli, but cannot configure things like diff ignores
#argocd app create --project default --name welcome \
# --repo http://github.com/eformat/welcome.git \
# --path argocd/base \
# --dest-server $(argocd cluster list | grep api-foo-eformat-me | awk '{print $1}') \
# --dest-namespace welcome \
# --revision master \
# --sync-policy automated

-- easier to deploy the CR directly
-- deploy to on premise cluster
cat <<EOF | oc apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  finalizers:
  - resources-finalizer.argocd.argoproj.io
  name: welcome-on-premise
  namespace: labs-ci-cd
spec:
  destination:
    namespace: welcome
    server: https://api.foo.eformat.me:6443
  project: default
  source:
    path: argocd/base
    repoURL: http://github.com/eformat/welcome.git
    targetRevision: master
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
      validate: true
  ignoreDifferences:
  - group: apps.openshift.io
    jsonPointers:
    - /spec/template/spec/containers/0/image
    - /spec/triggers/0/imageChangeParams/lastTriggeredImage
    kind: DeploymentConfig
EOF

-- deploy to clould cluster
cat <<EOF | oc apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  finalizers:
  - resources-finalizer.argocd.argoproj.io
  name: welcome-public-cloud
  namespace: labs-ci-cd
spec:
  destination:
    namespace: welcome
    server: https://api.hivec.sandbox1604.opentlc.com:6443
  project: default
  source:
    path: argocd/overlays/cluster1
    repoURL: http://github.com/eformat/welcome.git
    targetRevision: master
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
      validate: true
  ignoreDifferences:
  - group: apps.openshift.io
    jsonPointers:
    - /spec/template/spec/containers/0/image
    - /spec/triggers/0/imageChangeParams/lastTriggeredImage
    kind: DeploymentConfig
EOF

-- test the app
curl -s http://$(oc --context=default/api-hivec-sandbox1604-opentlc-com:6443/admin get route -n welcome)
curl -s http://$(oc --context=default/api-foo-eformat-me:6443/kube:admin get route -n welcome)
```


### Namespaced Mode

The namespaced mode feature was designed to enable managing resources with namespace permissions only. If namespaces are specified in cluster configuration then Argo CD assumes it cannot manage cluster level resources.

You can create a secret for managing cluster connections in argocd, e.g. by using the `argocd-application-controller` token (or create your own service account). The label `argocd.argoproj.io/secret-type: cluster` tells argocd to configure the cluster connection

```
oc -n labs-ci-cd apply -f - << EOF
apiVersion: v1
stringData:
  config: '{"bearerToken":"$(oc serviceaccounts get-token argocd-application-controller)","tlsClientConfig":{"insecure":true}}'
  name: argocd-managed
  namespaces: labs-ci-cd,labs-dev,labs-test,labs-staging,openshift-operators
  server: https://kubernetes.default.svc
kind: Secret
metadata:
  annotations:
    managed-by: argocd.argoproj.io
  labels:
    argocd.argoproj.io/secret-type: cluster
  name: cluster-kubernetes.default.svc-argocd-managed
type: Opaque
EOF
```

Check
```
$ argocd cluster list
SERVER                                         NAME            VERSION  STATUS      MESSAGE
https://kubernetes.default.svc (4 namespaces)  argocd-managed  1.19     Successful  

$ argocd cluster get https://kubernetes.default.svc
config:
  tlsClientConfig:
    insecure: true
connectionState:
  attemptedAt: "2020-12-22T22:02:31Z"
  message: ""
  status: Successful
info:
  applicationsCount: 10
  cacheInfo:
    apisCount: 190
    lastCacheSyncTime: "2020-12-22T22:02:31Z"
    resourcesCount: 566
  connectionState:
    attemptedAt: "2020-12-22T22:02:31Z"
    message: ""
    status: Successful
  serverVersion: "1.19"
name: argocd-managed
namespaces:
- labs-ci-cd
- labs-dev
- labs-test
- labs-staging
server: https://kubernetes.default.svc
serverVersion: "1.19"
```