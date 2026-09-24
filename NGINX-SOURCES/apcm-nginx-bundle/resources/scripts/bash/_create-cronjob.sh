#!/bin/bash 
#
# Copyright (c) 2026 Ampacimon S.A.,
# Rue Alfred Deponthière 40, B4431 Loncin, Belgium
# All rights reserved.
#
# This software is the confidential and proprietary information
# of Ampacimon S.A. ("Confidential Information").
# You SHALL NOT disclose such Confidential Information and SHALL ONLY use
# or redistribute it in source or binary forms in accordance with the
# terms of the license agreement you entered into with Ampacimon S.A.
#

#Create Cron job to export nginx logs on the Datadir.

echo "Creating crontab."
currentdir=$(pwd)
parrentdir=$(dirname "$(pwd)")

service="Scriptuser"
scriptdest="$parrentdir/apcm-maintenance"
datadest="$scriptdest/data"
bindest="$scriptdest/bin"
mkdir -p $scriptdest
mkdir -p $datadest
mkdir -p $bindest

Maintenanceconfg="generated/conf/apcm-maintenance/maintenance.ini"
Maintenanceconfgd="$datadest/maintenance.ini"
nginxconfg="generated/conf/apcm-maintenance/exportNGINX.ini"
nginxconfgd="$datadest/exportNGINX.ini"
source <(grep '=' $Maintenanceconfg | tr -d '"' | tr -d '\r')

logdir="@nginx.log.directory@"
outfolderLog="$destination/nginxLogs"
mkdir -p "$outfolderLog"
chmod 775 "$outfolderLog"

echo "defining script variables."
LogsS="generated/scripts/bash/cron/exportNGINXLogs.sh"
LogsSd="$scriptdest/exportNGINXLogs.sh"

echo "Create/update the $service account."
# Check if user exists and create if not
if id -u "$service" >/dev/null 2>&1; then
    echo "User $service exists."
else
    echo "User $service does not exist. Creating..."
    useradd -m "$service"
fi
#Add user to the root group to give him read access to payara server logs.
gpasswd --add Scriptuser root
#Add user to the adm group to give him read access to the /var/log/ folders.
gpasswd --add Scriptuser adm


#Has the user read access to log directory?
for logfile in $(find "$logdir" -maxdepth 1 -type f)
do
    sudo -u $service test -r $logfile
    if [ "$?" -gt 0 ]; then
        echo "[WARNING]  $logfile could not be read by $service who is member of root group."
        echo "Auto remediation: chmod -R 750 ${$logdir}"
        chmod -R 750 ${$logdir}
    fi
done

# Copy script and INI file to user's home directory
echo "Copying config, scripts."
cp "$Maintenanceconfg" "$Maintenanceconfgd"
cp "$nginxconfg" "$nginxconfgd"
cp "$LogsS" "$LogsSd"

logdirconfg="logdir=\"${logdir}\""
echo $logdirconfg >> $nginxconfgd

# Set permissions
echo "Set permission and owner on the scripts and config files"
chown "$service":"$service" "$scriptdest"
chown "$service":"$service" "$Maintenanceconfgd"
chown "$service":"$service" "$nginxconfgd"
chown "$service":"$service" "$LogsSd"

chmod 700 "$scriptdest"
chmod 600 "$Maintenanceconfgd"
chmod 600 "$nginxconfgd"
chmod 700 "$LogsSd"

# Add cron job if it doesn't exist
echo "Create the cron job."
cron_entry1="10 0 * * * cd $scriptdest && $LogsSd"
(crontab -l -u "$service" 2>/dev/null | grep -q -F -- "$cron_entry1") || (crontab -l -u "$service" ; echo "$cron_entry1") | crontab -u "$service" -
