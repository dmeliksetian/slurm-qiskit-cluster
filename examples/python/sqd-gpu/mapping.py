"""
mapping.py — Step 1: Build Krylov basis circuits and save them.
"""

import numpy as np
import scipy
import ffsim
from qiskit import QuantumCircuit, QuantumRegister
from qiskit.circuit.library import CPhaseGate, XGate, XXPlusYYGate

from config import (
    N_MODES, NELEC, U, DT, N_KRYLOV,
    IMPURITY_INDEX, CIRCUITS_FILE,
    build_hamiltonians,
)
from common import save_circuits, get_logger

log = get_logger("mapping")


def initial_state(q_circuit, norb, nocc):
    for i in range(nocc):
        q_circuit.append(XGate(), [i])
        q_circuit.append(XGate(), [norb + i])
    rot = XXPlusYYGate(np.pi / 2, -np.pi / 2)
    for i in range(3):
        for j in range(nocc - i - 1, nocc + i, 2):
            q_circuit.append(rot, [j, j + 1])
            q_circuit.append(rot, [norb + j, norb + j + 1])
    q_circuit.append(rot, [j + 1, j + 2])
    q_circuit.append(rot, [norb + j + 1, norb + j + 2])


def append_diagonal_evolution(dt, u, impurity_qubit, num_orb, q_circuit):
    if u != 0:
        q_circuit.append(
            CPhaseGate(-dt / 2 * u),
            [impurity_qubit, impurity_qubit + num_orb],
        )


if __name__ == "__main__":
    h1e, _ = build_hamiltonians()
    Utar = scipy.linalg.expm(-1j * DT * h1e)
    free_fermion_evolution = ffsim.qiskit.OrbitalRotationJW(N_MODES, Utar)

    nocc = NELEC[0]
    qubits = QuantumRegister(2 * N_MODES, name="q")
    init_state = QuantumCircuit(qubits)
    initial_state(init_state, N_MODES, nocc)

    circuits = []
    for i in range(N_KRYLOV):
        circ = init_state.copy()
        for _ in range(i):
            append_diagonal_evolution(DT, U, IMPURITY_INDEX, N_MODES, circ)
            circ.append(free_fermion_evolution, qubits)
            append_diagonal_evolution(DT, U, IMPURITY_INDEX, N_MODES, circ)
        circ.measure_all()
        circuits.append(circ)

    log.info(f"Generated {len(circuits)} Krylov circuits (N_KRYLOV={N_KRYLOV})")
    save_circuits(CIRCUITS_FILE, circuits)
    log.info(f"Saved circuits to {CIRCUITS_FILE}")
