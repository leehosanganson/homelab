# Plan a K3s migration from Flannel to Cilium

## Status and scope

This document is a **migration plan, not an approved procedure**. The accompanying draft PR includes a Cilium Helm release configured for a secondary overlay, opens candidate Geneve UDP port 6081 in the shared NixOS firewall, and adds per-node CNI configuration that selects no nodes by default. Merging the PR would change production: NixOS auto-upgrades could apply the firewall change, and Flux would install Cilium and create its secondary overlay. Do not merge or reconcile it until the lab trial and other stop gates below pass and the production rollout is separately approved. Do not change K3s networking flags, disable the existing policy controller, remove Flannel, clean firewall rules, restart K3s, reboot nodes, or uncordon `k3s-work-02` based on this document alone.

The target is the existing eight-node K3s cluster. The intended outcome is Cilium-managed pod networking and Kubernetes NetworkPolicy enforcement, with the existing Traefik and Authentik routes continuing to work. This plan does not select kube-proxy replacement, change Cloudflare Tunnel, migrate other services, or change the Kubernetes Service CIDR.

## Observed starting state

The read-only inventory on 2026-11-26 found eight nodes using K3s: three embedded-etcd servers, four NixOS workers, and the Ubuntu GPU worker `k3s-gpu-01`. Flannel uses VXLAN, and current node PodCIDRs are inside `10.42.0.0/16`.

The API Service IP is `10.43.0.1`; the complete Service CIDR still needs to be confirmed from the live K3s server configuration. Six nodes reported K3s `v1.35.6+k3s1`, while the API and two nodes reported `v1.36.6+k3s1`. Cilium's current K3s install guide was verified for Cilium `1.20.5`, but the reviewed compatibility evidence did not establish support for this cluster's K3s/Kubernetes 1.36 nodes.

Seven nodes are managed by the NixOS flake. The Ubuntu GPU node is outside that flake and its host configuration could not be inspected over SSH. The two inspected NixOS nodes use `/var/lib/rancher/k3s/data/cni` for CNI binaries and `/var/lib/rancher/k3s/agent/etc/cni/net.d` for CNI configuration; verify these paths on every node before using them. `k3s-work-02` remains cordoned.

The existing K3s NetworkPolicy controller has reported iptables rule-append failures. Do not treat existing NetworkPolicy objects as proof of enforcement. The Mini QR route has Authentik ForwardAuth, but direct backend access has not been shown to be blocked; policy downtime therefore remains a security concern during migration.

## Candidate design

- The draft HelmRelease pins Cilium chart `1.20.5`, matching the version in the reviewed official K3s and live-migration guides. Re-check the supported Kubernetes versions and chart version before any merge or reconciliation.
- Use Cluster Pool IPAM with candidate PodCIDR `10.44.0.0/16`, which the operator considers acceptable. Before production use, verify it does not overlap any LAN, VPN, routed, reserved, or cluster ranges; the current inventory does not prove this.
- Use Geneve rather than Flannel's VXLAN overlay, on candidate UDP port `6081`. The draft opens that port in the shared NixOS firewall, but the node's existing firewall and network path must still be verified; the Ubuntu GPU host is managed separately.
- Keep kube-proxy enabled. Kube-proxy replacement is a separate change and is not required for Cilium NetworkPolicy.
- Follow Cilium's secondary-overlay migration model: first establish Cilium without taking over the CNI configuration, then migrate one node at a time through an explicit per-node configuration. The draft chart values use the K3s CNI binary and configuration paths observed on two NixOS nodes; confirm them on every node before installation. The Flux `cilium` Kustomization waits for both the Cilium HelmRelease to become Ready and the `ciliumnodeconfigs.cilium.io` CRD to be Established before the dependent `CiliumNodeConfig` Kustomization can apply. That per-node resource matches only nodes explicitly labeled `io.cilium.migration/k3s-cilium=true`. Do not apply that label through GitOps or by hand until the rollout is separately approved. Do not switch all nodes through a single uncoordinated Git or auto-upgrade rollout.
- Keep policy enforcement disabled during the network-provider transition only if an approved plan accepts that risk. Cilium documents an existing NetworkPolicy provider as an untested migration case. K3s also documents that disabling its policy controller does not remove the rules it previously created.

## Stop gates before production installation or migration

The draft PR prepares a secondary-overlay Helm release, but it is not safe to merge or reconcile that release until all gates below have evidence and an operator has separately approved the production rollout plan. The later CNI takeover and policy transition require additional approval; a merged PR does not authorize those actions.

