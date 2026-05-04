#!/bin/bash

# Script to run the dashboard locally
# Useful for development and debugging

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

echo "🏠 Starting Home Server Dashboard in development mode"
echo ""

# Check if Node.js is installed
if ! command -v node >/dev/null 2>&1; then
    echo "❌ Node.js is not installed"
    echo "   Install it from: https://nodejs.org/"
    exit 1
fi

# Check if npm is available
if ! command -v npm >/dev/null 2>&1; then
    echo "❌ npm is not available"
    exit 1
fi

# Install dependencies if not present
if [[ ! -d "node_modules" ]]; then
    echo "📦 Installing dependencies..."
    npm install
fi

# Environment variables for local development
export NODE_ENV=development
export PORT=3000

echo "🚀 Starting server in development mode..."
echo "   📍 URL: http://localhost:3000"
echo "   🔧 Mode: development"
echo "   ⏹️  Ctrl+C to stop"
echo ""

# Start server
npm run dev 2>/dev/null || npm start
