#!/bin/bash
# sync-synology-crds.sh - Copy latest CRDs from synology-csi repo to homelab infra base
set -euo pipefail

SYNOLOGY_CSI_DIR="../synology-csi"
HOMELAB_BASE="./kubernetes/infra/synology-csi/base"
CSI_VERSION_DIR="deploy/kubernetes/v1.20"

echo "📥 Syncing Synology CSI CRDs from $SYNOLOGY_CSI_DIR/$CSI_VERSION_DIR to $HOMELAB_BASE"

# Ensure synology-csi repo exists and is on latest
if [[ ! -d "$SYNOLOGY_CSI_DIR" ]]; then
  echo "❌ synology-csi repo not found at $SYNOLOGY_CSI_DIR"
  echo "💡 Run: git clone https://github.com/SynologyOpenSource/synology-csi.git ../synology-csi"
  exit 1
fi

if [[ ! -d "$SYNOLOGY_CSI_DIR/$CSI_VERSION_DIR" ]]; then
  echo "❌ $CSI_VERSION_DIR not found in $SYNOLOGY_CSI_DIR"
  exit 1
fi

pushd "$SYNOLOGY_CSI_DIR" >/dev/null
git pull origin main
popd >/dev/null

# Create base dir if missing
mkdir -p "$HOMELAB_BASE"

UPDATED=false

# Copy core CSI manifests only if different
echo "🔍 Checking core manifests..."
if ls "$SYNOLOGY_CSI_DIR/$CSI_VERSION_DIR"/*.yml >/dev/null 2>&1; then
  for src in "$SYNOLOGY_CSI_DIR/$CSI_VERSION_DIR"/*.yml; do
    dest="$HOMELAB_BASE/$(basename "$src")"
    if [[ ! -f "$dest" || "$(diff -q "$src" "$dest" 2>/dev/null || echo 'diff')" != "Files "$src" and "$dest" differ" ]]; then
      cp -v "$src" "$dest"
      UPDATED=true
    else
      echo "✅ $(basename "$src") unchanged"
    fi
  done
fi

# Copy snapshotter CRDs only if different
echo "🔍 Checking snapshotter CRDs..."
mkdir -p "$HOMELAB_BASE/snapshotter"
if [[ -d "$SYNOLOGY_CSI_DIR/$CSI_VERSION_DIR/snapshotter" ]]; then
  for src in "$SYNOLOGY_CSI_DIR/$CSI_VERSION_DIR/snapshotter"/*.yml; do
    dest="$HOMELAB_BASE/snapshotter/$(basename "$src")"
    if [[ ! -f "$dest" || "$(diff -q "$src" "$dest" 2>/dev/null || echo 'diff')" != "Files "$src" and "$dest" differ" ]]; then
      cp -v "$src" "$dest"
      UPDATED=true
    else
      echo "✅ $(basename "$src") unchanged"
    fi
  done
else
  echo "⚠️  No snapshotter dir found, skipping"
fi

# Copy client-info template only if different
echo "🔍 Checking client-info template..."
src="$SYNOLOGY_CSI_DIR/config/client-info-template.yml"
if [[ -f "$src" ]]; then
  dest="$HOMELAB_BASE/client-info-template.yml"
  if [[ ! -f "$dest" || "$(diff -q "$src" "$dest" 2>/dev/null || echo 'diff')" != "Files "$src" and "$dest" differ" ]]; then
    cp -v "$src" "$dest"
    UPDATED=true
  else
    echo "✅ client-info-template.yml unchanged"
  fi
else
  echo "⚠️  client-info-template.yml not found, skipping"
fi

if [[ "$UPDATED" == "true" ]]; then
  echo "✅ Synced $(find "$HOMELAB_BASE" -name "*.yml" | wc -l) files to $HOMELAB_BASE (some updated)"
else
  echo "✅ No changes detected - all files up to date"
fi

echo "📋 Verify:"
ls -la "$HOMELAB_BASE/" "$HOMELAB_BASE/snapshotter/" 2>/dev/null || true
echo "🚀 Ready: kustomize build kubernetes/infra/synology-csi/overlays/default"

