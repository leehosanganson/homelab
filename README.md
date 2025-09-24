# Homelab

This repository details the configuration and deployment of my Kubernetes-native homelab.

As a Machine Learning Engineer, the purpose of my homelab is to serve as a platform for me to try and learn the newest and greatest, from Cloud Native technologies to state-of-the-art AI models. Since the best way for me to learn is to be under pressure, I started to self-host various kinds of applications for my family such that I am responsible for making any changes to the cluster and keeping the deployments operating 24/7. This repository serves as an artifact to document my journey on maintaining a secure, scalable and efficient homelab.

## Overview

I use k3s for setting up my HA Kubernetes cluster, with 3 Ubuntu VMs as Control nodes, and 1 Ubuntu VM GPU Worker Node. All VMs are provisioned from my Proxmox Cluster with currently 2 Mini PCs and 1 old gaming PC. I chose k3s as it is a lightweight Kubernetes distribution and I can spin up more VMs for node replacment easily from my PVE cluster if it needs more resources.

My most recent addition to the cluster is a GPU node with a low-mid tier consumer graphics card (RTX5060 Ti). It allows me to schedule GPU workload such as local LLM inferencing server, or lightweight model training. With the current configuration, I can easily add more GPU nodes and scale out & up my private LLM inferencing service for AI workflows and Agentic Coding concurrently with my own resources.

## Key Components

### Applications

| Name | Description |
|---|---|
| Actual Budget | A personal finance management application |
| Commafeed | RSS reader |
| IT-Tools | Collection of handy online tools for developers, with great UX. |
| Uptime Kuma | Service monitoring and health check |
| Zotero WebDAV | Database for my Zotero Research Paper Reader |
| Minecraft Server | Game server for Minecraft |
| Media Services (*arr) | A suite of applications for my media collection management. |

### AI

| Name | Description |
|---|---|
| vLLM | A high-throughput and memory-efficient inference and serving engine for LLMs  |
| LiteLLM | LLM Gateway for my local LLM server & other cloud providers. |
| Open WebUI | Frontend Chat interface connected to LiteLLM |

### Infrastructure

| Name | Description |
|---|---|
| Traefik | Ingress Controller |
| Cloudflare Tunnel (`cloudflared`) | Zero Trust Tunnel to expose services publicly |
| GPU Operator | NVIDIA runtime class Manager for AI/ML workloads |
| Cert Manager | Automated X.509 certificate management |
| External Secrets Operator | Manages external secrets in Azure Key Vault |
| Cloud Native PostgreSQL | Deploys Postgres Cluster for other applications |
| Synology CSI Driver | Persistent Volume Provisioning from my Synology NAS |

### Monitoring & Observability

| Name | Description |
|---|---|
| kube-prometheus-stack | Out-of-the-box monitoring solution: Prometheus, Grafana, and Alertmanager. |
| Loki | Prometheus, but for logs |
| Alloy | OpenTelemetry Collector |
