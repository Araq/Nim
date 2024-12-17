@echo off
rem DO NO EDIT DIRECTLY! auto-generated by `nim r tools/ci_generate.nim`
rem Build development version of the compiler; can be rerun safely
rem bare bones version of ci/funs.sh adapted for windows.

rem Read in some common shared variables (shared with other tools),
rem see https://stackoverflow.com/questions/3068929/how-to-read-file-contents-into-a-variable-in-a-batch-file
for /f "delims== tokens=1,2" %%G in (config/build_config.txt) do set %%G=%%H
SET nim_csources=bin\nim_csources_%nim_csourcesHash%.exe
echo "building from csources: %nim_csources%"

if not exist %nim_csourcesDir% (
  git clone -q --depth 1 -b %nim_csourcesBranch% %nim_csourcesUrl% %nim_csourcesDir%
)

if not exist %nim_csources% (
  cd %nim_csourcesDir%
  git checkout %nim_csourcesHash%
  echo "%PROCESSOR_ARCHITECTURE%"
  if "%PROCESSOR_ARCHITECTURE%"=="AMD64" (
    SET ARCH=64
  )
  CALL build.bat
  cd ..
  copy /y bin\nim.exe  %nim_csources%
)
bin\nim.exe c --noNimblePath --skipUserCfg --skipParentCfg --hints:off koch
koch boot -d:release --skipUserCfg --skipParentCfg --hints:off
koch tools --skipUserCfg --skipParentCfg --hints:off
