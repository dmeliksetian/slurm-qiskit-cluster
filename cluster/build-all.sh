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
info "Installing pinned packages from pyenv-frozen.txt ..."
info "(this will take several minutes — pyscf, jax, ffsim are large)"
pip install -r /build/pyenv-frozen.txt 
success "Pinned packages installed"

# ── Step 2b: Install GPU packages into pyenv ──────────────────────────────────
if [[ "${INSTALL_GPU_PACKAGES:-0}" == "1" ]]; then
    info "Installing GPU packages (cupy-cuda12x, qiskit-addon-dice-solver) ..."
    pip install cupy-cuda12x==14.0.1
    pip install qiskit-addon-dice-solver
    success "GPU packages installed"
fi

# ── Step 2c: Install quantum-GPU packages into pyenv ─────────────────────────
# qiskit-aer-gpu requires CUDA 12.x at runtime — only functional on qg1.
# Like CuPy, it lives in /shared/pyenv rather than baked into the image.
# qiskit-aer-gpu conflicts with qiskit-aer (CPU) — uninstall it first if
# present (e.g. installed via pyenv-frozen.txt) to avoid a broken mixed state.
if [[ "${INSTALL_QUANTUM_GPU_PACKAGES:-0}" == "1" ]]; then
    info "Installing quantum-GPU packages (qiskit-aer-gpu) ..."
    if pip show qiskit-aer &>/dev/null; then
        warn "qiskit-aer (CPU) found — removing before installing qiskit-aer-gpu ..."
        pip uninstall -y qiskit-aer
    fi
    pip install qiskit-aer-gpu
    success "Quantum-GPU packages installed"
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
echo "    cupy:              $(pip show cupy-cuda12x             | grep Version || echo NOT FOUND)"
echo "    dice-solver:       $(pip show qiskit-addon-dice-solver | grep Version || echo NOT FOUND)"
echo "    qiskit-aer-gpu:    $(pip show qiskit-aer-gpu           | grep Version || echo NOT FOUND)"
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
