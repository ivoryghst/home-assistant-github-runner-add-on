# HA GitHub Runner Add-ons Repository

[![GitHub Release][releases-shield]][releases]
![Project Stage][project-stage-shield]

A collection of Home Assistant add-ons for running GitHub Actions runners.

## Why This Fork?

This repository is a fork of the original GitHub Actions Runner add-on with critical improvements:

- **✅ addon_configs mounting**: The original never mounted the system's addon_configs directory, preventing workflows from accessing persistent storage
- **✅ rsync support**: Added rsync for reliable file synchronization in workflows
- **✅ Multi-addon structure**: Reorganized to support multiple add-ons in one repository
- **✅ Enhanced security**: Checksum verification, retry logic, and improved error handling
- **✅ Better reliability**: Exponential backoff, input validation, and optimized configuration

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
