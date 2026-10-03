@echo off
rem Ends the background hosting of the EventLens owner dashboard.
cd /d "%~dp0"
py -m eventlens_dashboard stop || python -m eventlens_dashboard stop
pause
