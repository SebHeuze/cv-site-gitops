#!/bin/bash
set -e

# Validate all Helm charts
# Run this before committing changes

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GITOPS_DIR="$(dirname "$SCRIPT_DIR")"
CHARTS_DIR="$GITOPS_DIR/charts"
ENVS_DIR="$GITOPS_DIR/environments"

echo "================================================"
echo "  Validating Helm Charts"
echo "================================================"
echo ""

ERRORS=0

for chart_dir in "$CHARTS_DIR"/*/; do
    chart_name=$(basename "$chart_dir")
    echo "Validating: $chart_name"

    # Lint the chart
    if helm lint "$chart_dir" --quiet; then
        echo "  ✓ Lint passed"
    else
        echo "  ✗ Lint failed"
        ERRORS=$((ERRORS + 1))
    fi

    # Template with production values
    values_file="$ENVS_DIR/production/${chart_name}-values.yaml"
    if [ -f "$values_file" ]; then
        if helm template "$chart_name" "$chart_dir" -f "$values_file" > /dev/null 2>&1; then
            echo "  ✓ Template passed"
        else
            echo "  ✗ Template failed"
            ERRORS=$((ERRORS + 1))
        fi
    else
        echo "  - No production values file"
    fi

    echo ""
done

echo "================================================"
if [ $ERRORS -eq 0 ]; then
    echo "  All charts validated successfully!"
else
    echo "  Validation failed with $ERRORS errors"
    exit 1
fi
echo "================================================"
