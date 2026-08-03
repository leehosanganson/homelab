# Prometheus Operator (kube-prometheus-stack) Migration

Migrates the `monitoring` namespace from the legacy
`prometheus-community/prometheus` chart (classic `stable/prometheus`, annotation-based
scrape discovery) to the modern **kube-prometheus-stack** (Prometheus Operator, declarative
`ServiceMonitor`/`Prometheus` CR discovery).

## What changes

| | Legacy (current) | kube-prometheus-stack (new) |
|---|---|---|
| HelmRelease name | `prometheus` | `kube-prometheus-stack` |
| Prometheus workload | `prometheus-server` **Deployment** | `prometheus-kube-prometheus-stack-prometheus` **StatefulSet** (`Prometheus` CR `kube-prometheus-stack-prometheus`) |
| Prometheus API service | `prometheus-server.monitoring.svc` | `kube-prometheus-stack-prometheus.monitoring.svc:9090` |
| Discovery model | annotations (`prometheus.io/scrape`) + `kubernetes_sd_configs` | `ServiceMonitor` / `PodMonitor` CRs (+ operator generated config) |
| Alertmanager | `prometheus-alertmanager` STF | `kube-prometheus-stack-alertmanager` STF |
| node-exporter / kube-state-metrics | standalone copies | bundled by the stack (with default ServiceMonitors) |
| Retention | 90d / 130GB, PVC `prometheus-server` (150Gi) | 90d / 130GB, PVC `prometheus-kube-prometheus-stack-prometheus-db-prometheus-0` (150Gi) |

**Grafana is NOT migrated** — the repo keeps the standalone `grafana` chart; only its
Prometheus datasource URL was repointed to `kube-prometheus-stack-prometheus.monitoring.svc`.

**CRDs / operator state:** `monitoring.coreos.com` CRDs already exist (leftover from a prior
operator install ~398d ago, visible as the orphaned PVC
`prometheus-prometheus-kube-prometheus-prometheus-db-prometheus-…`). The new chart owns and
upgrades them. Its default `serviceMonitorSelector: {}` matches all namespaces, so the
existing `gpu-operator/gpu-operator` ServiceMonitor keeps working untouched.

## Pre-flight checks (before merge)

- Confirm the firewall rule added for node-exporter port **9100** is present on all nodes
  (the stack's node-exporter is also `hostNetwork` on `:9100`). See the earlier UFW fix.
- Note the current metrics history lives in PVC `prometheus-server` (150Gi, 94d old).

## After the PR merges (Flux reconciles)

1. Confirm the new stack is healthy:

   ```bash
   kubectl get prometheus,alertmanager -n monitoring
   kubectl get sts,pods -n monitoring | grep -E 'kube-prometheus|alertmanager'
   kubectl get servicemonitor,servicemonitor,podmonitor -A | grep -iE 'node|kube-'
   ```

2. Confirm Grafana now reads from the new Prometheus (datasource
   `kube-prometheus-stack-prometheus`) and node metrics appear for **all** nodes.
   The initial history will be empty until step 3 completes.

## Migrate the existing 90d TSDB (optional but requested)

Prometheus writes a single-writer TSDB, so the old server MUST be fully stopped before the
data is copied, and the new server MUST be stopped while the copy runs.

```bash
NS=monitoring

# 1. Stop the OLD (legacy) prometheus-server cleanly so its TSDB/WAL is flushed & consistent
kubectl scale deploy prometheus-server -n $NS --replicas=0
kubectl wait --for=delete pod -n $NS -l app.kubernetes.io/name=prometheus --timeout=120s

# 2. Stop the NEW operator-prometheus so it isn't writing during the copy
kubectl patch prometheus kube-prometheus-stack-prometheus -n $NS \
  --type merge -p '{"spec":{"replicas":0}}'
kubectl wait --for=delete pod -n $NS -l app.kubernetes.io/name=prometheus,app.kubernetes.io/instance=kube-prometheus-stack --timeout=120s
```

The copy must mount **both** PVCs (old `prometheus-server` as source, new
`prometheus-kube-prometheus-stack-prometheus-db-prometheus-0` as destination). Use this Job
manifest and `kubectl apply -f` it:

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: migrate-prometheus-tsdb
  namespace: monitoring
spec:
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: rsync
          image: alpine/rsync
          command: ["/bin/sh","-c"]
          args:
            - apk add --no-cache rsync >/dev/null 2>&1 || true;
              mkdir -p /src/prometheus /dst/prometheus;
              rsync -a --exclude '*.lock' /src/prometheus/ /dst/prometheus/;
              echo "COPY DONE"
          volumeMounts:
            - { name: src, mountPath: /src }
            - { name: dst, mountPath: /dst }
      volumes:
        - name: src
          persistentVolumeClaim: { claimName: prometheus-server }
        - name: dst
          persistentVolumeClaim:
            claimName: prometheus-kube-prometheus-stack-prometheus-db-prometheus-0
```

Run, verify `COPY DONE`, then restart the new Prometheus:

```bash
kubectl logs -n $NS job/migrate-prometheus-tsdb
kubectl delete job -n $NS migrate-prometheus-tsdb
kubectl patch prometheus kube-prometheus-stack-prometheus -n $NS \
  --type merge -p '{"spec":{"replicas":1}}'
```

Verify history is present:

```bash
kubectl exec -n $NS deploy/prometheus-kube-prometheus-stack-prometheus -- \
  wget -qO- 'http://127.0.0.1:9090/api/v1/query?query=up{job="kubernetes-nodes"}' | jq -c '.data.result|length'
kubectl exec -n $NS deploy/prometheus-kube-prometheus-stack-prometheus -- \
  wget -qO- 'http://127.0.0.1:9090/api/v1/query?query=node_uname_info' | jq -r '.data.result[].metric.instance'
```

## Cleanup the legacy stack

Once the new stack is verified, remove the old classic-chart resources (Flux does **not**
garbage-collect a removed HelmRelease — you must uninstall it explicitly):

```bash
# The old `prometheus` HelmRelease is no longer in git, so clean up manually:
kubectl delete hr prometheus -n monitoring
kubectl delete deploy prometheus-server -n monitoring
kubectl delete sts prometheus-alertmanager -n monitoring
kubectl delete ds prometheus-prometheus-node-exporter -n monitoring
kubectl delete deploy prometheus-kube-state-metrics prometheus-prometheus-pushgateway -n monitoring

# Release the old TSDB PVC (equivalent amounts of data now live in the new PVC):
kubectl delete pvc prometheus-server storage-prometheus-alertmanager-0 -n monitoring

# (Optional) reclaim space + remove leftover artifacts from the PRIOR operator install:
kubectl delete pvc prometheus-prometheus-kube-prometheus-prometheus-db-prometheus-prometheus-kube-prometheus-prometheus-0 -n monitoring
kubectl delete pvc prometheus-grafana -n monitoring  # ReclaimPolicy=Retain
```

## Notes / pitfalls

- The new stack's node-exporter ServiceMonitor scrapes each node on host `:9100` — the
  UFW `9100/tcp` allow from the earlier incident is still required and unchanged.
- Grafana dashboards: the `grafana` chart (standalone) and its sidecar dashboards are
  unchanged; only the Prometheus datasource URL moved.
- If you ever label the `litellm` Service with a dedicated label, the
  `additionalScrapeConfigs` block for litellm can be replaced by a real
  `ServiceMonitor` in the `llm` namespace.
- Changing the HelmRelease name from `prometheus` → `kube-prometheus-stack` intentionally
  avoids resource-name collisions with the still-running legacy workload during the
  transition window.
