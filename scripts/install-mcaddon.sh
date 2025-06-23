#!/bin/bash

set -e

if [ -z "$1" ]; then
  echo "Usage: $0 <your-addon>.mcaddon"
  exit 1
fi

MCADDON_FILE="$1"
BASENAME=$(basename "$MCADDON_FILE" .mcaddon)
TEMP_DIR="/tmp/${BASENAME}_extracted"
DATA_DIR="/root/tools/minecraft"
WORLD_DIR="$DATA_DIR/worlds/Bedrock level"
BEHAVIOR_DIR="$DATA_DIR/behavior_packs/$BASENAME"
RESOURCE_DIR="$DATA_DIR/resource_packs/$BASENAME"

echo ">>> Extracting $MCADDON_FILE..."
rm -rf "$TEMP_DIR"
mkdir -p "$TEMP_DIR"
unzip -q "$MCADDON_FILE" -d "$TEMP_DIR"

# Find manifest files
echo ">>> Detecting manifest.json files..."
MANIFESTS=$(find "$TEMP_DIR" -type f -name "manifest.json")

# Detect pack types by reading manifest "type"
while IFS= read -r manifest; do
  TYPE=$(jq -r '.modules[0].type' "$manifest")
  DIR=$(dirname "$manifest")
  if [[ "$TYPE" == "data" ]]; then
    BEHAVIOR_SRC="$DIR"
  elif [[ "$TYPE" == "resources" ]]; then
    RESOURCE_SRC="$DIR"
  fi
done <<< "$MANIFESTS"

if [[ -z "$BEHAVIOR_SRC" || -z "$RESOURCE_SRC" ]]; then
  echo "❌ Could not identify both behavior and resource packs. Aborting."
  exit 1
fi

echo ">>> Installing behavior and resource packs..."
mkdir -p "$BEHAVIOR_DIR"
mkdir -p "$RESOURCE_DIR"

cp -r "$BEHAVIOR_SRC/"* "$BEHAVIOR_DIR/"
cp -r "$RESOURCE_SRC/"* "$RESOURCE_DIR/"

echo ">>> Extracting UUIDs..."
BEHAVIOR_UUID=$(jq -r '.header.uuid' "$BEHAVIOR_DIR/manifest.json")
BEHAVIOR_VERSION=$(jq -c '.header.version' "$BEHAVIOR_DIR/manifest.json")
RESOURCE_UUID=$(jq -r '.header.uuid' "$RESOURCE_DIR/manifest.json")
RESOURCE_VERSION=$(jq -c '.header.version' "$RESOURCE_DIR/manifest.json")

echo ">>> Updating world pack references..."
mkdir -p "$WORLD_DIR"

cat <<EOF | tee "$WORLD_DIR/world_behavior_packs.json" >/dev/null
[
  {
    "pack_id": "$BEHAVIOR_UUID",
    "version": $BEHAVIOR_VERSION
  }
]
EOF

cat <<EOF | tee "$WORLD_DIR/world_resource_packs.json" >/dev/null
[
  {
    "pack_id": "$RESOURCE_UUID",
    "version": $RESOURCE_VERSION
  }
]
EOF

# Optional: enable experimental gameplay
if ! grep -q 'experimental-gameplay=true' "$DATA_DIR/server.properties"; then
  echo ">>> Enabling experimental gameplay in server.properties..."
  echo "experimental-gameplay=true" >> "$DATA_DIR/server.properties"
fi

echo ">>> Restarting Minecraft server..."
docker restart minecraft

# Extract identifier
echo ">>> Detecting entity identifier..."

ENTITY_FILE=$(find "$RESOURCE_DIR/entity" -type f -name "*.json" | head -n 1)

# Try server-side first, then client-side as fallback
IDENTIFIER=$(jq -r '
  (."minecraft:entity"?.description.identifier) //
  (."minecraft:client_entity"?.description.identifier) //
  empty
' "$ENTITY_FILE" 2>/dev/null)

if [[ -z "$IDENTIFIER" ]]; then
  IDENTIFIER="<unknown>"
fi

echo
echo "✅ Done!"
if [[ "$IDENTIFIER" != "<unknown>" ]]; then
  echo "🧙‍♂️ You can summon your custom entity with:"
  echo "    /summon $IDENTIFIER"
else
  echo "⚠️ Could not detect entity identifier automatically."
  echo "   Please check your .entity.json file under:"
  echo "   $RESOURCE_DIR/entity/"
fi