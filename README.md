# Homelab

This repository details the configuration and deployment of my Kubernetes-native homelab.

As a Machine Learning Engineer, the purpose of my homelab is to serve as a platform for me to try and learn the newest and greatest, from Cloud Native technologies to state-of-the-art AI models. Since the best way for me to learn is to be under pressure, I started to self-host various kinds of applications for my family such that I am responsible for making any changes to the cluster and keeping the deployments operating 24/7. This repository serves as an artifact to document my journey on maintaining a secure, scalable and efficient homelab.

## Overview

![Homelab Network Diagram](./docs/network-diagram.png)

I use k3s for setting up my HA Kubernetes cluster, with 3 Ubuntu VMs as Control nodes, and 1 Ubuntu VM GPU Worker Node. All VMs are provisioned from my Proxmox Cluster with currently 2 Mini PCs and 1 old gaming PC. I chose k3s as it is a lightweight Kubernetes distribution and I can spin up more VMs for node replacment easily from my PVE cluster if it needs more resources.

My most recent addition to the cluster is a GPU node with a low-mid tier consumer graphics card (RTX5060 Ti). It allows me to schedule GPU workload such as local LLM inferencing server, or lightweight model training. With the current configuration, I can easily add more GPU nodes and scale out & up my private LLM inferencing service for AI workflows and Agentic Coding concurrently with my own resources.

## Services

### Applications

| Logo | Name | Description |
|:-:|---|---|
| <img src="https://actualbudget.org/img/actual.png" alt="Actual Budget Logo" height="32"/> | [Actual Budget](https://github.com/actualbudget/actual) | Personal finance management |
| <img src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/commafeed.svg" height="32"/> | [Commafeed](https://github.com/Athou/commafeed) | RSS reader |
| <img src="https://github.com/CorentinTh/it-tools/raw/main/.github/logo-white.png" alt="IT-Tools" height="32" /> | [IT-Tools](https://github.com/CorentinTh/it-tools) | Collection of handy online tools for developers |
| <img src="https://raw.githubusercontent.com/louislam/uptime-kuma/023079733a2697f6544616e56225eff6de77060b/public/icon.svg" alt="Uptime Kuma" height="32"/>| [Uptime Kuma](https://github.com/louislam/uptime-kuma) | Service monitoring and health check |
| <img src="https://minecraft.wiki/images/Minecraft_franchise_logo.svg?59f89" height="32"/>| [Minecraft Server](https://github.com/itzg/minecraft-server-charts) | Game server for Minecraft |
|  | [WebDAV](https://github.com/danuk/k8s-webdav) | Database for my Zotero Research Paper Reader |
|  | [Media Services (*arr)](https://github.com/Ravencentric/awesome-arr) | A suite of applications for my media collection management. |

### AI

| Logo | Name | Description |
|:-:|---|---|
| <img src="https://docs.vllm.ai/en/latest/assets/logos/vllm-logo-text-dark.png" height="32" /> | [vLLM](https://github.com/vllm-project/vllm) | High-throughput and memory-efficient inference and serving engine for LLMs  |
|  | [LiteLLM](https://github.com/BerriAI/litellm) | LLM Gateway for local LLM servers & other cloud providers. |
| <img src="https://openwebui.com/logo.png" height="32" /> | [Open WebUI](https://github.com/open-webui/open-webui) | Frontend Chat interface connected to LiteLLM |

### Infrastructure

| Logo | Name | Description |
|:-:|---|---|
| <img src="https://github.com/traefik/traefik/raw/master/docs/content/assets/img/traefik.logo-dark.png" height="32" /> | [Traefik](https://github.com/traefik/traefik) | Ingress Controller |
| <img src="https://developers.cloudflare.com/_astro/logo.DAG2yejx.svg" height="32" /> | [Cloudflare Tunnel](https://github.com/cloudflare/cloudflared) | Zero Trust Tunnel to expose services publicly |
| <img src="https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/_static/nvidia-logo-horiz-rgb-wht-for-screen.svg" height="32" /> | [GPU Operator](https://github.com/NVIDIA/gpu-operator) | NVIDIA runtime class manager for AI/ML workloads |
| <img src="https://github.com/cert-manager/cert-manager/raw/master/logo/logo-small.png" height="32" /> | [Cert Manager](https://github.com/cert-manager/cert-manager) | Automated X.509 certificate management |
| <img src="https://external-secrets.io/latest/pictures/eso-round-logo.svg" height="32" /> | [External Secrets Operator](https://external-secrets.io/latest/) | External secrets in Azure Key Vault |
| <img src="https://cloudnative-pg.io/logo/large_logo.svg" height="32" /> | [CloudNativePG](https://github.com/cloudnative-pg/cloudnative-pg) | PostgreSQL DB Cluster for other applications |
| <img src="https://www.synology.com/img/company/branding/synology_logo.jpg" height="32" /> | [Synology CSI Driver](https://github.com/SynologyOpenSource/synology-csi) | Persistent Volume Provisioning from my Synology NAS |

### Monitoring & Observability

| Logo | Name | Description |
|:-:|---|---|
| <img src="https://avatars.githubusercontent.com/u/66682517?s=48&v=4" height="32" /> <img src="https://avatars.githubusercontent.com/u/7195757?s=48&v=4" height="32"/> <img src="https://prometheus.io/_next/static/media/prometheus-logo.7aa022e5.svg" height="32" />| [kube-prometheus-stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack) | Out-of-the-box monitoring solution: Prometheus, Grafana, and Alertmanager. |
| <img src="https://github.com/grafana/loki/raw/main/docs/sources/logo_and_name.png" height="32" /> | [Loki](https://github.com/grafana/loki) | Prometheus, but for logs |
| <img src="https://github.com/grafana/alloy/raw/main/docs/sources/assets/logo_alloy_light.svg#gh-dark-mode-only" height="32" /> | [Alloy](https://github.com/grafana/alloy) | OpenTelemetry Collector |
