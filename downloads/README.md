# Downloads Folder

## Purpose
This folder contains the EdgeTelemetry deployment package that users will download from Step 4 of the deployment wizard.

## Setup Instructions

1. **Place your deployment ZIP file here**
   - File name: `EdgeTelemetryDeployment.zip`
   - This should contain all deployment files (Docker Compose, scripts, configs, etc.)

2. **Update the deployment package**
   - Rebuild it from the deployment repo (tracked files only — never secrets or real .env):
     ```bash
     cd /path/to/EdgeTelemetryDeployment
     git archive --format=zip --prefix=EdgeTelemetryDeployment/ \
       -o /path/to/runbook/downloads/EdgeTelemetryDeployment.zip HEAD
     ```
   - No code changes needed - the wizard automatically serves the latest file

## File Structure
```
downloads/
├── README.md                          # This file
└── EdgeTelemetryDeployment.zip       # Your deployment package (add this)
```

## What to Include in the ZIP

Your `EdgeTelemetryDeployment.zip` should contain:
- Docker Compose files
- Environment configuration templates
- Deployment scripts (getstarted.sh, etc.)
- Nginx configuration templates
- Database migration scripts
- Service manifests
- Any other deployment dependencies

## Notes
- The wizard serves this file directly via HTTP
- No GitHub API or authentication required
- Works perfectly in locked client environments
- Users get instant downloads with no CORS issues
