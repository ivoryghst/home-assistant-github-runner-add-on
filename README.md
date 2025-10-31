# HA GitHub Runner Add-ons Repository

[![GitHub Release][releases-shield]][releases]
![Project Stage][project-stage-shield]

A collection of Home Assistant add-ons for running GitHub Actions runners.

## Why This Fork?

This repository is a fork of the original GitHub Actions Runner add-on with critical improvements:

- **✅ addon_configs mounting**: The original never mounted the system's addon_configs directory, preventing workflows from accessing persistent storage
- **✅ rsync support**: Added rsync for reliable file synchronization in workflows
- **✅ Multi-addon structure**: Reorganized to support multiple add-ons in one repository

## Available Add-ons

### HA GitHub Runner

Run a self-hosted GitHub Actions runner directly within your Home Assistant installation with full addon_configs access and rsync support.

[**Documentation →**](ha-github-runner/README.md)

## Installation

1. Add this repository to your Home Assistant add-on store:
   ```
   https://github.com/ivoryghst/ha-addons
   ```
2. Install the "HA GitHub Runner" add-on
3. See individual add-on documentation for configuration details

## Support

Got questions or issues? Please open an issue on the [GitHub repository][github].

## Contributing

This is an active open-source project. We welcome contributions!

See [CONTRIBUTING.md](CONTRIBUTING.md) for detailed guidelines.

## License

MIT License

Copyright (c) 2024

[releases-shield]: https://img.shields.io/github/release/ivoryghst/ha-addons.svg
[releases]: https://github.com/ivoryghst/ha-addons/releases
[project-stage-shield]: https://img.shields.io/badge/project%20stage-production%20ready-brightgreen.svg
[github]: https://github.com/ivoryghst/ha-addons

---

## Configuration (Legacy - See ha-github-runner/README.md)

### Required Options

**`repo_url`** - The URL of your GitHub repository or organization
- Repository: `https://github.com/username/repo`
- Organization: `https://github.com/organization`

**Authentication** (one of the following is required):

**`runner_token`** - Registration token from GitHub (traditional method)
- Get it from: Repository/Organization → Settings → Actions → Runners → New self-hosted runner
- Valid for 1 hour after generation
- Only needed for initial setup (configuration persists across restarts)
- **Limitation**: Must be regenerated every hour if runner needs to re-register

**`github_pat`** - Personal Access Token (recommended for persistent setups)
- Get it from: GitHub → Settings → Developer Settings → Personal Access Tokens
- **For Fine-grained tokens (recommended)**:
  - Select specific repository or organization
  - Grant "Actions" permission with "Read and write" access
  - Note: Fine-grained tokens for organizations are currently in beta
- **For Classic tokens**:
  - Required scopes for repository runners: `repo` (Full control of private repositories)
  - Required scopes for organization runners: `admin:org` (Full control of orgs and teams)
- **Advantage**: Never expires (unless you set an expiration), automatically fetches fresh registration tokens
- **Use case**: Ideal for long-running setups where automatic re-registration is needed

### Optional Options

**`runner_name`** - Custom name for your runner (default: auto-generated)

**`runner_labels`** - Comma-separated custom labels (default: `self-hosted,Linux,X64`)
- Example: `"production,fast"`
- Note: Custom labels replace defaults; include defaults explicitly if needed

**`debug_logging`** - Enable verbose logging (default: `false`)

### Example Configuration

**Using Registration Token (traditional method):**
```yaml
repo_url: "https://github.com/username/repo"
runner_token: "YOUR_RUNNER_TOKEN_HERE"
runner_name: "my-home-assistant-runner"
runner_labels: "self-hosted,Linux,X64,production"
debug_logging: false
```

**Using Personal Access Token (recommended):**
```yaml
repo_url: "https://github.com/username/repo"
github_pat: "YOUR_PERSONAL_ACCESS_TOKEN_HERE"
runner_name: "my-home-assistant-runner"
runner_labels: "self-hosted,Linux,X64,production"
debug_logging: false
```

## Features

