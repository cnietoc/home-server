#!/usr/bin/env bash

# Script de diagnóstico para yq
# Ayuda a identificar qué versión está instalada y si funciona correctamente

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
STACK_CONFIG="$PROJECT_ROOT/config/stacks.yml"

echo "🔍 Diagnóstico de yq"
echo "===================="
echo ""

# Verificar si yq está instalado
if command -v yq >/dev/null 2>&1; then
    echo "✅ yq está instalado"
    echo "   Ubicación: $(which yq)"
else
    echo "❌ yq NO está instalado"
    exit 1
fi

# Obtener versión
echo ""
echo "📋 Información de versión:"
yq --version 2>/dev/null || echo "❌ No se pudo obtener la versión"

# Verificar archivo de configuración
echo ""
echo "📁 Archivo de configuración:"
echo "   Ruta: $STACK_CONFIG"
if [[ -f "$STACK_CONFIG" ]]; then
    echo "   ✅ Archivo existe"
    echo "   Tamaño: $(ls -lh "$STACK_CONFIG" | awk '{print $5}')"
else
    echo "   ❌ Archivo NO existe"
    exit 1
fi

# Mostrar ayuda de yq para identificar versión
echo ""
echo "🛠️  Identificando versión por características:"
if yq --help 2>&1 | grep -q "yaml-output"; then
    echo "   🐍 Detectado: yq versión Python (jq wrapper)"
    YQ_VERSION="python"
elif yq --help 2>&1 | grep -q "eval"; then
    echo "   🐹 Detectado: yq versión Go (nativo YAML)"
    YQ_VERSION="go"
else
    echo "   ❓ Versión desconocida"
    YQ_VERSION="unknown"
fi

# Probar comandos básicos
echo ""
echo "🧪 Probando comandos:"

echo "   Prueba 1: Sintaxis Go (yq eval '.stacks' file)"
if yq eval '.stacks' "$STACK_CONFIG" >/dev/null 2>&1; then
    echo "   ✅ Funciona con sintaxis Go"
else
    echo "   ❌ NO funciona con sintaxis Go"
fi

echo "   Prueba 2: Sintaxis Python (yq '.stacks' file)"
if yq '.stacks' "$STACK_CONFIG" >/dev/null 2>&1; then
    echo "   ✅ Funciona con sintaxis Python"
else
    echo "   ❌ NO funciona con sintaxis Python"
fi

# Mostrar contenido del archivo YAML
echo ""
echo "📄 Contenido del archivo (primeras 10 líneas):"
head -10 "$STACK_CONFIG" | sed 's/^/   /'

echo ""
echo "🎯 Recomendación:"
case "$YQ_VERSION" in
    "python")
        echo "   Usar sintaxis: yq '.query' archivo.yml"
        echo "   Ejemplo: yq '.stacks | keys[]' config/stacks.yml"
        ;;
    "go")
        echo "   Usar sintaxis: yq eval '.query' archivo.yml"
        echo "   Ejemplo: yq eval '.stacks | keys | .[]' config/stacks.yml"
        ;;
    *)
        echo "   ❓ Versión no identificada claramente"
        echo "   Consulta la documentación específica de tu instalación"
        ;;
esac

# Probar comando específico que estaba fallando
echo ""
echo "🎯 Prueba específica del comando problemático:"
echo "   Comando: get_stack_config_files platform"

# Simular el comando que estaba fallando
if [[ "$YQ_VERSION" == "go" ]]; then
    result=$(yq eval ".stacks.platform.config_files | join(\",\")" "$STACK_CONFIG" 2>/dev/null)
    echo "   Resultado (Go): $result"
elif [[ "$YQ_VERSION" == "python" ]]; then
    result=$(yq ".stacks.platform.config_files[]" "$STACK_CONFIG" 2>/dev/null | sed 's/"//g' | tr '\n' ',' | sed 's/,$//')
    echo "   Resultado (Python): $result"
    echo "   Resultado esperado: cloudflare,auth,watchtower"
fi

echo ""
echo "✨ Diagnóstico completado"
