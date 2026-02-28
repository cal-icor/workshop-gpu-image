ARG PANGEO_BASE_IMAGE_TAG=2026.01.30
FROM pangeo/pytorch-notebook:${PANGEO_BASE_IMAGE_TAG}

# 1. Switch to root to install system-level C/C++ compilers
# (Keeping this as a reliable fallback for basic system libraries)
USER root
RUN apt-get update && \
    apt-get install -y build-essential && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# 2. Switch back to the default Pangeo user (jovyan)
USER ${NB_USER:-jovyan}

# 3. Copy and update the environment
COPY environment.yml /tmp/environment.yml

RUN mamba env update -f /tmp/environment.yml --name notebook && \
    mamba clean --all -f -y

# 4. Set environment variables to force pip to build with CUDA
ENV CMAKE_ARGS="-DGGML_CUDA=on -DCUDAToolkit_ROOT=/srv/conda/envs/notebook"
ENV FORCE_CMAKE=1

# 5. Compile llama-cpp-python from source
# CRITICAL FIX: Using 'mamba run' to ensure the environment is activated during the build!
RUN mamba run -n notebook python -m pip install -v llama-cpp-python --no-cache-dir