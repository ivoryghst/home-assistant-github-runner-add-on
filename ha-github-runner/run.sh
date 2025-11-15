#!/usr/bin/env bashio
set -e

bashio::log.info "Starting GitHub Actions Runner..."

# PID of the runner process
RUNNER_PID=""

# Ensure /addon_configs exists and is writable
# This directory is mounted by Home Assistant when all_addon_configs:rw is in config.yaml
if [ -d "/addon_configs" ]; then
    bashio::log.info "Found /addon_configs mount point"
    # Try to set permissions to 775 (owner+group can write, others can read)
    # If that fails, fall back to 777 (all can write)
    if chmod 775 /addon_configs 2>/dev/null; then
        bashio::log.info "Set /addon_configs permissions to 775 (group writable)"
    elif chmod 777 /addon_configs 2>/dev/null; then
        bashio::log.warning "Set /addon_configs permissions to 777 (world writable)"
    else
        bashio::log.warning "Could not set permissions on /addon_configs (may already be correct)"
    fi
    bashio::log.info "Current /addon_configs permissions: $(stat -c '%a' /addon_configs 2>/dev/null || echo 'unknown')"
else
    bashio::log.warning "/addon_configs directory not found - this may indicate the all_addon_configs:rw mapping in config.yaml is not configured correctly in Home Assistant"
    bashio::log.warning "Workflows attempting to use /addon_configs will fail"
fi

# Graceful shutdown handler
graceful_shutdown() {
    bashio::log.info "Received shutdown signal. Initiating graceful shutdown..."
    
    if [ -n "$RUNNER_PID" ] && kill -0 "$RUNNER_PID" 2>/dev/null; then
        bashio::log.info "Sending SIGTERM to runner process (PID: $RUNNER_PID) to stop accepting new jobs..."
        # Send SIGTERM to the runner process group
        kill -TERM -"$RUNNER_PID" 2>/dev/null || true
        
        bashio::log.info "Waiting for current job to complete (if any)..."
        # Wait for the runner process to finish gracefully
        wait "$RUNNER_PID" 2>/dev/null || true
        bashio::log.info "Runner stopped gracefully."
    else
        bashio::log.info "Runner process not running or already stopped."
    fi
    
    exit 0
}

# Trap signals for graceful shutdown
# SIGTERM: Sent by Docker/Home Assistant on container stop
# SIGINT: Sent on Ctrl+C (if run interactively)
# SIGHUP: Sent on terminal hangup or system shutdown
trap 'graceful_shutdown' SIGTERM SIGINT SIGHUP

# Get configuration from Home Assistant options file
CONFIG_FILE="/data/options.json"
REPO_URL=$(jq -r '.repo_url // empty' "$CONFIG_FILE")
RUNNER_TOKEN=$(jq -r '.runner_token // empty' "$CONFIG_FILE")
GITHUB_PAT=$(jq -r '.github_pat // empty' "$CONFIG_FILE")
RUNNER_NAME=$(jq -r '.runner_name // empty' "$CONFIG_FILE")
RUNNER_LABELS=$(jq -r '.runner_labels // empty' "$CONFIG_FILE")
DEBUG_LOGGING=$(jq -r '.debug_logging // false' "$CONFIG_FILE")

# Helper functions for input normalization
trim_whitespace() {
    local value="$1"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    echo "$value"
}

