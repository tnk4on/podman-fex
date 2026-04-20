# Issue #25272: Angular build hangs on Apple Silicon for amd64 platform
# https://github.com/containers/podman/issues/25272
#
# Original report:
#   FROM node:20-alpine3.18 AS build
#   RUN npm install -g @angular/cli
#   COPY ... && npm install
#   RUN ng build --c=$NG_APP_ENV --verbose
#   → ng build hangs indefinitely under emulation
#
# This test reproduces the issue faithfully:
#   1. Install Angular CLI
#   2. Create a minimal Angular project (ng new --minimal)
#   3. Run ng build — the step that hangs in the original issue
FROM --platform=linux/amd64 node:20-alpine3.18

WORKDIR /src

# Install Angular CLI (same as original issue)
RUN npm install -g @angular/cli@18

# Create a minimal Angular project with --minimal to reduce size
# --skip-git: no git init, --skip-tests: no spec files, --minimal: inline templates
RUN ng new test-app --minimal --skip-git --skip-tests --defaults --ssr=false

WORKDIR /src/test-app

# This is the exact step that hangs in the original issue
RUN ng build

RUN echo "Angular build completed successfully"
