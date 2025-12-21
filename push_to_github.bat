@echo off
REM Script to initialize git repository and push to GitHub
REM Make sure you have created a GitHub repository first

echo Initializing git repository...
git init

echo Adding all files...
git add .

echo Committing files...
git commit -m "Initial commit: Dr. Rajneesh Chaudhary App"

echo.
echo ========================================
echo IMPORTANT: Next steps:
echo ========================================
echo 1. Go to GitHub and create a new repository
echo 2. Copy the repository URL (e.g., https://github.com/username/repo-name.git)
echo 3. Run the following commands:
echo.
echo    git remote add origin YOUR_REPOSITORY_URL
echo    git branch -M main
echo    git push -u origin main
echo.
echo ========================================
echo.
pause

