#!/bin/bash
# =============================================================================
# 03-configure-credentials.sh
# Creates cluster/config/qrmi_config.json from the example file.
# This file is gitignored — credentials are never committed to the repo.
#
# Usage:
#   ./setup/03-configure-credentials.sh
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
EXAMPLE="$REPO_ROOT/cluster/config/qrmi_config.json.example"
TARGET="$REPO_ROOT/cluster/config/qrmi_config.json"

# ── Colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; NC='\033[0m'

info()    { echo -e "${CYAN}[credentials]${NC} $*"; }
success() { echo -e "${GREEN}[done]${NC}       $*"; }
warn()    { echo -e "${YELLOW}[warn]${NC}       $*"; }
die()     { echo -e "${RED}[error]${NC}      $*" >&2; exit 1; }

# ── Check example exists ──────────────────────────────────────────────────────
[[ -f "$EXAMPLE" ]] || die "Example file not found: $EXAMPLE"

# ── Check if already configured ───────────────────────────────────────────────
if [[ -f "$TARGET" ]]; then
    warn "qrmi_config.json already exists at:"
    warn "  $TARGET"
    echo ""
    read -rp "Overwrite it? [y/N] " answer
    [[ "${answer,,}" == "y" ]] || { info "Keeping existing file. Done."; exit 0; }
    echo ""
fi

# ── Copy example ──────────────────────────────────────────────────────────────
cp "$EXAMPLE" "$TARGET"
success "Created $TARGET"
echo ""

# ── Instructions ─────────────────────────────────────────────────────────────
echo -e "${CYAN}Next steps:${NC}"
echo ""
echo "  Edit the file and replace all placeholders with your credentials:"
echo ""
echo "    $TARGET"
echo ""
echo "  The file contains three backend types:"
echo ""
echo "    direct-access          IBM Quantum Direct Access"
echo "                           Needs: IAM API key, CRN, AWS S3 credentials"
echo ""
echo "    qiskit-runtime-service IBM Quantum Platform"
echo "                           Needs: IAM API key, IQP instance CRN"
echo "                           Endpoints are pre-filled (standard IBM URLs)"
echo ""
echo "    pasqal-cloud           Pasqal neutral atom backend"
echo "                           Needs: Pasqal Cloud endpoint URL"
echo ""
echo "  Remove any backend blocks you are not using."
echo ""
echo "  To open the file now:"
echo "    \${EDITOR:-vi} $TARGET"
echo ""

# ── Offer to open editor ──────────────────────────────────────────────────────
read -rp "Open in editor now? [y/N] " answer
if [[ "${answer,,}" == "y" ]]; then
    EDITOR="${EDITOR:-vi}"
    info "Opening with $EDITOR ..."
    "$EDITOR" "$TARGET"
    echo ""
fi

# ── Validate no placeholders remain ───────────────────────────────────────────
if grep -q "<YOUR" "$TARGET" 2>/dev/null; then
    echo ""
    warn "The following placeholders are still unfilled:"
    grep -n "<YOUR" "$TARGET" | sed 's/^/    /'
    echo ""
    warn "Fill them in before running setup/04-start-cluster.sh"
    warn "The cluster will start but QRMI job submission will fail."
else
    echo ""
    success "No placeholders detected — credentials look complete."
fi

echo ""
info "Next step: ./setup/04-start-cluster.sh"
