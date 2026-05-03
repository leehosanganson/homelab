# Homelab

This repository details the configuration and deployment of my Kubernetes-native homelab.

As a Machine Learning Engineer, the purpose of my homelab is to serve as a platform for me to try and learn the newest and greatest, from Cloud Native technologies to state-of-the-art AI models. Since the best way for me to learn is to be under pressure, I started to self-host various kinds of applications for my family such that I am responsible for making any changes to the cluster and keeping the deployments operating 24/7. This repository serves as an artifact to document my journey on maintaining a secure, scalable and efficient homelab.

## Overview

### Network Architecture

Infrastructure topology from external → Proxmox → K3s cluster → Kubernetes services.

```mermaid
flowchart TD
    %% EXTERNAL LAYER
    subgraph External["External / Internet"]
        USER["👤 Users"]:::ext
        CF_DNS["Cloudflare DNS\n*.infra.leehosanganson.dev"]:::ext
        CF_TUNNEL["Cloudflare Tunnel\nZero Trust"]:::ext
    end

    %% PHYSICAL LAYER - Proxmox Cluster
    subgraph Physical["Proxmox VE Cluster"]
        LAN["LAN 192.168.1.0/24"]:::phy
        PVE01["pve01\nMini PC"]:::vm
        PVE02["pve02\nMini PC"]:::vm
        PVE03["pve03\nGaming PC"]:::vm
    end

    %% PROXMOX VMs - Infrastructure Services
    subgraph InfraVMs["Infrastructure VMs"]
        HAP1["haproxy-1\n.251"]:::svc
        HAP2["haproxy-2\n.252"]:::svc
        HAP3["haproxy-3\n.253"]:::svc
        OPN1["opencode-1\n.161"]:::svc
    end

    %% K3S CLUSTER - Host Nodes
    subgraph K3sNodes["K3s Cluster Nodes"]
        CTRL01["ctrl-01\n.151"]:::vm
        CTRL02["ctrl-02\n.152"]:::vm
        CTRL03["ctrl-03\n.153"]:::vm
        GWORKER["worker-gpu\nRTX 5060 Ti"]:::vm
    end

    %% K8s INFRASTRUCTURE SERVICES
    subgraph K8sInfra["Kubernetes Infrastructure (kubernetes/infra/)"]
        INF1["Traefik\nIngress"]:::svc
        INF2["Cert Manager\nTLS"]:::svc
        INF3["GPU Operator\nNVIDIA"]:::svc
        INF4["External Secrets\nAzure KV"]:::svc
        INF5["CloudNativePG\nPostgreSQL"]:::svc
        INF6["Synology CSI\nPV Provisioner"]:::svc
        INF7["Harbor\nRegistry"]:::svc
        INF8["Rancher\nManagement"]:::svc
        INF9["Velero\nBackup"]:::svc
        INF10["Metrics Server\nResource Metrics"]:::svc
    end

    %% EXTERNAL SERVICES (non-managed)
    subgraph ExtServices["External Services"]
        SYN["Synology NAS\n.197"]:::ext
        PIH1["Pi-hole 1\n.132"]:::ext
        PIH2["Pi-hole 2\n.133"]:::ext
    end

    %% CONNECTIONS
    USER -->|"HTTPS"\| CF_DNS
    CF_DNS --> CF_TUNNEL
    CF_TUNNEL --> HAP1
    USER --> HAP1

    HAP1 -->|"k3s VIP"\| CTRL01
    HAP1 -->|"k3s VIP"\| CTRL02
    HAP1 -->|"k3s VIP"\| CTRL03
    HAP1 -->|"nas-1"\| SYN
    HAP1 -->|"pihole"\| PIH1

    LAN --- PVE01
    LAN --- PVE02
    LAN --- PVE03
    PVE01 -.-> HAP1
    PVE01 -.-> OPN1
    PVE02 -.-> HAP2
    PVE03 -.-> HAP3

    CTRL01 <-->|"etcd"\| CTRL02
    CTRL02 <-->|"etcd"\| CTRL03
    CTRL01 -->|"scheduler"\| GWORKER

    HAP1 -->|"traefik"\| INF1
    INF6 --> SYN
    GWORKER -.-> INF3

    classDef vm fill:#e3f2fd,stroke:#1565c0,stroke-width:2px,color:#0d47a1;
    classDef svc fill:#e8f5e9,stroke:#2e7d32,stroke-width:2px,color:#1b5e20;
    classDef ext fill:#fff3e0,stroke:#e65100,stroke-width:2px,color:#bf360c;
    classDef phy fill:#eceff1,stroke:#455a64,stroke-width:2px,color:#263238;
```

### Application Data Flow

Kubernetes application services and their data dependencies.

