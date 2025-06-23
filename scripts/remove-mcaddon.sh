#!/bin/bash

set -e

DATA_DIR="/root/tools/minecraft"
WORLD_DIR="$DATA_DIR/worlds/Bedrock level"
BEHAVIOR_DIR="$DATA_DIR/behavior_packs"
RESOURCE_DIR="$DATA_DIR/resource_packs"

# Colors for better output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to get all custom packs
get_custom_packs() {
    local CUSTOM_PACKS=()

    # Scan behavior packs
    if [ -d "$BEHAVIOR_DIR" ]; then
        while IFS= read -r -d '' pack; do
            basename_pack=$(basename "$pack")
            # Skip vanilla, chemistry, and experimental packs
            if [[ ! "$basename_pack" =~ ^(vanilla|chemistry|experimental) ]]; then
                CUSTOM_PACKS+=("$basename_pack")
            fi
        done < <(find "$BEHAVIOR_DIR" -maxdepth 1 -type d -not -path "$BEHAVIOR_DIR" -print0 2>/dev/null)
    fi

    # Scan resource packs
    if [ -d "$RESOURCE_DIR" ]; then
        while IFS= read -r -d '' pack; do
            basename_pack=$(basename "$pack")
            # Skip vanilla, chemistry, and editor packs
            if [[ ! "$basename_pack" =~ ^(vanilla|chemistry|editor) ]]; then
                CUSTOM_PACKS+=("$basename_pack")
            fi
        done < <(find "$RESOURCE_DIR" -maxdepth 1 -type d -not -path "$RESOURCE_DIR" -print0 2>/dev/null)
    fi

    # Remove duplicates and sort
    printf '%s\n' "${CUSTOM_PACKS[@]}" | sort -u
}

# Function to remove specific packs
remove_packs() {
    local packs_to_remove=("$@")
    local removed_count=0

    echo -e "${YELLOW}🗑️  Removing selected packs...${NC}"

    for pack in "${packs_to_remove[@]}"; do
        echo -e "${BLUE}Removing: $pack${NC}"
        local pack_removed=false

        if [ -d "$BEHAVIOR_DIR/$pack" ]; then
            rm -rf "$BEHAVIOR_DIR/$pack"
            echo "  ✓ Removed behavior pack"
            pack_removed=true
        fi

        if [ -d "$RESOURCE_DIR/$pack" ]; then
            rm -rf "$RESOURCE_DIR/$pack"
            echo "  ✓ Removed resource pack"
            pack_removed=true
        fi

        if [ "$pack_removed" = true ]; then
            ((removed_count++))
        else
            echo "  ⚠️ Pack not found: $pack"
        fi
    done

    return $removed_count
}

# Function to clean world pack references
clean_world_references() {
    if [ -f "$WORLD_DIR/world_behavior_packs.json" ] || [ -f "$WORLD_DIR/world_resource_packs.json" ]; then
        echo -e "${YELLOW}🧹 Cleaning world pack references...${NC}"

        # Create empty pack reference files
        echo "[]" > "$WORLD_DIR/world_behavior_packs.json"
        echo "[]" > "$WORLD_DIR/world_resource_packs.json"

        echo "  ✓ Cleared world pack references"
    fi
}

# Function to restart minecraft server
restart_server() {
    echo -e "${YELLOW}🔄 Restarting Minecraft server...${NC}"
    if docker restart minecraft > /dev/null 2>&1; then
        echo "  ✓ Server restarted successfully"
        return 0
    else
        echo "  ⚠️ Warning: Could not restart server (container may not be running)"
        return 1
    fi
}

