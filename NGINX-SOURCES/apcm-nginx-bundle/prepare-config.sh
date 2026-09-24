#!/bin/bash
# Version: 4.0.11
# Check if one argument is provided
if [ $# -eq 0 ]
  then
    echo "You need to provide one argument with the profile name"
    exit 1
fi

PROFILE=$1
echo "Use profile" ${PROFILE}

echo "Cleaning"
rm -rf generated

# Execute ant build script that performs the resource filtering
./tools/apache-ant-1.10.14/bin/ant -Dprofile=${PROFILE}
