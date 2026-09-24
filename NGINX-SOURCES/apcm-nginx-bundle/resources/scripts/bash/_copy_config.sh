#!/bin/bash
#
# Copyright (c) 2024 Ampacimon S.A.,
# Rue Alfred Deponthière 40, B4431 Loncin, Belgium
# All rights reserved.
#
# This software is the confidential and proprietary information
# of Ampacimon S.A. ("Confidential Information").
# You SHALL NOT disclose such Confidential Information and SHALL ONLY use
# or redistribute it in source or binary forms in accordance with the
# terms of the license agreement you entered into with Ampacimon S.A.
#

if [ "$OSTYPE" == "linux-gnu" ]; then
    dest='/etc/nginx'
    nginxconfdest='/etc/nginx'
    echo "Do you want to overwrite the nginx.conf? (default: No, unless specified by the update guide)"
    select ynnginx in "Yes" "No"
    do
        echo "Selected answer: $ynnginx"
        break;
    done
    echo "Do you want to overwrite the proxysocks.conf? (default: No, unless specified by the update guide)"
    select ynproxysocks in "Yes" "No"
    do
        echo "Selected answer: $ynproxysocks"
        break;
    done
    echo "Do you want to overwrite the @nginx.config.name@.conf and shared ? (default: Yes, unless specified by the update guide)"
    select ynampacimon in "Yes" "No"
    do
        echo "Selected answer: $ynampacimon"
        break;
    done
    echo "Do you want to overwrite the @nginx.config.name@-config configuration folder? (default: No, unless specified by the update guide)"
    select ynapcm in "Yes" "No"
    do
        echo "Selected answer: $ynapcm"
        break;
    done
elif [ "$OSTYPE" == "msys" ]; then
    dest='nginx'
    nginxconfdest='nginx/conf'
    ynnginx="Yes"
    ynproxysocks="Yes"
    ynampacimon="Yes"
    ynapcm="Yes"
fi

mkdir -p $dest/@nginx.config.name@-shared/
mkdir -p $dest/@nginx.config.name@-config/
mkdir -p $dest/sites-enabled

case $ynnginx in
    "Yes" ) cp generated/config/nginx/conf/nginx.conf $nginxconfdest/nginx.conf;;
    "No" ) echo 'skip nginx.conf';;
esac
case $ynproxysocks in
    "Yes" ) cp generated/config/nginx/tcpconf.d/proxysocks.conf $dest/tcpconf.d/proxysocks.conf;;
    "No" ) echo 'skip proxysocks.conf';;
esac
case $ynampacimon in
    "Yes" ) cp generated/config/nginx/sites-enabled/ampacimon.conf $dest/sites-enabled/@nginx.config.name@.conf;
            cp generated/config/nginx/apcm-shared/* $dest/@nginx.config.name@-shared/;;
    "No" ) echo 'skip @nginx.config.name@.conf';;
esac
case $ynapcm in
    "Yes" ) cp generated/config/nginx/apcm-config/* $dest/@nginx.config.name@-config/;;
    "No" ) echo 'skip @nginx.config.name@-config';;
esac