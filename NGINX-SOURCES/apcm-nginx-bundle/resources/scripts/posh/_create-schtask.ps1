Write-host "Creating Scheduled task."
Set-Location $PSScriptRoot
$Bundlepath=$((get-item $pwd).Parent.parent.parent).fullname
$parrentdir=$((get-item $pwd).Parent.parent.parent.parent).fullname
#region initialisation

#Read ini file
$Maintenanceconfg="$Bundlepath\generated\conf\apcm-maintenance\maintenance.ini"
$maintenancecontent = get-content $Maintenanceconfg
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

#Define Var
$service="Scriptuser"
$groupmembershipID="S-1-5-32-559"
$groupmembership=(Get-LocalGroup -SID $groupmembershipID).name
$logdir="@nginx.log.directory@"
$scriptdest="$parrentdir\apcm-maintenance"
$datadest="$scriptdest\data"
$bindest="$scriptdest\bin"
$Maintenanceconfgd="$datadest\maintenance.ini"
$nginxconfg="$Bundlepath\generated\conf\apcm-maintenance\exportNGINX.ini"
$nginxconfgd="$datadest\exportNGINX.ini"
$outfolderLog="$($maintenancedata.destination)\nginxLogs"
$secretfolder="$scriptdest\data\protected"
$LogrotateS="$Bundlepath\generated\scripts\posh\schtasks\rotateNGINXLogs.ps1"
$LogrotateSd="$scriptdest\rotateNGINXLogs.ps1"
$LogsS="$Bundlepath\generated\scripts\posh\schtasks\exportNGINXLogs.ps1"
$LogsSd="$scriptdest\exportNGINXLogs.ps1"
$OnDemandtaskS="$Bundlepath\generated\scripts\posh\schtasks\onDemandTask.ps1"
$OnDemandtaskD="$scriptdest\onDemandTask.ps1"
$OnDemandsecure="$scriptdest\data\protected\$service.txt" #New file with plain text.
$Datadirsecure="$scriptdest\data\protected\datadir.txt" #New file with plain text.  
$Datadirsecuretarget="$scriptdest\data\protected\SecureStringdatadir.txt" #expected file name once encrypted
$OndemandTaskname="apcm-maintenance"
$SCOnDemandTask="powershell.exe"
$SCOnDemandTaskArgs="-noprofile -executionpolicy bypass -file ""$OnDemandtaskD"""

#Test and connect to sharedfolder
#Verify shared folder or local path
try{
    if($maintenancedata.destination -match '[a-zA-Z]:\\.*'){
        #Local Path do nothing
    }elseif($maintenancedata.destination -match '\\\\.*'){
        #remotepath Mount it
        if($maintenancedata.user -and $maintenancedata.password){
            #Mount datadir as username
            New-SmbMapping -RemotePath $maintenancedata.destination -UserName $($maintenancedata.user) -Password $($maintenancedata.password)
            
        }else{
            #Mount datadir without user
            New-SmbMapping -RemotePath $maintenancedata.destination
        }
    }else{
        #unknown path
    }
}catch{
    "[Error] Could not mount the $($maintenancedata.destination). Error: $($_.Exception.Message)"
    exit 1
}

new-item -path $scriptdest -ItemType Directory -force
new-item -path $datadest -ItemType Directory -force
new-item -path $bindest -ItemType Directory -force
new-item -path $outfolderLog -ItemType Directory -force
new-item -path $secretfolder -ItemType Directory -force
#endregion

#region service account and ondemand task
$randompassword = $null
((65..90) + (97..122) | Get-Random -Count 10)+((48..57) | Get-Random -Count 2)+((37..47) + 33 + 35 + (58..63) | Get-Random -Count 2) | Sort-Object {Get-Random} | %{ $randompassword += [char]$_ }