```mermaid
flowchart TD
    %% K8s INFRASTRUCTURE (anchor)
    subgraph Infra["Kubernetes Infrastructure"]
        TRAFIK["Traefik\nIngress Controller"]:::svc
        CNPG["CloudNativePG\nPostgreSQL"]:::db
        REDIS_I["Redis\nImmich"]:::db
        REDIS_P["Redis\nPaperless"]:::db
    end

    %% PRODUCTIVITY & DEV TOOLS
    subgraph Productivity["Productivity & Dev Tools"]
        AB["Actual Budget"]:::svc
        CHROME["Chrome"]:::svc
        ITTOOL["IT-Tools"]:::svc
        TERMIX["Termix"]:::svc
        WHOAMI["Whoami"]:::svc
        PORTFOLIO["Portfolio"]:::svc
    end

    %% DASHBOARD & BROWSING
    subgraph Dashboard["Dashboard & Browsing"]
        HOMEPAGE["Homepage"]:::svc
        CFED["Commafeed\nRSS Reader"]:::svc
    end

    %% PHOTO & DOCUMENT MANAGEMENT
    subgraph PhotoDoc["Photo & Document Mgmt"]
        IMMICH["Immich\nPhoto/Video"]:::svc
        PAPERLESS["Paperless-ngx\nDocuments"]:::svc
    end

    %% MEDIA SUITE
    subgraph Media["Media Suite"]
        JELLYFIN["Jellyfin\nServer & Player"]:::svc
        JELLYSEERR["Jellyseerr\nDiscovery"]:::svc
        NAV["Navidrome\nMusic Streaming"]:::svc
    end

    %% *ARR SUITE
    subgraph ArrSuite["*arr Suite (Media Management)"]
        PROWLARR["Prowlarr\nIndexer"]:::svc
        QBT["qBittorrent\nDownloader"]:::svc
        RAD["Radarr\nMovies"]:::svc
        SON["Sonarr\nTV Shows"]:::svc
        LID["Lidarr\nMusic"]:::svc
        BAZ["Bazarr\nSubtitles"]:::svc
    end

    %% AI STACK (on GPU Worker)
    subgraph AIStack["AI Services (GPU Worker)"]
        VL["vLLM\nInference"]:::svc
        LLAMA_CPP["llama.cpp\nLLM Inference"]:::svc
        LITELLM["LiteLLM\nGateway"]:::svc
        OWEBUI["OpenWebUI\nChat UI"]:::svc
    end

    %% OTHER APPLICATIONS
    subgraph OtherApps["Other Applications"]
        HA["Home Assistant"]:::svc
        N8N["n8n\nWorkflow"]:::svc
        SYNCT["Syncthing\nFile Sync"]:::svc
        GRIM["Grimmory\nLibrary Mgmt"]:::svc
        MINIQR["Mini QR\nGenerator"]:::svc
        LUKQ["Life in the UK Quiz"]:::svc
    end

    %% MONITORING & OBSERVABILITY
    subgraph Monitoring["Monitoring & Observability"]
        PROM["Prometheus + Grafana"]:::svc
        LOKI["Loki\nLogs"]:::svc
        ALLOY["Alloy\nOTEL Collector"]:::svc
    end

    %% OTHER SERVICES
    subgraph OtherSvc["Other Services"]
        MINECRAFT["Minecraft Server"]:::svc
        ZOTERO["Zotero WebDAV"]:::svc
        KARA["Karakeep\nCollection"]:::svc
    end

    %% CONNECTIONS - Application Data Flow
    TRAFIK --> AB
    TRAFIK --> CHROME
    TRAFIK --> ITTOOL
    TRAFIK --> TERMIX
    TRAFIK --> WHOAMI
    TRAFIK --> PORTFOLIO
    TRAFIK --> HOMEPAGE
    TRAFIK --> CFED
    TRAFIK --> HA
    TRAFIK --> N8N
    TRAFIK --> SYNCT
    TRAFIK --> GRIM
    TRAFIK --> MINIQR
    TRAFIK --> LUKQ
    TRAFIK --> IMMICH
    TRAFIK --> PAPERLESS
    TRAFIK --> JELLYFIN
    TRAFIK --> JELLYSEERR
    TRAFIK --> NAV
    TRAFIK --> OWEBUI
    TRAFIK --> MINECRAFT

    %% AI flow
    OWEBUI -->|"LLM API"\| LITELLM
    LITELLM --> VL
    LITELLM --> LLAMA_CPP

    %% *arr suite
    PROWLARR <-->|"indexer"\| QBT
    RAD <-->|"API"\| QBT
    SON <-->|"API"\| QBT
    LID <-->|"API"\| QBT
    RAD --> JELLYFIN
    SON --> JELLYFIN
    NAV --> JELLYFIN

    %% Database connections
    IMMICH -->|"PostgreSQL"\| CNPG
    PAPERLESS -->|"PostgreSQL"\| CNPG
    N8N -->|"PostgreSQL"\| CNPG
    IMMICH -->|"Redis"\| REDIS_I
    PAPERLESS -->|"Redis"\| REDIS_P

    %% Monitoring
    ALLOY -->|"OTEL"\| PROM
    LOKI -->|"logs"\| PROM

    classDef svc fill:#e8f5e9,stroke:#2e7d32,stroke-width:2px,color:#1b5e20;
    classDef db fill:#f3e5f5,stroke:#7b1fa2,stroke-width:2px,color:#4a148c;
```

