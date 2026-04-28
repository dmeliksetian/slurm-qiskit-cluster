#!/bin/bash
# =============================================================================
# build-all.sh — runs inside the builder container
# Populates /shared/pyenv and builds the SPANK plugin.
# Called by: podman run --rm -v ./shared:/shared hpc-quantum-builder
#
# Expected mounts:
#   /shared        — host ./shared directory (read/write)
#                    must already contain qrmi/ and spank-plugins/ submodules
#   /build         — baked into image (requirements/, this script)
# =============================================================================

set -euo pipefail

# ── Colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; NC='\033[0m'

info()    { echo -e "${CYAN}[build]${NC} $*"; }
success() { echo -e "${GREEN}[done]${NC}  $*"; }
warn()    { echo -e "${YELLOW}[warn]${NC}  $*"; }
die()     { echo -e "${RED}[error]${NC} $*" >&2; exit 1; }

# ── Validate mounts ───────────────────────────────────────────────────────────
[[ -d /shared ]]              || die "/shared is not mounted"
[[ -d /shared/qrmi ]]         || die "/shared/qrmi not found — run: git submodule update --init --recursive"
[[ -d /shared/spank-plugins ]] || die "/shared/spank-plugins not found — run: git submodule update --init --recursive"
[[ -f /shared/qrmi/Cargo.toml ]] || die "/shared/qrmi appears empty — submodule not initialised"

SPANK_PLUGIN_DIR=/shared/spank-plugins/plugins/spank_qrmi

[[ -d $SPANK_PLUGIN_DIR ]] || die "spank_qrmi plugin directory not found at $SPANK_PLUGIN_DIR"

# ── Step 1: Create /shared/pyenv ──────────────────────────────────────────────
if [[ -d /shared/pyenv ]]; then
    warn "/shared/pyenv already exists — skipping venv creation"
    warn "Run with FORCE=1 to rebuild: FORCE=1 /build/build-all.sh"
else
    info "Creating Python 3.12 venv at /shared/pyenv ..."
    python3.12 -m venv /shared/pyenv
    success "Venv created"
fi

source /shared/pyenv/bin/activate
pip install --upgrade pip --quiet

# ── Step 2: Install pinned packages ───────────────────────────────────────────
if [[ "${PACKAGES_ONLY:-0}" == "1" ]]; then
    info "Skipping pyenv-frozen.txt (--packages-only) — adding GPU packages only"
else
    info "Installing pinned packages from pyenv-frozen.txt ..."
    info "(this will take several minutes — pyscf, jax, ffsim are large)"
    pip install -r /build/pyenv-frozen.txt
    success "Pinned packages installed"
fi

# ── Step 2b: Install GPU packages into pyenv ──────────────────────────────────
if [[ "${INSTALL_GPU_PACKAGES:-0}" == "1" ]]; then
    [[ -n "${CUDA_VERSION:-}" ]] || die "CUDA_VERSION not set — run ./setup/00b-configure-system.sh to detect your GPU"
    CUDA_MAJOR=$(echo "$CUDA_VERSION" | cut -d'-' -f1)
    CUPY_PACKAGE="cupy-cuda${CUDA_MAJOR}x"
    info "Installing GPU packages (${CUPY_PACKAGE}, qiskit-addon-dice-solver) ..."
    pip install "${CUPY_PACKAGE}"
    pip install qiskit-addon-dice-solver
    success "GPU packages installed"
fi

