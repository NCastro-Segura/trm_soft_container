# Developer & Maintainer Guide

This document provides technical details for developers and maintainers of the TRM-Doppler & Lcurve Docker container.

## Architecture Overview

The container uses a **multi-stage Docker build** with three stages:

1. **cpp-builder**: Compiles all C++ libraries
2. **python-builder**: Builds Python packages with Cython extensions
3. **runtime**: Minimal image with only runtime dependencies

```
┌─────────────────────────────────────────────────────────────────┐
│                        cpp-builder Stage                        │
│  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐             │
│  │ PGPLOT  │  │ SLALIB  │  │  ERFA   │  │ cpp-mem │             │
│  └────┬────┘  └────┬────┘  └────┬────┘  └────┬────┘             │
│       └────────────┴───────────┬┴──────-─────┘                  │
│                                ▼                                │
│                          ┌─────────┐                            │
│                          │cpp-subs │ (base library)             │
│                          └────┬────┘                            │
│                     ┌─────────┼─────────┐                       │
│                     ▼         ▼         ▼                       │
│              ┌──────────┐ ┌──────────┐                          │
│              │cpp-colly │ │cpp-binary│                          │
│              └────┬─────┘ └────┬─────┘                          │
│                   └─────┬──────┘                                │
│                         ▼                                       │
│                   ┌──────────┐                                  │
│                   │cpp-roche │                                  │
│                   └────┬─────┘                                  │
│                        ▼                                        │
│                  ┌───────────┐                                  │
│                  │cpp-lcurve │                                  │
│                  └───────────┘                                  │
│                                                                 │
│  Output: /opt/trm/{lib,include,bin}                             │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      python-builder Stage                       │
│   ┌───────────┐  ┌───────────┐  ┌───────────┐                   │
│   │ trm-subs  │  │trm-doppler│  │ trm-roche │                   │
│   │ (Python)  │  │ (Python)  │  │ (Cython)  │                   │
│   └───────────┘  └───────────┘  └───────────┘                   │
│                                                                 │
│  Output: Python site-packages                                   │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                        runtime Stage                            │
│  • Minimal Debian (slim)                                        │
│  • Runtime libraries only (no build tools)                      │
│  • Copy /opt/trm from cpp-builder                               │
│  • Copy site-packages from python-builder                       │
│  • JupyterLab + scientific Python packages                      │
└─────────────────────────────────────────────────────────────────┘
```

## Dependency Chain

### Build Order (Critical!)

The C++ libraries must be built in this exact order due to dependencies:

```
1. System dependencies (PGPLOT, SLALIB, ERFA)
2. cpp-mem (standalone, for trm-doppler)
3. cpp-subs (base library)
4. cpp-colly (depends on: subs)
5. cpp-binary (depends on: subs)
6. cpp-roche (depends on: subs, binary)
7. cpp-lcurve (depends on: subs, colly, binary, roche)
```

### Python Package Order

```
1. trm-subs (pure Python utilities)
2. trm-doppler (depends on: cpp-mem via TRM_SOFTWARE)
3. trm-roche (depends on: cpp-roche, trm-subs via Cython)
```

## Key Technical Details

### SLALIB + ERFA Compatibility

The cpp-subs library requires modern SLALIB functions (`slaEpv`, `slaPneqx`, `slaI2o`) that don't exist in the old pyslalib. We solve this by:

1. Building pyslalib Fortran code as `libcsla.a`
2. Adding C wrapper functions that call ERFA equivalents
3. Patching the `slalib.h` header to include new function declarations

**Wrapper location in Dockerfile**: See the `sla_wrappers.c` section (lines ~67-130)

**Function mappings**:
- `slaEpv` → `eraEpv00` (Earth position/velocity)
- `slaPneqx` → `eraPnm06a` (Precession-nutation matrix)
- `slaI2o` → `eraApco13` + `eraAtioq` (ICRS to observed)

### PGPLOT Configuration

PGPLOT is built with:
- **gfortran** (not g77)
- `-fallow-argument-mismatch` flag for modern gfortran
- Drivers: PSDRIV (PostScript), XWDRIV (X Windows)
- PNG driver disabled (png.h conflicts)

### Cython Compatibility

trm-roche uses wildcard `cimport` which broke in Cython 3.x. We pin to `cython<3`:

```dockerfile
RUN pip install --no-cache-dir 'cython<3' && \
    git clone ... trm-roche ...
```

## Repository Sources

| Repository | Description | URL |
|------------|-------------|-----|
| trm-doppler | Doppler tomography | https://github.com/genghisken/trm-doppler |
| cpp-mem | MEM algorithm | https://github.com/trmrsh/cpp-mem |
| cpp-subs | Base utilities | https://github.com/trmrsh/cpp-subs |
| cpp-colly | Molly spectra | https://github.com/trmrsh/cpp-colly |
| cpp-binary | Binary functions | https://github.com/trmrsh/cpp-binary |
| cpp-roche | Roche geometry | https://github.com/trmrsh/cpp-roche |
| cpp-lcurve | Light curves | https://github.com/trmrsh/cpp-lcurve |
| trm-subs | Python utilities | https://github.com/trmrsh/trm-subs |
| trm-roche | Python Roche bindings | https://github.com/trmrsh/trm-roche |
| pyslalib | SLALIB Fortran | https://github.com/scottransom/pyslalib |

