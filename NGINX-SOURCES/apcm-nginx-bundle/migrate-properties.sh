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

#
# @Author: Bruno Saverino & ChatGPT
# Version: 4.0.11
#
# To be ran from the root of apcm-payara-bundle (like other scripts).
# Usage: ./migrate-properties.sh {config-name}
#   with {config-name} = name of directory under /profiles containing the config.properties to migrate to the latest version.
#
# Properties already existing in the migrating file {config-name}/config.properties will be injected in the new template.
#   (let /profiles/template unchanged please)
#
# Typical usage:
#   1. Copy your existing config.properties (from previous bundle) to i.e. profiles/prev
#   2. Execute this script:     $ ./migrate-properties.sh prev
#   3. Pass to next step:       $ ./prepare-config.sh latest
#
# The script generates:
#	- a diff file (updates.txt) in the directory /profiles.
#	- a migrated profiles/latest config.properties file
#
# Note: the script may be slow on Windows due to bash emulation. It is lightning-fast on Linux.
#

# Get input files
template_file=profiles/template/config.properties

original_file=profiles/$1/config.properties
update_file=profiles/latest/intermediate.properties
output_file=profiles/latest/config.properties
outlog_file=profiles/updates.txt

if [[ -z $1 ]]; then
    echo "Name the profile to migrate with arg.1"
    exit 1
fi

if [[ $1 == "latest" ]]; then
  echo "you can't call this script on latest please rename your profile"
  exit 1
fi

echo ""
echo "This script will update the referenced properties to the latest version and place it under /profiles/latest"
echo "A diff file will be generated as profiles/updates.txt"
echo ""

# Prepare out:
mkdir profiles/latest >/dev/null 2>&1
rm $output_file >/dev/null 2>&1
rm $outlog_file >/dev/null 2>&1

#rename old parameters
cp $original_file $update_file
sed -i 's|^front.host|adr.front.host|g' $update_file
sed -i 's|^server.host|adr.server.host|g' $update_file


#complete parameters
total_lines=$(wc -l < "$template_file")
line_count=0

# Loop through the lines of the template file
while read -r line || [ -n "$line" ]; do

  # Ignore comments and empty lines
  if [[ $line == \#* ]] || [[ -z ${line// } ]]; then
        echo "$line" >> $output_file
        ((line_count++))
    continue
  fi

  # Extract the key and value from the template file
  #key=$(echo $line | cut -d= -f1)
  #value=$(echo $line | cut -d= -f2-)

  IFS='=' read -r key value <<< "$line"

  # clean all whitespaces from value
  value="$(echo "${value}" | tr -d '[:space:]' | tr -d '\r')"

  # Check if the key exists in the update file
  if [[ ! -z $key ]] && (( ${#key} > 2 )); then
	  # Check if the key exists in the update file
	  update_value=$(grep "^$key=" $update_file | cut -d= -f2-)
	  if [[ ! -z $update_value ]]; then
			update_value="$(echo "${update_value}" | tr -d '[:space:]' | tr -d '\r')"
			  if [[ $update_value != "$value" ]]; then
					echo "$key: [$value] -> [$update_value]" >> $outlog_file
			  fi
			value="$update_value"
		else 
		  if [[ ! -z $value ]]; then
			  # Log new additions as well (without outputting null keys)
			  echo "$key: [$value] -> NEW" >> $outlog_file
			else
			  echo "$key: [$value] -> []" >> $outlog_file
		  fi
	  fi

	  # Write the property to the output file
	  echo "$key=$value" >> $output_file
  fi

  # update progress
  ((line_count++))
  if [ "$(($line_count % 5))" -eq 0 ]; then
    echo "Processed $line_count lines out of $total_lines"
  fi

done < $template_file
rm $update_file

#we clean up all spaces
sed -i 's|deny\\all\\|deny\\ all\\|g' $output_file

echo "---------------------------------------------------------------------"
cat $outlog_file
echo "---------------------------------------------------------------------"
echo "END."
exit 0
