#!/bin/bash
# =============================================================================
# 01-build-images.sh
# Builds all container images from the multi-stage Dockerfile.
# Must be run before 02-build-shared.sh and before starting the cluster.
#
# Usage:
#   ./setup/01-build-images.sh [--no-cache]
#
# Options:
#   --no-cache    Force full rebuild (bypasses layer cache)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CLUSTER_DIR="$REPO_ROOT/cluster"
ENV_FILE="$REPO_ROOT/.env"

# ── Colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

info()    { echo -e "${CYAN}[build]${NC} $*"; }
success() { echo -e "${GREEN}[done]${NC}  $*"; }
warn()    { echo -e "${YELLOW}[warn]${NC}  $*"; }
die()     { echo -e "${RED}[error]${NC} $*" >&2; exit 1; }

# ── Parse arguments ───────────────────────────────────────────────────────────
NO_CACHE=""
QUANTUM_GPU=0
for arg in "$@"; do
    case $arg in
        --no-cache)    NO_CACHE="--no-cache" ;;
        --quantum-gpu) QUANTUM_GPU=1          ;;
        *) die "Unknown argument: $arg" ;;
    esac
done

# ── Ensure podman-compose is available (may live in project .venv) ───────────
VENV_BIN="$REPO_ROOT/.venv/bin"
[[ -d "$VENV_BIN" ]] && export PATH="$VENV_BIN:$PATH"

# ── Load .env ─────────────────────────────────────────────────────────────────
if [[ -f "$ENV_FILE" ]]; then
    set -a; source "$ENV_FILE"; set +a
    info "Loaded .env"
else
    die ".env not found — copy .env.example to .env and set SLURM_TAG"
fi

# ── Validate required variables ───────────────────────────────────────────────
[[ -n "${SLURM_TAG:-}" ]]  || die "SLURM_TAG not set in .env (e.g. SLURM_TAG=slurm-23-11-9-1)"
[[ -n "${IMAGE_TAG:-}" ]]  || IMAGE_TAG="latest" && warn "IMAGE_TAG not set — using 'latest'"

info "SLURM_TAG:    $SLURM_TAG"
info "IMAGE_TAG:    $IMAGE_TAG"
info "Build context: $REPO_ROOT"
[[ "$QUANTUM_GPU" -eq 1 ]] && info "Building builder-gpu image (--quantum-gpu)"
[[ -n "$NO_CACHE" ]] && warn "Cache disabled (--no-cache)"

if [[ "$QUANTUM_GPU" -eq 1 ]]; then
    if [[ -z "${CUDA_ARCH:-}" || -z "${CUDA_VERSION:-}" ]]; then
        die "--quantum-gpu requires a CUDA-capable GPU.\n       No GPU detected or 00b-configure-system.sh not yet run.\n       Run: ./setup/00b-configure-system.sh"
    fi
fi
echo ""

# ── Validate credentials exist before baking into images ──────────────────────
QRMI_CONFIG="$CLUSTER_DIR/config/qrmi_config.json"
if [[ ! -f "$QRMI_CONFIG" ]]; then
    die "cluster/config/qrmi_config.json not found\n       Run: ./setup/03-configure-credentials.sh"
fi
if grep -q "<YOUR" "$QRMI_CONFIG" 2>/dev/null; then
    die "qrmi_config.json still has unfilled placeholders\n       Run: ./setup/03-configure-credentials.sh"
fi

# ── Build builder image ───────────────────────────────────────────────────────
info "Building builder image ..."
podman build $NO_CACHE \
    --target builder \
    --tag "slurm-qiskit-builder:${IMAGE_TAG}" \
    --build-arg SLURM_TAG="${SLURM_TAG}" \
    --build-arg GOSU_VERSION="${GOSU_VERSION:-1.17}" \
    --build-arg MY_PMIX_VERSION="${MY_PMIX_VERSION:-4.2.9}" \
    --build-arg OPENMPI_VERSION="${OPENMPI_VERSION:-4.1.6}" \
    --file "$CLUSTER_DIR/Dockerfile" \
    "$REPO_ROOT"
success "builder image built"

# ── Build builder-gpu image (only when --quantum-gpu) ─────────────────────────
if [[ "$QUANTUM_GPU" -eq 1 ]]; then
    info "Building builder-gpu image ..."
    podman build $NO_CACHE \
        --target builder-gpu \
        --tag "slurm-qiskit-builder-gpu:${IMAGE_TAG}" \
        --build-arg SLURM_TAG="${SLURM_TAG}" \
        --build-arg GOSU_VERSION="${GOSU_VERSION:-1.17}" \
        --build-arg MY_PMIX_VERSION="${MY_PMIX_VERSION:-4.2.9}" \
        --build-arg OPENMPI_VERSION="${OPENMPI_VERSION:-4.1.6}" \
        --build-arg CUDA_VERSION="${CUDA_VERSION:-12-9}" \
        --file "$CLUSTER_DIR/Dockerfile" \
        "$REPO_ROOT"
    success "builder-gpu image built"
fi

# ── Build runtime images via compose ─────────────────────────────────────────
info "Building cluster images (control, compute-base, quantum, gpu, quantum-gpu) ..."
info "Note: gpu and quantum-gpu stages are large — this may take 10-20 minutes"
echo ""

(cd "$CLUSTER_DIR" && podman compose --env-file "$ENV_FILE" build \
    --build-arg SLURM_TAG="${SLURM_TAG}" \
    --build-arg GOSU_VERSION="${GOSU_VERSION:-1.17}" \
    --build-arg MY_PMIX_VERSION="${MY_PMIX_VERSION:-4.2.9}" \
    --build-arg OPENMPI_VERSION="${OPENMPI_VERSION:-4.1.6}" \
    $NO_CACHE)

success "All images built"
echo ""

# ── Summary ───────────────────────────────────────────────────────────────────
echo -e "${BOLD}Images available:${NC}"
podman images | grep -E "slurm-qiskit|REPOSITORY" || true
echo ""
echo -e "Next step: ${CYAN}./setup/02-build-shared.sh${NC}"
echo ""