sanitize_labels() {
    local input="$1"
    local IFS=','
    local -a raw_labels=()
    local -a cleaned_labels=()

    # shellcheck disable=SC2206
    read -ra raw_labels <<< "$input" || true

    for label in "${raw_labels[@]}"; do
        local trimmed
        trimmed=$(trim_whitespace "$label")
        if [ -n "$trimmed" ]; then
            cleaned_labels+=("$trimmed")
        fi
    done

    if [ ${#cleaned_labels[@]} -eq 0 ]; then
        echo ""
        return
    fi

    local IFS=','
    echo "${cleaned_labels[*]}"
}

# Normalize runner name and labels to avoid GitHub API validation failures
if [ -n "$RUNNER_NAME" ]; then
    trimmed_runner_name=$(trim_whitespace "$RUNNER_NAME")
    if [ "$trimmed_runner_name" != "$RUNNER_NAME" ]; then
        bashio::log.info "Normalized runner name from '${RUNNER_NAME}' to '${trimmed_runner_name}'"
    fi
    RUNNER_NAME="$trimmed_runner_name"
fi

if [ -n "$RUNNER_LABELS" ]; then
    normalized_runner_labels=$(sanitize_labels "$RUNNER_LABELS")
    if [ -n "$normalized_runner_labels" ] && [ "$normalized_runner_labels" != "$RUNNER_LABELS" ]; then
        bashio::log.info "Normalized runner labels from '${RUNNER_LABELS}' to '${normalized_runner_labels}'"
    fi
    RUNNER_LABELS="$normalized_runner_labels"
fi

# Enable debug logging if requested
if [ "$DEBUG_LOGGING" = "true" ]; then
    bashio::log.info "Debug logging enabled"
    set -x
fi

# Validate required parameters
if [ -z "$REPO_URL" ]; then
    bashio::log.fatal "repo_url is required!"
    exit 1
fi

# Sanitize and validate REPO_URL
REPO_URL=$(trim_whitespace "$REPO_URL")
# Remove trailing slash if present
REPO_URL="${REPO_URL%/}"

# Validate repository URL format
if [[ ! "$REPO_URL" =~ ^https://github\.com/[a-zA-Z0-9_-]+(/[a-zA-Z0-9_.-]+)?$ ]]; then
    bashio::log.fatal "Invalid repository URL format!"
    bashio::log.fatal "Expected format:"
    bashio::log.fatal "  - For repository: https://github.com/owner/repo"
    bashio::log.fatal "  - For organization: https://github.com/organization"
    bashio::log.fatal "Provided URL: ${REPO_URL}"
    exit 1
fi

# Check that either runner_token or github_pat is provided
if [ -z "$RUNNER_TOKEN" ] && [ -z "$GITHUB_PAT" ]; then
    bashio::log.fatal "Either runner_token or github_pat is required!"
    bashio::log.fatal "  - runner_token: Short-lived token from GitHub UI (valid for 1 hour)"
    bashio::log.fatal "  - github_pat: Personal Access Token for automatic token renewal"
    exit 1
fi

# Validate token format (basic check)
if [ -n "$RUNNER_TOKEN" ]; then
    RUNNER_TOKEN=$(trim_whitespace "$RUNNER_TOKEN")
    if [ "${#RUNNER_TOKEN}" -lt 20 ]; then
        bashio::log.warning "Runner token appears to be too short (length: ${#RUNNER_TOKEN})"
        bashio::log.warning "Please ensure you're using a valid registration token from GitHub"
    fi
fi

if [ -n "$GITHUB_PAT" ]; then
    GITHUB_PAT=$(trim_whitespace "$GITHUB_PAT")
    if [ "${#GITHUB_PAT}" -lt 20 ]; then
        bashio::log.warning "GitHub PAT appears to be too short (length: ${#GITHUB_PAT})"
        bashio::log.warning "Please ensure you're using a valid Personal Access Token"
    fi
fi

bashio::log.info "Repository URL: ${REPO_URL}"

# Function to fetch registration token using PAT with retry logic
fetch_registration_token() {
    local pat="$1"
    local repo_url="$2"
    local api_url=""
    local max_retries=3
    local retry_delay=5
    
    # Determine if this is an org or repo registration
    if [[ "$repo_url" =~ ^https://github\.com/([^/]+)/([^/]+)$ ]]; then
        # Repository registration
        local owner="${BASH_REMATCH[1]}"
        local repo="${BASH_REMATCH[2]}"
        api_url="https://api.github.com/repos/${owner}/${repo}/actions/runners/registration-token"
        bashio::log.info "Fetching registration token for repository: ${owner}/${repo}"
    elif [[ "$repo_url" =~ ^https://github\.com/([^/]+)$ ]]; then
        # Organization registration
        local org="${BASH_REMATCH[1]}"
        api_url="https://api.github.com/orgs/${org}/actions/runners/registration-token"
        bashio::log.info "Fetching registration token for organization: ${org}"
    else
        bashio::log.error "Invalid repository URL format"
        return 1
    fi
    
    # Retry loop for fetching the registration token
    local attempt=1
    local response
    local exit_code
    
    while [ $attempt -le $max_retries ]; do
        if [ $attempt -gt 1 ]; then
            bashio::log.info "Retry attempt $attempt of $max_retries after ${retry_delay}s delay..."
            sleep $retry_delay
            # Exponential backoff
            retry_delay=$((retry_delay * 2))
        fi
        
        # Fetch the registration token
        response=$(curl -sSf -X POST \
            -H "Accept: application/vnd.github+json" \
            -H "Authorization: Bearer ${pat}" \
            -H "X-GitHub-Api-Version: 2022-11-28" \
            --max-time 30 \
            --connect-timeout 10 \
            "${api_url}" 2>&1)
        
        exit_code=$?
        
        if [ $exit_code -eq 0 ]; then
            # Extract token from response
            local token
            token=$(echo "$response" | jq -r '.token // empty' 2>/dev/null)
            
            if [ -n "$token" ]; then
                bashio::log.info "Successfully fetched registration token"
                echo "$token"
                return 0
            fi
        fi
        
        bashio::log.warning "Failed to fetch registration token (attempt $attempt/$max_retries): curl error ${exit_code}"
        attempt=$((attempt + 1))
    done
    
    # All retries failed
    bashio::log.error "Failed to fetch registration token from GitHub API after $max_retries attempts"
    bashio::log.error "Last response: ${response}"
    bashio::log.error ""
    bashio::log.error "Common causes:"
    bashio::log.error "  1. PAT doesn't have required permissions:"
    bashio::log.error "     - Fine-grained tokens: 'Actions' with 'Read and write' access"
    bashio::log.error "     - Classic tokens: 'repo' scope for repos, 'admin:org' for orgs"
    bashio::log.error "  2. PAT is expired or invalid"
    bashio::log.error "  3. Repository/Organization URL is incorrect"
    bashio::log.error "  4. Network connectivity issues"
    return 1
}

# If PAT is provided, use it to fetch a fresh registration token
if [ -n "$GITHUB_PAT" ]; then
    bashio::log.info "Using Personal Access Token to fetch registration token..."
    
    RUNNER_TOKEN=$(fetch_registration_token "$GITHUB_PAT" "$REPO_URL")
    
    if [ -z "$RUNNER_TOKEN" ]; then
        bashio::log.fatal "Failed to fetch registration token using PAT"
        exit 1
    fi
    
    bashio::log.info "Successfully fetched fresh registration token using PAT"
else
    bashio::log.info "Using provided registration token"
    bashio::log.info "Note: Registration tokens expire after 1 hour. If you see 404 errors,"
    bashio::log.info "generate a new token from: GitHub → Settings → Actions → Runners → New runner"
    bashio::log.info "Or use a Personal Access Token (github_pat) for automatic token renewal"
fi

# Calculate token length for debug logging
TOKEN_LENGTH=${#RUNNER_TOKEN}

# Debug information
if [ "$DEBUG_LOGGING" = "true" ]; then
    bashio::log.info "=== Debug Information ==="
    bashio::log.info "OS Version: $(grep PRETTY_NAME /etc/os-release | cut -d'=' -f2 | tr -d '\"')"
    bashio::log.info "Installed packages:"
    dpkg -l | grep -E "(libicu|libkrb5|liblttng|libssl|zlib)" || true
    bashio::log.info "Runner directory contents:"
    ls -la /runner
    bashio::log.info "Runner version:"
    cat /runner/.runner 2>/dev/null || echo "Runner not yet configured"
    bashio::log.info "Token length: ${TOKEN_LENGTH:-unknown} characters"
    bashio::log.info "Persistent config directory contents:"
    ls -la /data/runner-config/ 2>/dev/null || echo "No persistent config yet"
    bashio::log.info "========================="
fi

# Change to runner directory
cd /runner

# Ensure runner user owns the directory
chown -R runner:runner /runner

# Persistent storage for runner configuration
RUNNER_CONFIG_DIR="/data/runner-config"
mkdir -p "$RUNNER_CONFIG_DIR"
chown runner:runner "$RUNNER_CONFIG_DIR"

# Function to configure the runner
configure_runner() {
    bashio::log.info "Configuring GitHub Actions Runner..."
    
    # Build the config command
    CONFIG_CMD="./config.sh --url \"${REPO_URL}\" --token \"${RUNNER_TOKEN}\""
    
    # Add runner name if specified
    if [ -n "$RUNNER_NAME" ]; then
        bashio::log.info "Using custom runner name: ${RUNNER_NAME}"
        CONFIG_CMD="${CONFIG_CMD} --name \"${RUNNER_NAME}\""
    fi
    
    # Add labels if specified
    if [ -n "$RUNNER_LABELS" ]; then
        bashio::log.info "Using custom runner labels: ${RUNNER_LABELS}"
        CONFIG_CMD="${CONFIG_CMD} --labels \"${RUNNER_LABELS}\""
    fi
    
    CONFIG_CMD="${CONFIG_CMD} --unattended --replace"
    
    # Execute configuration
    if ! su runner -c "${CONFIG_CMD}"; then
        return 1
    fi
    
    # Backup configuration files to persistent storage
    bashio::log.info "Backing up runner configuration to persistent storage..."
    cp -f .runner "$RUNNER_CONFIG_DIR/" 2>/dev/null || true
    cp -f .credentials "$RUNNER_CONFIG_DIR/" 2>/dev/null || true
    cp -f .credentials_rsaparams "$RUNNER_CONFIG_DIR/" 2>/dev/null || true
    chown runner:runner "$RUNNER_CONFIG_DIR"/.* 2>/dev/null || true
    
    # Extract and display the runner name
    if [ -f ".runner" ]; then
        CONFIGURED_RUNNER_NAME=$(jq -r '.agentName // empty' .runner 2>/dev/null)
        if [ -n "$CONFIGURED_RUNNER_NAME" ]; then
            bashio::log.info "Runner successfully configured with name: ${CONFIGURED_RUNNER_NAME}"
        fi
    fi
    
    return 0
}

# Function to restore runner configuration
restore_runner_config() {
    if [ -f "$RUNNER_CONFIG_DIR/.runner" ] && [ -f "$RUNNER_CONFIG_DIR/.credentials" ]; then
        bashio::log.info "Found existing runner configuration, attempting to restore..."
        cp -f "$RUNNER_CONFIG_DIR/.runner" . 2>/dev/null || return 1
        cp -f "$RUNNER_CONFIG_DIR/.credentials" . 2>/dev/null || return 1
        cp -f "$RUNNER_CONFIG_DIR/.credentials_rsaparams" . 2>/dev/null || true
        chown runner:runner .runner .credentials .credentials_rsaparams 2>/dev/null || true
        
        # Extract and display the runner name
        if [ -f ".runner" ]; then
            CONFIGURED_RUNNER_NAME=$(jq -r '.agentName // empty' .runner 2>/dev/null)
            if [ -n "$CONFIGURED_RUNNER_NAME" ]; then
                bashio::log.info "Restored runner configuration with name: ${CONFIGURED_RUNNER_NAME}"
            fi
        fi
        
        return 0
    fi
    return 1
}

# Function to start runner with auto-recovery
start_runner() {
    # Extract and display the runner name before starting
    if [ -f ".runner" ]; then
        CONFIGURED_RUNNER_NAME=$(jq -r '.agentName // empty' .runner 2>/dev/null)
        if [ -n "$CONFIGURED_RUNNER_NAME" ]; then
            bashio::log.info "Starting runner with name: ${CONFIGURED_RUNNER_NAME}"
        else
            bashio::log.info "Starting runner..."
        fi
    else
        bashio::log.info "Starting runner..."
    fi
    
    # Try to start the runner in the background to capture PID
    su runner -c "./run.sh" &
    RUNNER_PID=$!
    
    # Wait for the runner process
    if wait "$RUNNER_PID"; then
        return 0
    else
        EXIT_CODE=$?
        bashio::log.warning "Runner exited with code $EXIT_CODE"
        
        # If runner failed and we have a persisted config, it might have been deleted from GitHub
        # Try to re-register
        if [ -f ".runner" ]; then
            bashio::log.info "Attempting to re-register runner (may have been deleted from GitHub portal)..."
            rm -f .runner .credentials .credentials_rsaparams 2>/dev/null || true
            
            if configure_runner; then
                bashio::log.info "Runner re-registered successfully! Starting runner..."
                su runner -c "./run.sh" &
                RUNNER_PID=$!
                wait "$RUNNER_PID"
                return $?
            else
                bashio::log.error "Failed to re-register runner. Please check token and configuration."
                return 1
            fi
        fi
        
        return $EXIT_CODE
    fi
}

# Try to restore existing configuration
if restore_runner_config; then
    bashio::log.info "Found existing runner configuration. Will attempt to use it."
else
    # No existing configuration - first-time setup
    bashio::log.info "No existing runner configuration found. Registering new runner..."
    if ! configure_runner; then
        bashio::log.error "Failed to configure runner. Common causes:"
        bashio::log.error "  1. Registration token expired (valid for 1 hour only)"
        bashio::log.error "  2. Invalid repository URL format"
        bashio::log.error "  3. Insufficient permissions for the repository/organization"
        bashio::log.error "  4. Network connectivity issues"
        bashio::log.error ""
        bashio::log.error "To fix:"
        bashio::log.error "  1. Go to GitHub → Your Repo → Settings → Actions → Runners"
        bashio::log.error "  2. Click 'New self-hosted runner'"
        bashio::log.error "  3. Copy the NEW registration token shown"
        bashio::log.error "  4. Update the add-on configuration with the new token"
        bashio::log.error "  5. Restart the add-on"
        exit 1
    fi
    bashio::log.info "Runner configured successfully!"
fi

# Start the runner (with auto-recovery if needed)
start_runner
