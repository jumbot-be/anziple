#
# Copyright (c) 2023 Ampacimon S.A.,
# Rue de Wallonie 11, B4460 Grace-Hollogne, Belgium.
# All rights reserved.
#
# This software is the confidential and proprietary information
# of Ampacimon S.A. ("Confidential Information").
# You SHALL NOT disclose such Confidential Information and SHALL ONLY use
# or redistribute it in source or binary forms in accordance with the
# terms of the license agreement you entered into with Ampacimon S.A.
#
##Author: Arnaud De Jaegere
##email: arnaud.dejaegere@ampacimon.com
##Date: 12/2024
# Version: 4.0.11

#parameters
# read the INI file
Set-Location -Path $($PSScriptRoot)
$maintenancecontent = get-content .\data\maintenance.ini
$maintenancedata = @{}
foreach ($line in $maintenancecontent) {
    # Skip comments and empty lines
    if ($line -match '^\s*;|^\s*$') {
        continue
    }

    # Match key-value pairs
    if ($line -match '^\s*(\w+)\s*=\s*(.*)') {
        $key = $matches[1]
        $value = $($matches[2] -replace '"','')

        # Add the key-value pair to the hashtable
        $maintenancedata[$key] = $value
    }
}

$nginxcontent = get-content .\data\exportNGINX.ini
$nginxcedata = @{}
foreach ($line in $nginxcontent) {
    # Skip comments and empty lines
    if ($line -match '^\s*;|^\s*$') {
        continue
    }

    # Match key-value pairs
    if ($line -match '^\s*(\w+)\s*=\s*(.*)') {
        $key = $matches[1]
        $value = $($matches[2] -replace '"','')

        # Add the key-value pair to the hashtable
        $nginxcedata[$key] = $value
    }
}

#Test and connect to sharedfolder
#Verify shared folder or local path
try{
    if($maintenancedata.destination -match '[a-zA-Z]:\\.*'){
        #Local Path do nothing
    }elseif($maintenancedata.destination -match '\\\\.*'){
        #remotepath Mount it
        if($maintenancedata.user -and $maintenancedata.password){
            #Mount datadir as username
            #Get the password
            $netsharepasswordss = get-content $maintenancedata.password | convertto-SecureString
            $netsharepassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($netsharepasswordss))
            New-SmbMapping -RemotePath $maintenancedata.destination -UserName $($maintenancedata.user) -Password $netsharepassword
            
        }else{
            #Mount datadir without user
            New-SmbMapping -RemotePath $maintenancedata.destination
        }
    }else{
        #unknown path
    }
}catch{
    "[Error] Could not mount the $($maintenancedata.destination). Error: $($_.Exception.Message)" | out-file -Append -FilePath errorexportADRLogs.txt
    exit 1
}

#Define all paths
$logdir=$nginxcedata.logdir
$tempout="temp\nginxLogs"
$hostname = hostname
$outfolder="$($maintenancedata.destination)\nginxLogs\$hostname"
New-Item -Force -ItemType Directory -Path "$outfolder" | Out-Null
New-Item -Force -ItemType Directory -Path "$tempout" | Out-Null


#function definition
function copy-log {
    param(
        [string]$source,
        [string]$destination
    )
    if (-not (Test-Path -Path $destination -PathType Leaf)) {
        #Ensure the source still exist befor copying to temp location.
        if (Test-Path -Path $source -PathType Leaf -EA 0){
            Copy-Item -Path $source -Dest $destination
        }
    }
}
function export-log {
    param(
        [string]$name
    )
    #For the last 15 days, check if we have logs.
    for ($i = 1; $i -lt 16; $i++) {
        #Clean var
        $logpath=$null
        $logpaths=$null
        $logserver=$null
        $destlogpath=$null
        #Craft the date
        $prevdate = ($(Get-Date).adddays(-$i)).ToString("yyyy-MM-dd")
        #Craft the log paths based on file name
        $logserver="$logdir\*$name-$prevdate.zip"
        $logpaths=$(Get-ChildItem  $logserver)

        if($logpaths){
            foreach($logpath in $logpaths){
                $destlogpath="$tempout\$($logpath.name)"
                copy-log -source $($logpath.FullName) -destination $destlogpath
            }
        }
    }
}
#Exporting 15 days of logs into temp location
export-log -name nginx

#For each log file in temp location.
foreach($item in (get-childitem $tempout -File)){
    #prepare destination filepath
    $itemdate=$($item.name | Select-String -Pattern '(\d{4}-\d{2}-\d{2})').Matches.value    
    $outdate = $itemdate.Substring(0,7)

    #Create the folder for the month
    $destinationfolder="$outfolder\$outdate"
    New-Item -Force -ItemType Directory -Path "$destinationfolder" | Out-Null

    $fulldestinationpath="$destinationfolder\$($item.name)"
    copy-log -source $($item.fullname) -destination $fulldestinationpath 

    #Clean up the item if older than 15 days.
    if((get-date $itemdate) -lt (get-date).AddDays(-15)){
        Remove-Item -path $($item.fullname) -force
    }
} 
