# FEX-Emu Code Cache Warmup Benchmark

- **Date**: Fri Apr 10 07:19:35 JST 2026
- **Connection**: test
- **Iterations**: 5 per test
- **Mode**: In-container (same container, cache accumulates across iterations)

### W1: Fedora dnf check-update

- **Image**: `docker.io/library/fedora:latest`
- **Command**: `dnf check-update -q 2>/dev/null; true`
- **Total**: 22s | Exit: 0

| Run | Time | Exit | vs Run 1 |
|:---:|-----:|:----:|:--------:|
| 1 | 14.5s | 0 | baseline |
| 2 | 2.0s | 0 | 13% |
| 3 | 1.0s | 0 | 7% |
| 4 | 1.0s | 0 | 6% |
| 5 | .9s | 0 | 6% |

### W2: Arch pacman sync

- **Image**: `docker.io/library/archlinux:latest`
- **Command**: `pacman -Sy --noconfirm >/dev/null 2>&1 && echo 'pacman sync done'`
- **Total**: 3s | Exit: 0

| Run | Time | Exit | vs Run 1 |
|:---:|-----:|:----:|:--------:|
| 1 | .2s | 1 | baseline |
| 2 | .2s | 1 | 97% |
| 3 | 0s | 1 | 41% |
| 4 | 0s | 1 | 34% |
| 5 | 0s | 1 | 16% |

### W3: Perl startup

- **Image**: `docker.io/library/perl:5-slim`
- **Command**: `perl -e 'print "hello\n"'`
- **Total**: 7s | Exit: 0

| Run | Time | Exit | vs Run 1 |
|:---:|-----:|:----:|:--------:|
| 1 | .1s | 0 | baseline |
| 2 | .1s | 0 | 84% |
| 3 | 0s | 0 | 10% |
| 4 | 0s | 0 | 10% |
| 5 | 0s | 0 | 10% |

### W4: Ubuntu dpkg list

- **Image**: `docker.io/library/ubuntu:latest`
- **Command**: `dpkg -l | wc -l`
- **Total**: 3s | Exit: 0

| Run | Time | Exit | vs Run 1 |
|:---:|-----:|:----:|:--------:|
| 1 | .1s | 0 | baseline |
| 2 | .1s | 0 | 91% |
| 3 | 0s | 0 | 13% |
| 4 | 0s | 0 | 13% |
| 5 | 0s | 0 | 13% |

### W5: Python startup

- **Image**: `docker.io/library/python:3-slim`
- **Command**: `python3 -c 'print(42)'`
- **Total**: 7s | Exit: 0

| Run | Time | Exit | vs Run 1 |
|:---:|-----:|:----:|:--------:|
| 1 | .2s | 0 | baseline |
| 2 | .2s | 0 | 106% |
| 3 | .2s | 0 | 86% |
| 4 | 0s | 0 | 27% |
| 5 | 0s | 0 | 14% |

### W6: rustc version

- **Image**: `docker.io/library/rust:latest`
- **Command**: `rustc -vV`
- **Total**: 16s | Exit: 0

| Run | Time | Exit | vs Run 1 |
|:---:|-----:|:----:|:--------:|
| 1 | .3s | 0 | baseline |
| 2 | .4s | 0 | 153% |
| 3 | .1s | 0 | 43% |
| 4 | 0s | 0 | 32% |
| 5 | 0s | 0 | 30% |

### W7: Fedora rpm verify

- **Image**: `docker.io/library/fedora:latest`
- **Command**: `rpm -V bash`
- **Total**: 3s | Exit: 0

| Run | Time | Exit | vs Run 1 |
|:---:|-----:|:----:|:--------:|
| 1 | .3s | 0 | baseline |
| 2 | .4s | 0 | 113% |
| 3 | 0s | 0 | 20% |
| 4 | .1s | 0 | 31% |
| 5 | 0s | 0 | 21% |

