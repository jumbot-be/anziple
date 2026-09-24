#!/bin/bash
# Shell script for redeploying crontab.
# Version: 4.0.11
# Create the logs cron jobs:
echo
if [ "$OSTYPE" == "linux-gnu" ]; then 
    echo "Deploying cron tab"
    ./generated/scripts/bash/_create-cronjob.sh
elif [ "$OSTYPE" == "msys" ]; then
    echo "Deploying Scheduled task"
    currentdir=$(pwd)
    schtaskscript=$(cygpath -w "${currentdir}/generated/scripts/posh/_create-schtask.ps1")
    #Call the script in a runas admin powershell window.
    powershell.exe -executionpolicy bypass -Command "Start-Process -FilePath powershell.exe -ArgumentList \"-executionpolicy bypass -File \"\"${schtaskscript}\"\"\" -verb runas -wait"
fi
echo