if((Get-LocalUser -Name $service 2>$null)){
    write-host "$service account already exist."
    if((Get-ScheduledTask $OndemandTaskname 2>$null)){
        write-host "And task $OndemandTaskname too."
    }else{
        write-host "But the ondemand task not. Please Remove the account $service from the system, then restart the deploy-cron script."
    }
}else{
    Write-Host "Create $service account."
    #Create a user account to run the task
    net user $service $randompassword /ADD
    $randompassword | Out-File $OnDemandsecure
    Set-LocalUser $service -PasswordNeverExpires $True
    Add-LocalGroupMember -group (Get-LocalGroup $groupmembership) -Member $service
    #Create a temporary script to run as Scriptuser
@'
param($b64param)
#Decode the base 64 string
$params=[System.Text.Encoding]::Unicode.GetString([System.Convert]::FromBase64String($b64param))
#convert the json into object to be used in the script
$json = $params | convertfrom-json

$action = New-ScheduledTaskAction -Execute "$($json.SCOnDemandTask)" -Argument $($json.SCOnDemandTaskArgs)

$class = get-cimclass MSFT_TaskEventTrigger root/Microsoft/Windows/TaskScheduler
$trigger = $class | New-CimInstance -ClientOnly
$trigger.Enabled = $true
$trigger.Subscription = '<QueryList><Query Id="0" Path="Application"><Select Path="Application">*[System[Provider[@Name=''ADR''] and EventID=100]]</Select></Query></QueryList>'

write-host "Creating new Task: $($json.OndemandTaskname)"
#Create a scheduled task owned by the service account
Register-ScheduledTask -TaskName "$($json.OndemandTaskname)" -Action $action -Trigger $trigger -User $($json.service) -Password $($json.randompassword)
'@ | Out-File $scriptdest\tempscript.ps1

    #Create a json string with all the parameters
$paramjsonvar=@"
{
    "SCOnDemandTask" : "$SCOnDemandTask",
    "SCOnDemandTaskArgs" : "$($SCOnDemandTaskArgs.replace('\','\\').replace('"','\"'))",
    "randompassword" : "$($randompassword.replace('\','\\').replace('"','\"'))",
    "OndemandTaskname" : "$OndemandTaskname",
    "service" : "$service"
}
"@
    #Encode the string in base 64 to be passed as a param.
    $b64param = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($paramjsonvar))

    #Create a credential to be used in the start-process
    [securestring]$secStringPassword = ConvertTo-SecureString $randompassword -AsPlainText -Force
    [pscredential]$scriptusercredential = New-Object System.Management.Automation.PSCredential ($service, $secStringPassword)
    #Start a powershell process as the service account. and run the temporary script with the param
    write-host "Create the service scheduledtask."
    Start-Process -FilePath powershell.exe -Credential $scriptusercredential -ArgumentList "-executionpolicy bypass -File $scriptdest\tempscript.ps1 -b64param $b64param" -wait -nonewwindow

    #Remove the temp script
    Remove-Item $scriptdest\tempscript.ps1
}
#endregion

#region permissions
write-host "Check $service permissions."
#Add account to performance log group
if((Get-LocalGroupMember $groupmembership) -and (Get-LocalGroupMember $groupmembership).Name.contains($service)){
    write-host "Groupmembership OK."
}else{
    write-host "[Warning] $service permission missing."
    write-host "Auto remediation: Add-LocalGroupMember -group (Get-LocalGroup $groupmembership) -Member $service"
    Add-LocalGroupMember -group (Get-LocalGroup $groupmembership) -Member $service
}

#Give the account permission on apcm-maintenance folder.
#Old way: icacls $scriptdest /grant "$service:(OI)(CI)F" /T
$ACL = Get-acl -Path $scriptdest 
$permission = New-Object -TypeName System.Security.AccessControl.FileSystemAccessRule -ArgumentList $service, 'FullControl', 'ContainerInherit, ObjectInherit', 'InheritOnly', 'Allow'
$ACL.SetAccessRule($permission)
Set-Acl -Path $ACL.path -AclObject $ACL

