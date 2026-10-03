#!/bin/sh
# Starts the EventLens owner dashboard in the background and opens it.
cd "$(dirname "$0")" && python3 -m eventlens_dashboard start --background
