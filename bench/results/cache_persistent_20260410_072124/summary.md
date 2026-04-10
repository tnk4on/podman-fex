# FEX-Emu Persistent Container Cache Test

- **Date**: Fri Apr 10 07:21:26 JST 2026
- **Connection**: test
- **Rounds**: 5
- **Method**: `podman create` + `podman start` + `podman exec bash -c "loop"` (internal loop, same as warmup)

### W1: Fedora dnf check-update

- **Image**: `docker.io/library/fedora:latest`
- **Command**: `dnf check-update -q 2>/dev/null; true`

| Round | Time | Exit | vs R1 |
|:-----:|-----:|:----:|:-----:|
| 1 | 22.2s | 0 | baseline |
| 2 | 1.9s | 0 | 8% |
| 3 | 1.0s | 0 | 4% |
| 4 | .8s | 0 | 4% |
| 5 | .8s | 0 | 4% |

### W2: Arch pacman sync

- **Image**: `docker.io/library/archlinux:latest`
- **Command**: `pacman -Sy --noconfirm >/dev/null 2>&1 && echo 'pacman sync done'`

| Round | Time | Exit | vs R1 |
|:-----:|-----:|:----:|:-----:|
| 1 | .1s | 1 | baseline |
| 2 | .2s | 1 | 129% |
| 3 | 0s | 1 | 47% |
| 4 | 0s | 1 | 20% |
| 5 | 0s | 1 | 18% |

### W3: Perl startup

- **Image**: `docker.io/library/perl:5-slim`
- **Command**: `perl -e 'print "hello\n"'`

| Round | Time | Exit | vs R1 |
|:-----:|-----:|:----:|:-----:|
| 1 | .1s | 0 | baseline |
| 2 | .1s | 0 | 87% |
| 3 | 0s | 0 | 27% |
| 4 | 0s | 0 | 11% |
| 5 | 0s | 0 | 10% |

### W4: Ubuntu dpkg list

- **Image**: `docker.io/library/ubuntu:latest`
- **Command**: `dpkg -l | wc -l`

| Round | Time | Exit | vs R1 |
|:-----:|-----:|:----:|:-----:|
| 1 | .1s | 0 | baseline |
| 2 | .1s | 0 | 94% |
| 3 | 0s | 0 | 15% |
| 4 | 0s | 0 | 34% |
| 5 | 0s | 0 | 13% |

### W5: Python startup

- **Image**: `docker.io/library/python:3-slim`
- **Command**: `python3 -c 'print(42)'`

| Round | Time | Exit | vs R1 |
|:-----:|-----:|:----:|:-----:|
| 1 | .2s | 0 | baseline |
| 2 | .2s | 0 | 107% |
| 3 | .2s | 0 | 109% |
| 4 | 0s | 0 | 13% |
| 5 | 0s | 0 | 14% |

### W6: rustc version

- **Image**: `docker.io/library/rust:latest`
- **Command**: `rustc -vV`

| Round | Time | Exit | vs R1 |
|:-----:|-----:|:----:|:-----:|
| 1 | .2s | 0 | baseline |
| 2 | .5s | 0 | 169% |
| 3 | 0s | 0 | 32% |
| 4 | 0s | 0 | 30% |
| 5 | 0s | 0 | 30% |

### W7: Fedora rpm verify

- **Image**: `docker.io/library/fedora:latest`
- **Command**: `rpm -V bash`

| Round | Time | Exit | vs R1 |
|:-----:|-----:|:----:|:-----:|
| 1 | .3s | 0 | baseline |
| 2 | .4s | 0 | 133% |
| 3 | 0s | 0 | 25% |
| 4 | 0s | 0 | 25% |
| 5 | 0s | 0 | 24% |

