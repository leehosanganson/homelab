# Homelab

This repository documents the configuration and deployment of my Kubernetes-native homelab.

<p align="center">
  <img src="./docs/homelab-architecture/server-rack.jpg" alt="Server Rack" width="80%" />
</p>

As a Machine Learning Engineer, I built this space to learn Cloud Native technologies and state-of-the-art AI models by putting myself under real pressure - running them for real instead of just tinkering in isolation. To keep things interesting, I started self-hosting all sorts of apps for my family, so now I'm the one responsible for keeping everything running 24/7. This repo is my way of documenting that journey as I try to maintain a homelab that's secure, scalable, and actually useful.

<p align="center">
  <a href="https://www.cncf.io/training/kubestronaut/" target="_blank" rel="noopener">
    <img src="https://images.credly.com/size/340x340/images/cd6c6449-6814-4613-a2d3-13cf4ac5be4f/image.png" alt="Linux Foundation Kubestronaut Badge" width="150" />
  </a>
</p>

I'm also a [Kubestronaut](https://www.credly.com/badges/664b0259-2896-430d-a552-3db866a66d34), recognised by the CNCF for passing all Kubernetes certifications and contributing to the Cloud Native community.

## Overview

### Architecture

<p align="center">
  <img src="./docs/homelab-architecture/homelab-diagram.svg" alt="Homelab Architecture" width="100%" />
</p>

I run a 3-node HA Kubernetes cluster using k3s, with Ubuntu VMs handling the control plane and one GPU-enabled worker node doing the heavy lifting. Everything runs out of my Proxmox cluster, currently 2 Mini PCs and an old gaming PC. I picked k3s because it's lightweight enough that I can spin up replacement nodes from Proxmox whenever a machine needs more resources or gets swapped out.

The newest addition to the cluster is a GPU node packed with an RTX 5060 Ti, not top-of-the-line, but more than enough to run local LLM inference and light model training. It's opened up a whole new world for running AI workflows and Agentic Coding locally. And if I ever need more compute, adding another GPU node to the cluster is pretty straightforward, so I can scale out and up without relying on anyone else's resources.

## Infrastructure as Code

The entire homelab is provisioned and configured using a fully declarative IaC approach:

- **VM Lifecycle (OpenTofu):** OpenTofu manages the virtual hardware boundary of each NixOS VM on Proxmox from the [`terraform/`](terraform/). It creates VMs with defined CPU, memory, disk, and network configuration.
- **OS & Configuration (NixOS):** Host provisioning uses `nixos-anywhere` + `disko` from the [`nixos/`](nixos/) flake directory. All configuration is declarative and reproducible.

## Services

### Applications

