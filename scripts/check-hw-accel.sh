#!/bin/bash
set -e

echo "=== Comprobando compatibilidad de aceleración por hardware ==="
echo

sudo apt update -qq
sudo apt install -y pciutils vainfo mesa-utils vdpauinfo hwinfo 2>/dev/null || true

echo "------------------------------------"
echo "🔍 GPU detectada:"
lspci | grep -Ei 'vga|3d|display'
echo "------------------------------------"
echo

# Intel Quick Sync Video
echo "🧠 Comprobando Intel Quick Sync (QSV)..."
if lspci | grep -qi "Intel"; then
    if command -v vainfo &>/dev/null; then
        echo "→ Ejecución de vainfo:"
        vainfo 2>/dev/null | grep -E "Driver version|Intel" || echo "vainfo no muestra soporte claro para QSV."
    else
        echo "vainfo no disponible."
    fi
    echo "✅ Es probable que tu CPU Intel tenga QSV si es de 2011 o posterior (serie Core)."
else
    echo "❌ No se detecta GPU Intel."
fi
echo

# NVIDIA NVENC
echo "🧠 Comprobando NVIDIA NVENC..."
if lspci | grep -qi "NVIDIA"; then
    echo "→ GPU NVIDIA detectada."
    if ! command -v nvidia-smi &>/dev/null; then
        echo "⚙️ Instalando herramientas NVIDIA (sin driver propietario todavía)..."
        sudo apt install -y nvidia-utils-535 2>/dev/null || echo "No se pudo instalar nvidia-utils, puede que no haya drivers disponibles."
    fi
    if command -v nvidia-smi &>/dev/null; then
        nvidia-smi --query-gpu=name,driver_version --format=csv,noheader
        echo "✅ Compatible con NVENC si aparece un modelo reciente (GTX 600 o superior)."
    else
        echo "❌ No se detecta soporte NVENC (falta driver o toolkit)."
    fi
else
    echo "❌ No se detecta GPU NVIDIA."
fi
echo

# AMD VAAPI
echo "🧠 Comprobando AMD VAAPI..."
if lspci | grep -qi "AMD"; then
    echo "→ GPU AMD detectada."
    if command -v vainfo &>/dev/null; then
        echo "→ Ejecución de vainfo:"
        vainfo 2>/dev/null | grep -E "Driver version|AMD" || echo "vainfo no muestra soporte VAAPI claro."
    fi
    echo "✅ Soporte VAAPI disponible en la mayoría de GPUs AMD desde 2014 (GCN 1.0+)."
else
    echo "❌ No se detecta GPU AMD."
fi

echo
echo "------------------------------------"
echo "✅ Comprobación completada."
echo "Revisa la salida anterior para ver qué tecnología puedes habilitar en Tdarr."
