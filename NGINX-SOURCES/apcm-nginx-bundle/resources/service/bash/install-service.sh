#!/bin/bash

#Read the /generated/conf/service.conf
parrentdir=$(dirname $(dirname "$(pwd)"))
source $parrentdir/conf/service.conf

#Deploy the service base on service.conf

echo "Configure systemd"
mkdir /etc/$servicename 2> /dev/null
cp $parrentdir/conf/$servicename.env /etc/$servicename/
cp $parrentdir/conf/$servicename.service /etc/systemd/system/
cp $parrentdir/conf/$servicename.service /lib/systemd/system/
chown -R $servicename: /etc/$servicename/


# Start and enable
echo "Configure service"
systemctl daemon-reload
systemctl enable $servicename.service
systemctl start $servicename.service
systemctl status $servicename

exit 0
