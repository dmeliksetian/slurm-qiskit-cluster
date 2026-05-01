# QAOA — Quantum Approximate Optimization Algorithm

**Demonstrates:** An autonomous quantum-classical optimization loop where quantum circuit evaluation and classical parameter updates alternate as separate SLURM jobs on g1.

## What it does

Solves MaxCut on a 4-node ring graph using QAOA (depth p=1). The optimal cut is 4 (all edges cut, bipartition {0,2} vs {1,3}).

The optimizer runs as a self-chaining job loop: each quantum step evaluates the cost function and the gradient shifts needed for the parameter shift rule, then chains to a classical step that computes the gradient with CuPy and applies an Adam update. If not converged, the classical step re-submits the next quantum step.

## Workflow

```
submit.sh
  initialise params.npy, iteration.txt in runs/TIMESTAMP/
  └── quantum_step.sh (g1, AerSimulator GPU)
        Evaluates 1 + 2*N_PARAMS = 5 circuits:
          E(θ), E(θ+π/2·e₀), E(θ-π/2·e₀), E(θ+π/2·e₁), E(θ-π/2·e₁)
        Saves: expectation_values.npy
        Chains to →
      classical_step.sh (g1, CuPy)
        Parameter shift gradient: ∂⟨C⟩/∂θᵢ = [E(θ+π/2·eᵢ) - E(θ-π/2·eᵢ)] / 2
        Adam update on GPU (gradient ascent on ⟨C⟩).
        Saves: params.npy, energy_history.npy, adam_state.json
        If not converged → re-submits quantum_step.sh (next iteration)
        If converged     → prints approximation ratio ⟨C⟩ / 4
```

## State files (in `runs/TIMESTAMP/`)

| File | Contents |
|------|----------|
| `params.npy` | Current QAOA parameters `[beta, gamma]` |
| `expectation_values.npy` | `E(θ)` + shifted evaluations for gradient |
| `adam_state.json` | Adam moment estimates `m`, `v`, step `t` |
| `energy_history.npy` | `⟨C⟩` value per iteration |
| `iteration.txt` | Current iteration number |

## Files

| File | Description |
|------|-------------|
| `config.py` | Problem (graph, QAOA depth), optimizer hyperparameters, path management |
| `common.py` | Logging and NumPy/JSON I/O helpers |
| `quantum_step.py` | QAOA circuit evaluation via AerSimulator GPU |
| `classical_step.py` | CuPy gradient + Adam update + conditional re-submission |
| `quantum_step.sh` | SLURM job: g1, `--gres=gpu:1`, chains to `classical_step.sh` |
| `classical_step.sh` | SLURM job: g1, `--gres=gpu:1` |
| `submit.sh` | Initialises run state and submits the first quantum step |

## Run

```bash
bash submit.sh
```
