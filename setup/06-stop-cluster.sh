#!/bin/bash
# =============================================================================
# 06-stop-cluster.sh
# Stops the Slurm cluster started by podman compose.
#
# Usage:
#   ./setup/06-stop-cluster.sh          # stop and remove containers
#   ./setup/06-stop-cluster.sh --volumes  # also remove named volumes (DESTRUCTIVE)
#
# To start the cluster again:
#   ./setup/04-start-cluster.sh
#
# To view logs before stopping:
#   podman compose -f "$CLUSTER_DIR/docker-compose.yml" logs -f
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CLUSTER_DIR="$REPO_ROOT/cluster"
ENV_FILE="$REPO_ROOT/.env"

# ── Ensure podman-compose is available (may live in project .venv) ───────────
VENV_BIN="$REPO_ROOT/.venv/bin"
[[ -d "$VENV_BIN" ]] && export PATH="$VENV_BIN:$PATH"

# ── Colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

info()    { echo -e "${CYAN}[cluster]${NC} $*"; }
success() { echo -e "${GREEN}[done]${NC}   $*"; }
warn()    { echo -e "${YELLOW}[warn]${NC}   $*"; }
die()     { echo -e "${RED}[error]${NC}  $*" >&2; exit 1; }

# ── Parse args ────────────────────────────────────────────────────────────────
REMOVE_VOLUMES=0
for arg in "$@"; do
    case $arg in
        --volumes) REMOVE_VOLUMES=1 ;;
        *) die "Unknown argument: $arg" ;;
    esac
done

# ── Pre-flight checks ─────────────────────────────────────────────────────────
info "Running pre-flight checks ..."

COMPOSE_FILE="$CLUSTER_DIR/docker-compose.yml"
[[ -f "$COMPOSE_FILE" ]] \
    || die "docker-compose.yml not found\n       Run: ./setup/00b-configure-system.sh"

success "Pre-flight checks passed"
echo ""

# ── Warn on destructive volume removal ────────────────────────────────────────
if [[ "$REMOVE_VOLUMES" -eq 1 ]]; then
    warn "This will remove named volumes: shared state, munge keys, Slurm job"
    warn "data, log data, and the MariaDB accounting database will be lost."
    read -rp "Are you sure you want to continue? [y/N] " CONFIRM
    [[ "$CONFIRM" =~ ^[Yy]$ ]] || { warn "Aborted — no changes made."; exit 0; }
    echo ""
fi

# ── Show current state before stopping ────────────────────────────────────────
info "Current cluster state:"
(cd "$CLUSTER_DIR" && podman compose --env-file "$ENV_FILE" ps) || true
echo ""

# ── Stop cluster ───────────────────────────────────────────────────────────────
info "Stopping cluster ..."
if [[ "$REMOVE_VOLUMES" -eq 1 ]]; then
    (cd "$CLUSTER_DIR" && podman compose --env-file "$ENV_FILE" down --volumes)
else
    (cd "$CLUSTER_DIR" && podman compose --env-file "$ENV_FILE" down)
fi
echo ""

success "Cluster stopped"
echo ""

if [[ "$REMOVE_VOLUMES" -eq 0 ]]; then
    info "Named volumes were preserved (shared, munge keys, job data, DB)."
    info "To also wipe them next time: ./setup/06-stop-cluster.sh --volumes"
fi
echo ""
echo -e "Next step: ${CYAN}./setup/04-start-cluster.sh${NC}"
echo ""
