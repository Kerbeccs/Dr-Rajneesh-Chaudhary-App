@echo off
REM Script to push code to GitHub
REM Git repository is already initialized and files are committed

echo ========================================
echo GitHub Push Instructions
echo ========================================
echo.
echo Step 1: Create a new repository on GitHub
echo    - Go to https://github.com/new
echo    - Enter repository name (e.g., Dr-Rajneesh-Chaudhary-App)
echo    - Choose public or private
echo    - DO NOT initialize with README, .gitignore, or license
echo    - Click "Create repository"
echo.
echo Step 2: Copy your repository URL
echo    - After creating, GitHub will show you the repository URL
echo    - It will look like: https://github.com/username/repo-name.git
echo.
echo Step 3: Run these commands (replace YOUR_REPOSITORY_URL):
echo.
echo    git remote add origin YOUR_REPOSITORY_URL
echo    git branch -M main
echo    git push -u origin main
echo.
echo ========================================
echo.
echo Your code is already committed and ready to push!
echo.
pause

