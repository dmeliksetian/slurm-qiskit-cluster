#!/bin/bash
# =============================================================================
# 04-start-cluster.sh
# Starts the Slurm cluster with podman compose.
# Waits for slurmctld to become ready before exiting.
#
# Usage:
#   ./setup/04-start-cluster.sh
#
# To stop the cluster:
#   podman compose down
#
# To view logs:
#   podman compose logs -f
#   podman logs -f slurmctld
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SHARED_DIR="$REPO_ROOT/shared"

# ── Colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

info()    { echo -e "${CYAN}[cluster]${NC} $*"; }
success() { echo -e "${GREEN}[done]${NC}   $*"; }
warn()    { echo -e "${YELLOW}[warn]${NC}   $*"; }
die()     { echo -e "${RED}[error]${NC}  $*" >&2; exit 1; }

# ── Pre-flight checks ─────────────────────────────────────────────────────────
info "Running pre-flight checks ..."

# pyenv must be built
[[ -d "$SHARED_DIR/pyenv" ]] \
    || die "/shared/pyenv not found\n       Run: ./setup/02-build-shared.sh"

# SPANK plugin must be built
SO_FILE="$SHARED_DIR/spank-plugins/plugins/spank_qrmi/build/spank_qrmi.so"
[[ -f "$SO_FILE" ]] \
    || die "spank_qrmi.so not found\n       Run: ./setup/02-build-shared.sh"

# Credentials must be configured
QRMI_CONFIG="$REPO_ROOT/cluster/config/qrmi_config.json"
[[ -f "$QRMI_CONFIG" ]] \
    || die "qrmi_config.json not found\n       Run: ./setup/03-configure-credentials.sh"

if grep -q "<YOUR" "$QRMI_CONFIG" 2>/dev/null; then
    die "qrmi_config.json still has unfilled placeholders\n       Run: ./setup/03-configure-credentials.sh"
fi

success "Pre-flight checks passed"
echo ""

# ── Start cluster ─────────────────────────────────────────────────────────────
info "Starting cluster ..."
(cd "$REPO_ROOT" && podman compose up -d)
echo ""

# ── Wait for slurmctld ────────────────────────────────────────────────────────
info "Waiting for slurmctld to become ready ..."

MAX_WAIT=60
ELAPSED=0
until podman exec slurmctld sinfo &>/dev/null 2>&1; do
    if [[ "$ELAPSED" -ge "$MAX_WAIT" ]]; then
        echo ""
        die "slurmctld did not become ready within ${MAX_WAIT}s\n       Check logs: podman logs slurmctld"
    fi
    echo -n "."
    sleep 2
    ((ELAPSED+=2)) || true
done

echo ""
success "slurmctld is ready"
echo ""

# ── Show cluster state ────────────────────────────────────────────────────────
echo -e "${BOLD}Cluster nodes:${NC}"
podman exec slurmctld sinfo
echo ""

echo -e "${BOLD}SPANK plugin check (should show --qpu option):${NC}"
podman exec slurmctld sbatch --help 2>&1 | grep -A2 "Options provided by plugins" || \
    warn "SPANK plugin options not visible — check plugstack.conf and spank_qrmi.so"
echo ""

# ── Running containers ────────────────────────────────────────────────────────
echo -e "${BOLD}Running containers:${NC}"
podman compose ps
echo ""

success "Cluster is up"
echo ""
echo "  Login to a node:    podman exec -it c1 bash"
echo "  View logs:          podman compose logs -f"
echo "  Stop cluster:       podman compose down"
echo ""
echo -e "Next step: ${CYAN}./setup/05-verify.sh${NC}"
echo ""
