# argocd

Latest Release
- https://github.com/argoproj/argo-cd/releases

#### Install from template
```
oc new-project argocd --display-name="ArgoCD" --description="ArgoCD"
oc apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/v1.4.2/manifests/install.yaml
sudo curl -L  https://github.com/argoproj/argo-cd/releases/download/v1.4.2/argocd-linux-amd64 -o /usr/bin/argocd
sudo chmod +x /usr/bin/argocd
oc port-forward svc/argocd-server -n argocd 4443:443 &
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
oc create -f https://raw.githubusercontent.com/argoproj-labs/argocd-operator/master/deploy/service_account.yaml
oc create -f https://raw.githubusercontent.com/argoproj-labs/argocd-operator/master/deploy/role.yaml
oc create -f https://raw.githubusercontent.com/argoproj-labs/argocd-operator/master/deploy/role_binding.yaml

oc create -f https://raw.githubusercontent.com/argoproj-labs/argocd-operator/master/deploy/argo-cd/argoproj_v1alpha1_application_crd.yaml
oc create -f https://raw.githubusercontent.com/argoproj-labs/argocd-operator/master/deploy/argo-cd/argoproj_v1alpha1_appproject_crd.yaml
oc create -f https://raw.githubusercontent.com/argoproj-labs/argocd-operator/master/deploy/crds/argoproj_v1alpha1_argocd_crd.yaml

oc create -n openshift-marketplace -f https://raw.githubusercontent.com/argoproj-labs/argocd-operator/master/deploy/catalog_source.yaml
oc get pods -n openshift-marketplace -l olm.catalogSource=argocd-catalog

oc new-project argocd --display-name="ArgoCD" --description="ArgoCD"
oc create -n argocd -f https://raw.githubusercontent.com/argoproj-labs/argocd-operator/master/deploy/operator_group.yaml

#oc create -n argocd -f https://raw.githubusercontent.com/argoproj-labs/argocd-operator/master/deploy/subscription.yaml

cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: argocd-operator
  namespace: argocd
spec:
  channel: alpha
  installPlanApproval: Automatic
  name: argocd-operator
  source: argocd-catalog
  sourceNamespace: openshift-marketplace
  startingCSV: argocd-operator.v0.0.3
EOF

oc get installplan --all-namespaces
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
  -p '{"spec": {"template": {"spec": {"containers": [{"name": "dex","image": "quay.io/ablock/dex:openshift-connector"}]}}}}'

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
```

Add default policy as `role:admin`
```
-- https://github.com/argoproj/argo-cd/blob/master/docs/operator-manual/argocd-rbac-cm.yaml

oc edit cm argocd-rbac-cm

data:
  policy.default: role:admin
```

Restart server pod if not operator
```
oc delete pod argocd-server-7f8cbd865f-t6xbg
```

Login sso
```
argocd login $HOST:443 --sso --insecure --username admin
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

metadata:
  annotations:
    argocd.argoproj.io/sync-options: Validate=false
```

### Sealed Secrets

- https://github.com/bitnami-labs/sealed-secrets

`bitnami sealed-secrets`
```
argocd repo add git@github.com:eformat/argocd.git --ssh-private-key-path ~/.ssh/id_rsa
argocd app create sealed-secrets \
  --repo git@github.com:eformat/argocd.git \
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
oc get secret -n kube-system -l sealedsecrets.bitnami.com/sealed-secrets-key=active -o yaml > ~/tmp/sealed-secret-master.key
```
(new cluster) Replace new secret install with existing key
```
oc replace -f ~/tmp/sealed-secret-master.key
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

`cluser-foo`
```
argocd repo add git@github.com:eformat/argocd.git --ssh-private-key-path ~/.ssh/id_rsa
argocd app create cluster-foo \
  --repo git@github.com:eformat/argocd.git \
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

### Infrastructure Applications

`amq-streams operator`
```
argocd repo add git@github.com:eformat/argocd.git --ssh-private-key-path ~/.ssh/id_rsa
argocd app create amq-streams \
  --repo git@github.com:eformat/argocd.git \
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
argocd repo add git@github.com:eformat/argocd.git --ssh-private-key-path ~/.ssh/id_rsa
argocd app create nexus \
  --repo git@github.com:eformat/argocd.git \
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
argocd repo add git@github.com:eformat/argocd.git --ssh-private-key-path ~/.ssh/id_rsa
argocd app create tekton \
  --repo git@github.com:eformat/argocd.git \
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
argocd repo add git@github.com:eformat/argocd.git --ssh-private-key-path ~/.ssh/id_rsa
argocd app create crw \
  --repo git@github.com:eformat/argocd.git \
  --path crw \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace crw \
  --revision master \
  --sync-policy automated

argocd app get crw
argocd app sync crw --prune
#
argocd app delete crw

oc patch checluster.org.eclipse.che codeready-workspaces -n crw --type='json' -p='[{"op": "replace", "path": "/metadata/finalizers", "value":[]}]'
```

`keycloak`
```
argocd repo add git@github.com:eformat/argocd.git --ssh-private-key-path ~/.ssh/id_rsa
argocd app create keycloak \
  --repo git@github.com:eformat/argocd.git \
  --path keycloak \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace keycloak \
  --revision master \
  --sync-policy automated

argocd app get keycloak
argocd app sync keycloak --prune
#
argocd app delete keycloak

# fixme reecnrypt route has private key, so keep separate for now
oc apply -f ./keycloak/route.yml
```

### Applications

`quarkus-coffe-demo`
```
argocd repo add git@github.com:eformat/argocd.git --ssh-private-key-path ~/.ssh/id_rsa
argocd app create quarkus-coffeeshop-demo \
  --repo git@github.com:eformat/argocd.git \
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
argocd repo add git@github.com:eformat/welcome.git --ssh-private-key-path ~/.ssh/id_rsa
argocd app create welcome \
  --repo git@github.com:eformat/welcome.git \
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