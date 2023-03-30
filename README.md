# Reclaim the Stack: Get Started

## Local Cluster

### Bootstrap

**Prerequisites**

- Docker
- kubectl
- yq
- talosctl (`curl -sL https://talos.dev/install | sh`)

Now bootstrap a local Docker based Talos cluster with:

```
talosctl cluster create \
  --name reclaim-the-stack \
  --image ghcr.io/siderolabs/talos:v1.3.6 \
  --kubernetes-version 1.26.2 \
  --workers 1 \
  --cpus "3.0" \
  --cpus-workers "3.0" \
  --memory 4096 \
  --memory-workers 4096 \
  --config-patch-worker @platform/talos-worker-patch.yaml
```

When your cluster is up and running you can configure `kubectl` and `talosctl` to use it by:

```
kubectl config set-context admin@reclaim-the-stack
talosctl config context reclaim-the-stack
talosctl config node $(kubectl get node reclaim-the-stack-controlplane-1 -o yaml | yq .status.addresses.0.address)
```

You should now be able to list the nodes of your cluster via:

```
kubectl get nodes -o wide
talosctl get members
```

### Tear-down

```
talosctl cluster destroy --name reclaim-the-stack
kubectl config unset contexts.admin@reclaim-the-stack
kubectl config unset users.admin@reclaim-the-stack
kubectl config unset clusters.reclaim-the-stack
```

There is no command to unset the context added by `talosctl` so this one you have to delete manually from your `~/.talos/config` file.

## Installation

The following assumes you have cloned this repository and changed current working directory into the git repository.

First we install ArgoCD
```
kubectl create -k platform/argocd
```

Give it a few seconds to resolve and now you should be able to log in to the ArgoCD UI. Get the admin password and start a port-forward to be able to access it:

```
# Copy the admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o yaml | yq '.data.password | @base64d'

# Port forward the argocd web server
kubectl port-forward services/argocd-server -n argocd 8080:443
```

Now navigate to https://localhost:8080 in your web browser, proceed through the self signed certificate warning and login with username `admin` and the password you exposed using the above command.

You can now apply our `argocd-root` manifest to get the platform installed via ArgoCD:

```
kubectl create -f argocd-root.yaml
```

### Cloudflared Ingress Configuration

The following assumes that you have admin access to a domain managed by [Cloudflare](https://cloudflare.com).

Create the Cloudflare tunnel:

```
cloudflared tunnel login
cloudflared tunnel --credentials-file tunnel-credentials.json create reclaim-the-stack
kubectl create secret generic tunnel-credentials --dry-run=client \
  --from-file=credentials.json=tunnel-credentials.json \
  -o yaml | kubeseal -o yaml > platform/cloudflared/templates/tunnel-credentials.yaml

echo "Check out your tunnel at https://one.dash.cloudflare.com/$(yq .AccountTag tunnel-credentials.json)/access/tunnels" &&
echo "Add DNS entries at https://dash.cloudflare.com/$(yq .AccountTag tunnel-credentials.json)" &&
echo "Configure DNS entries with CNAME target $(yq .TunnelID tunnel-credentials.json).cfargotunnel.com"
```

For DNS entries you either have to manually configure a subdomain entry for each ingress entry you want to expose with or use a wildcard entry. Wildcard entry is strongly recommended as it significantly simplifies configuration, eg: `*.example.com` -> `<tunnel-id>.cfargotunnel.com`.

If you have [Total TLS](https://developers.cloudflare.com/ssl/edge-certificates/additional-options/total-tls/) enabled on your Cloudflare domain you also have the option to put the ingress on a subdomain wildcard, eg. `*.reclaim-the-stack.example.com` -> `<tunnel-id>.cfargotunnel.com`.

Open `platform/cloudflared/config.yaml` and search + replace `example.com` with your own Cloudflare domain.
