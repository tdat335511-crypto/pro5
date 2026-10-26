@echo off
title Billiards Media Sync Server (Port 5555)
cd /d "%~dp0"
echo ==========================================================
echo  Billiards Media - Local Project Asset Sync Server
echo  Tu dong ghi file anh va tournaments.json vao thu muc project
echo ==========================================================
echo.
powershell -ExecutionPolicy Bypass -File "%~dp0sync_server.ps1"
pause