## Environment Variables

| Variable | Value | Purpose |
|----------|-------|---------|
| `TRM_SOFTWARE` | `/opt/trm` | Installation prefix |
| `LD_LIBRARY_PATH` | `/opt/trm/lib:...` | Runtime library path |
| `PATH` | `/opt/trm/bin:...` | Binary search path |
| `PGPLOT_DIR` | `/opt/trm/lib` | PGPLOT data files |
| `CPPFLAGS` | `-I/opt/trm/include` | Compiler include path |
| `LDFLAGS` | `-L/opt/trm/lib` | Linker library path |

## Common Build Issues & Fixes

### 1. "slalib.h not found" during cpp-subs configure

**Cause**: autoconf's `AC_CHECK_HEADERS` doesn't respect `CPPFLAGS` correctly.

**Fix**: Copy slalib.h to `/usr/include/`:
```dockerfile
RUN cp /opt/trm/include/slalib.h /usr/include/slalib.h && ...
```

### 2. "libpcrecpp.so.0 not found" at runtime

**Cause**: Missing runtime library in slim image.

**Fix**: Add `libpcrecpp0v5` to runtime apt install.

### 3. Cython "undeclared name" errors in trm-roche

**Cause**: Cython 3.x doesn't support wildcard `cimport *` from pxd files.

**Fix**: Pin to Cython 2.x:
```dockerfile
RUN pip install 'cython<3' && ...
```

### 4. PGPLOT PNG driver fails

**Cause**: png.h conflicts or missing libpng-dev.

**Fix**: Disable PNG driver by not uncommenting PNDRIV in drivers.list.

### 5. Fortran linking errors (undefined slaXxx)

**Cause**: Fortran symbols use trailing underscore (`sla_xxx_`), C headers expect mixed case (`slaXxx`).

**Fix**: Create C wrapper functions that bridge the naming:
```c
extern double sla_airmas_(double*);
double slaAirmas(double zd) { return sla_airmas_(&zd); }
```

## Adding New Software

### Adding a New C++ Library

1. Identify dependencies from `configure.ac`
2. Add build step after its dependencies in Dockerfile
3. Use consistent pattern:
```dockerfile
RUN git clone --depth 1 https://github.com/trmrsh/cpp-NEW.git && \
    cd cpp-NEW && \
    ./bootstrap && \
    ./configure --prefix=/opt/trm \
        CPPFLAGS="-I/opt/trm/include" \
        LDFLAGS="-L/opt/trm/lib" \
        LIBS="-ldeps..." && \
    make -j$(nproc) && \
    make install && \
    cd .. && rm -rf cpp-NEW
```

### Adding a New Python Package

Add after existing packages in python-builder stage:
```dockerfile
RUN git clone --depth 1 https://github.com/trmrsh/trm-NEW.git && \
    cd trm-NEW && \
    pip install --no-cache-dir . && \
    cd .. && rm -rf trm-NEW
```

## Update Script (update.sh)

The update script tracks repositories via GitHub API:

```bash
# Check latest commit
curl -s "https://api.github.com/repos/OWNER/REPO/commits/main" | jq -r '.sha'
```

### Adding Tracking for New Repos

Edit `update.sh` and add to the `check_updates()` function:

```bash
REPOS=(
    "genghisken/trm-doppler"
    "trmrsh/cpp-mem"
    "trmrsh/cpp-subs"
    "trmrsh/NEW-REPO"  # Add here
)
```

## Testing Changes

### Quick Test

```bash
# Build
docker compose build

# Test imports
docker run --rm doppler-dev python3 -c "
import trm.doppler
import trm.roche
import trm.subs
print('All imports successful')
"

# Test binaries
docker run --rm doppler-dev ls /opt/trm/bin/lcurve/
docker run --rm doppler-dev lagrange 0.5
```

### Full Test

```bash
# Start container
docker compose up -d

# Access Jupyter at http://localhost:8888

# Run a sample notebook
# Check that all tools are accessible
```

## File Locations

| File | Purpose |
|------|---------|
| `Dockerfile` | Main build file |
| `docker-compose.yml` | Container orchestration |
| `update.sh` | Update management |
| `README.md` | User documentation |
| `DEVELOPER.md` | This file |
| `workspace/` | User data directory |
| `software/` | Reference/example files |

## Release Checklist

1. [ ] All C++ libraries build successfully
2. [ ] All Python packages import without errors
3. [ ] Jupyter starts correctly
4. [ ] All binaries are accessible
5. [ ] update.sh works
6. [ ] Documentation is current
7. [ ] Container size is reasonable (~3-4GB)

## Debugging Tips

### View Build Logs

```bash
docker compose build --progress=plain 2>&1 | tee build.log
```

### Interactive Shell in Build Stage

```dockerfile
# Add temporarily for debugging:
RUN ls -la /opt/trm/include/ && sleep 3600
```

### Check Library Dependencies

```bash
docker run --rm doppler-dev ldd /opt/trm/bin/lcurve/lroche
```

### Inspect Container

```bash
docker run --rm -it doppler-dev bash
```

## Contact & Support

For issues with:
- **Container setup**: Open an issue in this repository
- **Scientific software**: Contact the respective repository maintainers
