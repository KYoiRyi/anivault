@echo off
setlocal
powershell -ExecutionPolicy Bypass -File "%~dp0build_windows_cached.ps1" %*
endlocal
