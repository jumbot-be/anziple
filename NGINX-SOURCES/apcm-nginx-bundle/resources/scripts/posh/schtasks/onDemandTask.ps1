# Version: 4.0.11
Set-Location -Path $($PSScriptRoot)
Start-Transcript UpdateTaskScheduler.txt
Write-Host "This script is running as $($Env:UserName)" 

#region Encrypt plaintext password
$plaintextfiles = get-childitem 'data\protected\' -File | where-object {$_.name -notlike "SecureString*" }
foreach($plaintextfile in $plaintextfiles){
    #Get the plaintext password
    $plain=Get-Content $plaintextfile.FullName
    write-host "Content from $($plaintextfile.FullName): $plain"
    #Encrypt the password
    $securePassword = ConvertTo-SecureString -String $plain -AsPlainText -Force
    #Set the destination path for the encrypted password
    $securefilepath=$($plaintextfile.fullName).replace($($plaintextfile.Name),"SecureString$($plaintextfile.Name)")
    #Save the password to file
    $securePassword | ConvertFrom-SecureString | Out-File -FilePath $securefilepath -force
    #Remove the plaintext password file.
    $plaintextfile | Remove-Item
}
#endregion

#region Change current password
$passwordupdate=$false
# Get last password set (minimum password age on windows is 1 day)
$pwdlastset = $(Get-LocalUser $($Env:UserName)).PasswordLastSet
if ($pwdlastset -lt $(get-date).AddDays(-1)){
    #Read from securestring:
    $OldpasswordSS= get-content "data\protected\SecureString$($Env:UserName).txt"| convertto-SecureString
    #Convert to plaintext
    $Oldpassword=$([System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($OldpasswordSS)))

    #Random password generator: get 12 random char + 2 random number + 2 random special char. Scramble and make a string:
    $NewPassword = $null
    ((65..90) + (97..122) | Get-Random -Count 12)+((48..57) | Get-Random -Count 2)+((37..47) + 33 + 35 + (58..63) | Get-Random -Count 2) | Sort-Object {Get-Random} | %{ $NewPassword += [char]$_ }

    write-host "[debug] Old password: $OldPassword"
    write-host "[debug] New password: $NewPassword"

    #Change the password
    ([ADSI]"WinNT://./$($Env:UserName)").ChangePassword("$Oldpassword", "$NewPassword")
    $passwordupdate=$true
    
    #rotation securestring file
    $OldPasswordfiles = get-childitem 'data\protected\' -File | where-object {$_.name -like "SecureString$($Env:UserName).txt*" }
    #write-host "[debug] Got $($oldpasswordfiles.count)"
    
    for ($i=$($oldpasswordfiles.count); $i -gt 0; $i--){
        if($i -eq 1){
            $oldname="SecureString$($Env:UserName).txt"
            $newname="SecureString$($Env:UserName).txt.1"
        
        }else{
            $j=$i-1
            $oldname="SecureString$($Env:UserName).txt.$j"
            $newname="SecureString$($Env:UserName).txt.$i"
        }
        write-host "renaming data\protected\$oldname to $newname"
        Rename-Item -Path "data\protected\$oldname" -NewName $newname
    }

    $securePassword = ConvertTo-SecureString -String $NewPassword -AsPlainText -Force
    $securePassword | ConvertFrom-SecureString | Out-File -FilePath "data\protected\SecureString$($Env:UserName).txt" -force

}else{
    write-host "[Information] Last password change less than 24 hours ago."
    $passwordupdate=$false
}
#endregion

#region Refresh the Scheduled task
#Read existing apcm-task
$apcmScheduledTasks= Get-ScheduledTask -TaskName apcm-*
$TaskpasswordSS= get-content "data\protected\SecureString$($Env:UserName).txt"| convertto-SecureString
#Convert to plaintext
$Taskpassword=$([System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($TaskpasswordSS)))
if(test-path .\data\scheduledtasks.csv){
    #Read CSV file with task to create.
    $NewScheduledtasks= import-csv .\data\scheduledtasks.csv -Delimiter ';'

    foreach($NewScheduledtask in $NewScheduledtasks){
        if($apcmScheduledTasks.TaskName.contains($NewScheduledtask.TaskName)){
            write-host "Task $($NewScheduledtask.TaskName) already exist. Unregistering..."
            Unregister-ScheduledTask -TaskName "$($NewScheduledtask.TaskName)" -confirm:$false
        }
        $action = New-ScheduledTaskAction -Execute "$($NewScheduledtask.TaskAction)" -Argument "$($NewScheduledtask.TaskArguments)"
        $trigger = New-ScheduledTaskTrigger -Daily -DaysInterval 1 -At 00:10
        write-host "Creating new Task: $($NewScheduledtask.TaskName)"
        Register-ScheduledTask -TaskName "$($NewScheduledtask.TaskName)" -Action $action -Trigger $trigger -User $($Env:UserName) -Password $Taskpassword
    }
    
    remove-item .\data\scheduledtasks.csv -force
}else{
    write-host "No scheduledtasks csv file."
}

if($passwordupdate){
    #Update password
    foreach ($apcmScheduledTask in $apcmScheduledTasks){
        if($apcmScheduledTask.TaskName -notin $NewScheduledtasks.TaskName){
            write-host "Task $($apcmScheduledTask.TaskName) need password update"
            Set-ScheduledTask -TaskName "$($apcmScheduledTask.TaskName)" -User $($Env:UserName) -Password $Taskpassword
        }
    }

}
#endregion
Stop-Transcript