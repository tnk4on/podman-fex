# Issue #24647: sudo does not work in foreign x86_64 containers under BuildKit + Rosetta 2
# https://github.com/containers/podman/issues/24647
# Symptom: sudo: effective uid is not 0, is /usr/bin/sudo on a file system with the 'nosuid' option set
FROM --platform=linux/amd64 alpine

RUN apk add shadow sudo
RUN echo '%wheel ALL=(ALL:ALL) NOPASSWD: ALL' >> /etc/sudoers
RUN useradd --create-home --non-unique --uid 1000 --groups wheel user

USER 1000
RUN sudo /bin/ls
