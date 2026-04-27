#!/bin/bash
# =============================================================================
# utilities/install-packages.sh
# Install or upgrade packages into /shared/pyenv without touching the frozen
# baseline, qrmi wheel, or SPANK plugin.
#
# Uses a running cluster container if available; falls back to the builder
# image if the cluster is not running.
#
# Usage:
#   ./utilities/install-packages.sh <pkg> [<pkg> ...]
#   ./utilities/install-packages.sh --from-file <file>
#   ./utilities/install-packages.sh --from-file <file> <pkg> [<pkg> ...]
#
# Examples:
#   ./utilities/install-packages.sh cupy-cuda12x==14.0.1
#   ./utilities/install-packages.sh --from-file requirements/gpu-extras.txt
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SHARED_DIR="$REPO_ROOT/shared"
ENV_FILE="$REPO_ROOT/.env"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; NC='\033[0m'

info()    { echo -e "${CYAN}[install]${NC} $*"; }
success() { echo -e "${GREEN}[done]${NC}  $*"; }
warn()    { echo -e "${YELLOW}[warn]${NC}  $*"; }
die()     { echo -e "${RED}[error]${NC} $*" >&2; exit 1; }

# ── Parse arguments ───────────────────────────────────────────────────────────
PACKAGES=()
FROM_FILE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --from-file)
            [[ -n "${2:-}" ]] || die "--from-file requires a file argument"
            FROM_FILE="$2"
            shift 2
            ;;
        --*)
            die "Unknown option: $1"
            ;;
        *)
            PACKAGES+=("$1")
            shift
            ;;
    esac
done

if [[ -n "$FROM_FILE" ]]; then
    [[ -f "$FROM_FILE" ]] || die "File not found: $FROM_FILE"
fi

if [[ ${#PACKAGES[@]} -eq 0 && -z "$FROM_FILE" ]]; then
    echo "Usage: $0 [--from-file <file>] [<package> ...]"
    exit 1
fi

# ── Load .env ─────────────────────────────────────────────────────────────────
if [[ -f "$ENV_FILE" ]]; then
    set -a; source "$ENV_FILE"; set +a
fi
IMAGE_TAG="${IMAGE_TAG:-latest}"

# ── Find a container to use ───────────────────────────────────────────────────
# Prefer a running cluster node; fall back to builder image.
EXEC_MODE=""
EXEC_TARGET=""

for candidate in c1 c2 q1 qg1 g1 login; do
    if podman ps --format "{{.Names}}" 2>/dev/null | grep -q "^${candidate}$"; then
        EXEC_MODE="exec"
        EXEC_TARGET="$candidate"
        break
    fi
done

if [[ -z "$EXEC_MODE" ]]; then
    if podman image exists "slurm-qiskit-builder:${IMAGE_TAG}" 2>/dev/null; then
        EXEC_MODE="run"
        EXEC_TARGET="slurm-qiskit-builder:${IMAGE_TAG}"
    else
        die "No running cluster containers and no builder image found.\n       Start the cluster with ./setup/04-start-cluster.sh\n       or build images with ./setup/01-build-images.sh"
    fi
fi

if [[ "$EXEC_MODE" == "exec" ]]; then
    info "Using running container: $EXEC_TARGET"
else
    info "No cluster running — using builder image: $EXEC_TARGET"
fi

# ── Build pip install args ────────────────────────────────────────────────────
PIP_ARGS=""
if [[ -n "$FROM_FILE" ]]; then
    ABS_FILE="$(cd "$(dirname "$FROM_FILE")" && pwd)/$(basename "$FROM_FILE")"
    PIP_ARGS="-r $ABS_FILE"
fi
if [[ ${#PACKAGES[@]} -gt 0 ]]; then
    PIP_ARGS="$PIP_ARGS ${PACKAGES[*]}"
fi

info "Installing: $PIP_ARGS"
echo ""

# ── Show before state for named packages ──────────────────────────────────────
if [[ ${#PACKAGES[@]} -gt 0 ]]; then
    info "Current versions:"
    for pkg in "${PACKAGES[@]}"; do
        pkg_name="${pkg%%[>=<!]*}"
        if [[ "$EXEC_MODE" == "exec" ]]; then
            VER=$(podman exec "$EXEC_TARGET" bash -c \
                "source /shared/pyenv/bin/activate && pip show '$pkg_name' 2>/dev/null | grep Version || echo 'not installed'")
        else
            VER=$(podman run --rm -v "$SHARED_DIR:/shared:z" "$EXEC_TARGET" bash -c \
                "source /shared/pyenv/bin/activate && pip show '$pkg_name' 2>/dev/null | grep Version || echo 'not installed'")
        fi
        echo "    $pkg_name: $VER"
    done
    echo ""
fi

# ── Run pip install ───────────────────────────────────────────────────────────
if [[ "$EXEC_MODE" == "exec" ]]; then
    podman exec "$EXEC_TARGET" bash -c \
        "source /shared/pyenv/bin/activate && pip install $PIP_ARGS"
else
    if [[ -n "$FROM_FILE" ]]; then
        podman run --rm \
            -v "$SHARED_DIR:/shared:z" \
            -v "$ABS_FILE:/tmp/packages.txt:ro" \
            "$EXEC_TARGET" bash -c \
            "source /shared/pyenv/bin/activate && pip install -r /tmp/packages.txt ${PACKAGES[*]+"${PACKAGES[*]}"}"
    else
        podman run --rm \
            -v "$SHARED_DIR:/shared:z" \
            "$EXEC_TARGET" bash -c \
            "source /shared/pyenv/bin/activate && pip install ${PACKAGES[*]}"
    fi
fi

# ── Show after state for named packages ───────────────────────────────────────
echo ""
if [[ ${#PACKAGES[@]} -gt 0 ]]; then
    success "Installed versions:"
    for pkg in "${PACKAGES[@]}"; do
        pkg_name="${pkg%%[>=<!]*}"
        if [[ "$EXEC_MODE" == "exec" ]]; then
            VER=$(podman exec "$EXEC_TARGET" bash -c \
                "source /shared/pyenv/bin/activate && pip show '$pkg_name' 2>/dev/null | grep Version || echo 'not found'")
        else
            VER=$(podman run --rm -v "$SHARED_DIR:/shared:z" "$EXEC_TARGET" bash -c \
                "source /shared/pyenv/bin/activate && pip show '$pkg_name' 2>/dev/null | grep Version || echo 'not found'")
        fi
        echo "    $pkg_name: $VER"
    done
fi

echo ""
success "Done — /shared/pyenv updated"
echo ""
echo -e "  ${CYAN}Note:${NC} Running containers pick up the change immediately (bind-mount)."
echo -e "  If a package was replaced (e.g. qiskit-aer CPU→GPU), restart affected nodes:"
echo -e "    podman restart g1 qg1"
echo ""
