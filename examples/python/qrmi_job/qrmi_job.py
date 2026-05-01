import os
import numpy as np
from dotenv import load_dotenv
from qiskit.circuit.library import pauli_two_design
from qiskit.quantum_info import SparsePauliOp
from qiskit.transpiler.preset_passmanagers import generate_preset_pass_manager

from qrmi.primitives import QRMIService
from qrmi.primitives.ibm import EstimatorV2, get_target


load_dotenv()
service = QRMIService()

resources = service.resources()
if len(resources) == 0:
    raise ValueError("No quantum resource is available.")
qrmi = resources[0]
target = get_target(qrmi)

# Map problem
num_qubits = target.num_qubits
qc = pauli_two_design(num_qubits=num_qubits, reps=4, seed=5, insert_barriers=True)
parameters = qc.parameters
obs = SparsePauliOp.from_sparse_list([("Z", [num_qubits-2], 1)], num_qubits=num_qubits)

phi_max = 0.5 * np.pi
parameter_values = np.random.uniform(-1 * phi_max, phi_max, len(parameters))



# Optimize
pm = generate_preset_pass_manager(
        target=target, 
        optimization_level=1
      )
t_qc = pm.run(qc)
t_obs = obs.apply_layout(t_qc.layout)

# Execute
options = {}
estimator = EstimatorV2(qrmi, options=options)
job = estimator.run([(t_qc, t_obs, parameter_values)])
print(f"Job ID: {job.job_id()}")

# Postprocess
result = job.result()
expectation_value = result[0].data.evs
expectation_value_stds = result[0].data.stds
print(f"Expectation Value: {expectation_value}")