1. **Lab trial:** Rehearse the exact K3s release, embedded-etcd topology, NixOS kernel/module configuration, Ubuntu GPU host, CNI paths, current Flannel setup, storage, ingress, DNS, egress, NetworkPolicies, and rollback in an isolated representative cluster. A Kind trial alone does not validate these host and K3s differences.
2. **Version support:** Confirm that the selected Cilium release supports both K3s versions actually running in the cluster, including `v1.36.6+k3s1`, or complete a separately approved, verified Kubernetes version alignment first.
3. **Complete network inventory:** Confirm the full live Pod and Service CIDRs, all host routes, LAN/VPN/routed networks, overlay ports, node addresses, and the unmanaged GPU node's local K3s configuration. Confirm `10.44.0.0/16` is unused rather than relying on repository search or a default route.
4. **Host compatibility:** Verify Cilium's required eBPF kernel features, modules, cgroup configuration, and host firewall behavior on all seven NixOS nodes and on `k3s-gpu-01`. Kernel version alone is not proof.
5. **Controller and rule transition:** Design and test how K3s's kube-router policy controller is disabled consistently on all three servers and how any old `KUBE-NWPLCY`/`KUBE-POD-FW` rules are identified and removed safely on every node. Do not use `k3s-killall.sh` or broad firewall cleanup as an unreviewed shortcut.
6. **Ordered rollout:** Resolve how to prevent hourly NixOS auto-upgrades from applying network changes on multiple hosts without coordination, including the candidate firewall change in this PR. Verify whether the Ubuntu GPU host firewall also needs Geneve UDP port `6081` opened and arrange its separately managed change if required. Define a staged process for workers, the Ubuntu GPU node, and embedded-etcd servers; do not start with a control-plane node.
7. **Security and recovery:** Decide how to protect Mini QR while policies are not enforced, and rehearse a node-level rollback to Flannel. Preserve the existing Authentik route, TLS Certificate, and Secret. Define observable rollback checks before starting.
8. **Approval:** Have the exact production configuration and runbook reviewed, then obtain separate explicit authorization for each production rollout stage. A draft or merged PR is not authorization to reconcile, activate hosts, reboot, or uncordon nodes.

## Production rollout outline after all gates pass

The following outline is not executable until the stop gates are closed and the rollout is separately approved.

1. Capture fresh health, node, PodCIDR, Service CIDR, route, CNI-file, storage, ingress, DNS, and policy-enforcement baselines. Confirm control-plane quorum and workload recovery capacity. Do not proceed if a check is missing or unhealthy.
2. Apply only the approved preparatory Cilium configuration. Confirm Cilium is healthy on every intended node, its secondary overlay uses the verified distinct PodCIDR and encapsulation, no node has selected Cilium as its primary CNI, Flannel connectivity is unchanged, and the Cilium IPAM pool has no collision.
3. Select one worker with an approved workload and disruption plan. Cordon and drain it. Respect PodDisruptionBudgets and stop if an eviction is blocked; do not force deletion. Keep `k3s-work-02` cordoned unless a later separately approved decision changes that state.
4. Apply the approved per-node Cilium CNI selection for that node, then perform only the specifically approved activation or reboot step. Reboot no more than one node at a time. Verify the node's Pod IP, API access, DNS, egress, cross-node traffic, storage mounts, Traefik routing, and Cilium status before uncordoning it.
5. Test both allowed and denied NetworkPolicy traffic from representative pods on different nodes. Verify that Mini QR is reachable through Traefik and Authentik, while direct Service and Pod IP access from an unrelated pod is denied. Do not rely only on a Ready policy object or a successful HTTP request.
6. Repeat one node at a time only after the prior node passes every check. Stop on any loss of control-plane quorum, Cilium health, workload readiness, storage access, ingress, DNS, or expected policy behavior.
7. After every node has migrated and the old policy-provider rules have a tested cleanup procedure, complete the approved transition: enable Cilium policy enforcement, verify allowed and denied traffic again, remove Flannel and K3s policy-controller configuration as planned, and confirm no stale CNI or policy rules remain.
8. Record final node, PodCIDR, CNI, policy, ingress, and workload evidence. Keep the rollback procedure available until the agreed observation period passes.

## Recovery and rollback boundary

If a node fails any post-migration check, keep it cordoned and stop the rollout. Do not uncordon it or apply firewall cleanup to hide the failure. Use only the node rollback sequence proven in the lab and approved for production; it must restore a valid CNI configuration, recover that node's workloads, and preserve cluster quorum. If that sequence is not available or its preconditions are not met, stop and escalate rather than improvising.

Disabling K3s's NetworkPolicy controller does not remove its existing iptables rules. Do not manually delete `KUBE-NWPLCY` or `KUBE-POD-FW` chains until a per-node cleanup procedure has been tested and approved. Continue to treat Mini QR's direct-backend isolation as unverified until an unrelated-pod denial test passes.

## Official references

- [K3s basic network options](https://docs.k3s.io/networking/basic-network-options)
- [K3s networking services](https://docs.k3s.io/networking/networking-services)
- [Cilium installation using K3s](https://docs.cilium.io/en/stable/installation/k3s/)
- [Cilium Kubernetes requirements](https://docs.cilium.io/en/stable/network/kubernetes/requirements/)
- [Cilium cluster migration guide](https://docs.cilium.io/en/stable/installation/k8s-install-migration/)
- [Cilium system requirements](https://docs.cilium.io/en/stable/operations/system_requirements/)
- [Cilium per-node configuration](https://docs.cilium.io/en/stable/configuration/per-node-config/)
