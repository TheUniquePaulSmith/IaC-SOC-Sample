#!/bin/bash
# Cloud-init YAML validation script

echo "Validating cloud-init YAML syntax..."

# Check if cloud-init is available
if command -v cloud-init &> /dev/null; then
    echo "Using cloud-init to validate..."
    cloud-init devel schema --config-file scripts/cloud-init.yaml
else
    echo "cloud-init not available, using basic YAML validation..."
    # Basic YAML validation using Python
    python3 -c "
import yaml
import sys

try:
    with open('scripts/cloud-init.yaml', 'r') as file:
        yaml.safe_load(file)
    print('✅ YAML syntax is valid')
    sys.exit(0)
except yaml.YAMLError as e:
    print(f'❌ YAML syntax error: {e}')
    sys.exit(1)
except Exception as e:
    print(f'❌ Error reading file: {e}')
    sys.exit(1)
"
fi

echo "Validation complete."
