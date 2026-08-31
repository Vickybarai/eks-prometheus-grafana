# 📊 Prometheus & Grafana: Complete Observability Guide

## 🔗 Repository
**All scripts & configurations:** [https://github.com/Vickybarai/all-setups.git](https://github.com/Vickybarai/all-setups.git)

**Script Path:** `Ubuntu PGN/` → `prometheus.sh` · `grafana.sh` · `node_exporter.sh`

---


## 📑 Table of Contents

- [1. Why Monitoring?](#1-why-monitoring)
- [2. The Big Picture — Architecture](#2-the-big-picture--architecture)
- [3. Core Components](#3-core-components)
- [4. Prerequisites & Security Groups](#4-prerequisites--security-groups)
- [5. STEP 1 — Worker Node Setup (Node Exporter)](#5-step-1--worker-node-setup-node-exporter)
- [6. STEP 2 — Monitoring Server Setup (Prometheus + Grafana)](#6-step-2--monitoring-server-setup-prometheus--grafana)
- [7. STEP 3 — Connect Worker Node to Prometheus](#7-step-3--connect-worker-node-to-prometheus)
- [8. STEP 4 — PromQL Queries & Dashboard Navigation](#8-step-4--promql-queries--dashboard-navigation)
- [9. STEP 5 — Understanding prometheus.yml (Deep Dive)](#9-step-5--understanding-prometheusyml-deep-dive)
- [10. STEP 6 — Grafana: Data Source → Import Dashboards](#10-step-6--grafana-data-source--import-dashboards)
- [11. STEP 7 — Dashboard Panel Walkthrough](#11-step-7--dashboard-panel-walkthrough)
- [12. STEP 8 — Stress Testing Your Dashboard](#12-step-8--stress-testing-your-dashboard)
- [13. STEP 9 — EC2 Service Discovery (Auto-Registration)](#13-step-9--ec2-service-discovery-auto-registration)
- [14. STEP 10 — Grafana User Management (RBAC)](#10-step-10--grafana-user-management-rbac)
- [15. STEP 11 — Alert Manager + Slack Integration](#11-step-11--alert-manager--slack-integration)
- [16. STEP 12 — Push Gateway (Short-Lived Jobs)](#12-step-12--push-gateway-short-lived-jobs)
- [17. Complete Architecture Recap](#17-complete-architecture-recap)
- [18. Quick Reference Cheat Sheet](#18-quick-reference-cheat-sheet)
- [19. Troubleshooting](#19-troubleshooting)

---

## 1. Why Monitoring?

### 🍛 The Swiggy Analogy (From the Lecture)

```
You open Swiggy → Find mutton biryani for ₹100 (normally ₹400+)
    │
    ├── You add to cart
    ├── You tell 3 friends
    ├── Those 3 tell 9 more people
    ├── It goes viral on WhatsApp channels
    └── Millions of people flood the server simultaneously
                    │
                    ▼
            💥 SERVER CRASHES
```

### Without Monitoring vs With Monitoring

| Scenario | Without Monitoring | With Monitoring |
|---|---|---|
| Load increases | ❌ Nobody knows | ✅ Alert fires immediately |
| Server crashes | ❌ Users report it | ✅ You already know + auto-scale |
| Response time | ❌ Unknown | ✅ Tracked per request |
| Root cause | ❌ Manual investigation | ✅ Metrics point to exact issue |

### What Are Metrics?

```
Human Body Metrics          →    Server Metrics
─────────────────────        →    ─────────────────────
Age                         →    Uptime
Height / Weight             →    CPU / RAM utilization
Blood Pressure              →    Disk I/O rate
Heart Rate                  →    Requests per second
Temperature                 →    CPU temperature
```

**Metrics = CPU, RAM, Disk, Network traffic, Latency, Request/Response counts**

---

## 2. The Big Picture — Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        PROMETHEUS & GRAFANA ARCHITECTURE                     │
│                                                                              │
│  ┌─────────────────────────── WORKER NODES ───────────────────────────┐      │
│  │                                                                     │      │
│  │  ┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐     │      │
│  │  │ Web Srv 1│    │ Web Srv 2│    │ Web Srv 3│    │   ...    │     │      │
│  │  │ Apache   │    │ Apache   │    │ Apache   │    │          │     │      │
│  │  │ :80      │    │ :80      │    │ :80      │    │          │     │      │
│  │  │          │    │          │    │          │    │          │     │      │
│  │  │ Node Exp │    │ Node Exp │    │ Node Exp │    │ Node Exp │     │      │
│  │  │ :9100 ───┼────┼──:9100 ──┼────┼──:9100 ──┼────┼──:9100 ──┼─┐   │      │
│  │  └──────────┘    └──────────┘    └──────────┘    └──────────┘ │   │      │
│  └────────────────────────────────────────────────────────────────┼───┘      │
│                                                                   │          │
│  ┌─────────────────────────── SHORT-LIVED JOBS ──────────────────┐ │          │
│  │  Backup Job (10 sec) ──→ Push Gateway :9091 ─────────────────┼─┤          │
│  │  Cron Jobs           ──→ Push Gateway :9091 ─────────────────┘ │          │
│  └────────────────────────────────────────────────────────────────┘          │
│                                                                   │          │
│  ┌──────────────────── MONITORING SERVER ──────────────────────────┐          │
│  │                      ▼                                          │          │
│  │  ┌─────────────────────────────────────────┐                    │          │
│  │  │            PROMETHEUS :9090             │                    │          │
│  │  │  ┌───────────┐  ┌──────────────────┐    │                    │          │
│  │  │  │ Retrieval │  │  TSDB (30GB max) │    │                    │          │
│  │  │  │ (Pull)    │→ │  Time Series DB   │    │                    │          │
│  │  │  └───────────┘  └────────┬─────────┘    │                    │          │
│  │  │         ↑                │               │                    │          │
│  │  │         │           ┌────▼────┐          │                    │          │
│  │  │   Service Discovery  │ PromQL  │          │                    │          │
│  │  │   (EC2/K8s/DNS)     └────┬────┘          │                    │          │
│  │  │                            │               │                    │          │
│  │  │  ┌─────────────────────────┼───────────┐  │                    │          │
│  │  │  │      HTTP Server                   │  │                    │          │
│  │  │  └───┬─────────────────────┬──────────┘  │                    │          │
│  │  └──────┼─────────────────────┼─────────────┘                    │          │
│  │         │                     │                                  │          │
│  │         ▼                     ▼                                  │          │
│  │  ┌──────────────┐    ┌────────────────┐                         │          │
│  │  │   GRAFANA    │    │ ALERT MANAGER  │                         │          │
│  │  │   :3000      │    │    :9093       │                         │          │
│  │  │              │    │                │                         │          │
│  │  │ Dashboards   │    │  ┌──────────┐  │                         │          │
│  │  │ Visualizations│   │  │ Routes   │  │                         │          │
│  │  │ RBAC Users   │    │  └────┬─────┘  │                         │          │
│  │  └──────────────┘    │       │        │                         │          │
│  │                      │  ┌────▼─────┐  │                         │          │
│  │                      │  │Receivers │  │                         │          │
│  │                      │  │- Slack   │  │                         │          │
│  │                      │  │- Email   │  │                         │          │
│  │                      │  │- PagerDuty│  │                         │          │
│  │                      │  └──────────┘  │                         │          │
│  │                      └────────────────┘                         │          │
│  └─────────────────────────────────────────────────────────────────┘          │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Data Flow Summary

```
Node Exporter (collects) ──→ Prometheus (pulls & stores in TSDB) ──→ Grafana (visualizes)
                              │
                              ├── PromQL queries the TSDB
                              ├── HTTP Server exposes data
                              └── Alert Manager sends notifications

Push Gateway (collects short-lived) ──→ Prometheus (pulls) ──→ same flow

Service Discovery (auto-adds new VMs) ──→ Prometheus targets
```

---

## 3. Core Components

| Component | Port | Where Installed | Purpose | Stores Data? |
|---|---|---|---|---|
| **Node Exporter** | 9100 | Every Worker Node | Collects hardware/OS metrics | ❌ No (captures only) |
| **Prometheus** | 9090 | Monitoring Server | Pulls metrics, stores in TSDB, runs PromQL | ✅ TSDB (30GB default) |
| **Grafana** | 3000 | Monitoring Server | Visualizes data as dashboards | ❌ No (reads from Prometheus) |
| **Alert Manager** | 9093 | Monitoring Server | Triggers alerts to Slack/Email/PagerDuty | ❌ No |
| **Push Gateway** | 9091 | Monitoring Server (Docker) | Collects metrics from short-lived jobs | ❌ Temporary |

### Key Concepts

```
TSDB (Time Series Database):
┌──────────────┬─────────────────┬─────────┐
│  Timestamp   │     Metric      │  Value  │
├──────────────┼─────────────────┼─────────┤
│  09:00:00    │ cpu_usage       │  45%    │
│  09:00:15    │ cpu_usage       │  47%    │
│  09:00:30    │ cpu_usage       │  52%    │
│  09:00:45    │ cpu_usage       │  91% ⚠️ │
└──────────────┴─────────────────┴─────────┘
  ↑ Every 15 seconds (default), a new row is added

PromQL = Prometheus Query Language (like SQL but for time-series data)

Targets = The servers you are monitoring (shown in Prometheus → Status → Targets)
```

> **⚠️ Critical for SRE roles.** For DevOps it's important, but for SRE this is the **core** skill.

---

## 4. Prerequisites & Security Groups

### AWS EC2 Instances Needed

| Instance | Purpose | Type | Ports to Open |
|---|---|---|---|
| **Worker Node** | Runs your app + Node Exporter | t2/t3 Micro | 22, 80, 9100 |
| **Monitoring Server** | Runs Prometheus + Grafana + Alert Manager | t2/t3 Medium (recommended) | 22, 9090, 3000, 9093, 9091 |

### Security Group — Worker Node
```
┌─────────┬──────────┬─────────────────────────┐
│  Port   │ Protocol │         Source           │
├─────────┼──────────┼─────────────────────────┤
│   22    │   TCP    │  Your IP / Bastion      │
│   80    │   TCP    │  0.0.0.0/0              │
│  9100   │   TCP    │  Monitoring Server IP   │
└─────────┴──────────┴─────────────────────────┘
```

### Security Group — Monitoring Server
```
┌─────────┬──────────┬─────────────────────────┐
│  Port   │ Protocol │         Source           │
├─────────┼──────────┼─────────────────────────┤
│   22    │   TCP    │  Your IP / Bastion      │
│  9090   │   TCP    │  Your IP                │
│  3000   │   TCP    │  Your IP                │
│  9093   │   TCP    │  Your IP                │
│  9091   │   TCP    │  Your IP                │
└─────────┴──────────┴─────────────────────────┘
```

---

## 5. STEP 1 — Worker Node Setup (Node Exporter)

> **Rule:** Node Exporter goes on EVERY server you want to monitor. If you have 100 servers → install on all 100.

### Navigation Flow
```
SSH into Worker Node
    │
    ├── git clone the repository
    ├── cd into Ubuntu PGN/
    ├── chmod +x node_exporter.sh
    ├── ./node_exporter.sh          (takes ~15 seconds)
    │
    └── Verify: http://<worker-ip>:9100/metrics
```

### Commands
```bash
# SSH into your worker node
ssh -i your-key.pem ubuntu@<worker-public-ip>

# Clone the repository
git clone https://github.com/Vickybarai/all-setups.git
cd all-setups/Ubuntu\ PGN/

# Install Node Exporter
chmod +x node_exporter.sh
./node_exporter.sh

# Verify service is running
systemctl status node_exporter
# Expected: Active: active (running)
```

### Browser Verification
```
Open: http://<worker-public-ip>:9100/metrics

You should see hundreds of lines like:
  # HELP node_cpu_seconds_total Seconds the CPUs spent in each mode.
  # TYPE node_cpu_seconds_total counter
  node_cpu_seconds_total{cpu="0",mode="idle"} 12345.67
  node_cpu_seconds_total{cpu="0",mode="user"} 234.56
  ...

✅ If you see metrics → Node Exporter is WORKING
❌ If page doesn't load → Check security group port 9100
```

> **Key Point:** Node Exporter captures ALL metrics by default. No configuration needed. But it **cannot store** data — it only collects.

---

## 6. STEP 2 — Monitoring Server Setup (Prometheus + Grafana)

> **Rule:** Prometheus, Grafana, and Alert Manager ALL go on the Monitoring Server. Node Exporter on the monitoring server is **not required** (but harmless if installed).

### Navigation Flow
```
SSH into Monitoring Server
    │
    ├── git clone the repository
    ├── cd into Ubuntu PGN/
    │
    ├── Install Prometheus:  chmod +x prometheus.sh && ./prometheus.sh
    ├── Install Grafana:     chmod +x grafana.sh && ./grafana.sh
    │
    ├── Verify Prometheus:  http://<monitor-ip>:9090
    └── Verify Grafana:     http://<monitor-ip>:3000  (admin/admin)
```

### Commands
```bash
# SSH into monitoring server
ssh -i your-key.pem ubuntu@<monitoring-public-ip>

# Clone the repository
git clone https://github.com/Vickybarai/all-setups.git
cd all-setets/Ubuntu\ PGN/

# Install Prometheus (~15 seconds)
chmod +x prometheus.sh
./prometheus.sh

# Install Grafana (~15 seconds)
chmod +x grafana.sh
./grafana.sh

# Verify both services
systemctl status prometheus     # Active: active (running)
systemctl status grafana-server # Active: active (running)
```

### Browser Verification

**Prometheus Dashboard:**
```
Open: http://<monitoring-public-ip>:9090

You should see:
  ┌─────────────────────────────────────────────┐
  │  Prometheus                                 │
  │  ┌─────────────────────────────────────┐    │
  │  │  [Execute]  Graph  Table  Console   │    │
  │  │  ┌─────────────────────────────┐    │    │
  │  │  │  up                         │    │    │
  │  │  └─────────────────────────────┘    │    │
  │  └─────────────────────────────────────┘    │
  │                                              │
  │  Status → Targets → Configuration → TSDB     │
  └─────────────────────────────────────────────┘
```

**Grafana Dashboard:**
```
Open: http://<monitoring-public-ip>:3000

Login:
  Username: admin
  Password: admin

  → It will ask to change password (you can skip)

You should see the Grafana home page with:
  Dashboards · Explore · Alerting · Connections (Data Sources)
```

---

## 7. STEP 3 — Connect Worker Node to Prometheus

> **This is the MOST CRITICAL step.** Without this, Prometheus has nothing to monitor.

### The Problem
```
BEFORE:  Prometheus: "I'm running but monitoring nothing 😴"
         Node Exporter: "I'm collecting metrics but nobody asks 📦"

AFTER:   Prometheus: "I'm pulling metrics from Worker Node every 15s 📊"
         Node Exporter: "Here are the metrics! 📤"
```

### Navigation Flow
```
On Monitoring Server
    │
    ├── Open config: sudo nano /etc/prometheus/prometheus.yml
    ├── Add worker node IP:9100 under scrape_configs
    ├── Save file (Ctrl+O → Enter → Ctrl+X)
    ├── Restart: sudo systemctl restart prometheus
    ├── Verify: systemctl status prometheus
    │
    └── Browser: Prometheus → Status → Targets → Should show "UP"
```

### Step-by-Step

**7a. Open the config file:**
```bash
sudo nano /etc/prometheus/prometheus.yml
```

**7b. Edit the file to add your worker node:**
```yaml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: "prometheus"
    static_configs:
      - targets: ["localhost:9090"]

  # 👇 ADD THIS BLOCK 👇
  - job_name: "web-server"
    static_configs:
      - targets: ["<WORKER_NODE_PUBLIC_IP>:9100"]
```
> ⚠️ Replace `<WORKER_NODE_PUBLIC_IP>` with your actual IP (e.g., `54.123.45.67:9100`)

**7c. Save and restart:**
```bash
sudo systemctl restart prometheus
systemctl status prometheus
# Must show: Active: active (running)
# If it shows "failed" → YAML indentation error! Fix with ChatGPT.
```

**7d. Verify in Browser:**
```
Prometheus UI (http://<monitor-ip>:9090)
    │
    ├── Click "Status" (top navigation bar)
    ├── Click "Targets"
    │
    └── You should see:
        ┌─────────────────┬────────────────────────────┬─────────┐
        │   Endpoint      │          State             │  Health  │
        ├─────────────────┼────────────────────────────┼─────────┤
        │ prometheus      │ http://localhost:9090       │   UP    │
        │ web-server      │ http://54.123.45.67:9100   │   UP ✅ │
        └─────────────────┴────────────────────────────┴─────────┘
```

**Quick verification with PromQL:**
```
In Prometheus search bar, type:  up
Click: Execute

Result:
  up{instance="localhost:9090", job="prometheus"}       1
  up{instance="54.123.45.67:9100", job="web-server"}   1
                                                     ↑
                                              1 = UP, 0 = DOWN
```

---

## 8. STEP 4 — PromQL Queries & Dashboard Navigation

> **"You don't need to memorize queries. Everything is on Google. Just understand WHAT to run and WHAT NOT to run."**

### Prometheus UI Navigation Map
```
┌──────────────────────────────────────────────────────────────────┐
│  PROMETHEUS UI — http://<ip>:9090                               │
│                                                                   │
│  Top Bar:                                                         │
│  ┌─────────┬─────────┬─────────┬──────────┬──────────────────┐   │
│  │  Graph  │  Table  │ Console │  Alerts  │     Status ▼     │   │
│  └─────────┴─────────┴─────────┴──────────┴──────┬───────────┘   │
│                                                 │               │
│                                    ┌────────────┼──────────┐    │
│                                    │ Runtime    │ Targets   │    │
│                                    │ TSDB Status│ Config    │    │
│                                    │ Flags      │ Service   │    │
│                                    │            │ Discovery │    │
│                                    └────────────┴──────────┘    │
│                                                                   │
│  Query Bar:                                                       │
│  ┌────────────────────────────────────────┐  ┌─────────┐        │
│  │  type query here...                    │  │ Execute │        │
│  └────────────────────────────────────────┘  └─────────┘        │
│                                                                   │
│  Result Area:  (switch between Graph / Table tabs)                │
│  ┌──────────────────────────────────────────────────────────┐    │
│  │                                                          │    │
│  │  [Chart visualization or table data appears here]        │    │
│  │                                                          │    │
│  └──────────────────────────────────────────────────────────┘    │
│                                                                   │
│  Time Controls (top-right):                                      │
│  [Last 1 hour ▼]  [Auto-refresh: Off ▼]  [Zoom In/Out]          │
└──────────────────────────────────────────────────────────────────┘
```

### Essential Queries (Try Each One)

#### ✅ Query 1: Which Servers Are Up?
```promql
up
```
**Tab:** Table | **Result:** List of all targets with `1` (up) or `0` (down)

#### ✅ Query 2: CPU Information
```promql
node_cpu_seconds_total
```
**Tab:** Table | **Result:** CPU time per mode (idle, user, system, iowait) per CPU core

#### ✅ Query 3: CPU Utilization %
```promql
100 - (avg by(instance) (irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)
```
**Tab:** Graph | **Tip:** Change time range to "Last 5 minutes" to see live data

#### ✅ Query 4: Free Memory (Bytes)
```promql
node_memory_MemAvailable_bytes
```
**Tab:** Table | **Result:** Available RAM in bytes

#### ✅ Query 5: Memory Usage %
```promql
(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100
```
**Tab:** Graph

#### ✅ Query 6: HTTP Request Count (Total)
```promql
promhttp_metric_handler_requests_t