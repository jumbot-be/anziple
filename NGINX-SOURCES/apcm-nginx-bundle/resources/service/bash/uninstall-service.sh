#!/bin/bash

#Read the /generated/conf/service.conf
parrentdir=$(dirname $(dirname "$(pwd)"))
source $parrentdir/conf/service.conf

systemctl stop $servicename.service 2> /dev/null
systemctl disable $servicename.service 2> /dev/null

rm /lib/systemd/system/$servicename.service 2> /dev/null
rm /etc/systemd/system/$servicename.service 2> /dev/null

systemctl daemon-reload

exit 0