# Issue #26572: Node.js Express apps freeze when using Rosetta on macOS with linux/amd64
# https://github.com/containers/podman/issues/26572
#
# Original report:
#   - Container base image: debian:bookworm-slim
#   - Node.js version: 22.11.0
#   - Express.js app receiving parallel HTTP requests freezes
#   - QEMU workaround works; Rosetta causes the freeze
#
# This Dockerfile builds the Express app image.
# The actual freeze test is run by run/12-nodejs-express.sh
FROM --platform=linux/amd64 node:lts-slim

WORKDIR /app
COPY package.json server.js ./
RUN npm install

EXPOSE 3000
CMD ["node", "server.js"]
