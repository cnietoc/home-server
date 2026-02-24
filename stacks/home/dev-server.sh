#!/bin/bash

# Script para probar el dashboard localmente
# Útil para desarrollo y debugging

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

echo "🏠 Iniciando Dashboard del Home Server en modo desarrollo"
echo ""

# Verificar si Node.js está instalado
if ! command -v node >/dev/null 2>&1; then
    echo "❌ Node.js no está instalado"
    echo "   Instálalo desde: https://nodejs.org/"
    exit 1
fi

# Verificar si npm está disponible
if ! command -v npm >/dev/null 2>&1; then
    echo "❌ npm no está disponible"
    exit 1
fi

# Instalar dependencias si no existen
if [[ ! -d "node_modules" ]]; then
    echo "📦 Instalando dependencias..."
    npm install
fi

# Variables de entorno para desarrollo local
export NODE_ENV=development
export PORT=3000

echo "🚀 Iniciando servidor en modo desarrollo..."
echo "   📍 URL: http://localhost:3000"
echo "   🔧 Modo: desarrollo"
echo "   ⏹️  Ctrl+C para detener"
echo ""

# Iniciar servidor
npm run dev 2>/dev/null || npm start
