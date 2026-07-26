@echo off
powershell -ExecutionPolicy Bypass -File "%~dp0lock.ps1" %*
