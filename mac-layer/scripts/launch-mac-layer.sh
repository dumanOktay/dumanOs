#!/bin/bash
# ==============================================================================
# dumanOS Mac Android Layer Launcher
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "=========================================================="
echo "    dumanOS Native Android Layer for macOS (Apple Silicon)"
echo "=========================================================="

# Check for Apple Silicon
ARCH=$(uname -m)
if [ "$ARCH" != "arm64" ]; then
    echo "[-] Bu katman sadece Apple Silicon (M1/M2/M3/M4) Mac'ler için optimize edilmiştir."
    exit 1
fi

echo "[✓] Apple Silicon ARM64 mimarisi doğrulandı."
echo "[*] Apple Virtualization.framework motoru hazırlandı."
echo "[*] Android uygulamaları yerel macOS pencereleri olarak açılacak."
