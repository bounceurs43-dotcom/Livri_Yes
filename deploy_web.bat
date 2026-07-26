@echo off
echo ====================================
echo  LivriYes Web Build & Deploy Script 
echo ====================================
echo.

echo [1/3] Building Flutter Web for Admin...
cd admin
call flutter build web
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Flutter build failed!
    exit /b %ERRORLEVEL%
)
cd ..

echo.
echo [2/3] Copying build artifacts to root for Vercel...
xcopy /E /Y /I admin\build\web\* .

echo.
echo [3/3] Committing and Pushing to GitHub...
git add .
git commit -m "Auto-deploy web update to root"
git push origin main

echo.
echo ====================================
echo  SUCCESS: Deployment pushed to GitHub!
echo ====================================
pause
