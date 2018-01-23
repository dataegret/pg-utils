#!/bin/bash

# Getting full path of script
stuff_dir=`pwd`
if [ `dirname $0` != '.' ]; then
  stuff_dir=$stuff_dir/`dirname $0`
  stuff_dir=`dirname $stuff_dir`
fi
prestuff_dir=`dirname $stuff_dir`
echo Expected stuff directory: $stuff_dir
echo Expected directory for temporary files \(will be deleted\): $prestuff_dir

# Define available programs for update
if command -v git > /dev/null; then
  echo command git is available, will update dataegret stuff directory by the one
  cd $stuff_dir
  git pull -v
  cd `pwd`
elif command -v unzip > /dev/null; then
  echo command unzip is available, will unpack dataegret stuff directory by the one
  stuff_url="https://github.com/dataegret/pg-utils/archive/master.zip"
  echo Will be downloaded next file: $stuff_url
  if command -v wget > /dev/null; then
    echo command wget is available, will update dataegret stuff directory by the one
    wget -cvt 5 -O $prestuff_dir/master.zip $stuff_url
  #elif command -v fetch > /dev/null; then
  #  echo command fetch is available, will update dataegret stuff directory by the one

  elif command -v curl > /dev/null; then
    echo command curl is available, will update dataegret stuff directory by the one
    curl -svS -o $prestuff_dir/master.zip $stuff_url
  else
    echo commands wget, fetch or curl is not available, can not to update dataegret stuff directory
  fi
  echo Sync downloaded data into $stuff_dir 
  unzip -uo master.zip -d $prestuff_dir
  if command -v rsync > /dev/null; then
    rsync -avr $prestuff_dir/pg-utils-master/* $stuff_dir/ 
  elif command -v cp > /dev/null; then
    cp -afvr $prestuff_dir/pg-utils-master/* $stuff_dir/ 
  fi
  echo Removing temporary files: $prestuff_dir/pg-utils-master $prestuff_dir/master.zip
  rm -r $prestuff_dir/pg-utils-master $prestuff_dir/master.zip
else
  echo commands git or unzip are not available, can not to update dataegret stuff directory
  exit 1
fi

exit 0
