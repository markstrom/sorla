#!/usr/bin/env bash
# Deploys site/ as static assets to Cloudflare (Worker "sorla", sorla.zerolabs.se).
set -euo pipefail
cd "$(dirname "$0")/.."
npx --yes wrangler@latest deploy
