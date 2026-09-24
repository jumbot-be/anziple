# Install Windows service
#
# Author: Arnaud De Jaegere (2024)
write-host "--------------------------------------------------------------------------------"
write-host "Windows Service installation script."
write-host "--------------------------------------------------------------------------------"
write-host "Defining paths"
Set-Location $PSScriptRoot
$Generatedpath=$((get-item $pwd).Parent.parent).fullname
$Bundlepath=$((get-item $pwd).Parent.parent.parent).fullname
write-host "Reading service.conf"
$serviceconf = get-content $Generatedpath\conf\service.conf
$servicecontdata = @{}
foreach ($line in $serviceconf) {
    # Skip comments and empty lines
    if ($line -match '^\s*;|^\s*$') {
        continue
    }

    # Match key-value pairs
    if ($line -match '^\s*(\w+)\s*=\s*(.*)') {
        $key = $matches[1]
        $value = $($matches[2] -replace '"','')

        # Add the key-value pair to the hashtable
        $servicecontdata[$key] = $value
    }
}

$serviceinfo = get-content "$Generatedpath\conf\$($servicecontdata.servicename).json" | ConvertFrom-Json
$nssmpath = "$Bundlepath\tools\nssm-2.24\win64\nssm.exe"
$ServiceEnv = get-content "$Generatedpath\conf\$($servicecontdata.servicename).env"
$Service = @{}
foreach ($line in $ServiceEnv) {
    # Skip comments and empty lines
    if ($line -match '^\s*;|^\s*$') {
        continue
    }
    # Match key-value pairs
    if ($line -match '^\s*(\w+)\s*=\s*(.*)') {
        $key = $matches[1]
        $value = $($matches[2])
        # Add the key-value pair to the hashtable
        $Service[$key] = $value
    }
}
Write-host "The parameters that will be used to set the service: "
$serviceinfo | ft -AutoSize
$Service | ft -AutoSize

write-host "Do you want to continue ? (CTRL+c to abort)"
write-host " - "
pause
write-host "--------------------------------------------------------------------------------"
write-host "New $($serviceinfo.DisplayName) service installing..."

$Servicepath = "$Bundlepath\$($serviceinfo.Command)"
& $nssmpath install $($serviceinfo.Name) $Servicepath $($serviceinfo.Args)
& $nssmpath set $($serviceinfo.Name) Start SERVICE_DELAYED_AUTO_START
& $nssmpath set $($serviceinfo.Name) DisplayName $($serviceinfo.DisplayName)
& $nssmpath set $($serviceinfo.Name) Description $($serviceinfo.Description)
& $nssmpath set $($serviceinfo.Name) AppStopMethodSkip 0
& $nssmpath set $($serviceinfo.Name) AppStopMethodConsole 2000
& $nssmpath set $($serviceinfo.Name) AppStopMethodWindow 1500
& $nssmpath set $($serviceinfo.Name) AppStopMethodThreads 1500
& $nssmpath set $($serviceinfo.Name) AppThrottle 60000
& $nssmpath set $($serviceinfo.Name) AppExit Default Restart
& $nssmpath set $($serviceinfo.Name) AppRestartDelay 30000
# & $nssmpath set $($serviceinfo.Name) AppEnvironmentExtra 
# & $nssmpath set $($serviceinfo.Name) AppStdoutCreationDisposition 4
# & $nssmpath set $($serviceinfo.Name) AppStderrCreationDisposition 4
# & $nssmpath set $($serviceinfo.Name) AppRotateFiles 1
# & $nssmpath set $($serviceinfo.Name) AppRotateOnline 0
# & $nssmpath set $($serviceinfo.Name) AppRotateSeconds 86400
# & $nssmpath set $($serviceinfo.Name) AppRotateBytes 200000
& $nssmpath start $($serviceinfo.Name) 
write-host " - "
write-host "--------------------------------------------------------------------------------"
write-host "Please check manually the status of $($serviceinfo.DisplayName) Windows service."
write-host "--------------------------------------------------------------------------------"
write-host "If the service does not seem to start: check application log and event viewer. "
write-host "--------------------------------------------------------------------------------"
pause
exit 0