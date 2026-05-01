# SQD-GPU — Sample-based Quantum Diagonalization with GPU Postprocessing

**Demonstrates:** SQD workflow where the classical postprocessing runs on the GPU node (g1) using CuPy for array operations.

## What it does

Same SIAM problem as `sqd/` and `sqd-mpi/`, with the same QPU execution step. The difference is in postprocessing: the Hamiltonians are built as CuPy arrays on the GPU, the per-iteration occupancy averaging is computed with `cp.mean`, and arrays are converted to NumPy only at the `solve_sci_batch` boundary (ffsim/PySCF expects NumPy inputs). The SQD batches are solved sequentially on a single process — no MPI.

## Workflow

```
submit.sh
  ├── [1] mapping.sh       → mapping.py          (1 node)
  ├── [2] optimization.sh  → optimization.py     (1 node)
  ├── [3] execution.sh     → execution.py        (partition=quantum, ibm_torino)
  └── [4] postprocessing.sh → postprocessing.py  (g1, GPU)
            h1e, h2e built as CuPy arrays on GPU.
            SQD iterative loop: config recovery → subsampling →
            solve_sci_batch (numpy boundary) → cp.mean(occupancies).
            Prints ground state energy vs. exact reference.
```

## GPU boundary

```
CuPy (GPU)                     NumPy (CPU)
──────────────────────────────────────────────
h1e, h2e construction
avg_occupancy averaging
                          ──►  cp.asnumpy() at solve_sci_batch call
                               ffsim / PySCF eigensolver
```

## Files

| File | Description |
|------|-------------|
| `config.py` | Parameters and path management (shared with sqd-mpi) |
| `common.py` | Logging and I/O helpers (shared with sqd-mpi) |
| `mapping.py` | Circuit generation |
| `optimization.py` | ISA transpilation |
| `execution.py` | QPU sampling |
| `postprocessing.py` | GPU-accelerated SQD postprocessing with CuPy |
| `submit.sh` | Submits the full chain |

## Run

```bash
bash submit.sh
```
