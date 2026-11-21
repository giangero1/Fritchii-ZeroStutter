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

set "PGO_DATA=%CD%\build\pgo-data"
set "MERGED_PROF=%PGO_DATA%\hybrid.profdata"

if not exist "%PGO_DATA%\*.profraw" (
    echo Error: No .profraw profiles found in %PGO_DATA%.
    echo Please run tools\train-pgo.cmd and play representative scenes first.
    exit /b 1
)

echo Merging raw profiles into %MERGED_PROF%...
llvm-profdata merge -o "%MERGED_PROF%" "%PGO_DATA%\*.profraw"
if errorlevel 1 exit /b 1

echo Profile summary:
llvm-profdata show --counts --topn=10 "%MERGED_PROF%"
if errorlevel 1 exit /b 1

set "HYBRID_QT=%CD%/.tools/Qt/6.8.3/msvc2022_64"
if not exist "%HYBRID_QT%/lib/cmake/Qt6/Qt6Config.cmake" (
    echo Missing workspace Qt 6.8.3. See docs/hybrid/BUILD.md.
    exit /b 1
)

set "PGO_FLAGS=-fprofile-use=%MERGED_PROF:\=/%"
set "PGO_LINK_FLAGS=/OPT:REF,NOICF /opt:lldltojobs=12"

echo Configuring PGO-optimized build in build/hybrid-pgo-use...
cmake -S . -B build/hybrid-pgo-use -G Ninja ^
    "-UQt6*" "-UQT_*" ^
    -DCMAKE_BUILD_TYPE=Release ^
    -DCMAKE_C_COMPILER=clang-cl ^
    -DCMAKE_CXX_COMPILER=clang-cl ^
    -DCMAKE_LINKER=lld-link ^
    "-DCMAKE_C_FLAGS_RELEASE=/O2 /Ob2 /DNDEBUG %PGO_FLAGS%" ^
    "-DCMAKE_CXX_FLAGS_RELEASE=/O2 /Ob2 /DNDEBUG %PGO_FLAGS%" ^
    "-DCMAKE_EXE_LINKER_FLAGS_RELEASE=%PGO_LINK_FLAGS%" ^
    "-DGLSLANGVALIDATOR=%CD%/.tools/glslang-build/StandAlone/glslang.exe" ^
    "-DLICHII_LOCAL_BUILD_LABEL=Hybrid PGO-Optimized Candidate" ^
    -DYUZU_USE_BUNDLED_QT=OFF ^
    -DYUZU_STATIC_BUILD=OFF ^
    "-DQt6_DIR=%HYBRID_QT%/lib/cmake/Qt6" ^
    "-DQT_DIR=%HYBRID_QT%/lib/cmake/Qt6" ^
    "-DQT_HOST_PATH=%HYBRID_QT%" ^
    "-DQT_TARGET_PATH=%HYBRID_QT%" ^
    -DZLIB_BUILD_TESTING=OFF ^
    -DENABLE_LTO=ON ^
    -DBUILD_TESTING=ON ^
    -DYUZU_TESTS=ON ^
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

if exist build/hybrid-pgo-use/src/qt_common/CMakeFiles/qt_common_autogen.dir/AutogenInfo.json cmake -E cmake_autogen build/hybrid-pgo-use/src/qt_common/CMakeFiles/qt_common_autogen.dir/AutogenInfo.json Release
if errorlevel 1 exit /b 1
if exist build/hybrid-pgo-use/src/yuzu/CMakeFiles/yuzu_autogen.dir/AutogenInfo.json cmake -E cmake_autogen build/hybrid-pgo-use/src/yuzu/CMakeFiles/yuzu_autogen.dir/AutogenInfo.json Release
if errorlevel 1 exit /b 1
if exist build/hybrid-pgo-use/_deps/quazip-qt6-build/quazip/CMakeFiles/QuaZip_autogen.dir/AutogenInfo.json cmake -E cmake_autogen build/hybrid-pgo-use/_deps/quazip-qt6-build/quazip/CMakeFiles/QuaZip_autogen.dir/AutogenInfo.json Release
if errorlevel 1 exit /b 1

echo Compiling PGO-optimized binary...
cmake --build build/hybrid-pgo-use --parallel 8
if errorlevel 1 exit /b 1

if not exist build\hybrid-pgo-use\bin\user mkdir build\hybrid-pgo-use\bin\user

echo Running test suite verification on PGO build...
ctest --test-dir build/hybrid-pgo-use --output-on-failure --no-tests=error
if errorlevel 1 exit /b 1

echo Packaging isolated PGO distribution...
powershell -NoProfile -ExecutionPolicy Bypass -File tools\package-hybrid-pgo.ps1
if errorlevel 1 exit /b 1

echo ========================================================
echo PGO-optimized build successfully created and verified!
echo Package: portable-hybrid-pgo
echo ========================================================
