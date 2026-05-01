#!/bin/bash
#SBATCH --job-name=qaoa-classical
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --partition=gpu_only
#SBATCH --nodelist=g1
#SBATCH --gres=gpu:1
#SBATCH --output=logs/%j-classical.out
#SBATCH --error=logs/%j-classical.err

cd "$SLURM_SUBMIT_DIR"
source /shared/pyenv/bin/activate

export RUN_DIR=$(cat "$SLURM_SUBMIT_DIR/run_dir")

python -u /shared/examples/python/qaoa/classical_step.py
