# =============================================================================
# slurm-qiskit-cluster — Multi-stage Dockerfile
# https://github.com/<you>/slurm-qiskit-cluster
# =============================================================================
#
# Stage hierarchy:
#
#   base  ──────────────────────────────►  builder      (ephemeral — populates /shared)
#     │                                 ►  control      (login, slurmctld, slurmdbd)
#     └── compute-base  ───────────────►  c1, c2
#           ├── quantum  ───────────────► q1
#           └── gpu  ───────────────────► g1
#                 └── quantum-gpu  ──────► qg1
#
# /shared/pyenv design
# ────────────────────
# The entire quantum Python stack lives in /shared/pyenv on the host, built
# once by the builder container and bind-mounted into all compute nodes at
# runtime. Nothing quantum is pip-installed into any runtime image. This means:
#   - Updating qiskit/qrmi/addons never requires an image rebuild
#   - All nodes see identical package versions
#   - Credentials in /shared stay outside the image layers
#
# Confirmed working packages (see requirements/pyenv-frozen.txt):
#   qiskit 2.3.0, qrmi 0.10.1, qiskit-ibm-runtime 0.45.1,
#   qiskit-addon-sqd 0.12.1, ffsim 0.0.67, pyscf 2.12.1,
#   pulser 1.6.6, qiskit-pasqal-provider 0.1.1
#
# Build sequence
# ──────────────
# 1. git submodule update --init --recursive
# 2. podman build --target builder -t slurm-qiskit-builder ./cluster
# 3. podman run --rm -v ./shared:/shared slurm-qiskit-builder
#    → populates /shared/pyenv and builds spank_qrmi.so
# 4. podman compose up -d
# =============================================================================

# -----------------------------------------------------------------------------
# BASE — OS, build tools, munge, PMIx, Slurm, OpenMPI
# Foundation for every stage. No Python science stack, no GPU, no Qiskit.
# -----------------------------------------------------------------------------
FROM rockylinux:9 AS base

LABEL org.opencontainers.image.source="https://github.com/<you>/slurm-qiskit-cluster" \
      org.opencontainers.image.title="slurm-qiskit-cluster" \
      org.opencontainers.image.description="Slurm + Qiskit cluster on Rocky Linux 9" \
      org.opencontainers.image.licenses="Apache-2.0"

# ── OS packages ──────────────────────────────────────────────────────────────
RUN set -ex \
    && yum makecache \
    && yum -y update \
    && yum -y install dnf-plugins-core \
    && yum config-manager --set-enabled crb \
    && yum -y install \
       wget \
       bzip2 \
       perl \
       gcc \
       gcc-c++ \
       git \
       gnupg \
       make \
       munge \
       munge-devel \
       python3.12-devel \
       python3.12-pip \
       mariadb-server \
       mariadb-devel \
       psmisc \
       bash-completion \
       vim-enhanced \
       http-parser-devel \
       json-c-devel \
       cmake \
       clang-tools-extra \
       procps \
       iputils \
       net-tools \
       openblas-devel \
       jq \
       libyaml-devel \
       lua-devel \
       libevent-devel \
       hwloc \
       hwloc-devel \
       hwloc-libs \
       autoconf \
       automake \
       libtool \
       flex \
       numactl \
       numactl-devel \
    && yum clean all \
    && rm -rf /var/cache/yum

RUN alternatives --install /usr/bin/python3 python3 /usr/bin/python3.12 1
RUN pip3.12 install Cython pytest

# ── Rust ─────────────────────────────────────────────────────────────────────
# Required by qrmi._core.abi3.so at runtime (Rust extension in /shared/pyenv).
# Also used by the builder stage to compile the qrmi wheel from source.
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y

# ── gosu ─────────────────────────────────────────────────────────────────────
ARG GOSU_VERSION=1.17
RUN set -ex \
    && wget -O /usr/local/bin/gosu \
       "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-amd64" \
    && wget -O /usr/local/bin/gosu.asc \
       "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-amd64.asc" \
    && export GNUPGHOME="$(mktemp -d)" \
    && gpg --batch --keyserver hkps://keys.openpgp.org \
       --recv-keys B42F6819007F00F88E364FD4036A9C25BF357DD4 \
    && gpg --batch --verify /usr/local/bin/gosu.asc /usr/local/bin/gosu \
    && rm -rf "${GNUPGHOME}" /usr/local/bin/gosu.asc \
    && chmod +x /usr/local/bin/gosu \
    && gosu nobody true

