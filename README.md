# TRM-Doppler & Lcurve Docker Container

A Docker-based environment for Doppler tomography and light curve modeling software, with Jupyter Notebook support for interactive analysis.

## Contents

- [Features](#features)
- [Quick Start](#quick-start)
- [Directory Structure](#directory-structure)
- [Software Components](#software-components)
- [Usage Guide](#usage-guide)
- [Keeping Up to Date](#keeping-up-to-date)
- [Troubleshooting](#troubleshooting)
- [For Developers](#for-developers)

## Features

- **Doppler Tomography**: Full trm-doppler suite for Doppler imaging
- **Light Curve Modeling**: Lcurve and Roche geometry tools for binary star analysis
- **Isolated Environment**: All software compiled in a container, data I/O through mounted volumes
- **Jupyter Integration**: JupyterLab pre-installed for interactive analysis
- **Easy Updates**: Single command to check for and apply updates from all repositories
- **Auto-fix**: Automatic recovery from common Docker build issues

## Quick Start

### 1. Build and Start

```bash
# Build the container
docker compose build

# Start Jupyter Lab
docker compose up -d

# Or use the update script
./update.sh start
```

### 2. Access Jupyter

Open your browser to: **http://localhost:8888**

No token/password required by default.

### 3. Stop

```bash
docker compose down
# or
./update.sh stop
```

## Directory Structure

```
doppler_container/
├── Dockerfile              # Multi-stage build for all software
├── docker-compose.yml      # Container orchestration
├── update.sh              # Update management script
├── README.md              # This file (scientist documentation)
├── DEVELOPER.md           # Developer/maintainer documentation
├── software/              # Reference files (mounted read-only)
└── workspace/             # Your working directory (mounted read-write)
    ├── notebooks/         # Jupyter notebooks
    ├── input/             # Input data files
    └── output/            # Output results
```

### Workspace Folders

| Folder | Container Path | Purpose |
|--------|---------------|---------|
| `workspace/notebooks/` | `/home/doppler/workspace/notebooks` | Your Jupyter notebooks |
| `workspace/input/` | `/home/doppler/workspace/input` | Input data files |
| `workspace/output/` | `/home/doppler/workspace/output` | Analysis results |

## Software Components

### Python Packages

| Package | Description |
|---------|-------------|
| `trm.doppler` | Doppler tomography analysis |
| `trm.roche` | Roche lobe geometry calculations |
| `trm.subs` | Utility functions |

### Lcurve Binaries (in `/opt/trm/bin/lcurve/`)

| Binary | Description |
|--------|-------------|
| `lroche` | Light curve computation for Roche-lobe filling stars |
| `lroches` | Simplified light curve computation |
| `levmarq` | Levenberg-Marquardt fitting |
| `simplex` | Simplex optimization |
| `visualise` | Visualization tool |
| `picture` | Image generation |
| `lprofile` | Line profile computation |
| `rotprof` | Rotational profile tool |

### Roche Geometry Binaries (in `/opt/trm/bin/roche/`)

| Binary | Description |
|--------|-------------|
| `algol` | Algol-type binary modeling |
| `pstream` | Gas stream plotting |
| `pshade` | Shadow plotting |
| `vspace` | Velocity space visualization |
| `impact` | Impact parameter calculations |
| `lagrange` | Lagrange point calculations |
| `pcont` | Contour plotting |
| `pdwd` | Period distribution for DWDs |
| `cphase` | Phase calculations |
| `equalrv` | Equal radial velocity curves |

### Subs Utilities (in `/opt/trm/bin/subs/`)

| Binary | Description |
|--------|-------------|
| `gap` | Gap detection in data |
| `tcorr` | Time correction utilities |
| `weekday` | Day of week calculator |

## Usage Guide

### Using Python Packages

#### Basic Imports

```python
import trm.doppler as doppler
import trm.roche as roche
import trm.subs as subs
```

#### Roche Geometry Example

```python
import trm.roche as roche

# Calculate Lagrange points for mass ratio q=0.5
q = 0.5
print(f"L1 distance from primary: {roche.xl1(q):.6f}")
print(f"L2 distance from primary: {roche.xl2(q):.6f}")
print(f"L3 distance from primary: {roche.xl3(q):.6f}")

# Calculate Roche lobe
x, y = roche.lobe1(q, n=100)  # Primary's Roche lobe
```

#### Doppler Tomography Example

```python
import trm.doppler as doppler

# Load and analyze your Doppler data
# See trm-doppler documentation for detailed examples
```

### Using Command-Line Tools

From a Jupyter terminal or shell:

```bash
# Light curve fitting with lroche
lroche model.mod data.dat

# Visualize binary configuration
visualise model.mod

# Calculate Lagrange points
lagrange 0.5  # for q=0.5
```

Access from outside the container:

```bash
docker compose exec doppler lroche --help
docker compose exec doppler lagrange 0.5
```

### Complete Analysis Workflow Example

Create a notebook in `workspace/notebooks/analysis.ipynb`:

```python
# Cell 1: Imports
import trm.doppler as doppler
import trm.roche as roche
import numpy as np
import matplotlib.pyplot as plt
from astropy.io import fits

# Cell 2: Load data from input folder
data_path = '/home/doppler/workspace/input/your_data.fits'
# Load and process your data...

# Cell 3: Roche geometry calculations
q = 0.3  # mass ratio
x_lobe, y_lobe = roche.lobe1(q, n=200)

plt.figure(figsize=(10, 8))
plt.plot(x_lobe, y_lobe, 'b-', label='Primary Roche lobe')
plt.xlabel('x (orbital separation)')
plt.ylabel('y (orbital separation)')
plt.legend()
plt.savefig('/home/doppler/workspace/output/roche_lobe.png')

# Cell 4: Save results
output_path = '/home/doppler/workspace/output/results.fits'
# Save your analysis results...
```

## Keeping Up to Date

### Check for Updates

```bash
./update.sh
```

This will:
1. Check GitHub for new commits to all tracked repositories
2. Rebuild the container if updates are found
3. Restart the container automatically

### Force Update

```bash
./update.sh force
```

Rebuilds regardless of whether updates are detected.

### Check Status

```bash
./update.sh status
```

Shows current version info and container status.

### Update Script Commands

| Command | Description |
|---------|-------------|
| `./update.sh` | Check for updates and rebuild if needed |
| `./update.sh force` | Force rebuild |
| `./update.sh status` | Show version and container status |
| `./update.sh start` | Start the container |
| `./update.sh stop` | Stop the container |
| `./update.sh logs` | View container logs |
| `./update.sh help` | Show help |

## Troubleshooting

### Build Fails

The update script has auto-fix capabilities. Try:

```bash
./update.sh force
```

If that fails, manually clean up:

```bash
docker system prune -a
docker compose build --no-cache
```

### Container Won't Start

Check logs:

```bash
./update.sh logs
```

### Permission Issues

The container runs as user `doppler` (non-root). Ensure your workspace directories are writable:

```bash
chmod -R 755 workspace/
```

### Memory Issues

Adjust memory limits in `docker-compose.yml`:

```yaml
deploy:
  resources:
    limits:
      memory: 8G  # Increase as needed
```

### Import Errors

If you get "module not found" errors:

```bash
# Rebuild with fresh cache
docker compose build --no-cache
```

## Dependencies

Built into the container:
- **cpp-mem**: C++ MEM library
- **cpp-subs**: Base utility library
- **cpp-colly**: Molly spectra access
- **cpp-binary**: Binary star functions
- **cpp-roche**: Roche lobe geometry
- **cpp-lcurve**: Light curve modeling
- **pgplot**: Graphics library
- **slalib/erfa**: Positional astronomy
- **fftw3**: Fast Fourier Transform
- **Python packages**: numpy, scipy, matplotlib, astropy, pandas, emcee, corner, jupyterlab

## For Developers

See [DEVELOPER.md](DEVELOPER.md) for:
- Build system architecture
- Dependency chain details
- How to add new features
- Troubleshooting build issues
- Repository structure

## Links

- [trm-doppler](https://github.com/genghisken/trm-doppler) - Doppler tomography
- [cpp-lcurve](https://github.com/trmrsh/cpp-lcurve) - Light curve modeling
- [cpp-roche](https://github.com/trmrsh/cpp-roche) - Roche geometry
- [cpp-mem](https://github.com/trmrsh/cpp-mem) - MEM library
- [trm-roche](https://github.com/trmrsh/trm-roche) - Python Roche bindings

## License

This container setup is provided as-is. The scientific software is developed by Tom Marsh and collaborators.
