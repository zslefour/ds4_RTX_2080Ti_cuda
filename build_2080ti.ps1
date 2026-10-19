# Build helper for RTX 2080 Ti 22 GB on Windows.
# Prefer the MSYS2 route (see BUILD_WINDOWS.md). This script is a fallback
# for machines that have Visual Studio BuildTools + CUDA but no GNU make.

param(
    [switch]$Clean
)

$ErrorActionPreference = "Stop"

function Find-CudaHome {
    $nvcc = Get-Command nvcc -ErrorAction SilentlyContinue
    if ($nvcc) {
        return (Resolve-Path (Join-Path $nvcc.Source "..\..")).Path
    }
    $envCuda = $env:CUDA_HOME
    if ($envCuda) { return $envCuda }
    $candidates = @(
        "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.8",
        "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.6",
        "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.4",
        "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.2",
        "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.1",
        "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.0",
        "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v11.8"
    )
    foreach ($c in $candidates) {
        if (Test-Path (Join-Path $c "bin\nvcc.exe")) { return $c }
    }
    throw "Could not find CUDA. Set CUDA_HOME or add nvcc to PATH."
}

function Find-VisualStudio {
    $cl = Get-Command cl -ErrorAction SilentlyContinue
    if ($cl) { return $cl.Source }
    $vsWhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    if (Test-Path $vsWhere) {
        $installPath = & $vsWhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
        if ($installPath) {
            $cl = Get-ChildItem -Path "$installPath\VC\Tools\MSVC" -Recurse -Filter cl.exe | Select-Object -First 1
            if ($cl) { return $cl.FullName }
        }
    }
    throw "Could not find cl.exe. Run this script from a 'Developer PowerShell for VS 2022'."
}

$CUDA_HOME = Find-CudaHome
$env:CUDA_HOME = $CUDA_HOME
$env:PATH = "$CUDA_HOME\bin;$env:PATH"

# If GNU make is available, use the official Makefile (best path).
if (Get-Command make -ErrorAction SilentlyContinue) {
    Write-Host "Found GNU make; delegating to Makefile target 'cuda-turing'." -ForegroundColor Green
    make cuda-turing
    exit $LASTEXITCODE
}

Write-Host "GNU make not found; falling back to cl.exe + nvcc direct build." -ForegroundColor Yellow
Write-Host "CUDA_HOME = $CUDA_HOME"

$CL = Find-VisualStudio
$NVCC = "nvcc"

$OBJDIR = "obj"
if ($Clean -and (Test-Path $OBJDIR)) {
    Remove-Item -Recurse -Force $OBJDIR
}
New-Item -ItemType Directory -Force -Path $OBJDIR | Out-Null

$CFLAGS = @("/O2", "/MD", "/W3", "/std:c11", "/D_GNU_SOURCE", "/DDS4_CUDA_BUILD", "/I.", "/c")
$NVCCFLAGS = @("-O3", "-g", "-lineinfo", "--use_fast_math", "-arch=sm_75", "-Xcompiler", "/MD", "-std=c++17")

# C sources shared by all binaries.
$CoreCSrcs = @(
    "ds4.c",
    "ds4_distributed.c",
    "ds4_tp.c",
    "ds4_ssd.c",
    "ds4_layer_pack.c",
    "ds4_metrics.c"
)

$CommonCSrcs = @(
    "ds4_help.c",
    "linenoise.c",
    "ds4_gpu_args.c",
    "rax.c",
    "ds4_kvstore.c",
    "ds4_web.c"
)

$CudaSrcs = @(
    "ds4_cuda.cu",
    "cuda/mmq/ds4_ggml_stubs.cu",
    "cuda/mmq/ds4_mmq.cu",
    "cuda/mmq/ds4_mmq_d2r.cu",
    "cuda/mmq/quantize.cu",
    "cuda/mmq/mmid.cu",
    "cuda/mmq/mmvq.cu",
    "cuda/mmq/ds4_repack.cu"
)

function Compile-CFile($src) {
    $name = [System.IO.Path]::GetFileNameWithoutExtension($src)
    $obj = Join-Path $OBJDIR "$name.obj"
    if (Test-Path $obj) { Remove-Item $obj }
    Write-Host "cl $src -> $name.obj"
    & $CL @CFLAGS $src "/Fo$obj"
    if ($LASTEXITCODE -ne 0) { throw "Failed to compile $src" }
    return $obj
}

function Compile-CudaFile($src) {
    $name = [System.IO.Path]::GetFileNameWithoutExtension($src)
    $obj = Join-Path $OBJDIR "$name.obj"
    if (Test-Path $obj) { Remove-Item $obj }
    $inc = @("-I.", "-Icuda/mmq")
    Write-Host "nvcc $src -> $name.obj"
    & $NVCC @NVCCFLAGS @inc -c $src -o $obj
    if ($LASTEXITCODE -ne 0) { throw "Failed to compile $src" }
    return $obj
}

$CoreObjs = $CoreCSrcs | ForEach-Object { Compile-CFile $_ }
$CommonObjs = $CommonCSrcs | ForEach-Object { Compile-CFile $_ }
$CudaObjs = $CudaSrcs | ForEach-Object { Compile-CudaFile $_ }

$LinkLibs = @("-L""$CUDA_HOME\lib\x64""", "-lcudart", "-lcublas")

function Link-Binary($out, $objs) {
    if (Test-Path $out) { Remove-Item $out }
    Write-Host "Linking $out"
    & $NVCC -o $out @objs @LinkLibs
    if ($LASTEXITCODE -ne 0) { throw "Failed to link $out" }
}

Link-Binary "ds4"          (@("ds4_cli.obj") + $CommonObjs[0..3] + $CoreObjs + $CudaObjs)
Link-Binary "ds4-server"   (@("ds4_server.obj") + $CommonObjs + $CoreObjs + $CudaObjs)
Link-Binary "ds4-bench"    (@("ds4_bench.obj") + $CommonObjs[0..3] + $CoreObjs + $CudaObjs)
Link-Binary "ds4-eval"     (@("ds4_eval.obj") + $CommonObjs[0..0] + $CoreObjs + $CudaObjs)
Link-Binary "ds4-agent"    (@("ds4_agent.obj") + $CommonObjs + $CoreObjs + $CudaObjs)

Write-Host "Build complete: ds4, ds4-server, ds4-bench, ds4-eval, ds4-agent" -ForegroundColor Green
