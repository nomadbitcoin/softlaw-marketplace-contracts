#!/usr/bin/env bash
# DevContainer initialization script
# Loads environment and configures devtools based on .env settings

set -e

echo "🔧 DevContainer Startup"

# Load .env file
if [ -f /project/.env ]; then
    echo "📄 Loading .env file..."
    set -a
    . /project/.env
    set +a
    echo "✓ Environment loaded"
fi

# Check if PRIVATE_KEY is set
if [ -n "$PRIVATE_KEY" ]; then
    echo "✓ PRIVATE_KEY is already configured in .env"
    echo "  Using existing key: ${PRIVATE_KEY:0:10}..."

    # Export for all child processes
    export PRIVATE_KEY

    # Run only devcontainer setup, SKIP keypair setup
    echo "🚀 Running devtools setup-devcontainer..."
    devtools setup-devcontainer

    echo "⏭️  Skipping devtools setup-keypair (using .env key)"
    echo "✅ Startup complete - using PRIVATE_KEY from .env"
else
    echo "⚠️  No PRIVATE_KEY in .env file"
    echo "🚀 Running full devtools setup..."

    cd /project
    devtools setup-devcontainer
    devtools setup-keypair

    echo "✅ Startup complete"
fi