# ── PMIx ─────────────────────────────────────────────────────────────────────
ARG MY_PMIX_VERSION=4.2.9
RUN set -ex \
    && cd /tmp \
    && wget https://github.com/openpmix/openpmix/releases/download/v${MY_PMIX_VERSION}/pmix-${MY_PMIX_VERSION}.tar.gz \
    && tar xzf pmix-${MY_PMIX_VERSION}.tar.gz \
    && cd pmix-${MY_PMIX_VERSION} \
    && ./configure \
        --prefix=/usr \
        --libdir=/usr/lib64 \
        --with-libevent \
        --with-hwloc \
    && make -j$(nproc) \
    && make install \
    && ldconfig \
    && cd / \
    && rm -rf /tmp/pmix-${MY_PMIX_VERSION}*

RUN pmix_info --version && ls -la /usr/lib64/libpmix*

# ── Slurm ─────────────────────────────────────────────────────────────────────
ARG SLURM_TAG
RUN set -x \
    && git clone -b ${SLURM_TAG} --single-branch --depth=1 \
       https://github.com/SchedMD/slurm.git \
    && pushd slurm \
    && ./configure --enable-debug --prefix=/usr --sysconfdir=/etc/slurm \
        --with-mysql_config=/usr/bin --libdir=/usr/lib64 \
        --with-pmix=/usr \
        --with-hwloc \
    && make install \
    && install -D -m644 etc/cgroup.conf.example /etc/slurm/cgroup.conf.example \
    && install -D -m644 etc/slurm.conf.example /etc/slurm/slurm.conf.example \
    && install -D -m644 etc/slurmdbd.conf.example /etc/slurm/slurmdbd.conf.example \
    && install -D -m644 contribs/slurm_completion_help/slurm_completion.sh \
       /etc/profile.d/slurm_completion.sh \
    && rm -f /etc/profile.d/slurm_completion.sh \
    && popd \
    && rm -rf slurm \
    && groupadd -r --gid=990 slurm \
    && useradd -r -g slurm --uid=990 slurm \
    && mkdir /etc/sysconfig/slurm \
        /var/spool/slurmd \
        /var/run/slurmd \
        /var/run/slurmdbd \
        /var/lib/slurmd \
        /var/log/slurm \
        /data \
    && touch /var/lib/slurmd/node_state \
        /var/lib/slurmd/front_end_state \
        /var/lib/slurmd/job_state \
        /var/lib/slurmd/resv_state \
        /var/lib/slurmd/trigger_state \
        /var/lib/slurmd/assoc_mgr_state \
        /var/lib/slurmd/assoc_usage \
        /var/lib/slurmd/qos_usage \
        /var/lib/slurmd/fed_mgr_state \
    && chown -R slurm:slurm /var/*/slurm* \
    && /sbin/create-munge-key

# ── OpenMPI ───────────────────────────────────────────────────────────────────
ARG OPENMPI_VERSION=4.1.6
RUN set -ex \
    && cd /tmp \
    && wget https://download.open-mpi.org/release/open-mpi/v4.1/openmpi-${OPENMPI_VERSION}.tar.gz \
    && tar xzf openmpi-${OPENMPI_VERSION}.tar.gz \
    && cd openmpi-${OPENMPI_VERSION} \
    && ./configure \
        --prefix=/usr/local \
        --with-pmix=/usr \
        --with-slurm \
        --with-hwloc \
        --enable-mpi-cxx \
        --enable-mpi-fortran=no \
        --disable-getpwuid \
    && make -j$(nproc) \
    && make install \
    && ldconfig \
    && cd / \
    && rm -rf /tmp/openmpi-${OPENMPI_VERSION}*

RUN echo "/usr/local/lib" > /etc/ld.so.conf.d/openmpi-local.conf && ldconfig \
    && ln -sf /usr/local/bin/mpirun  /usr/bin/mpirun  \
    && ln -sf /usr/local/bin/mpiexec /usr/bin/mpiexec \
    && ln -sf /usr/local/bin/mpicc   /usr/bin/mpicc   \
    && ln -sf /usr/local/bin/mpicxx  /usr/bin/mpicxx

RUN echo "export PATH=/usr/local/bin:\$PATH" >> /etc/profile.d/openmpi.sh \
    && echo "export LD_LIBRARY_PATH=/usr/local/lib:\$LD_LIBRARY_PATH" \
       >> /etc/profile.d/openmpi.sh \
    && chmod +x /etc/profile.d/openmpi.sh \
    && echo "export PATH=/usr/local/bin:\$PATH" >> /etc/bashrc \
    && echo "export LD_LIBRARY_PATH=/usr/local/lib:\$LD_LIBRARY_PATH" >> /etc/bashrc

RUN /usr/local/bin/ompi_info | grep -E "(slurm|pmi)" | head -10 || true

# ── Slurm config files ────────────────────────────────────────────────────────
# Build context is ./cluster/ so paths are relative to that directory.
# qrmi_config.json is generated from qrmi_config.json.example by
# setup/03-configure-credentials.sh — never commit real credentials.
COPY cluster/config/slurm.conf          /etc/slurm/slurm.conf
COPY cluster/config/gres.conf           /etc/slurm/gres.conf
COPY cluster/config/task_prolog.sh      /etc/slurm/task_prolog.sh
COPY cluster/config/slurmdbd.conf       /etc/slurm/slurmdbd.conf
COPY cluster/config/cgroup.conf         /etc/slurm/cgroup.conf
COPY cluster/config/plugstack.conf      /etc/slurm/plugstack.conf
COPY cluster/config/qrmi_config.json    /etc/slurm/qrmi_config.json

RUN chown slurm:slurm /etc/slurm/slurmdbd.conf /etc/slurm/qrmi_config.json \
    && chmod 600 /etc/slurm/slurmdbd.conf /etc/slurm/qrmi_config.json \
    && chmod +x /etc/slurm/task_prolog.sh

COPY cluster/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]


# -----------------------------------------------------------------------------
# BUILDER — ephemeral artifact builder
# Inherits base (Rust, gcc, cmake, MPI, Slurm headers) and adds maturin.
# Run once before starting the cluster to populate /shared:
#
#   podman build --target builder -t slurm-qiskit-builder ./cluster
#   podman run --rm -v ./shared:/shared slurm-qiskit-builder
#
# Produces:
#   /shared/pyenv/                                   Python venv + all packages
#   /shared/spank-plugins/plugins/spank_qrmi/
#     build/spank_qrmi.so                            SPANK plugin for Slurm
#
# Prerequisite: git submodule update --init --recursive
# so that /shared/qrmi and /shared/spank-plugins are populated.
# -----------------------------------------------------------------------------
FROM base AS builder

# ── Boost + HDF5 needed to build SPANK plugin ────────────────────────────────
RUN yum -y install epel-release \
    && yum -y install \
       boost-devel \
       boost-openmpi-devel \
       hdf5-devel \
       hdf5-openmpi-devel \
    && yum clean all \
    && rm -rf /var/cache/yum

# ── maturin pinned to version used in confirmed working install ───────────────
RUN pip3.12 install maturin==1.12.2 build

# ── Copy requirements and build script into image ─────────────────────────────
# Build context is ./cluster/ — requirements/ is one level up, so we copy
# it into the image explicitly rather than relying on relative COPY paths.
COPY requirements/pyenv-frozen.txt    /build/pyenv-frozen.txt
COPY cluster/build-all.sh             /build/build-all.sh
RUN chmod +x /build/build-all.sh

CMD ["/build/build-all.sh"]


# -----------------------------------------------------------------------------
# CONTROL — login, slurmctld, slurmdbd
# Pure Slurm control plane. No compute libraries, no GPU, no Python packages.
# -----------------------------------------------------------------------------
FROM base AS control

CMD ["slurmdbd"]


# -----------------------------------------------------------------------------
# COMPUTE-BASE — c1, c2
# No quantum packages in the image. Auto-activates /shared/pyenv so job scripts
# can import qiskit, qrmi, etc. without an explicit source command.
# Guard ensures the image still works if /shared is not mounted.
# -----------------------------------------------------------------------------
FROM base AS compute-base

RUN printf '%s\n' \
    '# Auto-activate shared quantum venv when mounted' \
    'if [ -f /shared/pyenv/bin/activate ]; then' \
    '    source /shared/pyenv/bin/activate' \
    'fi' \
    > /etc/profile.d/shared-pyenv.sh \
    && chmod +x /etc/profile.d/shared-pyenv.sh \
    && echo 'source /etc/profile.d/shared-pyenv.sh' >> /etc/bashrc

CMD ["slurmd"]


# -----------------------------------------------------------------------------
# QUANTUM — q1
# IBM Quantum / QRMI execution node.
# All Python packages from /shared/pyenv. SPANK plugin (spank_qrmi.so) loads
# via plugstack.conf → /shared/spank-plugins/plugins/spank_qrmi/build/
# -----------------------------------------------------------------------------
FROM compute-base AS quantum

CMD ["slurmd"]


# -----------------------------------------------------------------------------
# GPU — g1
# GPU postprocessing node. Adds CUDA runtime libs and CuPy for GPU compute.
# Builds the Dice C++ eigensolver binary — needs Boost/HDF5 at compile time.
# The Python wrapper lives in /shared/pyenv; this stage provides the binary.
# CuPy installed into system Python (not /shared/pyenv) because it links
# against CUDA libs only present in this stage.
# WSL2: NVIDIA driver libs bind-mount at runtime via /usr/lib/wsl/lib.
# -----------------------------------------------------------------------------
FROM compute-base AS gpu

# ── CUDA runtime libraries ────────────────────────────────────────────────────
ARG CUDA_VERSION=12-9
RUN dnf config-manager \
       --add-repo https://developer.download.nvidia.com/compute/cuda/repos/rhel9/x86_64/cuda-rhel9.repo \
    && dnf -y install cuda-libraries-${CUDA_VERSION} \
    && dnf clean all \
    && rm -rf /var/cache/dnf

# ── WSL2 NVIDIA userspace lib path ───────────────────────────────────────────
RUN echo "/usr/lib/wsl/lib" > /etc/ld.so.conf.d/wsl-nvidia.conf && ldconfig || true \
    && echo "export LD_LIBRARY_PATH=/usr/lib/wsl/lib:\$LD_LIBRARY_PATH" \
       >> /etc/profile.d/wsl-nvidia.sh \
    && chmod +x /etc/profile.d/wsl-nvidia.sh \
    && echo "export LD_LIBRARY_PATH=/usr/lib/wsl/lib:\$LD_LIBRARY_PATH" >> /etc/bashrc

# ── Dice system dependencies ──────────────────────────────────────────────────
RUN yum -y install epel-release \
    && yum -y install \
       boost-devel \
       boost-openmpi-devel \
       hdf5-devel \
       hdf5-openmpi-devel \
       environment-modules \
    && yum clean all \
    && rm -rf /var/cache/yum

# ── Dice C++ binary ───────────────────────────────────────────────────────────
# Builds the binary; Python wrapper is in /shared/pyenv/qiskit_addon_dice_solver
# Builds the Dice binary only. The Python wrapper (qiskit-addon-dice-solver)
# lives in /shared/pyenv — installed via ./setup/02-build-shared.sh --gpu.
# Binary copied to /usr/local/bin/Dice so it is on PATH for all Slurm jobs.
# Boost shared libs copied to /usr/local/lib so the binary links correctly.
RUN git clone --depth=1 -b stable/0.3 \
       https://github.com/Qiskit/qiskit-addon-dice-solver.git /tmp/dice-solver \
    && cd /tmp/dice-solver \
    && mkdir -p external \
    && git clone https://github.com/caleb-johnson/Dice.git external/Dice \
    && DICE_ROOT=/tmp/dice-solver/external/Dice \
    && BOOST_INC=/usr/include/boost \
    && BOOST_LIB=/usr/lib64/openmpi/lib \
    && HDF5_INC=/usr/include/openmpi-x86_64 \
    && cd $DICE_ROOT \
    && sed -i "s|BOOST=.*|BOOST=${BOOST_INC}|g" Makefile \
    && sed -i "s|-I.*boost.*include|-I${BOOST_INC}|g" Makefile \
    && sed -i "s|-L.*boost.*/stage/lib|-L${BOOST_LIB}|g" Makefile \
    && sed -i "s|-L.*boost.*/lib|-L${BOOST_LIB}|g" Makefile \
    && sed -i "s|-I/usr/lib/x86_64-linux-gnu/hdf5/openmpi//include|-I${HDF5_INC}|g" Makefile \
    && PATH=/usr/lib64/openmpi/bin:$PATH make -j1 Dice \
    && cp $DICE_ROOT/bin/Dice /usr/local/bin/Dice \
    && find /usr/lib64 -name "libboost_mpi*.so*"           -exec cp {} /usr/local/lib \; \
    && find /usr/lib64 -name "libboost_serialization*.so*" -exec cp {} /usr/local/lib \; \
    && ldconfig \
    && cd / \
    && rm -rf /tmp/dice-solver

