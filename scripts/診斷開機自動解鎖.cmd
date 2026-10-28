@echo off
rem Run diagnose.ps1 as administrator (a UAC prompt will appear)
powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process powershell -Verb RunAs -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File','\"%~dp0diagnose.ps1\"')"
