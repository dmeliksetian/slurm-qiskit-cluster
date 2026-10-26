# Python Examples

Runnable examples for the SLURM/Qiskit cluster. Each example is self-contained in its own directory with Python scripts and SLURM job scripts.

## Setup

Copy the examples to the shared volume (run from the repo root):

```bash
podman cp examples/python/. login:/shared/examples/python/
```

Then follow the instructions in each example's `README.md`.

The examples that use a QPU (`qrmi_job`, `sqd`, `sqd-mpi`, `sqd-gpu`) request `--qpu=ibm_marrakesh` in their job scripts. Replace it with the name of a resource in your `cluster/config/qrmi_config.json` that is currently available. If that QPU is paused or not accessible, the job fails with `<name> is not accessible` and no quantum resource is available.

Run the `submit.sh` and `sbatch` commands of each example from `/shared/examples/python/<example>`. The `qaoa` example is the exception to "any node": its `submit.sh` runs a Python step with NumPy, so launch it from a compute node (for example `podman exec -it c1 bash`) or after `source /shared/pyenv/bin/activate`. The `login` node's default `python3` does not have the quantum stack.

## Examples

| Directory | Demonstrates |
|-----------|-------------|
| [`mpi-example/`](mpi-example/) | MPI parallelism across nodes using mpi4py — scatter/gather pattern |
| [`qrmi_job/`](qrmi_job/) | Single quantum job submitted to a real QPU via QRMI |
| [`sqd/`](sqd/) | Full SQD workflow as a 4-step SLURM chain (single-process postprocessing) |
| [`sqd-mpi/`](sqd-mpi/) | SQD with MPI-parallel postprocessing across both compute nodes |
| [`sqd-gpu/`](sqd-gpu/) | SQD with GPU-accelerated postprocessing on g1 using CuPy |
| [`qaoa/`](qaoa/) | QAOA optimisation loop alternating GPU quantum simulation and CuPy classical update |

## Cluster topology

| Node | Role |
|------|------|
| `c1`, `c2` | Compute nodes — `partition=normal` |
| `g1` | GPU node — `--nodelist=g1 --gres=gpu:1` |
| QPU partition | Quantum hardware access — `partition=quantum --gres=qpu:1` |

## Shared conventions

- All multi-step workflows include a `submit.sh` that chains jobs automatically.
- Intermediate files (circuits, counts, parameters) are written to a `data/` or per-run `runs/<job_id>/` directory.
- Job output and error logs go to `logs/` relative to the script directory.
