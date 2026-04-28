#!/bin/bash
#SBATCH --job-name=sqd-execution
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --partition=quantum
#SBATCH --gres=qpu:1
#SBATCH --qpu=ibm_marrakesh
#SBATCH --output=logs/%j-execution.out
#SBATCH --error=logs/%j-execution.err

cd "$SLURM_SUBMIT_DIR"
source /shared/pyenv/bin/activate

python -u /shared/examples/python/sqd/execution.py
