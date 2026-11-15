ARG PANGEO_BASE_IMAGE_TAG=2026.01.30
FROM pangeo/pangeo-notebook:${PANGEO_BASE_IMAGE_TAG}

# Same as pangeo/pytorch-notebook: lets the GKE-mounted NVIDIA driver be found.
ENV PATH=${PATH}:/usr/local/nvidia/bin
ENV LD_LIBRARY_PATH=${LD_LIBRARY_PATH}:/usr/local/nvidia/lib64
ENV PIP_NO_CACHE_DIR=1

# 1. Switch to root to install system-level C/C++ compilers
# (Keeping this as a reliable fallback for basic system libraries)
USER root
RUN apt-get update && \
    apt-get install -y build-essential libsm6 libice6 libx11-6 libxext6 && \
    apt-get install -y --only-upgrade ca-certificates libbrotli1 && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# 2. Switch back to the default Pangeo user (jovyan)
USER ${NB_USER:-jovyan}

# 3. CUDA torch first, so it is the only torch in the image and every pip
# package in environment.yml resolves against it.
RUN mamba run -n notebook pip install \
    torch==2.10.0+cu129 torchvision==0.25.0+cu129 \
    --index-url https://download.pytorch.org/whl/cu129

# 4. Copy and update the environment
COPY environment.yml /tmp/environment.yml

RUN export CONDA_OVERRIDE_CUDA=12.9 && \
    mamba env update -f /tmp/environment.yml --name notebook && \
    mamba install -y -n notebook "ca-certificates>=2026.10.19" "certifi>=2026.10.19" "brotli-python>=1.2.1" && \
    mamba install -y -n base "ca-certificates>=2026.10.19" "certifi>=2026.10.19" "brotli-python>=1.2.1" && \
    mamba clean --all -f -y

# Fail the build if pip dependency resolution replaced the CUDA torch.
RUN mamba run -n notebook python -c "import torch, torchvision; \
assert torch.__version__ == '2.10.0+cu129', torch.__version__; \
assert torchvision.__version__ == '0.25.0+cu129', torchvision.__version__"

# GPU extras pangeo/pytorch-notebook used to provide, pinned to its versions.
RUN mamba run -n notebook python -m pip install --no-cache-dir \
    gpytorch==1.15.1 linear-operator==0.6 \
    torchgeo==0.8.1 lightning==2.6.0 kornia==0.8.2 timm==1.0.24 \
    segmentation-models-pytorch==0.5.0 && \
    mamba run -n notebook python -c "import torch; assert torch.__version__ == '2.10.0+cu129', torch.__version__"

# 5. Compile llama-cpp-python from source
# CRITICAL FIX: Using 'mamba run' to ensure the environment is activated during the build!
RUN mamba run -n notebook env CMAKE_ARGS="-DGGML_CUDA=on -DCUDAToolkit_ROOT=/srv/conda/envs/notebook -DCMAKE_CUDA_ARCHITECTURES=75 -DGGML_NATIVE=OFF -DGGML_AVX=ON -DGGML_AVX2=ON -DGGML_FMA=ON -DGGML_F16C=ON -DGGML_AVX512=OFF -DGGML_AVX512_VBMI=OFF -DGGML_AVX512_VNNI=OFF" FORCE_CMAKE=1 \
    python -m pip install -v llama-cpp-python==0.3.37 --no-cache-dir

# 6. llama-index integration for the CUDA llama-cpp-python above. --no-deps so
# pip cannot swap in a CPU build of llama-cpp-python.
RUN mamba run -n notebook python -m pip install --no-cache-dir --no-deps \
    llama-index-llms-llama-cpp==0.7.0

# 7. GPU COLMAP (feature extraction + matching on CUDA). --no-deps so pip
# cannot touch the cu129 torch stack; cudart/curand already come with it.
RUN mamba run -n notebook python -m pip install --no-cache-dir --no-deps \
    pycolmap-cuda12==4.2.1

# 8. LAION-fMRI (CMU), same pins as base-user-image #183. The pangeo base
# already has s3fs, h5py and awscli 2, so pip only adds nibabel and laion-fmri.
# The check fails the build if pip pulled in awscli 1, which would pin botocore
# and break s3fs.
RUN mamba run -n notebook python -m pip install --no-cache-dir \
    nibabel==5.5.0 \
    "laion-fmri @ https://github.com/ViCCo-Group/LAION-fMRI/archive/cf5f97404f654410db75964210cefe5fa04f9d77.zip" && \
    mamba run -n notebook python -c "import laion_fmri, nibabel, s3fs, h5py, importlib.metadata as m; \
assert m.version('awscli').startswith('2.'), m.version('awscli')" && \
    mamba run -n notebook python -m awscli --version
