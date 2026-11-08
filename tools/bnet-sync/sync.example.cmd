@echo off
rem Copy to sync.cmd (ignored by git) and adjust both paths.
rem ENV_FILE: a file with BATTLENET_CLIENT_ID and BATTLENET_CLIENT_SECRET (Raidy's .env.local works).
set ENV_FILE=C:\_dev\workspace\Raidy\.env.local
set GUILDY_SV=C:\Spiele\World of Warcraft\_forever_\WTF\Account\YOUR_ACCOUNT\SavedVariables\Guildy.lua
node --env-file="%ENV_FILE%" "%~dp0sync.mjs" --sv "%GUILDY_SV%" %*
pause
