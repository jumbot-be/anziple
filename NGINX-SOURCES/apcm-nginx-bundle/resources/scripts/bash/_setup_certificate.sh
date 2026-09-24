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

#
# Scripts to install nginx certificates
#
# Written by De Jaegere Arnaud
#
if [ "$OSTYPE" == "linux-gnu" ]; then
    nginxhome='@nginx.home.directory@'
elif [ "$OSTYPE" == "msys" ]; then
    nginxhome=$(cygpath '@nginx.home.directory@')
fi

selfsigned () {
    echo "Generating selfsigned certificate";
    certificatefolder=$nginxhome/certs
    mkdir -p $certificatefolder
    #allow some invalid ips but if your server is named 299.299.299.299 you don't deserve a valid certificate
    if [[ "@ext.host.fqdn@" =~ ^([1-2]?[0-9]?[0-9]?)(\.[1-2]?[0-9]?[0-9]?){1,3}$ ]]; then
      echo "using IP based selfsigned"
      openssl req -x509 -newkey rsa:2048 -nodes -sha256 -keyout $certificatefolder/apcm-cert.key -out $certificatefolder/apcm-cert.crt -days 3600 -config generated/config/nginx/certs/default-cert-ip.cnf
    else
      echo "using Hostname based selfsigned"
      openssl req -x509 -newkey rsa:2048 -nodes -sha256 -keyout $certificatefolder/apcm-cert.key -out $certificatefolder/apcm-cert.crt -days 3600 -config generated/config/nginx/certs/default-cert-dns.cnf
    fi
}

deploycertificate () {
    echo "Deploying certificate and key file. Please provide file path that are reachable."
    certificatefolder=$nginxhome/certs
    mkdir -p $certificatefolder
    unset crtpath
    while [[ ! -f $crtpath  || ! ${crtpath} =~ ^.*\.crt$ ]] 
    do
        echo "Please enter a valid certificate (.crt) path :"
        read -r crtpath
        if [ "$OSTYPE" == "linux-gnu" ]; then 
            crtpath="$crtpath"
        elif [ "$OSTYPE" == "msys" ]; then
            crtpath=$(cygpath "$crtpath")
        fi
    done
    cp $crtpath $certificatefolder/apcm-cert.crt
    unset keypath
    while [[ ! -f $keypath  || ! ${keypath} =~ ^.*\.key$ ]] 
    do
        echo "Please enter a valid keyfile (.key) path :"
        read -r keypath
        if [ "$OSTYPE" == "linux-gnu" ]; then 
            keypath="$keypath"
        elif [ "$OSTYPE" == "msys" ]; then
            keypath=$(cygpath "$keypath")
        fi
    done
    cp $keypath $certificatefolder/apcm-cert.key

}

#Main
# https://ssl-config.mozilla.org/ffdhe2048.txt  https://datatracker.ietf.org/doc/html/rfc7919#appendix-A.1
cp generated/config/nginx/certs/ffdhe2048.txt $nginxhome/ffdhe2048.txt

echo "Do you want help deploying a certificate ?"
select yn in "Yes, deploy a Selfsigned certificate" "Yes, I will provide path to my own certificate" "No, Keep current certificate. (If no current certificate, you will have to install it yourself)"; 
do
    case $yn in
        "Yes, deploy a Selfsigned certificate" ) selfsigned; break;;
        "Yes, I will provide path to my own certificate" ) deploycertificate; break;;
        "No, Keep current certificate. (If no current certificate, you will have to install it yourself)" ) echo "skipping certificate"; break;;
    esac
done