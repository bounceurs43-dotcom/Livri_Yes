@echo off
echo Starting LivriYes Applications...

echo [1/2] Starting Admin Dashboard (Web)...
start cmd /k "cd admin && flutter run -d chrome"

echo [2/2] Starting Client Application (Connected Device)...
start cmd /k "cd client && flutter run"

echo Both applications are starting in separate windows.
pause
