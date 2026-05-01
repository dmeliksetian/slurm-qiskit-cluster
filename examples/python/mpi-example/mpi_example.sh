#!/bin/bash
#SBATCH --job-name=mpi-example
#SBATCH --nodes=2
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=1
#SBATCH --partition=normal
#SBATCH --output=logs/%j-mpi-example.out
#SBATCH --error=logs/%j-mpi-example.err

cd "$SLURM_SUBMIT_DIR"
mkdir -p logs
source /shared/pyenv/bin/activate

mpirun --allow-run-as-root python -u /shared/examples/python/mpi-example/mpi_example.py
