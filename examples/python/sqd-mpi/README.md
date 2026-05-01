# SQD-MPI — Sample-based Quantum Diagonalization with MPI Postprocessing

**Demonstrates:** SQD with MPI-parallel classical postprocessing distributed across both compute nodes.

## What it does

Same SIAM problem as `sqd/`, but the postprocessing step distributes the SQD batch eigensolves across MPI ranks using a round-robin assignment. With `NUM_BATCHES=3` and 2 nodes, rank 0 handles batches [0, 2] and rank 1 handles batch [1]. Two levels of parallelism: MPI across nodes (inter-node) and OMP threads within each node (intra-node, for PySCF's Davidson solver).

Uses `config.py` / `common.py` to share parameters and I/O helpers across all steps. Intermediate files are written to a per-run directory `runs/<mapping_job_id>/` so multiple runs don't interfere.

## Workflow

```
submit.sh
  ├── [1] mapping.sh       → mapping.py          (1 node)
  │         Generate Krylov circuits from config.py parameters.
  │         Creates RUN_DIR = runs/$SLURM_JOB_ID/
  │
  ├── [2] optimization.sh  → optimization.py     (1 node)
  │         Transpile circuits to ISA.
  │
  ├── [3] execution.sh     → execution.py        (partition=quantum, ibm_torino)
  │         Sample circuits on QPU via SamplerV2.
  │
  └── [4] postprocessing.sh → postprocessing.py  (2 nodes, MPI)
            Round-robin batch assignment across ranks.
            Each rank: solve_sci_batch → gather to rank 0.
            Rank 0: config recovery, occupancy update, energy reporting.
```

## Files

| File | Description |
|------|-------------|
| `config.py` | All physical and workflow parameters in one place |
| `common.py` | Logging, QPY/JSON I/O, QRMI resource acquisition |
| `mapping.py` | Circuit generation using config constants |
| `optimization.py` | ISA transpilation |
| `execution.py` | QPU sampling |
| `postprocessing.py` | MPI-parallel SQD iterative loop |
| `submit.sh` | Submits the full chain, propagating RUN_DIR via `MAPPING_JOB_ID` |

## Run

```bash
bash submit.sh
```
