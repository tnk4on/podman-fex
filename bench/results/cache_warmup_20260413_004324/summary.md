# FEX-Emu Code Cache Warmup Benchmark

- **Date**: Mon Apr 13 00:43:41 JST 2026
- **Connection**: test
- **Iterations**: 5 per test
- **Mode**: In-container (same container, cache accumulates across iterations)

### W1: Fedora dnf check-update

- **Image**: `docker.io/library/fedora:latest`
- **Command**: `dnf check-update -q 2>/dev/null; true`
- **Total**: 23s | Exit: 0

| Run | Time | Exit | vs Run 1 |
|:---:|-----:|:----:|:--------:|
| 1 | 16.2s | 0 | baseline |
| 2 | 2.0s | 0 | 12% |
| 3 | 1.1s | 0 | 6% |
| 4 | .9s | 0 | 5% |
| 5 | .9s | 0 | 6% |

### W2: Arch pacman sync

- **Image**: `docker.io/library/archlinux:latest`
- **Command**: `pacman -Sy --noconfirm >/dev/null 2>&1 && echo 'pacman sync done'`
- **Total**: 2s | Exit: 0

| Run | Time | Exit | vs Run 1 |
|:---:|-----:|:----:|:--------:|
| 1 | .2s | 1 | baseline |
| 2 | .2s | 1 | 101% |
| 3 | 0s | 1 | 44% |
| 4 | 0s | 1 | 17% |
| 5 | 0s | 1 | 18% |

### W3: Perl startup

- **Image**: `docker.io/library/perl:5-slim`
- **Command**: `perl -e 'print "hello\n"'`
- **Total**: 7s | Exit: 0

| Run | Time | Exit | vs Run 1 |
|:---:|-----:|:----:|:--------:|
| 1 | .1s | 0 | baseline |
| 2 | .1s | 0 | 103% |
| 3 | 0s | 0 | 10% |
| 4 | 0s | 0 | 11% |
| 5 | 0s | 0 | 54% |

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
| 2 | .2s | 0 | 107% |
| 3 | .2s | 0 | 85% |
| 4 | 0s | 0 | 17% |
| 5 | 0s | 0 | 14% |

### W6: rustc version

- **Image**: `docker.io/library/rust:latest`
- **Command**: `rustc -vV`
- **Total**: 17s | Exit: 0

| Run | Time | Exit | vs Run 1 |
|:---:|-----:|:----:|:--------:|
| 1 | .2s | 0 | baseline |
| 2 | .4s | 0 | 152% |
| 3 | 0s | 0 | 30% |
| 4 | 0s | 0 | 30% |
| 5 | 0s | 0 | 30% |

### W7: Fedora rpm verify

- **Image**: `docker.io/library/fedora:latest`
- **Command**: `rpm -V bash`
- **Total**: 3s | Exit: 0

| Run | Time | Exit | vs Run 1 |
|:---:|-----:|:----:|:--------:|
| 1 | .3s | 0 | baseline |
| 2 | .4s | 0 | 125% |
| 3 | 0s | 0 | 21% |
| 4 | 0s | 0 | 22% |
| 5 | 0s | 0 | 22% |

