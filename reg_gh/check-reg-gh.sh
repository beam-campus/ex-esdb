#!/bin/bash

# Health check for RegGh ExESDB Store
# This script checks if the RegGh application is running properly

# Check if the BEAM process is running
if ! ps aux | grep -v grep | grep "reg_gh" > /dev/null; then
    echo "ERROR: RegGh process not found"
    exit 1
fi

# Try to get the PID of the running node
/system/bin/reg_gh pid > /dev/null 2>&1
PID_RESULT=$?

if [ $PID_RESULT -eq 0 ]; then
    echo "OK: RegGh node is responding"
    exit 0
else
    echo "ERROR: RegGh node is not responding"
    exit 1
fi
