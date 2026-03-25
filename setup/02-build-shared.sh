#!/bin/bash
# =============================================================================
# 02-build-shared.sh
# Runs the builder container to populate ./shared with:
#   - /shared/pyenv        Python venv + all pinned quantum packages + qrmi
#   - /shared/spank-plugins/plugins/spank_qrmi/build/spank_qrmi.so
#
# By default skips if /shared/pyenv already exists. Use --force to rebuild.
#
# Usage:
#   ./setup/02-build-shared.sh [--force] [--gpu] [--quantum-gpu] [--packages-only]
#
#   --force          Remove and rebuild /shared/pyenv from scratch
#   --gpu            Install CuPy into /shared/pyenv (NVIDIA CUDA only, for g1)
#   --quantum-gpu    Install qiskit-aer-gpu into /shared/pyenv (NVIDIA CUDA only, for qg1)
#   --packages-only  Skip qrmi + SPANK plugin build — pip packages only (faster updates)
#
# Prerequisites:
#   - 01-build-images.sh must have been run (builder image must exist)
#   - git submodule update --init --recursive must have been run
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SHARED_DIR="$REPO_ROOT/shared"
ENV_FILE="$REPO_ROOT/.env"

# ── Colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; NC='\033[0m'

info()    { echo -e "${CYAN}[shared]${NC} $*"; }
success() { echo -e "${GREEN}[done]${NC}  $*"; }
warn()    { echo -e "${YELLOW}[warn]${NC}  $*"; }
die()     { echo -e "${RED}[error]${NC} $*" >&2; exit 1; }

# ── Parse arguments ───────────────────────────────────────────────────────────
FORCE=0
GPU=0
QUANTUM_GPU=0
PACKAGES_ONLY=0
for arg in "$@"; do
    case $arg in
        --force)         FORCE=1         ;;
        --gpu)           GPU=1           ;;
        --quantum-gpu)   QUANTUM_GPU=1   ;;
        --packages-only) PACKAGES_ONLY=1 ;;
        *) die "Unknown argument: $arg" ;;
    esac
done

# ── Warn if GPU flags used without a detectable NVIDIA GPU ────────────────────
if [[ "$GPU" -eq 1 || "$QUANTUM_GPU" -eq 1 ]]; then
    if ! command -v nvidia-smi &>/dev/null || ! nvidia-smi &>/dev/null; then
        warn "--gpu/--quantum-gpu specified but no NVIDIA GPU detected on this host"
        warn "Packages will be installed into /shared/pyenv but will only be"
        warn "functional at runtime on nodes with NVIDIA CUDA (g1, qg1)"
    fi
fi

# ── Load .env ─────────────────────────────────────────────────────────────────
if [[ -f "$ENV_FILE" ]]; then
    set -a; source "$ENV_FILE"; set +a
fi
IMAGE_TAG="${IMAGE_TAG:-latest}"

# ── Validate builder image exists ─────────────────────────────────────────────
if ! podman image exists "slurm-qiskit-builder:${IMAGE_TAG}"; then
    die "Builder image not found: slurm-qiskit-builder:${IMAGE_TAG}\n       Run: ./setup/01-build-images.sh"
fi

# ── Validate submodules are populated ─────────────────────────────────────────
[[ -f "$SHARED_DIR/qrmi/Cargo.toml" ]] \
    || die "shared/qrmi submodule not initialised\n       Run: git submodule update --init --recursive"
[[ -d "$SHARED_DIR/spank-plugins/plugins" ]] \
    || die "shared/spank-plugins submodule not initialised\n       Run: git submodule update --init --recursive"

# ── Check if already built ────────────────────────────────────────────────────
if [[ -d "$SHARED_DIR/pyenv" ]] && [[ "$FORCE" -eq 0 ]] && [[ "$PACKAGES_ONLY" -eq 0 ]]; then
    warn "/shared/pyenv already exists — skipping build"
    warn "Use --force to rebuild: ./setup/02-build-shared.sh --force"
    warn "Use --packages-only to re-run pip installs only: ./setup/02-build-shared.sh --packages-only"
    echo ""

    # Still check for the SPANK plugin
    SO_FILE="$SHARED_DIR/spank-plugins/plugins/spank_qrmi/build/spank_qrmi.so"
    if [[ -f "$SO_FILE" ]]; then
        success "spank_qrmi.so already present"
    else
        warn "spank_qrmi.so not found — running builder to build it"
        FORCE=1
    fi

    if [[ "$FORCE" -eq 0 ]]; then
        echo -e "Next step: ${CYAN}./setup/03-configure-credentials.sh${NC}"
        echo ""
        exit 0
    fi
fi

# ── If --force, remove existing pyenv ─────────────────────────────────────────
if [[ "$FORCE" -eq 1 ]] && [[ -d "$SHARED_DIR/pyenv" ]]; then
    warn "--force specified — removing existing /shared/pyenv"
    rm -rf "$SHARED_DIR/pyenv"
fi

# ── Create shared subdirectories on host ──────────────────────────────────────
mkdir -p "$SHARED_DIR/data"

# ── Run builder container ─────────────────────────────────────────────────────
info "Running builder container ..."
info "This will take 10-20 minutes (pyscf, jax, ffsim are large packages)"
echo ""

podman run --rm \
    --name slurm-qiskit-builder-run \
    -v "$SHARED_DIR:/shared:z" \
    -e INSTALL_GPU_PACKAGES="${GPU}" \
    -e INSTALL_QUANTUM_GPU_PACKAGES="${QUANTUM_GPU}" \
    -e PACKAGES_ONLY="${PACKAGES_ONLY}" \
    "slurm-qiskit-builder:${IMAGE_TAG}"

# ── Verify outputs ────────────────────────────────────────────────────────────
echo ""
info "Verifying outputs ..."

ERRORS=0

if [[ -d "$SHARED_DIR/pyenv" ]]; then
    success "/shared/pyenv created"
else
    warn "/shared/pyenv not found — builder may have failed"
    ((ERRORS++)) || true
fi

SO_FILE="$SHARED_DIR/spank-plugins/plugins/spank_qrmi/build/spank_qrmi.so"
if [[ -f "$SO_FILE" ]]; then
    success "spank_qrmi.so built: $(ls -lh $SO_FILE | awk '{print $5}')"
else
    warn "spank_qrmi.so not found — SPANK plugin build may have failed"
    ((ERRORS++)) || true
fi

echo ""
if [[ "$ERRORS" -gt 0 ]]; then
    die "Build completed with errors — check output above"
fi

success "shared/ is ready"
echo ""
echo -e "Next step: ${CYAN}./setup/03-configure-credentials.sh${NC}"
echo ""
