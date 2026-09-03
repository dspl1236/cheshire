@echo off
rem Compile AliceVision's depthMap/cuda tree as HIP through the compat layer (hip/port).
rem Usage: scripts\build-port.cmd [gfxArch] [clang|clangcl]   (defaults: gfx1201 clangcl)
setlocal
call "%~dp0env.cmd"
set ARCH=%~1
if "%ARCH%"=="" set ARCH=gfx1201
set VARIANT=%~2
if "%VARIANT%"=="" set VARIANT=clangcl
set LLVMBIN=%ROCM_PATH%/lib/llvm/bin
if "%VARIANT%"=="clang"   set CXX_=%LLVMBIN%/clang++.exe& set HIPCXX_=%LLVMBIN%/clang++.exe
if "%VARIANT%"=="clangcl" set CXX_=%LLVMBIN%/clang-cl.exe& set HIPCXX_=%LLVMBIN%/clang-cl.exe
set SRC=%CHESHIRE_ROOT:\=/%/hip/port
set BLD=%CHESHIRE_ROOT:\=/%/build/port-%ARCH%-%VARIANT%

cmake -S "%SRC%" -B "%BLD%" -G Ninja -DCMAKE_BUILD_TYPE=Release ^
  "-DCMAKE_CXX_COMPILER=%CXX_%" ^
  "-DCMAKE_HIP_COMPILER=%HIPCXX_%" ^
  "-DCMAKE_PREFIX_PATH=%ROCM_PATH%" ^
  "-DCMAKE_HIP_ARCHITECTURES=%ARCH%" ^
  "-DCMAKE_HIP_FLAGS=--rocm-path=%ROCM_PATH% --rocm-device-lib-path=%HIP_DEVICE_LIB_PATH%" ^
  %CHESHIRE_CMAKE_EXTRA% ^
  || exit /b 1
cmake --build "%BLD%" %CHESHIRE_BUILD_VERBOSE% -- -k 0 || exit /b 1
echo PORT BUILD OK
