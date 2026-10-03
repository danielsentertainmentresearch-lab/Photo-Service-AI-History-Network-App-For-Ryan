#!/bin/sh
# Ends the background hosting of the EventLens owner dashboard.
cd "$(dirname "$0")" && python3 -m eventlens_dashboard stop
