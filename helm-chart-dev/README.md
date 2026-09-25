# Red Hat Connectivity Link Operator

Red Hat Connectivity Link enables you to secure, protect, and connect your APIs and applications in multicluster, multicloud, and hybrid cloud environments.

## Installation

```sh
helm install rhcl-operator oci://registry.redhat.io/rhcl-1/rhcl-operator-helm-chart \
  --create-namespace \
  --namespace kuadrant-system \
  --set 'imagePullSecrets[0].name=registry-pull-secret'
```
