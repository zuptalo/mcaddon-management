#!/bin/bash

# Don't exit on individual command failures - we'll handle errors manually
set +e

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

# Function to extract entity identifiers from a pack before removal
get_pack_entities() {
    local pack_name="$1"
    local entities=()

    # Check resource pack entities
    local resource_entity_dir="$RESOURCE_DIR/$pack_name/entity"
    if [ -d "$resource_entity_dir" ]; then
        while IFS= read -r -d '' entity_file; do
            if [ -f "$entity_file" ]; then
                local identifier=$(jq -r '(."minecraft:entity"?.description.identifier) // (."minecraft:client_entity"?.description.identifier) // empty' "$entity_file" 2>/dev/null)
                if [ -n "$identifier" ] && [ "$identifier" != "null" ]; then
                    entities+=("$identifier")
                fi
            fi
        done < <(find "$resource_entity_dir" -name "*.json" -print0 2>/dev/null)
    fi

    # Check behavior pack entities
    local behavior_entity_dir="$BEHAVIOR_DIR/$pack_name/entities"
    if [ -d "$behavior_entity_dir" ]; then
        while IFS= read -r -d '' entity_file; do
            if [ -f "$entity_file" ]; then
                local identifier=$(jq -r '."minecraft:entity"?.description.identifier // empty' "$entity_file" 2>/dev/null)
                if [ -n "$identifier" ] && [ "$identifier" != "null" ]; then
                    entities+=("$identifier")
                fi
            fi
        done < <(find "$behavior_entity_dir" -name "*.json" -print0 2>/dev/null)
    fi

    # Remove duplicates
    printf '%s\n' "${entities[@]}" | sort -u
}

# Function to send commands to Minecraft server
send_minecraft_command() {
    local command="$1"
    echo "    Executing: $command"

    # Send command via Docker exec to the minecraft container
    # Don't fail the script if this command fails
    if docker exec minecraft rcon-cli "$command" >/dev/null 2>&1; then
        echo "    ✓ Command executed successfully"
        return 0
    else
        echo "    ⚠️ Command execution failed (server may not have RCON enabled or be unavailable)"
        return 1
    fi
}

# Function to clean up entities from removed packs
cleanup_entities() {
    local packs_to_remove=("$@")
    local all_entities=()

    echo -e "${YELLOW}🧹 Identifying entities to clean up...${NC}"

    # Collect all entities from packs being removed
    for pack in "${packs_to_remove[@]}"; do
        echo "  Scanning pack: $pack"
        local pack_entities=($(get_pack_entities "$pack"))
        if [ ${#pack_entities[@]} -gt 0 ]; then
            echo "    Found entities: ${pack_entities[*]}"
            all_entities+=("${pack_entities[@]}")
        else
            echo "    No entities found"
        fi
    done

    if [ ${#all_entities[@]} -eq 0 ]; then
        echo "  No entities to clean up"
        return 0
    fi

    echo -e "${YELLOW}🗑️ Removing existing entities from world...${NC}"

    # Remove all instances of each entity type
    for entity in "${all_entities[@]}"; do
        echo "  Attempting to remove all instances of: $entity"
        # Don't fail if the kill command doesn't work
        send_minecraft_command "kill @e[type=$entity]" || true
    done

    # Clear all players' inventories of spawn eggs (optional - commented out as it's aggressive)
    # echo "  Clearing spawn eggs from player inventories..."
    # send_minecraft_command "clear @a spawn_egg" || true

    echo "  ✓ Entity cleanup completed"
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

# Function to restart minecraft server with better error handling
restart_server() {
    echo -e "${YELLOW}🔄 Restarting Minecraft server...${NC}"

    # Check if minecraft container is running
    if ! docker ps --format "{{.Names}}" | grep -q "^minecraft$"; then
        echo "  ⚠️ Warning: Minecraft container is not running"
        return 1
    fi

    # Restart the container
    if docker restart minecraft >/dev/null 2>&1; then
        echo "  ✓ Restart command sent successfully"

        # Wait a moment for the restart to begin
        sleep 2

        # Wait for the server to come back online (up to 30 seconds)
        local count=0
        while [ $count -lt 30 ]; do
            if docker logs minecraft --tail 20 2>/dev/null | grep -q "Server started"; then
                echo "  ✓ Server restarted and online"
                return 0
            fi
            sleep 1
            ((count++))
        done

        echo "  ⚠️ Server restart initiated but status unclear"
        return 0
    else
        echo "  ❌ Failed to restart server"
        return 1
    fi
}

# Function to send notification to all players
notify_players() {
    local message="$1"
    echo -e "${YELLOW}📢 Notifying players...${NC}"

    # Try to send the message, but don't fail if it doesn't work
    if send_minecraft_command "say $message"; then
        echo "    ✓ Players notified"
    else
        echo "    ⚠️ Could not notify players (RCON may not be available)"
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

        # Notify players before starting
        notify_players "Server maintenance: Removing all addon packs. Server will restart shortly."

        # Clean up entities before removing packs (while server is still running)
        cleanup_entities "${ALL_PACKS[@]}"

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

        # Notify players before starting
        notify_players "Server maintenance: Removing addon packs (${PACKS_TO_REMOVE[*]}). Server will restart shortly."

        # Clean up entities before removing packs (while server is still running)
        cleanup_entities "${PACKS_TO_REMOVE[@]}"

        # Remove selected packs
        remove_packs "${PACKS_TO_REMOVE[@]}"
        removed_count=$?

        # Clean up world references if any packs were removed
        if [ $removed_count -gt 0 ]; then
            clean_world_references
            restart_server
        fi

        echo -e "${GREEN}✅ Successfully removed $removed_count addon pack(s)!${NC}"

        # Exit with success if we removed packs
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

            # Show entities
            local pack_entities=($(get_pack_entities "$pack_name"))
            if [ ${#pack_entities[@]} -gt 0 ]; then
                details+="[${#pack_entities[@]} entities] "
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
        echo -e "${RED}⚠️ Warning: This will remove all spawned entities and restart the server!${NC}"
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
        echo -e "${RED}⚠️  About to remove the following packs and all their entities:${NC}"
        for pack in "${PACKS_TO_REMOVE[@]}"; do
            echo "  - $pack"
            local pack_entities=($(get_pack_entities "$pack"))
            if [ ${#pack_entities[@]} -gt 0 ]; then
                echo "    Entities: ${pack_entities[*]}"
            fi
        done
        echo

        read -p "Are you sure? (y/N): " -r confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            echo -e "${BLUE}👋 Cancelled.${NC}"
            exit 0
        fi

        # Notify players
        notify_players "Server maintenance: Removing addon packs. Server will restart shortly."

        # Clean up entities first
        cleanup_entities "${PACKS_TO_REMOVE[@]}"

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