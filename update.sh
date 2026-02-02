#!/usr/bin/env bash
# update.sh - Update TRM-Doppler & Lcurve container to latest version
# Usage: ./update.sh [command]
# Compatible with bash 3.2+ (macOS default)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Tracked repositories (simple array for compatibility)
REPO_NAMES="trm-doppler cpp-mem cpp-subs cpp-colly cpp-binary cpp-roche cpp-lcurve trm-subs trm-roche"
REPO_URLS="genghisken/trm-doppler trmrsh/cpp-mem trmrsh/cpp-subs trmrsh/cpp-colly trmrsh/cpp-binary trmrsh/cpp-roche trmrsh/cpp-lcurve trmrsh/trm-subs trmrsh/trm-roche"

# State file to track last known commits
STATE_FILE=".update_state"

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Helper to convert to uppercase (bash 3.2 compatible)
to_upper() {
    echo "$1" | tr '[:lower:]' '[:upper:]'
}

# Get latest commit SHA from GitHub API
get_latest_commit() {
    local repo=$1
    local commit=$(curl -s "https://api.github.com/repos/${repo}/commits/master" 2>/dev/null | grep -m1 '"sha"' | cut -d'"' -f4)
    if [[ -z "$commit" ]]; then
        # Try 'main' branch if 'master' fails
        commit=$(curl -s "https://api.github.com/repos/${repo}/commits/main" 2>/dev/null | grep -m1 '"sha"' | cut -d'"' -f4)
    fi
    echo "$commit"
}

# Load previous state
load_state() {
    if [[ -f "$STATE_FILE" ]]; then
        source "$STATE_FILE"
    fi
}

# Save current state
save_state() {
    echo "# State file - auto-generated" > "$STATE_FILE"
    echo "LAST_UPDATE=\"$(date -Iseconds 2>/dev/null || date +%Y-%m-%dT%H:%M:%S)\"" >> "$STATE_FILE"
    # Parse CURRENT_COMMITS string of "name:commit name:commit ..."
    for entry in $CURRENT_COMMITS; do
        local name="${entry%%:*}"
        local commit="${entry#*:}"
        local safe_name="${name//-/_}"
        local upper_name=$(to_upper "$safe_name")
        echo "LAST_${upper_name}_COMMIT=\"$commit\"" >> "$STATE_FILE"
    done
}

# Check if updates are available
check_updates() {
    log_info "Checking for updates..."
    
    # Convert space-separated strings to arrays
    read -ra names <<< "$REPO_NAMES"
    read -ra urls <<< "$REPO_URLS"
    
    UPDATES_AVAILABLE=false
    CURRENT_COMMITS=""
    
    load_state
    
    for i in "${!names[@]}"; do
        local name="${names[$i]}"
        local repo="${urls[$i]}"
        local commit=$(get_latest_commit "$repo")
        
        if [[ -z "$commit" ]]; then
            log_warn "Could not fetch commit for $name"
            continue
        fi
        
        CURRENT_COMMITS="$CURRENT_COMMITS $name:$commit"
        
        # Check against stored state
        local safe_name="${name//-/_}"
        local upper_name=$(to_upper "$safe_name")
        local var_name="LAST_${upper_name}_COMMIT"
        local last_commit="${!var_name}"
        
        if [[ "$commit" != "$last_commit" ]]; then
            log_info "  $name: NEW commit ${commit:0:8}"
            UPDATES_AVAILABLE=true
        else
            echo "  $name: up to date (${commit:0:8})"
        fi
    done
    
    if [[ "$UPDATES_AVAILABLE" == "false" ]]; then
        log_success "All repositories up to date!"
        return 1
    fi
    
    return 0
}

# Build the container
build_container() {
    local no_cache_flag=""
    if [[ "$1" == "--no-cache" ]]; then
        no_cache_flag="--no-cache"
        log_info "Building with --no-cache (fresh build)"
    fi
    
    log_info "Building Docker container..."
    
    if docker compose build $no_cache_flag; then
        log_success "Build completed successfully!"
        return 0
    else
        log_error "Build failed!"
        return 1
    fi
}

# Auto-fix common Docker issues
auto_fix() {
    log_info "Attempting auto-fix..."
    
    # Fix 1: Clean up Docker build cache
    log_info "Cleaning Docker build cache..."
    docker builder prune -f 2>/dev/null || true
    
    # Fix 2: Remove old images
    log_info "Removing old doppler images..."
    docker images | grep -E "(doppler|trm)" | awk '{print $3}' | xargs -r docker rmi -f 2>/dev/null || true
    
    # Fix 3: Rebuild with no cache
    log_info "Rebuilding with fresh cache..."
    if build_container --no-cache; then
        return 0
    fi
    
    # Fix 4: Check disk space
    log_warn "Build still failing. Checking disk space..."
    df -h . | tail -1
    
    # Fix 5: Try pulling fresh base image
    log_info "Pulling fresh base images..."
    docker pull python:3.11-bookworm 2>/dev/null || true
    docker pull python:3.11-slim-bookworm 2>/dev/null || true
    
    # Final attempt
    log_info "Final build attempt..."
    build_container --no-cache
}

