"""
config.py — Single source of truth for all workflow parameters.

Every script in the pipeline imports from here. Never hard-code
a physical or SQD parameter in a step script.
"""

import os
from pathlib import Path
import numpy as np

# ── Paths ──────────────────────────────────────────────────────────────────
# RUN_DIR is injected by the SLURM shell scripts via the environment.
# This ensures all steps in a job chain read/write to the same directory.
# Falls back to a local "data/" folder for interactive/development use.
RUN_DIR = Path(os.environ.get("RUN_DIR", Path(__file__).parent / "data"))

CIRCUITS_FILE     = RUN_DIR / "circuits.qpy"
ISA_CIRCUITS_FILE = RUN_DIR / "isa_circuits.qpy"
COUNTS_FILE       = RUN_DIR / "counts.json"

# ── Physical model: Single-impurity Anderson model ─────────────────────────
N_BATH         = 7        # number of bath sites
V              = 1        # hybridization amplitude
T_HOP          = 1        # bath hopping amplitude  (renamed from 't' to avoid
                          # shadowing Python's built-in)
U              = 10       # impurity onsite repulsion
IMPURITY_INDEX = 0        # impurity is placed on the first site/qubit

# Derived physical quantities — computed once here, imported everywhere
EPS    = -U / 2           # chemical potential for the impurity
N_MODES = N_BATH + 1      # total number of modes (impurity + bath)
NELEC  = (N_MODES // 2, N_MODES // 2)   # (alpha, beta) electron counts

def build_hamiltonians():
    """
    Build and return (h1e, h2e) from the model parameters above.

    Called by mapping.py (to build circuits) and postprocessing.py
    (to diagonalize). Keeping the construction in one function
    guarantees both steps use an identical Hamiltonian.
    """
    h1e = (
        -T_HOP * np.diag(np.ones(N_BATH), k=1)
        - T_HOP * np.diag(np.ones(N_BATH), k=-1)
    )
    h1e[IMPURITY_INDEX, IMPURITY_INDEX + 1] = -V
    h1e[IMPURITY_INDEX + 1, IMPURITY_INDEX] = -V
    h1e[IMPURITY_INDEX, IMPURITY_INDEX]     = EPS

    h2e = np.zeros((N_MODES, N_MODES, N_MODES, N_MODES))
    h2e[IMPURITY_INDEX, IMPURITY_INDEX,
        IMPURITY_INDEX, IMPURITY_INDEX] = U

    return h1e, h2e

# ── Krylov / circuit generation ────────────────────────────────────────────
DT             = 0.2      # Trotter time step
N_KRYLOV       = 8        # number of Krylov basis states (circuit depth steps)

# ── Quantum execution ───────────────────────────────────────────────────────
DEFAULT_SHOTS  = 10_000

# ── Transpilation ───────────────────────────────────────────────────────────
OPTIMIZATION_LEVEL = 3

# ── SQD / postprocessing ────────────────────────────────────────────────────
SAMPLES_PER_BATCH = 300
NUM_BATCHES       = 3
MAX_ITERATIONS    = 10
SYMMETRIZE_SPIN   = True
SEED              = 24
EXACT_ENERGY      = -13.422491814605827
