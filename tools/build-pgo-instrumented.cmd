@echo off
setlocal
cd /d "%~dp0.."

:: Keep all temporary files and compiler caches strictly on D: (saving C: disk space)
set "TEMP=%CD%\.tmp"
set "TMP=%CD%\.tmp"
if not exist "%CD%\.tmp" mkdir "%CD%\.tmp"

call "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat"
if errorlevel 1 exit /b 1

set "PATH=C:\Program Files\LLVM\bin;C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja;%PATH%"

set "HYBRID_QT=%CD%/.tools/Qt/6.8.3/msvc2022_64"
if not exist "%HYBRID_QT%/lib/cmake/Qt6/Qt6Config.cmake" (
    echo Missing workspace Qt 6.8.3. See docs/hybrid/BUILD.md.
    exit /b 1
)

if not exist ".tools/glslang-build/StandAlone/glslang.exe" (
    echo Building glslang-standalone dependency...
    cmake -S .tools/glslang-src -B .tools/glslang-build -G Ninja -DCMAKE_BUILD_TYPE=Release -DENABLE_OPT=OFF -DGLSLANG_TESTS=OFF -DBUILD_TESTING=OFF
    if errorlevel 1 exit /b 1
    cmake --build .tools/glslang-build --target glslang-standalone --parallel 8
    if errorlevel 1 exit /b 1
)
set "PATH=%CD%\.tools\glslang-build\StandAlone;%PATH%"

set "PGO_DATA_DIR=%CD%/build/pgo-data"
if not exist "%PGO_DATA_DIR%" mkdir "%PGO_DATA_DIR%"

set "PGO_FLAGS=-fprofile-generate"
set "PGO_LINK_FLAGS=/libpath:\"C:/Program Files/LLVM/lib/clang/19/lib/windows\" clang_rt.profile-x86_64.lib"

echo Configuring instrumented PGO build in build/hybrid-pgo-gen...
cmake -S . -B build/hybrid-pgo-gen -G Ninja ^
    "-UQt6*" "-UQT_*" ^
    -DCMAKE_BUILD_TYPE=Release ^
    -DCMAKE_C_COMPILER=clang-cl ^
    -DCMAKE_CXX_COMPILER=clang-cl ^
    -DCMAKE_LINKER=lld-link ^
    "-DCMAKE_C_FLAGS_RELEASE=/O2 /Ob2 /DNDEBUG %PGO_FLAGS%" ^
    "-DCMAKE_CXX_FLAGS_RELEASE=/O2 /Ob2 /DNDEBUG %PGO_FLAGS%" ^
    "-DCMAKE_EXE_LINKER_FLAGS_RELEASE=%PGO_LINK_FLAGS%" ^
    "-DGLSLANGVALIDATOR=%CD%/.tools/glslang-build/StandAlone/glslang.exe" ^
    "-DLICHII_LOCAL_BUILD_LABEL=Hybrid PGO-Instrumented Build" ^
    -DYUZU_USE_BUNDLED_QT=OFF ^
    -DYUZU_STATIC_BUILD=OFF ^
    "-DQt6_DIR=%HYBRID_QT%/lib/cmake/Qt6" ^
    "-DQT_DIR=%HYBRID_QT%/lib/cmake/Qt6" ^
    "-DQT_HOST_PATH=%HYBRID_QT%" ^
    "-DQT_TARGET_PATH=%HYBRID_QT%" ^
    -DZLIB_BUILD_TESTING=OFF ^
    -DENABLE_LTO=ON ^
    -DBUILD_TESTING=OFF ^
    -DYUZU_TESTS=OFF ^
    -DDYNARMIC_TESTS=OFF ^
    -DYUZU_ROOM=OFF ^
    -DYUZU_ROOM_STANDALONE=OFF ^
    -DYUZU_CMD=ON ^
    -DENABLE_QT=ON ^
    -DENABLE_UPDATE_CHECKER=OFF ^
    -DUSE_DISCORD_PRESENCE=OFF ^
    -DUSE_CCACHE=OFF ^
    -DENABLE_WERROR=OFF
if errorlevel 1 exit /b 1

if exist build/hybrid-pgo-gen/src/qt_common/CMakeFiles/qt_common_autogen.dir/AutogenInfo.json cmake -E cmake_autogen build/hybrid-pgo-gen/src/qt_common/CMakeFiles/qt_common_autogen.dir/AutogenInfo.json Release
if errorlevel 1 exit /b 1
if exist build/hybrid-pgo-gen/src/yuzu/CMakeFiles/yuzu_autogen.dir/AutogenInfo.json cmake -E cmake_autogen build/hybrid-pgo-gen/src/yuzu/CMakeFiles/yuzu_autogen.dir/AutogenInfo.json Release
if errorlevel 1 exit /b 1
if exist build/hybrid-pgo-gen/_deps/quazip-qt6-build/quazip/CMakeFiles/QuaZip_autogen.dir/AutogenInfo.json cmake -E cmake_autogen build/hybrid-pgo-gen/_deps/quazip-qt6-build/quazip/CMakeFiles/QuaZip_autogen.dir/AutogenInfo.json Release
if errorlevel 1 exit /b 1

echo Building instrumented yuzu target...
cmake --build build/hybrid-pgo-gen --target yuzu --parallel 8
if errorlevel 1 exit /b 1

echo Instrumented build ready at build/hybrid-pgo-gen/bin/lichii.exe.
echo Run tools\train-pgo.cmd to capture representative gameplay profiles.
