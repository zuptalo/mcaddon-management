#!/bin/bash

# Debug script to examine the Chincobin addon entity files
RESOURCE_DIR="/root/tools/minecraft/resource_packs/Chincobin"
BEHAVIOR_DIR="/root/tools/minecraft/behavior_packs/Chincobin"

echo "=== Examining Chincobin Entity Files ==="
echo

echo "--- Resource Pack Entities ---"
if [ -d "$RESOURCE_DIR/entity" ]; then
    find "$RESOURCE_DIR/entity" -name "*.json" | while read file; do
        echo "File: $(basename "$file")"
        echo "Identifier:"
        jq -r '(."minecraft:client_entity"?.description.identifier) // (."minecraft:entity"?.description.identifier) // "NOT_FOUND"' "$file"
        echo "Textures:"
        jq -r '."minecraft:client_entity"?.description.textures // "NOT_FOUND"' "$file"
        echo "---"
    done
else
    echo "No entity directory found in resource pack"
fi

echo
echo "--- Behavior Pack Entities ---"
if [ -d "$BEHAVIOR_DIR/entities" ]; then
    find "$BEHAVIOR_DIR/entities" -name "*.json" | while read file; do
        echo "File: $(basename "$file")"
        echo "Identifier:"
        jq -r '."minecraft:entity"?.description.identifier // "NOT_FOUND"' "$file"
        echo "Components:"
        jq -r '."minecraft:entity"?.components | keys // "NOT_FOUND"' "$file" 2>/dev/null
        echo "---"
    done
else
    echo "No entities directory found in behavior pack"
fi

echo
echo "--- Checking for Common Issues ---"

# Check file permissions
echo "File permissions:"
find "$RESOURCE_DIR" "$BEHAVIOR_DIR" -name "*.json" -exec ls -la {} \;

echo
echo "--- Checking for Invalid Characters ---"
echo "Checking for BOM or invisible characters in entity files..."
find "$RESOURCE_DIR" "$BEHAVIOR_DIR" -name "*.json" | while read file; do
    if file "$file" | grep -q "UTF-8 Unicode (with BOM)"; then
        echo "WARNING: $file has BOM (Byte Order Mark)"
    fi
    if grep -P '[^\x00-\x7F]' "$file" >/dev/null 2>&1; then
        echo "WARNING: $file contains non-ASCII characters"
    fi
done

echo
echo "--- Full Entity File Contents ---"
echo "JC Entity Files:"
find "$RESOURCE_DIR" "$BEHAVIOR_DIR" -name "*jc*" -o -name "*JC*" | while read file; do
    echo "=== $file ==="
    cat "$file"
    echo
done

echo "TEO Entity Files:"
find "$RESOURCE_DIR" "$BEHAVIOR_DIR" -name "*teo*" -o -name "*TEO*" | while read file; do
    echo "=== $file ==="
    cat "$file"
    echo
done