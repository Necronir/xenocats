@echo off
:: TortoiseGit Start-commit hook wrapper for OpenCommit
set MESSAGE_FILE=%~2
if not "%~3"=="" cd /d "%~3"

:: If no files are staged yet, stage tracked modified files so OpenCommit can inspect the diff
git diff --cached --quiet
if errorlevel 1 goto :RUN_OCO
git add -u

:RUN_OCO
node "C:\Users\nicro\AppData\Roaming\npm\node_modules\opencommit\out\cli.cjs" "%MESSAGE_FILE%"
