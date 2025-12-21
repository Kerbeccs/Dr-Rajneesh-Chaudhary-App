@echo off
REM Script to install Android Build Tools 34.0.0
REM This script installs the required Android build tools for the Flutter project

echo Installing Android Build Tools 34.0.0...
echo.

set ANDROID_SDK=%ANDROID_HOME%
if "%ANDROID_SDK%"=="" (
    set ANDROID_SDK=%LOCALAPPDATA%\Android\Sdk
)

echo Android SDK Path: %ANDROID_SDK%
echo.

if exist "%ANDROID_SDK%\cmdline-tools\latest\bin\sdkmanager.bat" (
    "%ANDROID_SDK%\cmdline-tools\latest\bin\sdkmanager.bat" "build-tools;34.0.0"
) else if exist "%ANDROID_SDK%\tools\bin\sdkmanager.bat" (
    "%ANDROID_SDK%\tools\bin\sdkmanager.bat" "build-tools;34.0.0"
) else (
    echo Error: sdkmanager.bat not found!
    echo Please install Android SDK Command-line Tools through Android Studio:
    echo 1. Open Android Studio
    echo 2. Go to Tools -^> SDK Manager
    echo 3. Go to SDK Tools tab
    echo 4. Check "Android SDK Command-line Tools (latest)"
    echo 5. Click Apply to install
    echo.
    echo Alternatively, install build-tools;34.0.0 manually through Android Studio SDK Manager.
    pause
    exit /b 1
)

echo.
echo Build tools installation completed!
echo You can now run: flutter run
pause