CMD ["slurmd"]


# -----------------------------------------------------------------------------
# QUANTUM-GPU — qg1
# GPU-accelerated Aer simulation. Inherits full CUDA stack from gpu stage.
# qiskit-aer-gpu requires CUDA 12.x — satisfied by gpu stage.
#
# qiskit-aer-gpu is NOT installed here. Like CuPy, it lives in /shared/pyenv
# and is installed by the builder container via:
#   ./setup/02-build-shared.sh --quantum-gpu
# This keeps the install consistent with the rest of the quantum stack and
# avoids baking credentials or package versions into the image.
# -----------------------------------------------------------------------------
FROM gpu AS quantum-gpu

CMD ["slurmd"]


# -----------------------------------------------------------------------------
# BUILDER-GPU — ephemeral artifact builder for qiskit-aer-gpu from source
# Inherits the full CUDA runtime from gpu, then adds:
#   - cuda-toolkit-${CUDA_VERSION}  (nvcc + dev headers for compilation)
#   - nlohmann-json-devel            (required by qiskit-aer with DISABLE_CONAN=ON)
#   - scikit-build, pybind11         (Python build deps for setup.py bdist_wheel)
#   - maturin                        (for qrmi, same as builder)
#
# Used by 02-build-shared.sh --quantum-gpu in place of the standard builder.
# Produces the same /shared/pyenv and spank_qrmi.so outputs, plus a
# qiskit-aer wheel built from dmeliksetian/qiskit-aer@build/combined-patches.
# -----------------------------------------------------------------------------
FROM gpu AS builder-gpu

