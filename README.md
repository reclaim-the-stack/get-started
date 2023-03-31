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
  --workers 3 \
  --cpus "2.0" \
  --cpus-workers "2.0" \
  --memory 2048 \
  --memory-workers 2048 \
  --config-patch-worker @platform/talos-worker-patch.yaml
```

When your cluster is up and running you can configure `kubectl` and `talosctl` to use it by:

```
kubectl config use-context admin@reclaim-the-stack
talosctl config context reclaim-the-stack
talosctl config node $(kubectl get node reclaim-the-stack-controlplane-1 -o yaml | yq .status.addresses.0.address)
```

You should now be able to list the nodes of your cluster via:

```
kubectl get nodes -o wide
talosctl get members
```

Before proceeding to the Installation section, ensure to label the worker node with both `worker` and `database` roles to allow scheduling all types of workloads on it (NOTE: on a real production cluster you might want to keep worker and database nodes separate):

```
kubectl label nodes reclaim-the-stack-worker-1 node-role.kubernetes.io/worker=
kubectl label nodes reclaim-the-stack-worker-1 node-role.kubernetes.io/database=
```

### Tear-down

```
talosctl cluster destroy --name reclaim-the-stack
kubectl config unset contexts.admin@reclaim-the-stack
kubectl config unset users.admin@reclaim-the-stack
kubectl config unset clusters.reclaim-the-stack
yq eval -i 'del(.contexts."reclaim-the-stack")' ~/.talos/config
```

## Installation

The following assumes you have cloned this repository and changed current working directory into the git repository.

First we install the gitops tool ArgoCD:

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

Enable the `cloudflared` component of the stack:

```
mv platform-applications/disabled/cloudflared.yaml platform-applications/
```

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

After pushing the changes and refreshing the `platform` application in ArgoCD `cloudflared` will start deploying. When everything is green, provided you have set up your DNS entries correctly, you should now be able to access ArgoCD and Grafana via your domain on their respective subdomains.

### ArgoCD webhook

When you got ingress working and can reach ArgoCD via your domain you can add a webhook to this repository (via Settings -> Webhooks -> Add webhook) to allow ArgoCD to immediately sync changes after every git push.

The URL structure of the webhook is: `https://argocd.<your-domain.com>/api/webhook`
The content type should be `application/json`
For events you need "just the `push` event".
