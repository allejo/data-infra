---
jupytext:
  cell_metadata_filter: -all
  formats: md:myst
  text_representation:
    extension: .md
    format_name: myst
    format_version: 0.13
    jupytext_version: 1.10.3
kernelspec:
  display_name: Python 3 (ipykernel)
  language: python
  name: python3
---

# Kubernetes
## Cluster Administration ##
### preflight ###

Check logged in user

```bash
gcloud auth list
# ensure correct active user
# gcloud auth login
```

Check active project

```bash
gcloud config get-value project
# project should be cal-itp-data-infra
# gcloud config set project cal-itp-data-infra
```

Check compute region

```bash
gcloud config get-value compute/region
# region should be us-west1
# gcloud config set compute/region us-west1
```

### quick start ###

```bash
./kubernetes/gke/cluster-create.sh
# ...
export KUBECONFIG=$PWD/kubernetes/gke/kube/admin.yaml
kubectl cluster-info
```

### cluster lifecycle ###

Create the cluster by running `kubernetes/gke/cluster-create.sh`.

The cluster level configuration parameters are stored in
[`kubernetes/gke/config-cluster.sh`](../kubernetes/gke/config-cluster.sh).
Creating the cluster also requires configuring parameters for a node pool
named "default-pool" (unconfigurable name defined by GKE) in
[`kubernetes/gke/config-nodepool.sh`](../kubernetes/gke/config-nodepool.sh).
Any additional node pools configured in this file are also stood up at cluster
creation time.

Once the cluster is created, it can be managed by pointing the `KUBECONFIG`
environment variable to `kubernetes/gke/kube/admin.yaml`.

The cluster can be deleted by running `kubernetes/gke/cluster-delete.sh`.

### nodepool lifecycle ###

Certain features of node pools are immutable (e.g., machine type); to change
such parameters requires creating a new node pool with the desired new values,
migrating workloads off of the old node pool, and then deleting the old node pool.
The node pool lifecycle scripts help simplify this process.

#### create a new node pool ####

Configure a new node pool by adding its name to the `GKE_NODEPOOL_NAMES` array
in [`kubernetes/gke/config-nodepool.sh`](../kubernetes/gke/config-nodepool.sh).
For each nodepool property (`GKE_NODEPOOL_NODE_COUNT`, `GKE_NODEPOOL_NODE_LOCATIONS`, etc)
it is required to add an entry to the array which is mapped to the nodepool name.

Once the new nodepool is configured, it can be stood up by running `kubernetes/gke/nodepool-up.sh [nodepool-name]`,
or by simply running `kubernetes/gke/nodepool-up.sh`, which will stand up all configured node pools which do not yet
exist.

#### drain and delete an old node pool ####

Once a new nodepool has been created to replace an active node pool, the old node pool must be
removed from the `GKE_NODEPOOL_NAMES` array.

Once the old node pool is removed from the array, it can be drained and deleted by running `kubernetes/gke/nodepool-down.sh <nodepool-name>`.

## Deploy Cluster Workloads ##

Cluster workloads are divided into two classes:

1. system
2. apps

Apps are the workloads that users actually care about.

### system workloads ###

```bash
kubectl apply -k kubernetes/system
```

System workloads are used to support running applications. This includes items
such as an ingress controller, monitoring, logging, etc. The system deploy command
is run at cluster create time, but when new system workloads are added it may need
to be run again.

### app: metabase ###

First deploy:

```bash
helm install metabase kubernetes/apps/charts/metabase -f kubernetes/apps/values/metabase.yaml -n metabase --create-namespace
```

Apply changes:

```bash
helm upgrade metabase kubernetes/apps/charts/metabase -f kubernetes/apps/values/metabase.yaml -n metabase
```

### app: gtfs-rt-archive ###

First deploy:

```bash
# Archive url: https://bitwarden.jarv.us//attachments/1ef9cad1-40a3-41f2-963d-f43d64c06efb/09dd10cd528b5f9743f3
tar xzvf kubernetes-secrets.tar.gz && rm kubernetes-secrets.tar.gz

# Deploy app
kubectl apply -k kubernetes/secrets
kubectl apply -k kubernetes/apps/overlays/gtfs-rt-${environment}
```

Apply changes:

```bash
kubectl apply -k kubernetes/apps/overlays/gtfs-rt-${environment}
```

#### new service versions ####

In order to deploy a new version of the service script, a container image of the new version needs to
be built and pushed to the GCR repository (see the [service documentation](../services/gtfs-rt-archive.md)
for details). Once there, the image version must be changed in `kubernetes/apps/overlays/gtfs-rt-${environmnt}/kustomization.yaml`
and the manifest change must then be applied (see: "Apply changes" above).

#### agencies data ####

The secret in `kubernetes/secrets/agencies-data.yaml` is a complete base64 encoded version
of the rendered agencies.yml file. When there are changes to the agencies file, the following
steps are required:

1. Update the base64 data in `kubernetes/secrets/agencies-data.yaml` to contain the new agencies.yml contents
2. Upload the new data to the kubernetes API server
   * `kubectl apply -f kubernetes/secrets/agencies-data.yaml`
3. Restart the kubernetes deployment
   * `kubectl -n gtfs-rt rollout restart deployment/gtfs-rt-archive`

See the [gtfs-rt-archive service documentation](../services/gtfs-rt-archive.md) for details on downloading the
latest agencies file