ARG CUDA_VERSION=12-9

RUN dnf -y install \
       cuda-toolkit-${CUDA_VERSION} \
       nlohmann-json-devel \
       ninja-build \
    && dnf clean all \
    && rm -rf /var/cache/dnf

# EPEL spdlog-devel on Rocky 9 is broken (references spdlog/fmt/bundled/core.h
# which does not exist). Build spdlog from source so cmake can find it cleanly.
RUN cd /tmp \
    && git clone --depth=1 --branch v1.9.2 https://github.com/gabime/spdlog.git \
    && cmake -S spdlog -B spdlog/build \
       -DCMAKE_BUILD_TYPE=Release \
       -DSPDLOG_BUILD_SHARED=OFF \
       -DSPDLOG_BUILD_STATIC=ON \
       -DCMAKE_INSTALL_PREFIX=/usr/local \
    && cmake --build spdlog/build -j$(nproc) \
    && cmake --install spdlog/build \
    && rm -rf /tmp/spdlog \
    && ldconfig

RUN pip3.12 install maturin==1.12.2 build scikit-build pybind11

COPY requirements/pyenv-frozen.txt    /build/pyenv-frozen.txt
COPY cluster/build-all.sh             /build/build-all.sh
RUN chmod +x /build/build-all.sh

CMD ["/build/build-all.sh"]