I use k3s for setting up my HA Kubernetes cluster, with 3 Ubuntu VMs as Control nodes, and 1 Ubuntu VM GPU Worker Node. All VMs are provisioned from my Proxmox Cluster with currently 2 Mini PCs and 1 old gaming PC. I chose k3s as it is a lightweight Kubernetes distribution and I can spin up more VMs for node replacement easily from my PVE cluster if it needs more resources.

My most recent addition to the cluster is a GPU node with a low-mid tier consumer graphics card (RTX5060 Ti). It allows me to schedule GPU workload such as local LLM inferencing server, or lightweight model training. With the current configuration, I can easily add more GPU nodes and scale out & up my private LLM inferencing service for AI workflows and Agentic Coding concurrently with my own resources.

## Services

### Applications

|                                                                            Logo                                                                            | Name                                                                  | Description                                                 |
| :--------------------------------------------------------------------------------------------------------------------------------------------------------: | --------------------------------------------------------------------- | ----------------------------------------------------------- |
|              <img src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/actual-budget.png" alt="Actual Budget Logo" height="32"/>               | [Actual Budget](https://github.com/actualbudget/actual)               | Personal finance management                                 |
|                             <img src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/commafeed.svg" height="32"/>                             | [Commafeed](https://github.com/Athou/commafeed)                       | RSS reader                                                  |
|                     <img src="https://chroma.thefamiliarsite.com/assets/img/logos/chromewebstore/175.png" alt="Chrome" height="32"/>                      | [Chrome](https://www.google.com/chrome/)                              | Browser for internal web browsing                           |
|                             <img src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/home-assistant.svg" height="32"/>                        | [Home Assistant](https://www.home-assistant.io/)                      | Home automation platform                                    |
|                               <img src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/homepage-light.png" height="32"/>                      | [Homepage](https://github.com/gethomepage/homepage)                   | Customizable home page / dashboard                          |
|                                                                                                                                                            | [Grimmory](https://github.com/grimmory-tools/grimmory)                | Self-hosted digital library management                      |
|                  <img src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/it-tools-light.png" alt="IT-Tools" height="32" />                   | [IT-Tools](https://github.com/CorentinTh/it-tools)                    | Collection of handy online tools for developers             |
|                              <img src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/immich.png" height="32"/>                               | [Immich](https://github.com/immich-app/immich)                        | High performance self-hosted photo and video management     |
|                                                                                                            | [Life in the UK Quiz](https://github.com/)                            | Custom quiz app for Life in the UK citizenship test         |
|                                      <img src="https://docs.mini-qr.com/assets/images/logo.svg" height="32"/>                                                | [Mini QR](https://github.com/mini-qr/)                                | Lightweight QR code generator                               |
|                             <img src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/karakeep.png" height="32"/>                              | [Karakeep](https://github.com/karakeep/karakeep)                      | Digital collection organizer                                |
|                                 <img src="https://minecraft.wiki/images/Minecraft_franchise_logo.svg?59f89" height="32"/>                                  | [Minecraft Server](https://github.com/itzg/minecraft-server-charts)   | Game server for Minecraft                                   |
|                                                                                                                                                            | [Media Services (\*arr)](https://github.com/Ravencentric/awesome-arr) | A suite of applications for my media collection management. |
|                             <img src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/navidrome.png" height="32"/>                             | [Navidrome](https://github.com/navidrome/navidrome)                   | Music streaming server                                      |
|                                <img src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/n8n.png" height="32"/>                                | [n8n](https://n8n.io/)                                                | Workflow automation tool                                    |
|                           <img src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/paperless-ngx.png" height="32"/>                           | [Paperless-ngx](https://github.com/paperless-ngx/paperless-ngx)       | Document management system                                  |
|                                                                                                            | [Portfolio](https://github.com/)                                      | Personal portfolio website (self-hosted)                    |
|                              <img src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/zotero.png" height="32"/>                               | [Zotero WebDAV](https://github.com/danuk/k8s-webdav)                  | Database for my Zotero Research Paper Reader                |
|                                                                                                                                                            | [Termix](https://github.com/termux/)                                  | Terminal emulator and SSH client for mobile                 |
|                               <img src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/whoami.svg" height="32"/>                              | [Whoami](https://github.com/antonz/whoami)                            | Simple HTTP service for debugging                           |
|                     <img src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/syncthing.png" alt="Syncthing" height="32"/>                     | [Syncthing](https://syncthing.net/)                                   | Continuous file synchronization                             |

### AI

|                                                    Logo                                                    | Name                                                   | Description                                                                |
| :--------------------------------------------------------------------------------------------------------: | ------------------------------------------------------ | -------------------------------------------------------------------------- |
|       <img src="https://docs.vllm.ai/en/latest/assets/logos/vllm-logo-text-dark.png" height="32" />        | [vLLM](https://github.com/vllm-project/vllm)           | High-throughput and memory-efficient inference and serving engine for LLMs |
|                                                                                                            | [llama.cpp](https://github.com/ggerganov/llama2.cpp)   | LLM inference in C/C++                                                     |
|     <img src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/litlellm.png" height="32" />     | [LiteLLM](https://github.com/BerriAI/litellm)          | LLM Gateway for local LLM servers & other cloud providers.                 |
|                                                                                                            | [OpenCode](https://opencode.ai/docs/web/)              | Browser-based remote coding agent server (runs on Proxmox VM opencode-1)  |
| <img src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/open-webui-light.png" height="32" /> | [Open WebUI](https://github.com/open-webui/open-webui) | Frontend Chat interface connected to LiteLLM                               |

### Infrastructure

|                                                                      Logo                                                                      | Name                                                                      | Description                                         |
| :--------------------------------------------------------------------------------------------------------------------------------------------: | ------------------------------------------------------------------------- | --------------------------------------------------- |
|             <img src="https://github.com/traefik/traefik/raw/master/docs/content/assets/img/traefik.logo-dark.png" height="32" />              | [Traefik](https://github.com/traefik/traefik)                             | Ingress Controller for Kubernetes workloads         |
|                              <img src="https://developers.cloudflare.com/_astro/logo.DAG2yejx.svg" height="32" />                              | [Cloudflare Tunnel](https://github.com/cloudflare/cloudflared)            | Zero Trust Tunnel to expose services publicly       |
|              <img src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/haproxy.png" alt="HAProxy" height="32"/>                   | [HAProxy](https://www.haproxy.org/)                                       | L4 load balancer & SSL termination (3 VMs on Proxmox)|
|            <img src="https://www.pi-holes.com/assets/images/logo.svg" height="32" alt="Pi-hole">                                               | [Pi-hole](https://pi-hole.net/)                                           | Network-wide ad blocking DNS (2 VMs on Proxmox)     |
| <img src="https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/_static/nvidia-logo-horiz-rgb-wht-for-screen.svg" height="32" /> | [GPU Operator](https://github.com/NVIDIA/gpu-operator)                    | NVIDIA runtime class manager for AI/ML workloads    |
|                     <img src="https://github.com/cert-manager/cert-manager/raw/master/logo/logo-small.png" height="32" />                      | [Cert Manager](https://github.com/cert-manager/cert-manager)              | Automated X.509 certificate management              |
|                            <img src="https://external-secrets.io/latest/pictures/eso-round-logo.svg" height="32" />                            | [External Secrets Operator](https://external-secrets.io/latest/)          | External secrets in Azure Key Vault                 |
|                                    <img src="https://cloudnative-pg.io/logo/large_logo.svg" height="32" />                                     | [CloudNativePG](https://github.com/cloudnative-pg/cloudnative-pg)         | PostgreSQL DB Cluster for other applications        |
|                           <img src="https://www.synology.com/img/company/branding/synology_logo.jpg" height="32" />                            | [Synology NAS](https://www.synology.com/)                                 | File server & CSI Persistent Volume Provisioner     |

### Monitoring & Observability

|                                                                                                                                 Logo                                                                                                                                  | Name                                                                                                                | Description                                                                |
| :-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------: | ------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------- |
| <img src="https://avatars.githubusercontent.com/u/66682517?s=48&v=4" height="32" /> <img src="https://avatars.githubusercontent.com/u/7195757?s=48&v=4" height="32"/> <img src="https://prometheus.io/_next/static/media/prometheus-logo.7aa022e5.svg" height="32" /> | [kube-prometheus-stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack) | Out-of-the-box monitoring solution: Prometheus, Grafana, and Alertmanager. |
|                                                                                   <img src="https://github.com/grafana/loki/raw/main/docs/sources/logo_and_name.png" height="32" />                                                                                   | [Loki](https://github.com/grafana/loki)                                                                             | Prometheus, but for logs                                                   |
|                                                                    <img src="https://github.com/grafana/alloy/raw/main/docs/sources/assets/logo_alloy_light.svg#gh-dark-mode-only" height="32" />                                                                     | [Alloy](https://github.com/grafana/alloy)                                                                           | OpenTelemetry Collector                                                    |

