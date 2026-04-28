"""
config.py — Single source of truth for the QAOA MaxCut workflow.
"""

import os
import numpy as np
from pathlib import Path
from qiskit.circuit.library import QAOAAnsatz
from qiskit.quantum_info import SparsePauliOp

# ── Paths ──────────────────────────────────────────────────────────────────
# RUN_DIR is set by submit.sh and exported to every job in the chain.
# Falls back to a local data/ folder for interactive use.
RUN_DIR = Path(os.environ.get("RUN_DIR", Path(__file__).parent / "data"))

PARAMS_FILE          = RUN_DIR / "params.npy"
EXPECTATION_FILE     = RUN_DIR / "expectation_values.npy"
ENERGY_HISTORY_FILE  = RUN_DIR / "energy_history.npy"
ADAM_STATE_FILE      = RUN_DIR / "adam_state.json"
ITERATION_FILE       = RUN_DIR / "iteration.txt"

# ── Problem: MaxCut on a 4-node ring graph ─────────────────────────────────
#
#   0 ── 1
#   |    |
#   3 ── 2
#
# Optimal cut = 4 (every edge is cut when nodes split {0,2} vs {1,3})
N_QUBITS     = 4
EDGES        = [(0, 1), (1, 2), (2, 3), (3, 0)]
REPS         = 1          # QAOA depth p
N_PARAMS     = 2 * REPS   # [beta[0], gamma[0]] — QAOAAnsatz parameter order
MAX_CUT_VALUE = 4

# ── Optimizer (Adam gradient ascent on ⟨C⟩) ───────────────────────────────
LEARNING_RATE   = 0.1
BETA1           = 0.9
BETA2           = 0.999
EPSILON         = 1e-8
MAX_ITERATIONS  = 30
CONVERGENCE_TOL = 1e-4   # stop when ||grad|| < tol


def build_cost_operator() -> SparsePauliOp:
    """
    MaxCut cost Hamiltonian: C = Σ_(i,j)∈E (I - Z_i Z_j) / 2

    Maximising ⟨C⟩ = maximising the expected number of cut edges.
    Qiskit uses little-endian Pauli strings (qubit 0 is rightmost).
    """
    terms = []
    for i, j in EDGES:
        zz = ["I"] * N_QUBITS
        zz[N_QUBITS - 1 - i] = "Z"
        zz[N_QUBITS - 1 - j] = "Z"
        terms.append(("".join(zz), -0.5))
    terms.append(("I" * N_QUBITS, 0.5 * len(EDGES)))
    return SparsePauliOp.from_list(terms)


def build_qaoa_circuit() -> QAOAAnsatz:
    return QAOAAnsatz(cost_operator=build_cost_operator(), reps=REPS)
