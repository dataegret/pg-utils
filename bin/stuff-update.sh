#!/bin/bash

# Getting full path of script
stuff_dir=`pwd`
if [ `dirname $0` != '.' ]; then
  stuff_dir=$stuff_dir/`dirname $0`
fi
stuff_dir=`dirname $stuff_dir`
prestuff_dir=`dirname $stuff_dir`
echo Expected stuff directory: $stuff_dir
echo Expected directory for temporary files \(will be deleted\): $prestuff_dir

# Define available programs for update
if ([ -z $1 ] || [ "$1" != '--no-git' ]) && command -v git > /dev/null; then
  echo command git is available, will update dataegret stuff directory by the one
  cd $stuff_dir
  git pull
  cd `pwd`
elif command -v tar > /dev/null; then
  echo command tar is available, will unpack dataegret stuff directory by the one
  stuff_url="https://github.com/dataegret/pg-utils/archive/master.tar.gz"
  echo Will be downloaded next file: $stuff_url
  if command -v wget > /dev/null; then
    echo command wget is available, will update dataegret stuff directory by the one
    wget -qct 5 -O $prestuff_dir/master.tar.gz $stuff_url
  #elif command -v fetch > /dev/null; then
  #  echo command fetch is available, will update dataegret stuff directory by the one

  elif command -v curl > /dev/null; then
    echo command curl is available, will update dataegret stuff directory by the one
    curl -sS -o $prestuff_dir/master.tar.gz $stuff_url
  else
    echo commands wget, fetch or curl is not available, can not to update dataegret stuff directory
  fi
  echo Sync downloaded data into $stuff_dir 
  tar -xzf $prestuff_dir/master.tar.gz -C $prestuff_dir
  if [ ! -e $prestuff_dir/old_stuff ]; then
    if command -v rsync > /dev/null; then
      rsync -ar $prestuff_dir/stuff/* $prestuff_dir/old_stuff
    elif command -v cp > /dev/null; then
      cp -afr $prestuff_dir/stuff/* $prestuff_dir/old_stuff
    fi
  elif [ ! -d $prestuff_dir/old_stuff ]; then
    echo "$prestuff_dir/old_stuff" are not directory, please remove it, because there should be a backup of stuff
    exit 1
  elif [ `diff -qarx .git $prestuff_dir/stuff $prestuff_dir/old_stuff | wc -l` != 0 ]; then
    echo Previous backup of stuff and current stuff has some difference
    echo please check it before next updating stuff
    echo you can have o look on difference by command: diff -ar stuff old_stuff
    echo or just remove old_stuff if it does not matter for you
    exit 1
  fi
  if command -v rsync > /dev/null; then
    rsync -ar $prestuff_dir/pg-utils-master/* $stuff_dir/ 
  elif command -v cp > /dev/null; then
    cp -afr $prestuff_dir/pg-utils-master/* $stuff_dir/ 
  fi
  echo Removing temporary files: $prestuff_dir/pg-utils-master $prestuff_dir/master.tar.gz
  rm -r $prestuff_dir/pg-utils-master $prestuff_dir/master.tar.gz
  if [ `diff -qarx .git $prestuff_dir/stuff $prestuff_dir/old_stuff | wc -l` != 0 ]; then
    echo Copy of old stuff are in $prestuff_dir/old_stuff, please check difference beetwean stuff and old_stuff
    diff -qarx .git $prestuff_dir/stuff $prestuff_dir/old_stuff
  fi
else
  echo commands git or tar are not available, can not to update dataegret stuff directory
  exit 1
fi

exit 0
