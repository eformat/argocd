# argocd

```
oc new-project argocd --display-name="ArgoCD" --description="ArgoCD"
oc apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/v1.3.6/manifests/install.yaml
sudo curl -L  https://github.com/argoproj/argo-cd/releases/download/v1.3.6/argocd-linux-amd64 -o /usr/bin/argocd
sudo chmod +x /usr/bin/argocd
oc port-forward svc/argocd-server -n argocd 4443:443 &
```

```
PSWD=$(oc get pods -n argocd -l app.kubernetes.io/name=argocd-server -o name | cut -d'/' -f 2)
argocd login localhost:4443 --insecure --username admin --password $PSWD
argocd account update-password --insecure
argocd relogin
```

```
-- ignore first image in sync for deployment config
oc edit cm argocd-cm -n argocd

data:
  resource.customizations: |
    apps.openshift.io/DeploymentConfig:
      ignoreDifferences: |
        jsonPointers:
        - /spec/template/spec/containers/0/image
```

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