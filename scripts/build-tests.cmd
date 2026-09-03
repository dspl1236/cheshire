@echo off
rem Configure, build and run the HIP smoke tests in hip/tests on the local AMD GPU.
rem Usage: scripts\build-tests.cmd [gfxArch] [variant]
rem   variant = clang   : host CXX = clang++ (GNU-style driver), HIP = clang++   [default]
rem             clangcl : host CXX = clang-cl (MSVC-style driver), HIP = clang-cl
rem             msvc    : host CXX = cl.exe, HIP = clang++  (CMake rejects this mix; kept for reference)
setlocal
call "%~dp0env.cmd"
set ARCH=%~1
if "%ARCH%"=="" set ARCH=gfx1201
set VARIANT=%~2
if "%VARIANT%"=="" set VARIANT=clang
set LLVMBIN=%ROCM_PATH%/lib/llvm/bin
if "%VARIANT%"=="clang"   set CXX_=%LLVMBIN%/clang++.exe& set HIPCXX_=%LLVMBIN%/clang++.exe
if "%VARIANT%"=="clangcl" set CXX_=%LLVMBIN%/clang-cl.exe& set HIPCXX_=%LLVMBIN%/clang-cl.exe
if "%VARIANT%"=="msvc"    set CXX_=%CHESHIRE_CL%& set HIPCXX_=%LLVMBIN%/clang++.exe
set SRC=%CHESHIRE_ROOT:\=/%/hip/tests
set BLD=%CHESHIRE_ROOT:\=/%/build/tests-%ARCH%-%VARIANT%

cmake -S "%SRC%" -B "%BLD%" -G Ninja -DCMAKE_BUILD_TYPE=Release ^
  "-DCMAKE_CXX_COMPILER=%CXX_%" ^
  "-DCMAKE_HIP_COMPILER=%HIPCXX_%" ^
  "-DCMAKE_PREFIX_PATH=%ROCM_PATH%" ^
  "-DCMAKE_HIP_ARCHITECTURES=%ARCH%" ^
  "-DCMAKE_HIP_FLAGS=--rocm-path=%ROCM_PATH% --rocm-device-lib-path=%HIP_DEVICE_LIB_PATH%" ^
  || exit /b 1
cmake --build "%BLD%" %CHESHIRE_BUILD_VERBOSE% || exit /b 1
echo.
echo ===== hello_hip =====
"%BLD%\hello_hip.exe" || exit /b 1
echo.
echo ===== mipmap_tex =====
"%BLD%\mipmap_tex.exe" || exit /b 1
