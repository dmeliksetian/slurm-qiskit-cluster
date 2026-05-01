#!/bin/bash
# submit.sh — Submit the full quantum-classical workflow as a SLURM job chain.
# RUN_DIR is created by mapping.sh; logs go to logs/<mapping_id>/.

set -euo pipefail
cd "$(dirname "$0")"
echo "Starting Quantum-Classical Workflow Submission..."

# 1. Mapping
MAPPING_ID=$(sbatch --parsable \
    --output="logs/%j/%j-mapping.out" \
    --error="logs/%j/%j-mapping.err" \
    mapping.sh)
if [ $? -ne 0 ]; then echo "Error submitting Mapping job."; exit 1; fi
echo "  [1/4] Mapping submitted:        $MAPPING_ID"

# Create per-run log directory before any job starts executing
mkdir -p "logs/$MAPPING_ID"

# 2. Optimization
OPTIMIZE_ID=$(sbatch --parsable \
    --dependency=afterok:$MAPPING_ID \
    --output="logs/$MAPPING_ID/%j-optimization.out" \
    --error="logs/$MAPPING_ID/%j-optimization.err" \
    optimization.sh)
if [ $? -ne 0 ]; then echo "Error submitting Optimization job."; exit 1; fi
echo "  [2/4] Optimization submitted:   $OPTIMIZE_ID (after $MAPPING_ID)"

# 3. Execution
EXECUTE_ID=$(sbatch --parsable \
    --dependency=afterok:$OPTIMIZE_ID \
    --output="logs/$MAPPING_ID/%j-execution.out" \
    --error="logs/$MAPPING_ID/%j-execution.err" \
    execution.sh)
if [ $? -ne 0 ]; then echo "Error submitting Execution job."; exit 1; fi
echo "  [3/4] Execution submitted:      $EXECUTE_ID (after $OPTIMIZE_ID)"

# 4. Postprocessing
POSTPROCESSING_ID=$(sbatch --parsable \
    --dependency=afterok:$EXECUTE_ID \
    --output="logs/$MAPPING_ID/%j-postprocessing.out" \
    --error="logs/$MAPPING_ID/%j-postprocessing.err" \
    postprocessing.sh)
if [ $? -ne 0 ]; then echo "Error submitting Postprocessing job."; exit 1; fi
echo "  [4/4] Postprocessing submitted: $POSTPROCESSING_ID (after $EXECUTE_ID)"

echo "------------------------------------------------"
echo "Full chain submitted. Monitor with: watch squeue"
echo "Run directory: $(pwd)/runs/$MAPPING_ID"
echo "Log directory: $(pwd)/logs/$MAPPING_ID"
