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
    staticdest='@static.files.folder@'
elif [ "$OSTYPE" == "msys" ]; then
    staticdest=$(cygpath '@static.files.folder@')
fi

mkdir -p $staticdest
if [ "$OSTYPE" == "linux-gnu" ]; then
  chown -R www-data:www-data $staticdest
fi
cp generated/static/* $staticdest