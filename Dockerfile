# Multi-stage build for security and reduced image size
# Pinned to match the Terraform version used to validate/apply this repo's
# state (see .terraform/terraform.tfstate) -- an older Terraform reopening a
# newer version's local backend metadata fails with "Backend configuration
# changed", so this must stay in sync with whatever actually touches state.
FROM docker.io/hashicorp/terraform:1.15.8 AS terraform-builder

FROM docker.io/library/python:3.12-slim

# Create a non-root user and group. --system alone gives HOME=/nonexistent
# on Debian, which breaks "~/.aws" expansion for the credentials volume
# docker-compose mounts at /home/devuser/.aws -- --home/--create-home make
# that the user's real HOME so it actually resolves.
RUN addgroup --system devgroup && adduser --system --home /home/devuser --ingroup devgroup devuser

# Install system dependencies and AWS CLI
# We use a single RUN command to minimize layers and clean up apt cache afterwards
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    unzip \
    jq \
    git \
    && curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" \
    && unzip -q awscliv2.zip \
    && ./aws/install \
    && rm -rf awscliv2.zip ./aws \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Copy Terraform binary from the builder stage
COPY --from=terraform-builder /bin/terraform /usr/local/bin/terraform

# pytest es el unico paquete Python que hace falta para correr "pytest tests/":
# los tests fingen boto3 via types.ModuleType, no necesitan boto3/moto reales.
RUN pip install --no-cache-dir pytest

# Set the working directory
WORKDIR /workspace

# Give the non-root user ownership of the workspace directory
RUN chown -R devuser:devgroup /workspace

# Switch to the non-root user
USER devuser

# CMD (no ENTRYPOINT): "docker compose run env" sin comando abre bash
# interactivo igual que antes, pero "docker compose run env <cmd> <args>"
# ahora ejecuta <cmd> directo en vez de intentar correrlo como si fuera un
# script de shell (que es lo que pasaba con ENTRYPOINT ["/bin/bash"]).
CMD ["/bin/bash"]