|                                                              Logo                                                               | Name                                                                         | Description                                                 |
| :-----------------------------------------------------------------------------------------------------------------------------: | ---------------------------------------------------------------------------- | ----------------------------------------------------------- |
| <img src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/actual-budget.png" alt="Actual Budget Logo" height="32"/> | [Actual Budget](https://github.com/actualbudget/actual)                      | Personal finance management                                 |
|               <img src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/commafeed.svg" height="32"/>                | [Commafeed](https://github.com/Athou/commafeed)                              | RSS reader                                                  |
|          <img src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/chrome.png" alt="Chrome" height="32"/>           | [Chrome](https://www.google.com/chrome/)                                     | Browser for internal web browsing                           |
|        <img src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/coder-light.png" alt="Coder" height="32"/>         | [Coder](https://github.com/coder/coder)                                      | Web-based development environment                           |
|             <img src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/home-assistant.svg" height="32"/>             | [Home Assistant](https://www.home-assistant.io/)                             | Home automation platform                                    |
|                <img src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/homepage.png" height="32"/>                | [Homepage](https://github.com/gethomepage/homepage)                          | Customizable home page / dashboard                          |
|                      <img src="https://cdn.jsdelivr.net/gh/selfhst/icons/png/grimmory.png" height="32" />                       | [Grimmory](https://github.com/grimmory-tools/grimmory)                       | Self-hosted digital library management                      |
|     <img src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/it-tools-light.png" alt="IT-Tools" height="32" />     | [IT-Tools](https://github.com/CorentinTh/it-tools)                           | Collection of handy online tools for developers             |
|                 <img src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/immich.png" height="32"/>                 | [Immich](https://github.com/immich-app/immich)                               | High performance self-hosted photo and video management     |
|                                                                                                                                 | [Life in the UK Quiz](https://github.com/leehosanganson/life-in-the-uk-quiz) | Custom quiz app for Life in the UK citizenship test         |
|                       <img src="https://cdn.jsdelivr.net/gh/selfhst/icons/png/mini-qr.png" height="32"/>                        | [Mini QR](https://github.com/mini-qr/)                                       | Lightweight QR code generator                               |
|                <img src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/karakeep.png" height="32"/>                | [Karakeep](https://github.com/karakeep/karakeep)                             | Digital collection organizer                                |
|                  <img src="https://cdn.jsdelivr.net/gh/selfhst/icons/svg/minecraft-detailed.svg" height="32"/>                  | [Minecraft Server](https://github.com/itzg/minecraft-server-charts)          | Game server for Minecraft                                   |
|                                                                                                                                 | [Media Services (\*arr)](https://github.com/Ravencentric/awesome-arr)        | A suite of applications for my media collection management. |
|               <img src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/navidrome.png" height="32"/>                | [Navidrome](https://github.com/navidrome/navidrome)                          | Music streaming server                                      |
|                  <img src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/n8n.png" height="32"/>                   | [n8n](https://n8n.io/)                                                       | Workflow automation tool                                    |
|             <img src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/paperless-ngx.png" height="32"/>              | [Paperless-ngx](https://github.com/paperless-ngx/paperless-ngx)              | Document management system                                  |
|                                                                                                                                 | [Portfolio](https://github.com/leehosanganson/portfolio)                     | Personal portfolio website (self-hosted)                    |
|                 <img src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/zotero.png" height="32"/>                 | [Zotero WebDAV](https://github.com/danuk/k8s-webdav)                         | Database for my Zotero Research Paper Reader                |
|                <img src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/termix.png" height="32" />                 | [Termix](https://github.com/termux/)                                         | Terminal emulator and SSH client for mobile                 |
|                                                                                                                                 | [Whoami](https://github.com/antonz/whoami)                                   | Simple HTTP service for debugging                           |
|       <img src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/syncthing.png" alt="Syncthing" height="32"/>        | [Syncthing](https://syncthing.net/)                                          | Continuous file synchronization                             |

### AI

|                                                    Logo                                                    | Name                                                   | Description                                                |
| :--------------------------------------------------------------------------------------------------------: | ------------------------------------------------------ | ---------------------------------------------------------- |
|           <img src="https://cdn.jsdelivr.net/gh/selfhst/icons/png/llama-cpp.png" height="32" />            | [llama.cpp](https://github.com/ggerganov/llama2.cpp)   | LLM Inferencing Engine                                     |
|     <img src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/litlellm.png" height="32" />     | [LiteLLM](https://github.com/BerriAI/litellm)          | LLM Gateway for local LLM servers & other cloud providers. |
| <img src="https://cdn.jsdelivr.net/npm/@lobehub/icons-static-png@latest/light/opencode.png" height="32" /> | [OpenCode](https://opencode.ai/docs/web/)              | Browser-based remote coding agent server                   |
| <img src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/open-webui-light.png" height="32" /> | [Open WebUI](https://github.com/open-webui/open-webui) | Frontend Chat interface connected to LiteLLM               |

### Infrastructure

|                                                       Logo                                                       | Name                                                              | Description                                           |
| :--------------------------------------------------------------------------------------------------------------: | ----------------------------------------------------------------- | ----------------------------------------------------- |
|     <img src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/traefik-proxy.png" height="32" />      | [Traefik](https://github.com/traefik/traefik)                     | Ingress Controller for Kubernetes workloads           |
|       <img src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/cloudflare.png" height="32" />       | [Cloudflare Tunnel](https://github.com/cloudflare/cloudflared)    | Zero Trust Tunnel to expose services publicly         |
|  <img src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/haproxy.png" alt="HAProxy" height="32"/>  | [HAProxy](https://www.haproxy.org/)                               | L4 load balancer & SSL termination (3 VMs on Proxmox) |
|  <img src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/pi-hole.png" height="32" alt="Pi-hole">   | [Pi-hole](https://pi-hole.net/)                                   | Network-wide ad blocking DNS (2 VMs on Proxmox)       |
|         <img src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/nvidia.png" height="32" />         | [GPU Operator](https://github.com/NVIDIA/gpu-operator)            | NVIDIA runtime class manager for AI/ML workloads      |
|      <img src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/cert-manager.png" height="32" />      | [Cert Manager](https://github.com/cert-manager/cert-manager)      | Automated X.509 certificate management                |
|             <img src="https://external-secrets.io/latest/pictures/eso-round-logo.svg" height="32" />             | [External Secrets Operator](https://external-secrets.io/latest/)  | External secrets in Azure Key Vault                   |
|        <img src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/postgres.png" height="32" />        | [CloudNativePG](https://github.com/cloudnative-pg/cloudnative-pg) | PostgreSQL DB Cluster for other applications          |
|               <img src="https://cdn.jsdelivr.net/gh/selfhst/icons/png/synology.png" height="32" />               | [Synology NAS](https://www.synology.com/)                         | File server & CSI Persistent Volume Provisioner       |
|   <img src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/harbor.svg" alt="Harbor" height="32"/>   | [Harbor](https://github.com/goharbor/harbor)                      | Private container registry                            |
|  <img src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/rancher.svg" alt="Rancher" height="32"/>  | [Rancher](https://github.com/rancher/rancher)                     | Kubernetes management platform                        |
| <img src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/renovate.svg" alt="Renovate" height="32"/> | [Renovate](https://github.com/renovatebot/renovate)               | Automated dependency update bot                       |
|   <img src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/velero.svg" alt="Velero" height="32"/>   | [Velero](https://github.com/vmware-tanzu/velero)                  | Backup & disaster recovery for Kubernetes             |

### Monitoring & Observability

|                                                 Logo                                                 | Name                                      | Description                                  |
| :--------------------------------------------------------------------------------------------------: | ----------------------------------------- | -------------------------------------------- |
| <img src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/prometheus.png" height="32" /> | [Prometheus](https://prometheus.io/)      | Metrics collection and monitoring system     |
|  <img src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/grafana.png" height="32" />   | [Grafana](https://grafana.com/)           | Dashboard for metrics and logs visualization |
|    <img src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/loki.png" height="32" />    | [Loki](https://github.com/grafana/loki)   | Prometheus, but for logs                     |
|   <img src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/alloy.png" height="32" />    | [Alloy](https://github.com/grafana/alloy) | OpenTelemetry Collector                      |
