@echo off
REM ============================================================================
REM  gitpush.bat - stage everything, auto-commit, and push the current branch.
REM  Works in any repo: drop it in the root next to the .git folder and run it.
REM
REM  Usage:
REM    gitpush                 Auto commit message (timestamp + file count)
REM    gitpush "my message"    Use your own commit message
REM ============================================================================
setlocal EnableDelayedExpansion

REM --- Move to the repository root (the folder that contains .git) -------------
set "REPO_ROOT="
for /f "delims=" %%i in ('git rev-parse --show-toplevel 2^>nul') do set "REPO_ROOT=%%i"
if not defined REPO_ROOT (
  echo X Not inside a git repository.
  exit /b 1
)
cd /d "%REPO_ROOT%"

REM --- Bail out early if there is nothing to commit ---------------------------
set "DIRTY="
for /f "delims=" %%i in ('git status --porcelain') do set "DIRTY=1"
if not defined DIRTY (
  echo OK Nothing to commit - working tree is clean.
  exit /b 0
)

REM --- Stage all changes (new, modified, deleted) -----------------------------
git add -A

REM --- Build the commit message -----------------------------------------------
set "MSG=%*"
REM Strip surrounding quotes if the user passed a quoted message.
if defined MSG set "MSG=%MSG:"=%"
if not defined MSG (
  for /f "delims=" %%i in ('powershell -NoProfile -Command "Get-Date -Format \"yyyy-MM-dd HH:mm:ss\""') do set "TIMESTAMP=%%i"
  set "COUNT=0"
  for /f %%i in ('git diff --cached --name-only ^| find /c /v ""') do set "COUNT=%%i"
  set "MSG=chore: update !COUNT! file(s) - !TIMESTAMP!"
)

REM --- Commit -----------------------------------------------------------------
git commit -m "!MSG!"
if errorlevel 1 (
  echo X Commit failed.
  exit /b 1
)

REM --- Figure out the current branch and remote -------------------------------
set "BRANCH="
for /f "delims=" %%i in ('git rev-parse --abbrev-ref HEAD') do set "BRANCH=%%i"

set "REMOTE="
for /f "delims=" %%i in ('git remote') do (
  if not defined REMOTE set "REMOTE=%%i"
)
if not defined REMOTE (
  echo X No remote configured - commit done, but nothing to push to.
  exit /b 1
)

REM --- Push (set upstream automatically the first time) -----------------------
git rev-parse --abbrev-ref --symbolic-full-name "@{u}" >nul 2>&1
if errorlevel 1 (
  git push -u "%REMOTE%" "%BRANCH%"
) else (
  git push
)
if errorlevel 1 (
  echo X Push failed.
  exit /b 1
)

echo OK Pushed '%BRANCH%' to '%REMOTE%' - !MSG!
endlocal
