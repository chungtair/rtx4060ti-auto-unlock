@echo off
rem Run uninstall.ps1 as administrator (a UAC prompt will appear)
powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process powershell -Verb RunAs -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-NoExit','-File','\"%~dp0uninstall.ps1\"')"