#Export the service account direct groupmemberships.
$groupmembership=Get-LocalGroup | Where-Object { (Get-LocalUser $service).SID -in (Get-LocalGroupMember -Group $_ -ErrorAction silentlycontinue | Select-Object -ExpandProperty "SID") } | Select-Object -ExpandProperty "Name"
$principaltotest=$groupmembership+$service
#Verify the account and his groups can read the log folder
$logfiles=Get-childItem $logdir
$domainname=$(Get-WmiObject Win32_NTDomain | where {$_.DomainName -ne $null}).DomainName
foreach($logfile in $logfiles){
    $authorizedprincipal = ($(Get-Acl $logfile.fullname).access | Where-Object {$_.FileSystemRights -in ("FullControl", "ReadAndExecute, Synchronize", "Modify, Synchronize")} | Select-Object -ExpandProperty IdentityReference).value
    $AuthorizedUsersAndGroups = $authorizedprincipal -split '\\' | where-object {$_ -notin ($domainname, $($env:COMPUTERNAME), 'BUILTIN', 'NT AUTHORITY')}
    if ($null -eq $(Compare-Object $AuthorizedUsersAndGroups $principaltotest -IncludeEqual | Where-Object SideIndicator -eq '==')) {
        write-host "[Warning] $service account doesn't have read permission on file $logfile"
    }
}
#endregion

#region files installation
write-host "Copying config, and scripts."
copy-item -path "$Maintenanceconfg" -destination "$Maintenanceconfgd"
copy-item -path "$nginxconfg" -destination "$nginxconfgd"
copy-item -path "$LogrotateS" -destination "$LogrotateSd"
copy-item -path "$LogsS" -destination "$LogsSd"
copy-item -path "$OnDemandtaskS" -destination "$OnDemandtaskD"
 
#Writing the password to the futur encrypted file.
if('' -ne $maintenancedata.password){
    Write-Output $($maintenancedata.password) | Out-File $Datadirsecure -Encoding utf8
    #Replacing the password with the path to the futur encrypted file.
    (get-content $Maintenanceconfgd).replace($($maintenancedata.password),$Datadirsecuretarget) | set-content $Maintenanceconfgd
}


#Define schtasks:
write-host "Define Scheduled task name and actions."

$csvexportpath="$scriptdest\data\scheduledtasks.csv"
Write-Output "TaskName;TaskAction;TaskArguments" | Out-File $csvexportpath -Encoding utf8
Write-Output "apcm-maintenance-exportnginxLogs;powershell.exe;-noprofile -executionpolicy bypass -file ""$LogsSd""" | Out-File $csvexportpath -Append -Encoding utf8

#Creating Scheduled task for log rotation
try{
    $apcmScheduledTasks= Get-ScheduledTask -TaskName "apcm-maintenance-rotatenginxLogs" -ErrorAction stop
    if($apcmScheduledTasks.TaskName.contains("apcm-maintenance-rotatenginxLogs")){
        Unregister-ScheduledTask -TaskName "apcm-maintenance-rotatenginxLogs" -confirm:$false
    }
}catch{
    #nothing to do
}
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-noprofile -executionpolicy bypass -file ""$LogrotateSd"""
$trigger = New-ScheduledTaskTrigger -Daily -DaysInterval 1 -At 00:00
write-host "Creating new Task: apcm-maintenance-rotatenginxLogs"
Register-ScheduledTask -TaskName "apcm-maintenance-rotatenginxLogs" -Action $action -Trigger $trigger -User "System"

#Start the ondemand task to deploy
write-host "Starting the ondemand task."
New-EventLog -LogName "Application" -Source "ADR" -ErrorAction silentlycontinue
Write-EventLog -LogName "Application" -Source "ADR" -EventID 100 -EntryType Information -Message "APCM-Maintenance completed."

#endregion
write-host "Scheduled tasks deployment completed."
pause