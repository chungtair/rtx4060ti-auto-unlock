@echo off
rem Run fix_order.ps1 as administrator (a UAC prompt will appear)
powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process powershell -Verb RunAs -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File','\"%~dp0fix_order.ps1\"')"
