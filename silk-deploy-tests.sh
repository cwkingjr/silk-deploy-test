#!/bin/bash

# Author: Chuck King
# Date: 2013-07-30
# Reason: run some simple checks after a sensor deployment
#   to ensure silk data is pushed to repository in uncorrupted
#   form. Of course these can't test for every case, but they 
#   include enough tests to detect massively corrupt files.

### License ###
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
### License ###

# Configuration
# True for production configuration
# False for testing configuration (dev and testing conducted on FloCon 2012 training VM/data)
production="False"

# Params required:
#  $1 sensor name (e.g., S1)
#  $2 silk date:time (e.g., 2013/03/15:02)
#  $3 silk class (e.g., isr)

echo "[+] = Warning, Error, or Instructions" 
echo "[-] = Info" 

if [ $# -ne 3 ]; then
    echo "[+] ERROR: Missing mandatory parameters: sensor-name silk-date-time silk-class" 
    echo "[-] Example: $0 S1 2013/03/25:02 isr" 
    exit 1
fi

# warn about not including time
mytime=$(echo "$2" | cut -d: -f 2)
mylength=$(expr length "$mytime")
if [ $mylength -ne 2 ]; then
    echo "[+] ERROR: silk-date-time requires two digit time (e.g., 2013/03/25:03)" 
    exit 1
fi

#
# we'll dump the results to a folder, so let's make that now
#

if [ -z $HOME ]; then
    echo "[+] ERROR: $HOME not found"
    exit 1
fi

# reformat 2013/03/25:02 to 2013-03-25-02 for use in file name
file_datetime=$(echo "$2" | sed 's/\//-/g' | sed 's/:/-/g')
echo "[-] Using $file_datetime as YYYY-MM-DD-HH portion of working folder name (from input parameter)" 

epoch=$(date +%s)
echo "[-] Using epoch $epoch as portion of working folder name to prevent multiple-run collisions" 

folder=$HOME/deploy-tests-$1-$file_datetime-at-$epoch

echo "[-] Creating folder to store test results at: $folder"
mkdir $folder

if [ ! -d "$folder" ]; then
    echo "[+] ERROR: Failed to create the test results folder" 
    exit
fi

echo "[-] Assuming well formed sensor name (e.g., S1) of: $1"
sensor_name=$1

echo "[-] Assuming well formed silk-formatted date:hour (e.g., 2013/03/25:02) of: $2"
silk_date=$2

echo "[-] Assuming well formed silk-class (e.g., isr) of: $3"
silk_class=$3

echo "[-] Checking repository files for malformed sIP addresses"
echo "[-] This check should produce no results if the silk files are well formatted"
echo "[-] Only pulling first 20 via pipe to head so CLI terminated pipe chatter is normal."

rwfilter --start=$silk_date --sensors=$sensor_name --class=$silk_class --type=all \
  --proto=1- --pass=stdout | rwcut --fields=1 --no-final-delimiter --no-titles --no-columns | \
  grep -E -v '([[:digit:]]{1,3}\.){3}[[:digit:]]{1,3}' | \
  head -20 > $folder/malformed-sip-addresses.txt

filesize=$(stat --printf="%s" $folder/malformed-sip-addresses.txt)
if [ $filesize -ne 0 ]; then
    echo "[+] WARN: Found malformed sIP entries. Check malformed-sip-addresses.txt" 
else
    echo "[-] Found no malformed sIP entries." 
fi

# 
# Check for protocol distribution over the designated silk date 
#

echo "[-] Checking for protocol distribution over the designated silk date"
echo "[+] Check protocol-distribution.txt to ensure at least protocols's 1, 6, and 17 show up"

rwfilter --start-date=$silk_date --sensors=$sensor_name --class=$silk_class --type=all \
  --proto=1- --pass=stdout | rwtotal --proto --skip-zeroes > $folder/protocol-distribution.txt

#
# Check for repo file creation
#

echo "[-] Checking for repository file existence/creation"

# grab the date without an hour
date_only=$(echo "$silk_date" | cut -d: -f 1)

if [ -z $SILK_DATA_ROOTDIR ]; then
    echo "[+] ERROR: SILK_DATA_ROOTDIR not found"
    exit
fi

# we need to drop the hour from the silk date for this call
my_day=$(echo "$2" | cut -d: -f 1)

if [ $production == 'True' ]; then
    ls -l $SILK_DATA_ROOTDIR/$silk_class/*/$my_day/*$sensor_name* > $folder/silk-data-files.txt 
else
    ls -l $SILK_DATA_ROOTDIR/*/*/$my_day/*$sensor_name* > $folder/silk-data-files.txt 
fi

echo "[+] Check silk-data-files.txt to verify that all class type files are getting generated"
echo "[-] The isr class should at least generate in, inweb, out, and outweb types"

#
# Check for record counts for every minute across an hour per flow type.
# This will provide a listing, by minute, of the records, bytes, and packets.
#

echo "[-] Checking for record counts by each class type (e.g., in, inweb, out, outweb)"
echo "[-] This checks for activity for every minute to ensure we aren't seeing drops"
echo "[-] Of course, this assumes you are assessing a link that processes traffic every minute"

for mytype in in out inweb outweb
do
    echo "[-] Creating type $mytype record counts file"
    rwfilter --start-date=$silk_date --sensors=$sensor_name --class=$silk_class --type=$mytype \
      --proto=1- --pass=stdout | rwcount --bin-size=60 > $folder/record-counts-$mytype.txt
done

echo "[+] Check each record-counts-TYPE.txt file to verify traffic is generated for each minute"

#
# Check for record durations over 30 minutes
#

echo "[-] Checking for excessively long record durations"
echo "[-] Durations should not exceed 1800 seconds (30 minutes)"

rwfilter --start-date=$silk_date --sensors=$sensor_name --class=$silk_class --type=all \
  --proto=1- --pass=stdout | rwcut --fields=10 --no-final-delimiter --legacy-timestamps | \
  perl -e 'while (<>) { print if $_ > 1800 }' | sort | \
  uniq > $folder/improperly-long-record-durations.txt

filesize=$(stat --printf="%s" $folder/improperly-long-record-durations.txt)
if [ $filesize -ne 0 ]; then
    echo "[+] WARN: Found record durations exceeding 1800 secs. Check improperly-long-record-durations.txt" 
else
    echo "[-] Found no record durations exceeding 1800 secs." 
fi

echo "[-] The End."
