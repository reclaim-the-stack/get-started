# Reclaim the Stack: Get Started

Before proceeding fork and clone this repository. Then search and replace `https://github.com/<your-github-user>/<your-repo-name>.git` with the URL of your fork and commit + push the change.

The following script will do the search+replace for you provided that you cloned your fork via the https protocol:

```
ORIGINAL_URL="https://github.com/<your-github-user>/<your-repo-name>.git"
NEW_URL=`git remote get-url origin`
# NOTE: sed -i '' is required on MacOS but breaks on Linux, on Linux use -i'' without space instead
grep -rl $ORIGINAL_URL | grep -v README.md | xargs sed -i '' "s|$ORIGINAL_URL|$NEW_URL|g"
git add .
git commit -m "Switch repository to $NEW_URL"
git push
```

You're now ready to follow this README step by step and start reclaiming that stack! 💪

## Bootstrap a Local Cluster

If you already have an empty Kubernetes cluster ready you can skip this part. But if you don't here is a way to get a local Talos Linux based Kubernetes cluster going on top of Docker. When you're done experimenting you can follow the Tear Down instructions at the end of the README.

**Prerequisites**

- Docker (eg. via [Docker Desktop](https://www.docker.com/products/docker-desktop/))
- [kubectl](https://kubernetes.io/docs/tasks/tools/#kubectl)
- [yq](https://github.com/mikefarah/yq#install)
- [talosctl](https://www.talos.dev/v1.6/introduction/getting-started/#talosctl)

Now bootstrap a local Docker based Talos cluster with:

```
talosctl cluster create \
  --name reclaim-the-stack \
  --image ghcr.io/siderolabs/talos:v1.6.7 \
  --kubernetes-version 1.29.2 \
  --workers 1 \
  --cpus "2.0" \
  --cpus-workers "4.0" \
  --memory 2048 \
  --memory-workers 4096 \
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

## Installation

**Prerequisites**

- [kubectl](https://kubernetes.io/docs/tasks/tools/#kubectl)
- [yq](https://github.com/mikefarah/yq#install)
- [kubeseal](https://github.com/bitnami-labs/sealed-secrets#homebrew)

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

You can now prepare the elevated security rights for the default namespace (to support `linkerd` injection) and apply our `argocd-root` manifest to get the platform installed via ArgoCD:

```
kubectl label namespace default pod-security.kubernetes.io/enforce=privileged
kubectl label namespace default pod-security.kubernetes.io/warn=privileged

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

echo "" &&
echo "Check out your tunnel at https://one.dash.cloudflare.com/$(yq .AccountTag tunnel-credentials.json -oy)/access/tunnels" &&
echo "Add DNS entries at https://dash.cloudflare.com/$(yq .AccountTag tunnel-credentials.json -oy)" &&
echo "Configure DNS entries with CNAME target $(yq .TunnelID tunnel-credentials.json -oy).cfargotunnel.com"
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

### Tear-down

Wipe the local cluster and related config and the cloudflared tunnel:

```
talosctl cluster destroy --name reclaim-the-stack
kubectl config unset contexts.admin@reclaim-the-stack
kubectl config unset users.admin@reclaim-the-stack
kubectl config unset clusters.reclaim-the-stack
yq eval -i 'del(.contexts."reclaim-the-stack")' ~/.talos/config
cloudflared tunnel cleanup reclaim-the-stack
cloudflared tunnel delete reclaim-the-stack
```

If you set up any DNS records you'll have to delete those manually.
