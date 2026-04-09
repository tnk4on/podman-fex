# Issue #26919: podman build fails to go build, throws godump
# https://github.com/containers/podman/issues/26919
# This reproduces the Go runtime panic/godump during cross-arch build
# Uses multiple Go packages to trigger the issue
FROM --platform=linux/amd64 golang:1.24-alpine

WORKDIR /app
COPY go.mod .
COPY main.go .

ENV GOOS=linux
ENV GOARCH=amd64
ENV CGO_ENABLED=0

# The go build step is where the godump occurs in the original issue
RUN go build -v -o app ./

RUN echo "Go build completed successfully"
