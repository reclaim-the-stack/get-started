Original source:
https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.23/deploy/local-path-storage.yaml

## Changes

Added to Namespace:
```
metadata:
  labels:
    pod-security.kubernetes.io/audit: privileged
    pod-security.kubernetes.io/enforce: privileged
    pod-security.kubernetes.io/warn: privileged
```

Added to StorageClass:
```
metadata:
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
```