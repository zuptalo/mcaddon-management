#!/bin/bash

echo "=== Investigating MCADDON File Issues ==="

# Check if we still have the original mcaddon file
UPLOAD_DIR="/app/uploads"
MCADDON_FILE=$(find "$UPLOAD_DIR" -name "*.mcaddon" | head -1)

if [ -z "$MCADDON_FILE" ]; then
    echo "❌ Original .mcaddon file not found in uploads directory"
    echo "The file was likely cleaned up after installation"
    echo ""
    echo "Let's check what we actually extracted..."
else
    echo "✅ Found .mcaddon file: $MCADDON_FILE"
    echo "Let's re-examine the contents..."
fi

RESOURCE_DIR="/root/tools/minecraft/resource_packs/Chincobin"
BEHAVIOR_DIR="/root/tools/minecraft/behavior_packs/Chincobin"

echo ""
echo "=== Checking Installed Structure ==="

echo "--- Resource Pack Structure ---"
find "$RESOURCE_DIR" -type f | sort

echo ""
echo "--- Behavior Pack Structure ---"
find "$BEHAVIOR_DIR" -type f | sort

echo ""
echo "=== Checking for Missing Files ==="

# Check for missing render controllers
echo "--- Render Controllers ---"
if [ -d "$RESOURCE_DIR/render_controllers" ]; then
    ls -la "$RESOURCE_DIR/render_controllers/"
else
    echo "❌ No render_controllers directory found!"
fi

# Check what render controllers are referenced
echo ""
echo "--- Render Controller References ---"
echo "JC entity uses:"
grep -o '"controller\.render\.[^"]*"' "$RESOURCE_DIR/entity/jc.entity.json" || echo "None found"

echo "TEO entity uses:"
grep -o '"controller\.render\.[^"]*"' "$RESOURCE_DIR/entity/teo.entity.json" || echo "None found"

# Check animation controller references
echo ""
echo "--- Animation Controller References ---"
echo "JC animation controllers:"
grep -A5 '"animation_controllers"' "$RESOURCE_DIR/entity/jc.entity.json" | grep '"controller\.' || echo "None found"

echo "TEO animation controllers:"
grep -A10 '"animation_controllers"' "$RESOURCE_DIR/entity/teo.entity.json" | grep '"controller\.' || echo "None found"

echo ""
echo "=== Missing Texture Analysis ==="

# Check which textures are referenced vs available
echo "--- TEO Texture Issues ---"
echo "Textures referenced by TEO but not found:"

grep -o '"textures/entity/[^"]*"' "$RESOURCE_DIR/entity/teo.entity.json" | sort -u | while read texture_path; do
    # Remove quotes
    texture_path=$(echo "$texture_path" | tr -d '"')
    full_path="$RESOURCE_DIR/$texture_path.png"

    if [ ! -f "$full_path" ]; then
        echo "❌ Missing: $texture_path.png"
    fi
done

echo ""
echo "=== Checking Original Installation Logs ==="

# Look for any installation errors in recent logs
echo "Recent installation attempts from app logs:"
docker logs mcaddon-manager 2>/dev/null | grep -A5 -B5 "Chincobin" | tail -20

echo ""
echo "=== Recommended Actions ==="
echo ""
echo "1. 🔍 RE-EXAMINE THE ORIGINAL ADDON:"
echo "   - The addon may have been created incorrectly"
echo "   - TEO entity might be incomplete in the source"
echo "   - Missing render controllers suggest incomplete addon"
echo ""
echo "2. 🛠️  POTENTIAL FIXES:"
echo "   - Ask the addon creator to fix the missing render controller"
echo "   - Use our manual fix (create missing render controller)"
echo "   - Re-download the addon if available"
echo ""
echo "3. 📝 WHAT TO CHECK:"
echo "   - Does the original .mcaddon contain render_controllers folder?"
echo "   - Are all texture files present in the original?"
echo "   - Was the addon tested before distribution?"

echo ""
echo "=== Installation Script Analysis ==="
echo "Let's check if our installation script might have missed something..."

# Check the extraction logic in our script
echo "Our install script does:"
echo "1. Extracts .mcaddon with unzip"
echo "2. Finds manifest.json files to identify pack types"
echo "3. Copies behavior and resource pack contents"
echo ""
echo "This should preserve all files, so if render controllers are missing,"
echo "they were likely not in the original .mcaddon file."