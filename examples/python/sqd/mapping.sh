#!/bin/bash
#SBATCH --job-name=sqd-mapping
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --partition=normal
#SBATCH --output=logs/%j-mapping.out
#SBATCH --error=logs/%j-mapping.err

cd "$SLURM_SUBMIT_DIR"
source /shared/pyenv/bin/activate

python -u /shared/examples/python/sqd/mapping.py
