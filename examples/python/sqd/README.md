# SQD — Sample-based Quantum Diagonalization

**Demonstrates:** A complete SQD workflow as a 4-step SLURM job chain with single-process postprocessing.

## What it does

Solves the Single-Impurity Anderson Model (SIAM) — a correlated electron system — by combining QPU sampling with classical diagonalization. Each step runs as a separate SLURM job, passing intermediate results via files in a `data/` directory.

## Workflow

```
submit.sh
  ├── [1] mapping.sh       → mapping.py
  │         Build d=8 Krylov basis circuits from the SIAM Hamiltonian.
  │         Saves: data/circuits.qpy
  │
  ├── [2] optimization.sh  → optimization.py
  │         Transpile circuits to ISA using the QPU target (optimization_level=3).
  │         Saves: data/isa_circuits.qpy
  │
  ├── [3] execution.sh     → execution.py        (partition=quantum, ibm_torino)
  │         Sample all ISA circuits via SamplerV2 (10,000 shots each).
  │         Saves: data/counts.json
  │
  └── [4] postprocessing.sh → postprocessing.py
            Iterative SQD: configuration recovery → subsampling →
            diagonalize_fermionic_hamiltonian → repeat.
            Prints ground state energy vs. exact reference.
```

## Files

| File | Description |
|------|-------------|
| `mapping.py` | SIAM circuit generation with ffsim Trotter evolution |
| `optimization.py` | ISA transpilation via QRMI backend |
| `execution.py` | QPU sampling via QRMI SamplerV2 |
| `postprocessing.py` | Classical SQD diagonalization |
| `submit.sh` | Submits the full 4-job chain automatically |

## Run

```bash
bash submit.sh
```
