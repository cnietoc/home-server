#!/bin/bash
# ==============================================
#  check_hw_accel.sh
#  Detecta compatibilidad con Intel QSV, NVIDIA NVENC y AMD VAAPI
#  Instala las herramientas necesarias si no existen
# ==============================================

echo "=== Comprobando e instalando dependencias necesarias ==="

# Actualiza índices de paquetes si hace falta
sudo apt update -qq

# Instala utilidades básicas
sudo apt install -y vainfo mesa-utils pciutils usbutils 2>/dev/null

# Si existe GPU NVIDIA, instala herramientas correspondientes
if lspci | grep -qi nvidia; then
    echo "→ GPU NVIDIA detectada, instalando utilidades..."
    sudo apt install -y nvidia-utils-535 nvidia-smi 2>/dev/null || echo "⚠️ No se pudo instalar nvidia-utils (ajusta versión del driver manualmente)."
fi

echo
echo "=== Comprobando compatibilidad de aceleración por hardware ==="
echo

# ----- INTEL QSV -----
if command -v vainfo >/dev/null 2>&1; then
    if vainfo 2>/dev/null | grep -qi "Intel"; then
        echo "✅ Intel Quick Sync Video (QSV) detectado a través de VAAPI."
        vainfo | grep -i "Intel" | head -n 3
    else
        echo "⚠️ VAAPI disponible, pero no parece haber soporte Intel QSV."
    fi
else
    echo "❌ 'vainfo' no está disponible, no se puede comprobar Intel/VAAPI."
fi

echo

# ----- NVIDIA NVENC -----
if command -v nvidia-smi >/dev/null 2>&1; then
    echo "✅ NVIDIA GPU detectada:"
    nvidia-smi --query-gpu=gpu_name,driver_version --format=csv,noheader
    echo "→ Para comprobar compatibilidad NVENC: https://developer.nvidia.com/video-encode-decode-gpu-support-matrix"
else
    if lspci | grep -qi nvidia; then
        echo "⚠️ GPU NVIDIA detectada en hardware, pero 'nvidia-smi' no disponible (controladores no instalados correctamente)."
    else
        echo "❌ No se detecta GPU NVIDIA."
    fi
fi

echo

# ----- AMD VAAPI -----
if command -v vainfo >/dev/null 2>&1; then
    if vainfo 2>/dev/null | grep -qi "AMD"; then
        echo "✅ GPU AMD con soporte VAAPI detectada."
        vainfo | grep -i "AMD" | head -n 3
    else
        echo "⚠️ VAAPI no muestra soporte AMD."
    fi
else
    echo "❌ 'vainfo' no instalado, no se puede comprobar VAAPI."
fi

echo
echo "=== Comprobación finalizada ==="
echo "Si alguna GPU no aparece correctamente, verifica los controladores o la versión del kernel."
