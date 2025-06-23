#!/bin/bash

# Validate and fix common entity issues
RESOURCE_DIR="/root/tools/minecraft/resource_packs/Chincobin"
BEHAVIOR_DIR="/root/tools/minecraft/behavior_packs/Chincobin"

echo "=== Entity Validation and Repair ==="

# Function to validate JSON
validate_json() {
    local file="$1"
    if ! jq empty "$file" 2>/dev/null; then
        echo "❌ Invalid JSON: $file"
        echo "JSON errors:"
        jq empty "$file"
        return 1
    else
        echo "✅ Valid JSON: $file"
        return 0
    fi
}

# Function to check required fields
check_entity_structure() {
    local file="$1"
    local type="$2"

    echo "Checking $type entity: $file"

    if [ "$type" = "client" ]; then
        # Check client entity structure
        identifier=$(jq -r '."minecraft:client_entity"?.description.identifier // "MISSING"' "$file")
        textures=$(jq -r '."minecraft:client_entity"?.description.textures // "MISSING"' "$file")

        echo "  Identifier: $identifier"
        echo "  Textures: $textures"

        if [ "$identifier" = "MISSING" ]; then
            echo "  ❌ Missing identifier in client entity"
        fi
        if [ "$textures" = "MISSING" ]; then
            echo "  ❌ Missing textures in client entity"
        fi
    else
        # Check behavior entity structure
        identifier=$(jq -r '."minecraft:entity"?.description.identifier // "MISSING"' "$file")
        components=$(jq -r '."minecraft:entity"?.components // "MISSING"' "$file")

        echo "  Identifier: $identifier"
        echo "  Components: $(echo "$components" | jq -r 'keys | join(", ")' 2>/dev/null || echo "MISSING")"

        if [ "$identifier" = "MISSING" ]; then
            echo "  ❌ Missing identifier in behavior entity"
        fi
        if [ "$components" = "MISSING" ]; then
            echo "  ❌ Missing components in behavior entity"
        fi
    fi
}

echo "--- Validating JSON Files ---"
find "$RESOURCE_DIR" "$BEHAVIOR_DIR" -name "*.json" | while read file; do
    validate_json "$file"
done

echo
echo "--- Checking Entity Structure ---"
if [ -d "$RESOURCE_DIR/entity" ]; then
    find "$RESOURCE_DIR/entity" -name "*.json" | while read file; do
        check_entity_structure "$file" "client"
    done
fi

if [ -d "$BEHAVIOR_DIR/entities" ]; then
    find "$BEHAVIOR_DIR/entities" -name "*.json" | while read file; do
        check_entity_structure "$file" "behavior"
    done
fi

echo
echo "--- Checking Texture Files ---"
if [ -d "$RESOURCE_DIR/textures" ]; then
    echo "Available textures:"
    find "$RESOURCE_DIR/textures" -name "*.png" | sort

    echo
    echo "Checking texture references in entity files:"
    find "$RESOURCE_DIR/entity" -name "*.json" 2>/dev/null | while read file; do
        echo "Entity file: $(basename "$file")"
        textures=$(jq -r '."minecraft:client_entity"?.description.textures // {}' "$file" 2>/dev/null)
        if [ "$textures" != "{}" ] && [ "$textures" != "null" ]; then
            echo "$textures" | jq -r 'to_entries[] | "\(.key): \(.value)"' 2>/dev/null || echo "  Error parsing textures"
        fi
    done
else
    echo "❌ No textures directory found!"
fi

echo
echo "--- Generating Test Commands ---"
echo "Test these commands in-game:"
find "$RESOURCE_DIR/entity" "$BEHAVIOR_DIR/entities" -name "*.json" 2>/dev/null | while read file; do
    identifier=$(jq -r '(."minecraft:client_entity"?.description.identifier) // (."minecraft:entity"?.description.identifier) // empty' "$file" 2>/dev/null)
    if [ -n "$identifier" ] && [ "$identifier" != "null" ]; then
        echo "/summon $identifier"
        echo "/give @s spawn_egg 1 0 {\"item_lock\":{\"mode\":\"lock_in_inventory\"},\"can_place_on\":{\"blocks\":[\"minecraft:grass\"]},\"entity_data\":{\"id\":\"$identifier\"}}"
    fi
done