- ✅ Persistent configuration across restarts (no token re-entry needed)
- ✅ Auto-recovery if runner is deleted from GitHub
- ✅ Graceful shutdown handling
- ✅ Multi-architecture support (amd64, aarch64, armhf, armv7, i386)
- ✅ Configurable runner labels
- ✅ Access to /addon_configs for workflow configuration storage

## Security Considerations

This addon runs without AppArmor restrictions to allow GitHub Actions workflows to access the `/addon_configs` directory. This directory is mounted by Home Assistant when using the `all_addon_configs:rw` mapping, and workflows need to write persistent configuration data through this path.

**Important**: GitHub Actions runners inherently execute arbitrary code from your workflows. Only use this addon with repositories you trust, and ensure your workflows come from trusted sources. The reduced container isolation aligns with the expected security model of self-hosted runners.

## Usage Examples

### Syncing Files to /addon_configs

The `/addon_configs` directory is available for storing persistent configuration data from your workflows. Here's how to sync files correctly:

```yaml
- name: Sync files to addon_configs
  run: |
    # Create target directory if needed
    mkdir -p /addon_configs/my-config
    
    # Sync files using rsync (recommended flags to avoid permission errors)
    rsync -av --no-g --no-o --checksum --delete \
      ./source-directory/ \
      /addon_configs/my-config/
  shell: bash
```

**Important rsync flags for /addon_configs:**
- `--no-g`: Skip group preservation (avoids "Operation not permitted" errors)
- `--no-o`: Skip owner preservation (avoids permission issues)
- `-a`: Archive mode (preserves timestamps, symlinks, etc.)
- `-v`: Verbose output
- `--checksum`: Use checksums instead of mod-time & size for change detection (slower but more accurate)
- `--delete`: Delete files in destination that don't exist in source

### Writing Individual Files

```yaml
- name: Write configuration file
  run: |
    echo "my-config-data" > /addon_configs/my-app/config.yaml
  shell: bash
```

### Reading Files from /addon_configs

```yaml
- name: Read configuration
  run: |
    if [ -f /addon_configs/my-app/config.yaml ]; then
      cat /addon_configs/my-app/config.yaml
    fi
  shell: bash
```

## Troubleshooting

**404 Error During Registration**
- Most common: Token expired (registration tokens valid for 1 hour) → **Solution**: Use a Personal Access Token (PAT) instead for automatic token renewal, or generate a new registration token
- Check URL format: `https://github.com/owner/repo` (no trailing slash)
- Verify you have admin permissions on the repository/organization
- If using PAT: Ensure it has the correct scopes:
  - Fine-grained tokens: "Actions" with "Read and write" access
  - Classic tokens: `repo` scope for repository runners, `admin:org` for organization runners
- Don't use workflow `${{ github.token }}`; use registration tokens or PATs

**Permission Denied When Writing to /addon_configs**
- The add-on automatically sets permissions on `/addon_configs` at startup (version 1.6.6+)
- Check the add-on logs to verify `/addon_configs` mount point was found
- The mapping `all_addon_configs:rw` is pre-configured in the add-on and should work automatically
- If the mount point is not found in logs, try restarting the add-on
- The directory should be accessible at `/addon_configs` from within your workflows

**rsync "Operation not permitted" Errors When Syncing to /addon_configs**
- By default, `rsync` tries to preserve file ownership (user/group), which requires root privileges
- Non-root users (including the runner) cannot change file ownership, even with 777 permissions
- **Solution**: Use rsync with flags that skip ownership preservation:
  ```bash
  # Recommended: Skip group and owner preservation
  rsync -av --no-g --no-o /source/ /addon_configs/target/
  
  # Alternative: Skip all permissions (also disables chmod)
  rsync -av --no-perms --no-owner --no-group /source/ /addon_configs/target/
  
  # Or: Basic copy without preserving permissions
  rsync -rltv --no-g --no-o /source/ /addon_configs/target/
  ```
- If you see errors like `rsync: [generator] chgrp ... failed: Operation not permitted (1)`, add the `--no-g` flag
- You can still use `--checksum` and `--delete` flags as needed for your use case


