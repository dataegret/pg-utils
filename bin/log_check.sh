#!/bin/bash
# env variables
export PATH="/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin"
export LANG="en_US.UTF-8"

# colors
red=$(tput setaf 1)
green=$(tput setaf 2)
yellow=$(tput setaf 3)
reset=$(tput sgr0)

logDepthOfDays=6
logNTopMessages=10
logLimitNErrors=0

while getopts "hd:n:l:" opt; do
  case $opt in
    d)
      if [ $OPTARG -ge 0 ]; then
        logDepthOfDays=$OPTARG
      else 
        echo "Option -d must have numeric value" >&2
        exit 1
      fi
      ;;
    n)
      if [ $OPTARG -gt 0 ]; then
        logNTopMessages=$OPTARG
      else 
        echo "Option -n must have numeric value" >&2
        exit 1
      fi
      ;;
    l)
      if [ $OPTARG -gt 0 ]; then
        logLimitNErrors=$OPTARG
      else 
        echo "Option -l must have numeric value" >&2
        exit 1
      fi
      ;;
    \?|h)
      echo "log_check.sh can understand next options:" >&2
      echo "  -d N            How many logs in depth of days are defined by N will be parsed." >&2
      echo "  -n N            Top of lines which will be show in output are defined by N." >&2
      echo "  -l N            Low limit of a number of identical messages when lines will not be shown are defined by N." >&2
      echo "  N should be a positive numeric value." >&2
      exit 1
      ;;
  esac
done

[[ $(which pv) ]] && pvUtil=true || pvUtil=false
pvLimit="50M"                  # default rate-limit for pv

psqlCmd="psql -tXAF: $psqlArgs"
pgDataDir=$($psqlCmd -c "show data_directory")
pgLogDir=$($psqlCmd -c "show log_directory")
pgTmplateLogFile=$($psqlCmd -c "show log_filename")
pgLcMessages=$($psqlCmd -c "show lc_messages")

if [[ $(echo $pgLogDir |cut -c1) == "/" ]]; then      # this is an absolute path
    pgLogDir="$pgLogDir/$pgLogFile"
else                                                        # this is a relative path
    pgLogDir="$pgDataDir/$pgLogDir/$pgLogFile"
fi

for pgDayOfLog in $(seq 0 $logDepthOfDays); do

  pgLogFile=$(date --date="$pgDayOfLog day ago" +$pgTmplateLogFile)
  pgCompleteLogPath="$pgLogDir/$pgLogFile"

  if [[ -f $pgCompleteLogPath ]]; then
    ls -lh $pgCompleteLogPath
  else
    continue
  fi

  answer=""
  if [[ $(stat --printf="%s" $pgCompleteLogPath) -gt 1000000000 ]]; then      # print warning about the log size
    while [[ $answer != "y" &&  $answer != "n" ]]
      do
        echo -n "${yellow}Logfile size is more than 1Gb, parse it anyway? [y/n]: ${reset}" 
        read answer
      done
  else
      answer="y"          # size is less than 2Gb and it's acceptable for us.
  fi

  if [[ $answer == "y" ]]; then
    answer=""
    if [[ $pgLcMessages != 'C' && $pgLcMessages != *"en_US"* ]]; then      # print warning about the log size
      while [[ $answer != "y" &&  $answer != "n" ]]
        do
          echo -n "${red}PostgreSQL server's lc_messages is neither C nor en_US.UTF-8. ${yellow}Parse the log anyway? [y/n]: ${reset}"
          read answer
        done
    else
        answer="y"          # no problem with lc_messages
    fi
  fi

  if [[ $answer == "y" ]]; then       # we are ready to parse log
    tempPgLog=$(mktemp /tmp/pg.XXXXXX.out)
    if [[ $pvUtil == true ]]; then      # handle log with pv
        pv --progress --timer --eta --bytes --width 100 --rate-limit $pvLimit $pgCompleteLogPath |grep -oE '(ERROR|WARNING|FATAL|PANIC).*' > $tempPgLog
    else                                # do it without pv
        grep -oE '(ERROR|WARNING|FATAL|PANIC).*' $pgCompleteLogPath > $tempPgLog
    fi

    nPanic=$(grep -c ^PANIC $tempPgLog); nFatal=$(grep -c ^FATAL $tempPgLog); nError=$(grep -c ^ERROR $tempPgLog); nWarning=$(grep -c ^WARNING $tempPgLog)
    echo -e "  PANIC: total $nPanic (print all)"
    grep -wE ^PANIC $tempPgLog |sort |uniq -c |sort -rnk1
    echo -e "  FATAL: total $nFatal (print all)"
    grep -wE ^FATAL $tempPgLog |sort |uniq -c |sort -rnk1
    echo -e "  ERROR: total $nError (print top$logNTopMessages)"
    grep -wE ^ERROR $tempPgLog |sort |uniq -c |sort -rnk1 |head -n $logNTopMessages | awk -v limit=${logLimitNErrors} '$1 > limit{print}'
    echo -e "  WARNING: total $nWarning (print top$logNTopMessages)"
    grep -wE ^WARNING $tempPgLog |sort |uniq -c |sort -rnk1 |head -n $logNTopMessages | awk -v limit=${logLimitNErrors} '$1 > limit{print}'
    [[ -f $tempPgLog ]] && rm -f $tempPgLog
    echo ""
  fi
done
#######