# ── Step 2c: Build qiskit-aer with GPU support from source ───────────────────
# There is no official PyPI wheel for newer CUDA versions / architectures
# (e.g. Blackwell CC 12.0, CUDA 13.x). We build from a patched fork that
# adds Blackwell support and fixes nlohmann_json >= 3.11 compatibility.
#
# Source: github.com/dmeliksetian/qiskit-aer  branch: build/combined-patches
# Patches applied:
#   fix-cuda-arch-thrust-compat  — Blackwell sm_120, CUDA 13 Thrust/CCCL compat
#   fix-nlohmann-3.11-compat     — ADL fix for nlohmann_json >= 3.11
#
# cuTENSOR and cuQuantum are installed from pip (CUDA-major-suffixed packages),
# with unversioned .so symlinks created so cmake can link against them.
#
# Requires env vars (set by 02-build-shared.sh, sourced from .env):
#   CUDA_VERSION  e.g. "13-2"
#   CUDA_ARCH     e.g. "120"  (integer, no dot)
if [[ "${INSTALL_QUANTUM_GPU_PACKAGES:-0}" == "1" ]]; then
    info "Building qiskit-aer with GPU support from source ..."

    # Remove CPU-only qiskit-aer if present (installed via pyenv-frozen.txt)
    if pip show qiskit-aer &>/dev/null; then
        warn "qiskit-aer (CPU) found — removing before GPU build ..."
        pip uninstall -y qiskit-aer
    fi

    [[ -n "${CUDA_ARCH:-}"    ]] || die "CUDA_ARCH not set — run 00b-configure-system.sh to detect compute capability"
    [[ -n "${CUDA_VERSION:-}" ]] || die "CUDA_VERSION not set — check .env"

    # Derive CUDA major version and dotted string (e.g. "13-2" → "13", "13.2")
    CUDA_MAJOR=$(echo "$CUDA_VERSION" | cut -d'-' -f1)
    CUDA_DOTTED=$(echo "$CUDA_VERSION" | tr '-' '.')

    # C++ standard: CUDA 12+ bundles Thrust/CCCL which requires C++17;
    # CUDA 11 and earlier work with C++14 (qiskit-aer default)
    if [[ "$CUDA_MAJOR" -ge 12 ]]; then
        CXX_STANDARD=17
    else
        CXX_STANDARD=14
    fi
    info "C++ standard: ${CXX_STANDARD} (CUDA ${CUDA_DOTTED})"

    # Locate nvcc
    NVCC_PATH="/usr/local/cuda-${CUDA_DOTTED}/bin/nvcc"
    if [[ ! -x "$NVCC_PATH" ]]; then
        NVCC_PATH=$(command -v nvcc 2>/dev/null) \
            || die "nvcc not found — ensure cuda-toolkit-${CUDA_VERSION} is installed in this image"
    fi
    info "nvcc: $NVCC_PATH"

    # Verify GCC version is within CUDA's supported range
    # NVIDIA CUDA maximum supported GCC: CUDA 11 → 11, CUDA 12 → 13, CUDA 13 → 14
    GCC_MAJOR=$(gcc -dumpversion | cut -d'.' -f1)
    info "GCC version: $(gcc --version | head -1)  (major: ${GCC_MAJOR})"
    declare -A _CUDA_MAX_GCC=([11]=11 [12]=13 [13]=14)
    _MAX_GCC="${_CUDA_MAX_GCC[${CUDA_MAJOR}]:-13}"
    if [[ "$GCC_MAJOR" -gt "$_MAX_GCC" ]]; then
        die "GCC ${GCC_MAJOR} is not supported by CUDA ${CUDA_DOTTED} (max supported: GCC ${_MAX_GCC})\n       Install a compatible compiler or use gcc-toolset"
    fi
    unset _CUDA_MAX_GCC _MAX_GCC

    # Install cuQuantum, cuTensorNet, and NVIDIA CUDA runtime libs.
    # cuTENSOR is pulled in transitively by cutensornet-cu${CUDA_MAJOR}.
    info "Installing cuQuantum and cuTensorNet (cu${CUDA_MAJOR}) ..."
    pip install \
        cuquantum \
        "cuquantum-cu${CUDA_MAJOR}" \
        "cutensornet-cu${CUDA_MAJOR}" \
        nvidia-cublas \
        nvidia-cuda-nvrtc \
        nvidia-cuda-runtime \
        nvidia-cusolver \
        nvidia-cusparse \
        nvidia-nvjitlink

    # Find installed package directories
    CUQUANTUM_ROOT=$(python3 -c "
import importlib.util
spec = importlib.util.find_spec('cuquantum')
print(list(spec.submodule_search_locations)[0])
" 2>/dev/null)
    # cuTENSOR is a transitive dep of cutensornet; locate via nvidia.cutensor or cutensor
    CUTENSOR_ROOT=$(python3 -c "
import importlib.util
for pkg in ('nvidia.cutensor', 'cutensor'):
    spec = importlib.util.find_spec(pkg)
    if spec and spec.submodule_search_locations:
        print(list(spec.submodule_search_locations)[0]); break
" 2>/dev/null)
    [[ -n "$CUQUANTUM_ROOT" ]] || die "Could not locate cuquantum package directory"
    [[ -n "$CUTENSOR_ROOT"  ]] || die "Could not locate cutensor package directory"
    info "CUQUANTUM_ROOT: $CUQUANTUM_ROOT"
    info "CUTENSOR_ROOT:  $CUTENSOR_ROOT"

    # Create unversioned .so symlinks — cmake needs libXxx.so without version suffix
    for lib_dir in "${CUTENSOR_ROOT}/lib" "${CUQUANTUM_ROOT}/lib"; do
        [[ -d "$lib_dir" ]] || continue
        for f in "${lib_dir}"/lib*.so.*; do
            [[ -f "$f" ]] || continue
            unversioned="${f%.so.*}.so"
            [[ -e "$unversioned" ]] || ln -sf "$(basename "$f")" "$unversioned"
        done
    done

    export CUTENSOR_ROOT CUQUANTUM_ROOT
    export LD_LIBRARY_PATH="${CUTENSOR_ROOT}/lib:${CUQUANTUM_ROOT}/lib:${LD_LIBRARY_PATH:-}"

    # Clone patched fork
    AER_SRC="/tmp/qiskit-aer-build"
    rm -rf "$AER_SRC"
    info "Cloning dmeliksetian/qiskit-aer@build/combined-patches ..."
    git clone --depth=1 --branch build/combined-patches \
        https://github.com/dmeliksetian/qiskit-aer.git "$AER_SRC"
    cd "$AER_SRC"

    # scikit-build and pybind11 are build-time deps for setup.py bdist_wheel
    pip install scikit-build pybind11

    info "Building wheel (CUDA ${CUDA_DOTTED}, arch ${CUDA_ARCH}) — this will take several minutes ..."
    DISABLE_CONAN=ON python3 setup.py bdist_wheel -- \
        -DAER_THRUST_BACKEND=CUDA \
        -DCMAKE_CUDA_COMPILER="${NVCC_PATH}" \
        -DCMAKE_CUDA_ARCHITECTURES="${CUDA_ARCH}" \
        -DCMAKE_CXX_STANDARD="${CXX_STANDARD}" \
        -DCMAKE_CUDA_STANDARD="${CXX_STANDARD}" \
        -DAER_ENABLE_CUQUANTUM=TRUE \
        -DCUQUANTUM_ROOT="${CUQUANTUM_ROOT}" \
        -DCUTENSOR_ROOT="${CUTENSOR_ROOT}" \
        -- -j$(nproc)

    WHEEL=$(find "${AER_SRC}/dist" -name "qiskit_aer-*.whl" | sort -V | tail -1)
    [[ -n "$WHEEL" ]] || die "No qiskit_aer wheel found after build — check output above"
    info "Installing: $(basename "$WHEEL")"
    pip install --force-reinstall "$WHEEL"

    cd /
    rm -rf "$AER_SRC"

    # Append cuquantum/cutensor lib paths to pyenv activate so that
    # libcustatevec.so and libcutensor.so are found when the venv is sourced
    # (covers both interactive use and verify-script run_in calls).
    if ! grep -q "cuquantum runtime libraries" /shared/pyenv/bin/activate; then
        cat >> /shared/pyenv/bin/activate <<'ACTIVATE_APPEND'

# cuquantum/cutensor runtime libraries (added by build-all.sh)
for _cuq_pkg in cuquantum cutensor; do
    for _cuq_lib in "${VIRTUAL_ENV}"/lib/python3.*/site-packages/"${_cuq_pkg}"/lib; do
        [ -d "$_cuq_lib" ] && export LD_LIBRARY_PATH="${_cuq_lib}:${LD_LIBRARY_PATH:-}"
    done
done
unset _cuq_pkg _cuq_lib
ACTIVATE_APPEND
    fi

    success "qiskit-aer (GPU) built and installed"
fi

# ── Step 3: Build qrmi wheel from source ─────────────────────────────────────
if [[ "${PACKAGES_ONLY:-0}" == "1" ]]; then
    info "Skipping qrmi and SPANK plugin build (--packages-only)"
else
    # ── Step 3: Build qrmi wheel from source ─────────────────────────────────────
    info "Building qrmi wheel from source (/shared/qrmi) ..."

    # Activate Rust toolchain installed in base image
    source "$HOME/.cargo/env"

    cd /shared/qrmi

   # Install qrmi build dependencies
   if [[ -f requirements-dev.txt ]]; then
      pip install -r requirements-dev.txt --quiet
   fi

   # Build the wheel — release mode for performance
   maturin build --release

  # Find and install the built wheel
  WHEEL=$(find /shared/qrmi/target/wheels -name "qrmi-*.whl" | sort -V | tail -1)
  [[ -n "$WHEEL" ]] || die "No qrmi wheel found after build — check maturin output above"

  info "Installing wheel: $(basename $WHEEL)"
  pip install "$WHEEL"
  success "qrmi installed: $(pip show qrmi | grep Version)"

  # ── Step 4: Build SPANK plugin ────────────────────────────────────────────────
  info "Building SPANK plugin (spank_qrmi.so) ..."

  cd "$SPANK_PLUGIN_DIR"
  mkdir -p build
  cd build

  # Build against the locally built qrmi source for ABI consistency
  cmake -DQRMI_ROOT=/shared/qrmi .. \
    -DCMAKE_BUILD_TYPE=Release \
    2>&1 | tail -5

  make -j$(nproc) 2>&1 | tail -10

  SO_FILE="$SPANK_PLUGIN_DIR/build/spank_qrmi.so"
  [[ -f "$SO_FILE" ]] || die "spank_qrmi.so not found after build — check make output above"

  success "SPANK plugin built: $SO_FILE"
fi

# ── Step 5: Verify ────────────────────────────────────────────────────────────
info "Verifying build artifacts ..."

SO_FILE="$SPANK_PLUGIN_DIR/build/spank_qrmi.so"   # ← move definition here

echo ""
echo "  /shared/pyenv:"
echo "    qiskit:            $(pip show qiskit             | grep Version || echo NOT FOUND)"
echo "    qrmi:              $(pip show qrmi               | grep Version || echo NOT FOUND)"
echo "    qiskit-ibm-runtime:$(pip show qiskit-ibm-runtime | grep Version || echo NOT FOUND)"
echo "    qiskit-addon-sqd:  $(pip show qiskit-addon-sqd   | grep '^Version' || echo NOT FOUND)"
echo "    ffsim:             $(pip show ffsim               | grep Version || echo NOT FOUND)"
echo "    pyscf:             $(pip show pyscf               | grep Version || echo NOT FOUND)"
if [[ -n "${CUDA_VERSION:-}" ]]; then
    _CUPY_PKG="cupy-cuda$(echo "$CUDA_VERSION" | cut -d'-' -f1)x"
    echo "    cupy:              $(pip show "$_CUPY_PKG" | grep Version || echo NOT FOUND)"
else
    echo "    cupy:              N/A (no GPU build)"
fi
echo "    dice-solver:       $(pip show qiskit-addon-dice-solver | grep Version || echo NOT FOUND)"
echo "    qiskit-aer(-gpu):  $(pip show qiskit-aer               | grep Version || echo NOT FOUND)"
echo ""
if [[ -f "$SO_FILE" ]]; then
    echo "  SPANK plugin:"
    echo "    $(ls -lh $SO_FILE)"
else
    echo "  SPANK plugin: skipped (--packages-only)"
fi
echo ""

success "Build complete — /shared is ready for cluster startup"
echo ""
echo "  Next step: ./setup/04-start-cluster.sh"
