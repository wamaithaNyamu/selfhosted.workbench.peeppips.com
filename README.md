<div align="center">
  <h1>🚀 PeepPips AI Workbench</h1>
  <p>The ultimate self-hosted algorithmic trading and AI workbench.</p>
</div>

---

## What is PeepPips AI Workbench?
PeepPips AI Workbench is a professional-grade, self-hosted infrastructure suite designed for algorithmic trading, backtesting, and AI-driven market analysis. 

This repository contains the deployment scripts and Docker Compose configurations required to instantly spin up your private instance of the Workbench on your own infrastructure. Our proprietary services are distributed as pre-built Docker containers via the GitHub Container Registry.

> **Note:** A valid License Key is required to run this software. You can acquire a license at [peeppips.com](https://peeppips.com).

---

## ⚡ Streamlined Installation (Recommended)

To install or upgrade your Workbench, you only need to run a single command on your Linux server. 

```bash
curl -sL https://get.peeppips.org/install.sh -o /tmp/install.sh && sudo bash /tmp/install.sh
```

*The script will securely prompt you to paste your License Key during the installation process so that it is never exposed to the system logs.*

**What this script does securely behind the scenes:**
1. Verifies your license cryptographically with our central server.
2. Generates ultra-secure randomized passwords for Postgres, Redis, and internal services.
3. Provisions a secure Cloudflare Tunnel to expose your Workbench UI to the internet securely.
4. Pulls the latest stable production images from our container registry.
5. Boots up your entire infrastructure seamlessly.

*Your `.env` file containing all generated passwords and encryption keys will be saved in `/opt/peeppips-workbench`. Do not lose this file!*

---

## 🛠 Manual Installation

If you prefer to inspect the configuration and install manually, you can clone this repository:

```bash
git clone [https://github.com/wamaithaNyamu/selfhosted.workbench.peeppips.com.git](https://github.com/wamaithaNyamu/selfhosted.workbench.peeppips.com.git) /opt/peeppips-workbench
cd /opt/peeppips-workbench
```

You can then run the installation script locally. It will prompt you securely for your license key:
```bash
sudo ./install.sh
```

---

## 🔄 Updating Your Workbench

Updating your Workbench to the latest production release is entirely frictionless. You have three options:

### Option 1: 1-Click Update (Recommended)
You can seamlessly update your Workbench by clicking the **Update** button directly within the Workbench frontend UI. This will automatically pull the latest images and restart your services.

### Option 2: Re-run the install script
Simply re-run your original install command. The script will detect your existing `.env` file, safely preserve all your databases and passwords, prompt for your key (if not already saved in the `.env`), pull the latest images, and reboot your containers.
```bash
curl -sL https://get.peeppips.org/install.sh -o /tmp/install.sh && sudo bash /tmp/install.sh
```

### Option 3: Pure Docker Pull
If you want to manually update via Docker:
```bash
cd /opt/peeppips-workbench
docker compose -f docker-compose.prod.yml pull
docker compose -f docker-compose.prod.yml up -d
```

---

## 🏗 Architecture Overview

When deployed, the Workbench spins up the following stack:
* **Frontend**: Next.js UI dashboard
* **Server**: High-performance Go backend
* **Database**: PostgreSQL (Timescale/PGVector ready)
* **Cache**: Redis
* **Runners**: MetaTrader 5 (MT5) wrapped in a headless Wine + Python environment for execution
* **Ingress**: Cloudflare Tunnel (`cloudflared`) for secure Zero-Trust web access

## 🔒 Security & Telemetry
PeepPips is built with a strict Zero-Knowledge architecture. Your strategies, trading algorithms, ML models, and API keys remain completely encrypted on your self-hosted machine using a locally generated `CREDENTIALS_ENCRYPTION_KEY`. We do not have access to your data, your broker accounts, or your trades.

---

<div align="center">
  <p>Need help? Reach out to <b>support@peeppips.com</b> or visit <a href="https://peeppips.com">peeppips.com</a>.</p>
</div>