ARG PANGEO_BASE_IMAGE_TAG=2026.01.30
FROM pangeo/pytorch-notebook:${PANGEO_BASE_IMAGE_TAG}

# 1. Switch to root to install system-level C/C++ compilers
USER root
RUN apt-get update && \
    apt-get install -y build-essential && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# 2. Switch back to the default Pangeo user (jovyan)
USER ${NB_USER:-jovyan}

# Copy and install environment.yml
COPY environment.yml /tmp/environment.yml

# Set environment variables to force pip to build llama-cpp-python with CUDA
RUN mamba env update -f /tmp/environment.yml --name notebook && \
    mamba clean --all -f -y

    # Set environment variables to force pip to build with CUDA
ENV CMAKE_ARGS="-DGGML_CUDA=on -DCUDAToolkit_ROOT=/srv/conda/envs/notebook"
ENV FORCE_CMAKE=1

RUN /srv/conda/envs/notebook/bin/python -m pip install llama-cpp-python