# Restart container if running
restart_container() {
    if docker compose ps --quiet 2>/dev/null | grep -q .; then
        log_info "Restarting container..."
        docker compose down
        docker compose up -d
        log_success "Container restarted!"
    fi
}

# Main update function
do_update() {
    local force=$1
    
    # Convert space-separated strings to arrays
    read -ra names <<< "$REPO_NAMES"
    read -ra urls <<< "$REPO_URLS"
    
    if [[ "$force" != "true" ]]; then
        if ! check_updates; then
            return 0
        fi
    else
        log_info "Force update requested"
        CURRENT_COMMITS=""
        for i in "${!names[@]}"; do
            local name="${names[$i]}"
            local repo="${urls[$i]}"
            local commit=$(get_latest_commit "$repo")
            CURRENT_COMMITS="$CURRENT_COMMITS $name:$commit"
        done
    fi
    
    # First attempt: build with no cache (always use --no-cache for updates)
    if build_container --no-cache; then
        save_state
        restart_container
        log_success "Update completed successfully!"
        return 0
    fi
    
    # Build failed, try auto-fix
    log_warn "Initial build failed. Attempting auto-fix..."
    if auto_fix; then
        save_state
        restart_container
        log_success "Update completed after auto-fix!"
        return 0
    fi
    
    log_error "Update failed. Please check the error messages above."
    log_info "You can try:"
    log_info "  1. docker compose build --no-cache"
    log_info "  2. docker system prune -a"
    log_info "  3. Check GitHub issues for known problems"
    return 1
}

# Show status
show_status() {
    log_info "Current status:"
    echo ""
    
    load_state
    
    # Convert space-separated strings to arrays
    read -ra names <<< "$REPO_NAMES"
    read -ra urls <<< "$REPO_URLS"
    
    echo "Tracked repositories:"
    for i in "${!names[@]}"; do
        local name="${names[$i]}"
        local repo="${urls[$i]}"
        local safe_name="${name//-/_}"
        local upper_name=$(to_upper "$safe_name")
        local var_name="LAST_${upper_name}_COMMIT"
        local last_commit="${!var_name}"
        if [[ -n "$last_commit" ]]; then
            printf "  %-15s %s\n" "$name:" "${last_commit:0:8}"
        else
            printf "  %-15s %s\n" "$name:" "(not tracked)"
        fi
    done
    
    if [[ -n "$LAST_UPDATE" ]]; then
        echo ""
        echo "Last update: $LAST_UPDATE"
    fi
    
    echo ""
    
    # Check container status
    if docker compose ps --quiet 2>/dev/null | grep -q .; then
        log_success "Container is running"
        docker compose ps
    else
        log_warn "Container is not running"
    fi
}

# Print usage
print_usage() {
    # Convert space-separated strings to arrays
    read -ra names <<< "$REPO_NAMES"
    read -ra urls <<< "$REPO_URLS"
    
    echo "TRM-Doppler & Lcurve Update Script"
    echo ""
    echo "Usage: $0 [COMMAND]"
    echo ""
    echo "Commands:"
    echo "  update     Check for updates and rebuild if needed (default)"
    echo "  force      Force rebuild regardless of updates"
    echo "  status     Show current version and container status"
    echo "  start      Start the container"
    echo "  stop       Stop the container"
    echo "  logs       Show container logs"
    echo "  help       Show this help message"
    echo ""
    echo "Tracked repositories:"
    for i in "${!names[@]}"; do
        echo "  - ${urls[$i]}"
    done
    echo ""
    echo "Examples:"
    echo "  $0              # Check and update if needed"
    echo "  $0 force        # Force rebuild"
    echo "  $0 status       # Show status"
    echo "  $0 start        # Start Jupyter"
}

# Main entry point
main() {
    case "${1:-update}" in
        update)
            do_update false
            ;;
        force|--force|-f)
            do_update true
            ;;
        status|--status|-s)
            show_status
            ;;
        start)
            log_info "Starting container..."
            docker compose up -d
            log_success "Jupyter Lab available at http://localhost:8888"
            ;;
        stop)
            log_info "Stopping container..."
            docker compose down
            log_success "Container stopped"
            ;;
        logs)
            docker compose logs -f
            ;;
        help|--help|-h)
            print_usage
            ;;
        *)
            log_error "Unknown command: $1"
            print_usage
            exit 1
            ;;
    esac
}

main "$@"
