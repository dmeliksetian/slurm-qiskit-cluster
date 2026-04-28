from mpi4py import MPI

comm = MPI.COMM_WORLD
rank = comm.Get_rank()
size = comm.Get_size()

# Rank 0 prepares one work item per process
if rank == 0:
    workload = [i ** 2 for i in range(size)]
    print(f"[Rank 0] Scattering workload: {workload}")
else:
    workload = None

# Each rank receives one item
item = comm.scatter(workload, root=0)
print(f"[Rank {rank}] Received item: {item}")

# Each rank does some work on its item
result = item * 2
print(f"[Rank {rank}] Computed result: {result}")

# Rank 0 gathers all results
results = comm.gather(result, root=0)

if rank == 0:
    print(f"[Rank 0] Gathered results: {results}")
    print(f"[Rank 0] Total: {sum(results)}")
