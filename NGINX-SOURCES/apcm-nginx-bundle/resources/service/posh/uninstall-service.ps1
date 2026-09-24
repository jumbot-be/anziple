# Unnstall Windows service
#
# Author: Arnaud De Jaegere (2024)
write-host "--------------------------------------------------------------------------------"
write-host "Windows Service uninstallation script."
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

& $nssmpath stop $($serviceinfo.Name) 
& $nssmpath remove $($serviceinfo.Name) confirm

write-host " - "
write-host "--------------------------------------------------------------------------------"
write-host "$($serviceinfo.DisplayName) Windows service has been removed."
write-host "--------------------------------------------------------------------------------"
pause
exit 0