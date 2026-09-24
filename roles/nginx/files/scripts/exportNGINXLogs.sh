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

#parameters
# read the INI file
source <(grep '=' ./data/maintenance.ini | tr -d '"\r') #Should we have new ini file or could be reuse ADR export ini file for datadir?
source <(grep '=' ./data/exportNGINX.ini | tr -d '"\r')

#Define all paths
tempout=./temp/nginxLogs
hostname="$(hostname)"
outfolder="$destination/nginxLogs/$hostname"
mkdir -p "$outfolder"
mkdir -p "$tempout"

#function definition
copy_log(){
if [ ! -f $2 ]; then
    #Test if the ampacimon log exist
    if [ -f $1 ] && [ -r $1 ]; then
        #export the log
        if [[ $1 == *".gz" ]]; then
            cp $1 $2
        else
            gzip -c $1 > $2
        fi
    fi
fi
}
export_log() {
    #For the last 16 days.
    for ((i=1; i<16; i++)); do
        unset logpath
        unset logpaths
        unset logserver
        unset destlogpath

        fromdate=`date -d "-$i days" +"%Y-%m-%d"`
        todate=`date -d "-$((i-1)) days" +"%Y-%m-%d"`
        
        logpaths=$(find /var/log/nginx/*.log* -newermt "$fromdate 00:00:00" ! -newermt "$todate 00:00:00")
        logpathscount=$(find /var/log/nginx/*.log* -newermt "$fromdate 00:00:00" ! -newermt "$todate 00:00:00" | wc -l)
        
        if [ $logpathscount -eq 1 ]; then
            #one log for that day
            #rename the log
            # From logname.log.1    /  logname.log.2.gz
            # To   logname-nginx-date.log.gz
            filename=$(basename "$logpaths")
            logname=${filename%%.log*}
            destlogpath=$tempout/$logname-$1-$fromdate.log.gz
            copy_log $logpaths $destlogpath
        elif [ $logpathscount -gt 1 ]; then
            #multiple log for that day
            for logpath in ${logpaths[@]}; do
                filename=$(basename "$logpath")
                logname=${filename%%.log*}
                destlogpath=$tempout/$logname-$1-$fromdate.log.gz
                copy_log $logpath $destlogpath
            done
        fi
    done
}
#Exporting 15 days of logs into temp location
export_log nginx

#For each log file in temp location.
for filepath in $(find "$tempout" -maxdepth 1 -type f)
do
    #prepare destination filepath
    filename=$(basename "$filepath")
    itemdate=$(echo $filename | grep -Eo '[[:digit:]]{4}-[[:digit:]]{2}-[[:digit:]]{2}')
    outdate=${itemdate: 0:7}
    
    #Create the folder for the month
    destinationfolder="$outfolder/$outdate"
    mkdir -p "$destinationfolder"
    
    fulldestinationpath="$destinationfolder/$filename"
    if [ ! -f $fulldestinationpath ]; then
        copy_log $filepath $fulldestinationpath 
    fi
    #Clean up the item if older than 15 days.
    itemdatesec="$(date -d $itemdate +%s)"
    daysagosec="$(date -d"$(date -d"$(date +"%Y-%m-%d") - 15 days" +"%Y-%m-%d")" +%s)"
    if [ $itemdatesec -lt $daysagosec ]; then
        rm $filepath
    fi
done