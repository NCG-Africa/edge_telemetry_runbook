# EdgeTelemetry Interactive Deployment Guide

A single-file interactive HTML guide for deploying EdgeTelemetry on Linux (Ubuntu/Debian, RHEL/Rocky/Alma/CentOS/Fedora, SLES/openSUSE). Built with Material You Dark design system, progressive step unlocking, and GitHub integration.

## Features

- 🎯 **Progressive Step Unlocking** — Steps unlock sequentially to prevent skipping prerequisites
- 📦 **GitHub Integration** — Direct ZIP download from `NCG-Africa/EdgeTelemetryDeployment` master branch
- ⚙️ **Interactive .env Builder** — Form-based configuration with live preview
- 📋 **One-Click Copy** — All commands copyable with visual feedback
- 🎨 **Material You Dark** — Professional dark theme with green accents
- 🚀 **Zero Dependencies** — Pure client-side HTML/CSS/JavaScript, no backend required
- 📱 **Mobile Responsive** — Works on screens as small as 375px

## Quick Start

### Local Development
```bash
cd /Users/mktowett/Development/Windsurf/edge-telemetry-deployment-webpage
python3 -m http.server 8000
```

Open: **http://localhost:8000**

### Production Deployment
Copy `index.html` to your web server and serve as a static file. Works with any static hosting (Nginx, Apache, Netlify, Vercel, etc.).

## User Guide

### GitHub Personal Access Token
Users need a GitHub PAT with `repo` scope to download the deployment package:

1. Visit: https://github.com/settings/tokens/new
2. Select scope: `repo` (full repository access)
3. Generate token
4. Paste into the guide's Step 2

**Note:** The token is never stored or transmitted anywhere except directly to GitHub's API.

## System Requirements

- Modern browser (Chrome 90+, Firefox 88+, Safari 14+)
- JavaScript enabled
- Clipboard API support (for copy buttons)

## Architecture

The guide walks users through deploying:
- **Telemetry Collector** (Port 8001) - Data ingestion API
- **Telemetry Processor** (Port 8002) - Data processing service
- **Dashboard API** (Port 8003) - Query API with Redis caching
- **EdgeRum Portal** (Port 8004) - Web dashboard frontend
- **Kafka** (Internal) - Message broker
- **Redis** (Port 6379) - Caching layer
- **Kafka UI** (Port 8080) - Monitoring interface

## Support

For issues with the deployment itself, refer to:
- [EdgeTelemetry Deployment Repository](https://github.com/NCG-Africa/EdgeTelemetryDeployment)
- Troubleshooting panels within the guide
- Make commands: `make help`, `make health`, `make logs`

## License

Internal use only - NCG Africa 
