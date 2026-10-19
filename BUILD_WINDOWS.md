# Building on Windows for RTX 2080 Ti 22 GB

The project is developed primarily on Linux, but it can be built on Windows
using an MSYS2/MinGW-w64 environment plus the NVIDIA CUDA Toolkit. The steps
below were written for the RTX 2080 Ti 22 GB (`sm_75`) profile.

## Prerequisites

1. **NVIDIA driver and CUDA Toolkit** – CUDA 12.x or later is recommended.
   The fork's author tested on CUDA 13.3.1, but `sm_75` compiles fine with
   CUDA 12.6/12.8. Confirm with:

   ```powershell
   nvidia-smi
   nvcc --version
   ```

2. **MSYS2** – provides `bash`, `make`, and a Windows-native GCC.
   Download and install from <https://www.msys2.org/>, then open the
   **MSYS2 MinGW 64-bit** terminal and run:

   ```sh
   pacman -Syu
   pacman -S mingw-w64-x86_64-gcc mingw-w64-x86_64-make make git
   ```

3. **Add the MinGW-w64 binaries to PATH.** In PowerShell (run as
   Administrator):

   ```powershell
   [Environment]::SetEnvironmentVariable(
       "Path",
       $env:Path + ";C:\msys64\mingw64\bin;C:\msys64\usr\bin",
       "User"
   )
   ```

   Close and reopen any open terminals.

4. **Verify the toolchain** in an MSYS2 MinGW 64-bit terminal:

   ```sh
   gcc --version
   make --version
   nvcc --version
   ```

## Build

Open an **MSYS2 MinGW 64-bit** terminal and navigate to the project folder
(e.g. `D:\CCProjects\ds4_RTX_2080Ti_cuda`):

```sh
cd /d/CCProjects/ds4_RTX_2080Ti_cuda
make cuda-turing
```

This builds:

- `ds4`
- `ds4-server`
- `ds4-bench`
- `ds4-eval`
- `ds4-agent`

Compilation may take several minutes because the vendored `cuda/mmq/` kernels
are large template-heavy translation units.

## Run

1. Download a supported model (Q2/Q4_K recommended; avoid MXFP4/NVFP4 models
   because Turing does not have native FP4 Tensor Cores):

   ```sh
   ./download_model.sh ds4f-q2
   ```

2. Start the server:

   ```sh
   ./run_ds4_cuda_server_2080ti.sh
   ```

3. Open <http://127.0.0.1:18099>.

## Alternative: Visual Studio + PowerShell

If you prefer not to install MSYS2, a minimal PowerShell build script
(`build_2080ti.ps1`) is provided. It uses the existing Visual Studio C++
compiler (`cl.exe`) and `nvcc`. This path is less tested; the MSYS2 route
above is preferred.

```powershell
.\build_2080ti.ps1
```

## Troubleshooting

### `make: command not found`

Install MSYS2 and `make` as described above, or run the build from the
MSYS2 MinGW 64-bit terminal instead of Git Bash / PowerShell.

### `cc: command not found` / `gcc: command not found`

The Makefile uses `CC ?= cc`. In MSYS2 MinGW 64-bit, either `cc` should be a
symlink to `gcc`, or you can override it:

```sh
make cuda-turing CC=gcc
```

### CUDA not found

Set `CUDA_HOME` explicitly before building or running:

```sh
export CUDA_HOME="/c/Program Files/NVIDIA GPU Computing Toolkit/CUDA/v12.8"
export PATH="$CUDA_HOME/bin:$PATH"
make cuda-turing
```

### Out of memory at runtime

Lower the expert cache or context via environment variables:

```sh
export DS4_SERVER_EXPERT_CACHE=8GB
export DS4_SERVER_CTX=32768
./run_ds4_cuda_server_2080ti.sh
```
