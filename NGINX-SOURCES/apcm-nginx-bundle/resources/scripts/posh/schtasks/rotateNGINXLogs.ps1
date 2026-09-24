#PowerShell script deployed during nginx installation on Windows.
#This script must be scheduled to run with the same service account as the nginx service.
# Version: 4.0.11

#Location definition
$nginxlogdir="@nginx.log.directory@"
$nginxhomedir="@nginx.home.directory@"

$date=(get-date).AddDays(-1) | get-date -Format yyyy-MM-dd

#Get all log to be rotated
$logfiles=Get-ChildItem -Path $nginxlogdir | Where-Object {$_.name -like '*.log'}
foreach($logfile in $logfiles){
    $newlogname=$logfile.BaseName+"-nginx-"+$date+".log"
    copy-Item $logfile.FullName $nginxlogdir\$newlogname
    Compress-Archive -Path "$nginxlogdir\$newlogname" -Destination "$nginxlogdir\$($logfile.BaseName)-nginx-$date.zip"
    Remove-Item "$nginxlogdir\$newlogname"
    Remove-Item $logfile.FullName
}
#When all log have been rotated, run the nginx.exe -s reopen
.$nginxhomedir\nginx.exe -s reopen -p $nginxhomedir