# Main logic
case "${1:-interactive}" in
    "all")
        echo -e "${BLUE}🔍 Removing all custom addon packs...${NC}"

        # Get all custom packs
        ALL_PACKS=($(get_custom_packs))

        if [ ${#ALL_PACKS[@]} -eq 0 ]; then
            echo -e "${GREEN}✅ No custom addon packs found to remove.${NC}"
            exit 0
        fi

        echo -e "${YELLOW}📦 Found ${#ALL_PACKS[@]} custom addon pack(s) to remove${NC}"

        # Remove all packs
        remove_packs "${ALL_PACKS[@]}"
        removed_count=$?

        # Clean up world references
        clean_world_references

        # Restart server
        restart_server

        echo -e "${GREEN}✅ Successfully removed $removed_count addon pack(s)!${NC}"
        exit 0
        ;;

    "selective")
        # Remove specific packs by name
        shift # Remove the "selective" argument

        if [ $# -eq 0 ]; then
            echo -e "${RED}❌ No pack names provided for selective removal${NC}"
            exit 1
        fi

        # Parse pack names (remove quotes if present)
        PACKS_TO_REMOVE=()
        for pack_name in "$@"; do
            # Remove surrounding quotes
            clean_name=$(echo "$pack_name" | sed 's/^"//;s/"$//')
            PACKS_TO_REMOVE+=("$clean_name")
        done

        echo -e "${BLUE}🔍 Removing selected addon packs...${NC}"
        echo -e "${YELLOW}📦 Packs to remove: ${PACKS_TO_REMOVE[*]}${NC}"

        # Remove selected packs
        remove_packs "${PACKS_TO_REMOVE[@]}"
        removed_count=$?

        # Clean up world references if any packs were removed
        if [ $removed_count -gt 0 ]; then
            clean_world_references
            restart_server
            restart_exit_code=$?
        else
            restart_exit_code=0
        fi

        echo -e "${GREEN}✅ Successfully removed $removed_count addon pack(s)!${NC}"

        # Exit with success if we removed packs, even if restart failed
        if [ $removed_count -gt 0 ]; then
            exit 0
        else
            exit 1
        fi
        ;;

    "interactive"|*)
        # Original interactive mode
        echo -e "${BLUE}🔍 Scanning for custom addon packs...${NC}"
        echo

        # Find custom packs (exclude vanilla and chemistry packs)
        ALL_PACKS=($(get_custom_packs))

        if [ ${#ALL_PACKS[@]} -eq 0 ]; then
            echo -e "${GREEN}✅ No custom addon packs found to remove.${NC}"
            exit 0
        fi

        echo -e "${YELLOW}📦 Found the following custom addon packs:${NC}"
        echo

        # Display packs with details
        for i in "${!ALL_PACKS[@]}"; do
            pack_name="${ALL_PACKS[i]}"
            printf "%2d) %s\n" $((i+1)) "$pack_name"

            # Show which directories exist for this pack
            details=""
            if [ -d "$BEHAVIOR_DIR/$pack_name" ]; then
                details+="[Behavior] "
            fi
            if [ -d "$RESOURCE_DIR/$pack_name" ]; then
                details+="[Resource] "
            fi

            if [ -n "$details" ]; then
                echo -e "     ${BLUE}$details${NC}"
            fi
            echo
        done

        echo -e "${YELLOW}Select pack(s) to remove:${NC}"
        echo "  - Enter number(s) separated by spaces (e.g., 1 3 5)"
        echo "  - Enter 'all' to remove all custom packs"
        echo "  - Enter 'q' to quit without removing anything"
        echo

        read -p "Your choice: " -r user_input

        if [[ "$user_input" == "q" ]]; then
            echo -e "${BLUE}👋 Exiting without changes.${NC}"
            exit 0
        fi

        PACKS_TO_REMOVE=()

        if [[ "$user_input" == "all" ]]; then
            PACKS_TO_REMOVE=("${ALL_PACKS[@]}")
        else
            # Parse selected numbers
            for num in $user_input; do
                if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -ge 1 ] && [ "$num" -le ${#ALL_PACKS[@]} ]; then
                    PACKS_TO_REMOVE+=("${ALL_PACKS[$((num-1))]}")
                else
                    echo -e "${RED}❌ Invalid selection: $num${NC}"
                    exit 1
                fi
            done
        fi

        if [ ${#PACKS_TO_REMOVE[@]} -eq 0 ]; then
            echo -e "${RED}❌ No valid packs selected.${NC}"
            exit 1
        fi

        echo
        echo -e "${RED}⚠️  About to remove the following packs:${NC}"
        for pack in "${PACKS_TO_REMOVE[@]}"; do
            echo "  - $pack"
        done
        echo

        read -p "Are you sure? (y/N): " -r confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            echo -e "${BLUE}👋 Cancelled.${NC}"
            exit 0
        fi

        # Remove the selected packs
        remove_packs "${PACKS_TO_REMOVE[@]}"
        removed_count=$?

        # Clean up world references
        clean_world_references

        # Restart server
        restart_server

        echo -e "${GREEN}✅ Successfully removed $removed_count addon pack(s)!${NC}"
        echo -e "${BLUE}💡 You can now install new addons or re-run this script to remove more.${NC}"
        exit 0
        ;;
esac