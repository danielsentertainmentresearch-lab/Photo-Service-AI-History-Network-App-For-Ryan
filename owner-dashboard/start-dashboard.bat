@echo off
rem Starts the EventLens owner dashboard in the background and opens it.
cd /d "%~dp0"
py -m eventlens_dashboard start --background || python -m eventlens_dashboard start --background
pause
