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

# Shell script for installing nginx
# Author: Arnaud De Jaegere (2024)
# Version: 4.0.11

#Version var
NGINX_linux_version='1.30.2+'
NGINX_win_version='nginx-1.30.2'
NGINX_win_file="resources/nginx/$NGINX_win_version.zip"
generatedproxysocks=generated/config/nginx/tcpconf.d/proxysocks.conf
destproxysocksfolder=tcpconf.d

##Linux
if [ "$OSTYPE" == "linux-gnu" ]; then
    #linux variable
    rootpath=/etc/nginx/

    #Test nginx is installed
    nginx -v > /dev/null 2>&1
    if [ ! $? -eq 0 ]; then
        ##Installing nginx.
        echo "nginx is not installed. proceeding with installation"
        #Get the Linux flavor.
        if [ "`cat /etc/*release | grep Ubuntu | wc -l`" -ge "1"  ]; then
            echo "We are running on Ubuntu OS."
            #Check apt configuration
            if [ ! -f /etc/apt/sources.list.d/nginx.list ]; then
                #Configure the NGINX repo for Ubuntu
                echo "The nginx repository is not set. Configuring nginx repo"

                #Skipped for now. All those prerequisit are already installed
                #sudo apt install curl gnupg2 ca-certificates lsb-release ubuntu-keyring

                #Get nginx signing keys
                curl --insecure https://nginx.org/keys/nginx_signing.key | gpg --dearmor | tee /usr/share/keyrings/nginx-archive-keyring.gpg >/dev/null

                #Verify the fingerprints
                fingerprints=$(gpg --dry-run --quiet --no-keyring --import --import-options import-show /usr/share/keyrings/nginx-archive-keyring.gpg | sed -nr 's/^([ ]+)([0-9A-Z]{40}$)/\2/p')
                expectedfingerprints=$'8540A6F18833A80E9C1653A42FD21310B49F6B46\n573BFD6B3D8FBC641079A6ABABF5BD827BD9BF62\n9E9BE90EACBCDE69FE9B204CBCDCD8A38D88A2B3'
                #The output should contain the full fingerprints:
                #8540 A6F1 8833 A80E 9C16 53A4 2FD2 1310 B49F 6B46
                #573B FD6B 3D8F BC64 1079 A6AB ABF5 BD82 7BD9 BF62
                #9E9B E90E ACBC DE69 FE9B 204C BCDC D8A3 8D88 A2B3
                #https://docs.nginx.com/nginx/admin-guide/installing-nginx/installing-nginx-open-source/

                if [[ "$fingerprints | xargs" == "$expectedfingerprints | xargs" ]]; then
                    #repo fingerprint ok
                    #Add the package URL
                    echo "deb [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] http://nginx.org/packages/ubuntu `lsb_release -cs` nginx" | tee /etc/apt/sources.list.d/nginx.list
                    #Set nginx repo as prefered
                    echo -e "Package: *\nPin: origin nginx.org\nPin: release o=nginx\nPin-Priority: 900\n" | tee /etc/apt/preferences.d/99nginx
                else
                    echo "Wrong NGINX repository fingerprint. Please add the repository manually: https://docs.nginx.com/nginx/admin-guide/installing-nginx/installing-nginx-open-source/"
                    exit 1
                fi
            fi
            echo "Repo configured, installing package"
            #Install the package
            apt update
            apt satisfy "nginx (>=1.30.2)" -y
        else
            echo "Unsupported distribution. We dont install nginx autmatically on this distribution."
            echo "You have to configue the nginx repo and install it manually."
            echo "Ensure you install version $NGINX_linux_version"
            echo 'sudo apt apt satisfy "nginx (>=1.30.2)" -y'
            echo "https://docs.nginx.com/nginx/admin-guide/installing-nginx/installing-nginx-open-source/"
            exit 1
        fi
    else
        nginxversion=$(nginx -v 2>&1)
        if [[ "$nginxversion" =~ .*1\.(28|30)\.* ]]; then
            echo "nginx is up to date."
        else
            echo "[WARNING] The installed nginx version is not supported. Review the nginx version installed before continuing."
            echo "Updating the version could possible cause outage if current configuration is not compatible with new version"
            echo "review nginx manual update documentation on the Wiki."
            echo "This script will stop. Rerun the script once you have installed the target nginx version: $NGINX_linux_version "
            echo "Or removed the existing one (if installed used apt : sudo apt remove nginx )"
            exit 0
        fi
    fi
elif [ "$OSTYPE" == "msys" ]; then
    ##Windows
    ./generated/service/uninstall.sh

    #Windows folder
    rootpath=nginx/

    #Deploy nginx on Windows
    rm -rf nginx
    unzip $NGINX_win_file
    mv $NGINX_win_version nginx

fi

##Common actions
mkdir -p $rootpath$destproxysocksfolder

cp $generatedproxysocks $rootpath$destproxysocksfolder/

chmod -R 775 ./generated
./generated/scripts/bash/_copy_config.sh
./generated/scripts/bash/_copy_static.sh

#Certificate setup
./generated/scripts/bash/_setup_certificate.sh

if [ "$OSTYPE" == "linux-gnu" ]; then 
    # Verify config linux
    nginx -t && nginx -s reload || echo -e "\e[31mAn error occurred when testing the configuration, you'll need to manually restart the service\e[0m"

elif [ "$OSTYPE" == "msys" ]; then
    # Verify config Windows
    cd nginx
    ./nginx.exe -t
    cd ..
fi

#Windows service installation
if [ "$OSTYPE" == "msys" ]; then 
    ./generated/service/install.sh
fi

echo
echo If you get an ssl_stappling directive issue remove them from the .conf file.
echo If you get an reuseport issue remove reuseport from tcpconf.d/proxysocks.conf.
echo If you get a fopen or No such file error please check your certificates.
echo If you get a fopen or No such file error please check your certificates.

exit 0
