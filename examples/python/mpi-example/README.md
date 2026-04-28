# MPI Example

**Demonstrates:** MPI parallelism across compute nodes using `mpi4py`.

## What it does

Rank 0 creates a list of work items (one per MPI rank), scatters them across all ranks, each rank computes a result independently, then all results are gathered back to rank 0 which prints the collected output and total.

This is the foundational pattern for any multi-node parallel workload on the cluster.

## Workflow

```
mpi_example.sh
  └── srun python mpi_example.py   (2 ranks — one on c1, one on c2)
        rank 0: scatter [0, 1] → each rank
        rank N: compute item * 2
        rank 0: gather [0, 2] → print total
```

## Files

| File | Description |
|------|-------------|
| `mpi_example.py` | Scatter/gather computation using `MPI.COMM_WORLD` |
| `mpi_example.sh` | SLURM job: 2 nodes, 1 task per node, `partition=normal` |

## Run

```bash
sbatch mpi_example.sh
```
