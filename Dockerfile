ARG PANGEO_BASE_IMAGE_TAG=2026.01.30
FROM pangeo/pytorch-notebook:${PANGEO_BASE_IMAGE_TAG}


# Copy and install environment.yml
COPY environment.yml /tmp/environment.yml
RUN mamba env update -f /tmp/environment.yml --name notebook && \
    mamba clean --all -f -y