#!/bin/bash

# Check OS and call the OS specific script

# Read Service.conf
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
parrentdir=$(dirname $SCRIPT_DIR)

if [ "$OSTYPE" == "linux-gnu" ]; then
    echo "To do"
elif [ "$OSTYPE" == "msys" ]; then
    #Try uninstalling service
    #Test if service exist before runinning unintall script
    echo "Try to remove service"
    sc query $servicename >/dev/null
    if [ $? == 0 ]; then
        #write the script path.
        uninstallscriptpath=$(cygpath -w "${SCRIPT_DIR}/posh/uninstall-service.ps1")
        #Call the script in a runas admin powershell window.
        powershell.exe -executionpolicy bypass -Command "Start-Process -FilePath powershell.exe  -ArgumentList \"-executionpolicy bypass -File \"\"${uninstallscriptpath}\"\"\" -verb runas -wait"
    fi
else
    echo "Unknown operating system. Didn't remove service."
fi

exit 0