# argocd

Install
```
oc new-project argocd --display-name="ArgoCD" --description="ArgoCD"
oc apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/v1.3.6/manifests/install.yaml
sudo curl -L  https://github.com/argoproj/argo-cd/releases/download/v1.3.6/argocd-linux-amd64 -o /usr/bin/argocd
sudo chmod +x /usr/bin/argocd
oc port-forward svc/argocd-server -n argocd 4443:443 &
```

Login
```
PSWD=$(oc get pods -n argocd -l app.kubernetes.io/name=argocd-server -o name | cut -d'/' -f 2)
argocd login localhost:4443 --insecure --username admin --password $PSWD
argocd account update-password --insecure
argocd relogin
```

Configure
```
-- ignore first image in sync for deployment config
oc edit cm argocd-cm -n argocd

data:
  resource.customizations: |
    apps.openshift.io/DeploymentConfig:
      ignoreDifferences: |
        jsonPointers:
        - /spec/template/spec/containers/0/image
        - /spec/template/spec/triggers/1/imageChangeParams/lastTriggeredImage
    build.openshift.io/BuildConfig:
      ignoreDifferences: |
        jsonPointers:
        - /spec/triggers
        - /status
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

### Infrastructure Applications

`amq-streams operator`
```
argocd repo add git@github.com:eformat/argocd.git --ssh-private-key-path ~/.ssh/id_rsa
argocd app create amq-streams \
  --repo git@github.com:eformat/argocd.git \
  --path amq-streams \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace amq-streams

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
  --dest-namespace nexus

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
  --dest-namespace openshift-operators

argocd app get tekton
argocd app sync tekton --prune
#
argocd app delete tekton
```

### Applications

`quarkus-coffe-demo`
```
argocd repo add git@github.com:eformat/argocd.git --ssh-private-key-path ~/.ssh/id_rsa
argocd app create quarkus-coffeeshop-demo \
  --repo git@github.com:eformat/argocd.git \
  --path quarkus-coffeeshop-demo \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace quarkus-coffee

argocd app get quarkus-coffeeshop-demo
argocd app sync quarkus-coffeeshop-demo --prune
#
argocd app delete quarkus-coffeeshop-demo
```
```
oc -n quarkus-coffee create serviceaccount pipeline
oc -n quarkus-coffee adm policy add-scc-to-user privileged -z pipeline
oc -n quarkus-coffee adm policy add-role-to-user edit -z pipeline
```
