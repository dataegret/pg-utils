#!/bin/bash
# Author:       Lesovsky A.V. lesovsky@dataegret.com
# License:      BSD 3-Clause License
# Description: Do audit and make report.
# Usage: server-audit.sh [psql arguments]

# send stderr to /dev/null gloabally
exec 2>/tmp/file

# env variables
export PATH="/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin"
export LANG="en_US.UTF-8"

# colors
red=$(tput setaf 1)
green=$(tput setaf 2)
yellow=$(tput setaf 3)
reset=$(tput sgr0)

# defaults
psqlArgs=$@
psqlCmd="psql -tXAF: $psqlArgs"
prgPager="less"
[[ $(which vi) ]] && prgEditor=$(which vi) || prgEditor=$(which nano)
[[ $(which pv) ]] && pvUtil=true || pvUtil=false
[[ $(which curl) ]] && curlUtil=true || curlUtil=false
pvLimit="50M"                  # default rate-limit for pv

#
# Functions section
#
getHardwareData() {
  cpuModel=$(awk -F: '/^model name/ {print $2; exit}' /proc/cpuinfo)
  cpuCount=$(awk -F: '/^physical id/ { print $2 }' /proc/cpuinfo |sort -u |wc -l)
  cpuCoreCount=$(lscpu |grep "On-line CPU(s) list:" |xargs)
  cpuData="$cpuCount x $cpuModel ($cpuCoreCount)"

  numaNodes=$(lscpu |grep -w "^NUMA node" |awk '{print $3}')

  memTotal=$(awk -F: '/^MemTotal/ {print $2}' /proc/meminfo |xargs echo)
  swapTotal=$(awk -F: '/^SwapTotal/ {print $2}' /proc/meminfo |xargs echo)
  memData="physical memory: $memTotal; swap: $swapTotal"

  # required lspci for pci device_id and vendor_id translation
  storageData=$(lspci |awk -F: '/storage controller/ || /RAID/ || /SCSI/ { print $3 }' |xargs echo)

  for disk in $(grep -Ewo '(s|h|v|xv)d[a-z]|c[0-9]d[0-9]' /proc/partitions |sort -r |xargs echo); do
    size=$(echo $(($(cat /sys/dev/block/$(grep -w $disk /proc/partitions |awk '{print $1":"$2}')/size) * 512 / 1024 / 1024 / 1024)))
    diskData="$disk size ${size}GiB, $diskData"
  done
  diskData=$(echo $diskData |sed -e 's/,$//')

  # required lspci for pci device_id and vendor_id translation
  netData=$(lspci |awk -F: '/Ethernet controller/ {print $3}' |sort |uniq -c |sed -e 's/$/,/g' |xargs echo |tr -d ",$")
}

getOsData() {
  hostname=$(hostname)
  full_hostname=$(hostname -f)
  arch=$(uname --machine)
  os=$(find /etc -maxdepth 1 -name '*release' -type f | xargs cat |grep ^PRETTY_NAME |cut -d= -f2 |tr -d \")
  kernel=$(uname -sr)
  ip=$(ip address list |grep -oE "inet [0-9]{1,3}(\.[0-9]{1,3}){3}" |awk '{ print $2 }' |xargs echo)
  [[ $(lsblk -n -o type |grep -c lvm) > 0 ]] && isLvmUsed=true || isLvmUsed=false
  [[ $(lsblk -n -o type |grep -c raid) > 0 ]] && isMdraidUsed=true || isMdraidUsed=false
  sKernSchedMigCost=$(sysctl -n -e kernel.sched_migration_cost_ns kernel.sched_migration_cost) 
  sKernSchedAG=$(sysctl -n -e kernel.sched_autogroup_enabled)
  sVmDBytes=$(sysctl -n -e vm.dirty_bytes)
  sVmDBgBytes=$(sysctl -n -e vm.dirty_background_bytes)
  sVmDRatio=$(sysctl -n -e vm.dirty_ratio)
  sVmDBgRatio=$(sysctl -n -e vm.dirty_background_ratio)
  sVmDExpCSec=$(sysctl -n -e vm.dirty_expire_centisecs)
  sVmOverMem=$(sysctl -n -e vm.overcommit_memory)
  sVmOverRatio=$(sysctl -n -e vm.overcommit_ratio)
  sVmSwap=$(sysctl -n -e vm.swappiness)
  sVmMinFreeKb=$(sysctl -n -e vm.min_free_kbytes)
  sVmZoneReclaim=$(sysctl -n -e vm.zone_reclaim_mode)
  sKernNumaBal=$(sysctl -n -e kernel.numa_balancing)
  sVmNrHP=$(sysctl -n -e vm.nr_hugepages)
  sVmNrOverHP=$(sysctl -n -e vm.nr_overcommit_hugepages)
  hpSizeKb=$(grep -wE "^Hugepagesize:" /proc/meminfo |awk '{print $2}')
  hpTotalAlloc=$(grep -wE "^HugePages_Total:" /proc/meminfo |awk '{print $2}')
  hpTotalAllocMb=$(( $hpTotalAlloc * $hpSizeKb / 1024))
  thpTotalAllocMb=$(grep -wE "^AnonHugePages:" /proc/meminfo |awk '{print $2 / 1024}' )
  thpState=$(cat /sys/kernel/mm/transparent_hugepage/enabled |grep -oE '\[[a-z]+\]' |tr -d \[\])
  thpDefrag=$(cat /sys/kernel/mm/transparent_hugepage/defrag |grep -oE '\[[a-z]+\]' |tr -d \[\])
  sVmLaptop=$(sysctl -n -e vm.laptop_mode)
  blkMqMod=$(find /sys/module -name use_blk_mq |cut -d/ -f4 |xargs echo)
  hostList=$(ls -1 /sys/class/scsi_host/ |grep -owE 'host[0-9]+')
  useBlkMq=$(cat /sys/class/scsi_host/host*/use_blk_mq |uniq -c)
}

getPkgInfo() {
  [[ $(which pgbouncer) ]] && binPgbouncer=$(which pgbouncer) ||  binPgbouncer=""
  [[ $(which pgpool) ]] && binPgpool=$(which pgpool) || binPgpool=""
  [[ $(which pgqadm) ]] && binPgqadm=$(which pgqadm) || binPgqadm=""
  [[ $(which qadmin) ]] && binQadmin=$(which qadmin) || binQadmin=""
  [[ $(which slon) ]] && binSlon=$(which slon) || binSlon=""
  [[ $(which ntpd) ]] && binNtpd=$(which ntpd) || binNtpd=""
  

  [[ -n $binPgbouncer ]] && pgbVersion=$($binPgbouncer --version |cut -d" " -f3) || pgbVersion=""
  [[ -n $binPgpool ]] && pgpVersion=$($binPgpool --version |cut -d" " -f3) || pgpVersion=""
  [[ -n $binPgqadm ]] && pgqaVersion=$($binPgqadm --version |cut -d" " -f3) || pgqaVersion=""
  [[ -n $binQadmin ]] && qadVersion=$($binQadmin --version |cut -d" " -f3) || qadVersion=""
  [[ -n $binSlon ]] && slonVersion=$($binSlon -v |cut -d" " -f3) || slonVersion=""
  [[ -n $binNtpd ]] && ntpdVersion=$($binNtpd --version 2>&1 |head -n 1 |grep -woE '[0-9p\.]+'|head -n 1) || ntpdVersion=""

  pgVersion=$($psqlCmd -c 'show server_version')
  pgMajVersion=$($psqlCmd -c "select current_setting('server_version_num')::int / 10000")
}

getPostgresCommonData() {
  if [[ $($psqlCmd -c "select 1") != 1 ]]; then
      pgcheck_success=0
      return
  fi

  pgGetDbQuery="SELECT d.datname as name,
                       pg_catalog.pg_encoding_to_char(d.encoding) as encoding,
                       d.datcollate as collate,d.datctype as ctype,
                       CASE WHEN pg_catalog.has_database_privilege(d.datname, 'CONNECT')
                            THEN pg_catalog.pg_size_pretty(pg_catalog.pg_database_size(d.datname))
                            ELSE 'No Access'
                       END as size
                FROM pg_catalog.pg_database d
                JOIN pg_catalog.pg_tablespace t on d.dattablespace = t.oid
                ORDER BY pg_catalog.pg_database_size(d.datname) DESC LIMIT 5;"
  pgGetTblSpcQuery="SELECT spcname,
                           pg_catalog.pg_tablespace_location(oid),
                           pg_catalog.pg_size_pretty(pg_catalog.pg_tablespace_size(oid))
                    FROM pg_catalog.pg_tablespace
                    ORDER BY pg_catalog.pg_tablespace_size(oid) DESC LIMIT 5;"
  pgDataDir=$($psqlCmd -c "show data_directory")
  pgConfigFile=$($psqlCmd -c "show config_file")
  pgHbaFile=$($psqlCmd -c "show hba_file")
  pgAutoConfigFile=$(ls -1 $pgDataDir/postgresql.auto.conf)
  pgAutoConfigNumLines=$(grep -c -vE '^#|^#' $pgDataDir/postgresql.auto.conf)
  pgTblSpcNum=$($psqlCmd -c "select count(1) from pg_tablespace")
  pgTblSpcList=$($psqlCmd -c "$pgGetTblSpcQuery" |awk -F: '{print $1" (size: "$3", location: "$2");"}' |xargs echo |sed -e 's/;$/\./g')
  pgDbNum=$($psqlCmd -c "select count(1) from pg_database")
  pgDbList=$($psqlCmd -c "$pgGetDbQuery" |awk -F: '{print $1" ("$5", "$2", "$3");"}' |xargs echo |sed -e 's/;$/\./g')
  pgReplicaCount=$($psqlCmd -c "select count(*) from pg_stat_replication")
  pgRecoveryStatus=$($psqlCmd -c "select pg_is_in_recovery()")
  pgLogDir=$($psqlCmd -c "show log_directory")
  pgLogFile=$(date +$($psqlCmd -c "show log_filename"))
  pgLcMessages=$($psqlCmd -c "show lc_messages")
  numaMapsLocation="/proc/$(head -n 1 $pgDataDir/postmaster.pid)/numa_maps"
  if [[ -f $numaMapsLocation ]]; then numaCurPolicy=$(cat $numaMapsLocation|head -n 1 |cut -d" " -f2); fi
  [[ $curlUtil == "true" ]] && pgLatestAvailVer=$(curl --connect-timeout 3 -s https://www.postgresql.org/ |grep "PostgreSQL .* Released!" |grep -oE '[0-9\.]+' |grep $pgMajVersion)
}

printSummary() {
  echo -e "${yellow}Hardware: summary${reset}
  Cpu:               $( [[ -n $cpuData ]] && echo $cpuData || echo "${red}Can't understand.${reset}")
  Numa node(s):      $([[ $numaNodes -gt 1 ]] && echo ${red}$numaNodes${reset} || echo "${green}$numaNodes${reset}")
  Memory:            $([[ -n $memData ]] && echo $memData || echo "${red}Can't understand.${reset}")
  Storage:           $([[ -n $storageData ]] && echo $storageData || echo "${red}Can't understand.${reset}")
  Disks:             $([[ -n $diskData ]] && echo $diskData || echo "${red}Can't understand.${reset}")
  Storage layers:    $([[ $isLvmUsed == true ]] && echo "LVM: yes;" || echo "LVM: no;") $([[ $isMdraidUsed == true ]] && echo " MDRAID: yes." || echo " MDRAID: no.")
  Network:           $([[ -n $netData ]] && echo $netData || echo "${red}Can't understand.${reset}")
  Assigned IP(s):    $([[ -n $ip ]] && echo $ip || echo "${red}Can't understand.${reset}")

${yellow}Software: summary${reset}
System:            Hostname $([[ -n $full_hostname ]] && echo $full_hostname || echo $hostname); Distro $os; Arch $arch; Kernel $kernel.
  Process Scheduler: kernel.sched_migration_cost_ns = $([[ $sKernSchedMigCost -le 1000000 ]] && echo "${red}$sKernSchedMigCost${reset}" || echo "${green}$sKernSchedMigCost${reset}") \
\t\tkernel.sched_autogroup_enabled = $([[ $sKernSchedAG -eq 1 ]] && echo "${red}$sKernSchedAG${reset}" || echo "${green}$sKernSchedAG${reset}")
  Virtual Memory:    vm.dirty_background_bytes = $([[ $sVmDBgBytes -eq 0 ]] && echo "${red}$sVmDBgBytes${reset}" || echo "${green}$sVmDBgBytes${reset}") \
\t\t\tvm.dirty_bytes = $([[ $sVmDBytes -eq 0 ]] && echo "${red}$sVmDBytes${reset}" || echo "${green}$sVmDBytes${reset}")
                     vm.dirty_background_ratio = $([[ $sVmDBgRatio -gt 0 ]] && echo "${red}$sVmDBgRatio${reset}" || echo "${green}$sVmDBgRatio${reset}") \
\t\t\tvm.dirty_ratio = $([[ $sVmDRatio -gt 0 ]] && echo "${red}$sVmDRatio${reset}" || echo "${green}$sVmDRatio${reset}") \
\t\t\t\tvm.dirty_expire_centisecs = "${yellow}$sVmDExpCSec${reset}"
                     vm.overcommit_memory = $([[ $sVmOverMem -gt 0 ]] && echo "${red}$sVmOverMem${reset}" || echo "${green}$sVmOverMem${reset}") \
\t\t\t\tvm.overcommit_ratio = $([[ $sVmOverRatio -gt 50 ]] && echo "${red}$sVmOverRatio${reset}" || echo "${green}$sVmOverRatio${reset}")
                     vm.min_free_kbytes = $([[ $sVmMinFreeKb -lt 100000 ]] && echo "${red}$sVmMinFreeKb${reset}" || echo "${green}$sVmMinFreeKb${reset}") \
\t\t\tvm.swappiness = $([[ $sVmSwap -gt 10 ]] && echo "${red}$sVmSwap${reset}" || echo "${green}$sVmSwap${reset}")
  NUMA:              vm.zone_reclaim_mode = $([[ $sVmZoneReclaim -eq 1 ]] && echo "${red}$sVmZoneReclaim${reset}" || echo "${green}$sVmZoneReclaim${reset}") \
\t\t\t\tkernel.numa_balancing = $([[ $sKernNumaBal -eq 1 ]] && echo "${red}$sKernNumaBal${reset}" || echo "${green}$sKernNumaBal${reset}")
  Huge Pages:        Huge page size: $hpSizeKb kB, Total pages: $hpTotalAlloc ($hpTotalAllocMb MB)
                     vm.nr_hugepages = ${yellow}$sVmNrHP${reset} \
\t\t\t\tvm.nr_overcommit_hugepages = ${yellow}$sVmNrOverHP${reset}
  Transparent Hugepages:  Huge page size: $hpSizeKb kB, used: "$thpTotalAllocMb"MB
                          /sys/kernel/mm/transparent_hugepage/enabled: $([[ $thpState != "never" ]] && echo "${red}$thpState${reset}" || echo "${green}$thpState${reset}")
                          /sys/kernel/mm/transparent_hugepage/defrag: $([[ $thpDefrag != "never" ]] && echo "${red}$thpDefrag${reset}" || echo "${green}$thpDefrag${reset}")"

echo -n "  Storage IO:"
# analyze blk-mq support
echo -n "${yellow}        blk-mq support:${reset} $([[ -n $blkMqMod ]] && echo " $blkMqMod" || echo " not supported")"
echo -n -e "${yellow}\t host status:${reset} "
for host in $hostList;
do 
    if [[ -f /sys/class/scsi_host/$host/use_blk_mq ]]; then
        echo -n -e "$host: $([[ $(cat /sys/class/scsi_host/$host/use_blk_mq) == 1 ]] && echo "${green}active${reset}" || echo "${red}not active${reset}")\t";
    fi 
done
    echo ""

# analyze /sys/block
if [ -d /sys/block/ ]
  then
    for i in $(ls -1 /sys/block/ | grep -oE '(s|xv|v)d[a-z]');
      do
        echo -n "                     "
        echo "$i: rotational: $(cat /sys/block/$i/queue/rotational); \
        scheduler: $(cat /sys/block/$i/queue/scheduler); \
        nr_requests: $(cat /sys/block/$i/queue/nr_requests); \
        rq_affinity: $(cat /sys/block/$i/queue/rq_affinity); \
        read_ahead_kb: $(cat /sys/block/$i/queue/read_ahead_kb)";
      done #| awk '!(NR%2){print p "\t\t\t" $0}{p=$0}'
  else
    echo "/sys/block directory not found."
fi

echo -n -e "  Filesystems:       ${yellow}Check for Ext3, Ext4, ReiserFS, XFS and Rootfs${reset}\n"
mount |grep -w -E 'ext(3|4)|reiserfs|xfs|rootfs' |column -t | while read line; do echo "                     $line"; done

echo -n "  Power saving mode: ${yellow}CPU scaling governor${reset} (running kernel: $(uname -r)): "
if [ -d /sys/devices/system/cpu/cpu0/cpufreq/ ]
  then
    echo "${red}used.${reset}"         # offset
    for i in $(ls -1 /sys/devices/system/cpu/ | grep -oE 'cpu[0-9]+');
      do
        echo -n "                     "         # offset
        governor=$(cat /sys/devices/system/cpu/$i/cpufreq/scaling_governor)
        driver=$(cat /sys/devices/system/cpu/$i/cpufreq/scaling_driver)
        echo -n "$i: $([[ $governor == "performance" ]] && echo "${green}$governor${reset}" || echo "${red}$governor${reset}")"
        echo -n -e " (driver: $([[ $driver == "intel_pstate" ]] && echo "${green}$driver${reset}" || echo "${red}$driver${reset}"))\n"
      done | awk '!(NR%2){print p $0}{p=$0}'
    else
        echo "${green}not used${reset} (cpufreq directory not found)."
      echo -n "                     "              # offset
      echo "check frequency with lscpu:"
      lscpu |grep -E '^(Model|Vendor|CPU( min| max)? MHz)' |xargs -I $ echo "                     $"
fi
echo -n "                     "         # offset

echo "${yellow}Aggressive Link Power Management:${reset}"
if [[ -n $hostList ]]; then
    echo -n "                     "         # offset
    for host in $hostList;
      do
        if [[ -f /sys/class/scsi_host/$host/link_power_management_policy ]]; then
          state=$(cat /sys/class/scsi_host/$host/link_power_management_policy)
          echo -e -n "$host: $([[ $state == "max_performance" ]] && echo "${green}$state${reset}" || echo "${red}$state${reset}")\t";
        else
          echo -e -n "$host: ${green}ALPM not used${reset}\t";
        fi 
      done
    echo ""
fi

echo -n "                     "         # offset
echo "${yellow}Laptop mode:${reset} $([[ $sVmLaptop -ne 0 ]] && echo ${red}$sVmLaptop${reset} || echo ${green}$sVmLaptop${reset})"

echo -e "
${yellow}Services: summary${reset}
  PostgreSQL:        $([[ -n $pgVersion ]] && echo "$pgVersion installed" || echo "not installed.") \
$(if [[ -n $pgVersion && -n $pgLatestAvailVer ]]; then echo "(latest available: $pgLatestAvailVer)"; fi ) \
$(if [[ -n $pgVersion ]]; then [[ -n $(ps aux|grep postgres: |grep -v grep &>/dev/null && echo OK) ]] && echo "and running." || echo "but not running."; fi)
  pgBouncer:         $([[ -n $pgbVersion ]] && echo "$pgbVersion installed" || echo "not installed.") \
$(if [[ -n $pgbVersion ]]; then [[ -n $(pgrep pgbouncer) ]] && echo "and running." || echo "but not running."; fi)
  pgPool:            $([[ -n $pgpVersion ]] && echo "$pgpVersion installed" || echo "not installed.") \
$(if [[ -n $pgpVersion ]]; then [[ -n $(pgrep pgpool) ]] && echo "and running." || echo "but not running."; fi)
  Skytools2:         $([[ -n $pgqaVersion ]] && echo "$pgqaVersion installed" || echo "not installed.") \
$(if [[ -n $pgqaVersion ]]; then [[ -n $(pgrep pgqd) ]] && echo "and running." || echo "but not running."; fi)
  Skytools3:         $([[ -n $qadVersion ]] && echo "$qadVersion installed" || echo "not installed.") \
$(if [[ -n $qadVersion ]]; then [[ -n $(pgrep pgqd) ]] && echo "and running." || echo "but not running."; fi)
  Slony:             $([[ -n $slonVersion ]] && echo "$slonVersion installed" || echo "not installed.") \
$(if [[ -n $slonVersion ]]; then [[ -n $(pgrep slon) ]] && echo "and running." || echo "but not running."; fi)
  Ntpd:              $([[ -n $ntpdVersion ]] && echo "$ntpdVersion installed" || echo "not installed.") \
$(if [[ -n $ntpdVersion ]]; then [[ -n $(pgrep ntpd) ]] && echo "and running." || echo "but not running."; fi)
  Monitoring agents: $([[ -n $(pgrep zabbix_agentd) ]] && echo "Zabbix ") $([[ -n $(pgrep monit) ]] && echo "Monit ") \
$([[ -n $(pgrep okagent) ]] && echo "OKmeter ") $([[ -n $(pgrep munin) ]] && echo "Munin ")
"
echo -e "${yellow}PostgreSQL: summary${reset}
  Data directory:            $pgDataDir
  Main configuration:        $pgConfigFile
  Auto configuration:        $(if [[ -n $pgAutoConfigFile ]]; then echo "$pgAutoConfigFile"; else echo "Not found."; fi) \
$( if [[ -n $pgAutoConfigFile ]]; then if [[ $pgAutoConfigNumLines -gt 0 ]]; then echo "${red}exists and is not empty.${reset}"; else echo "${green}exists but nothing defined.${reset}"; fi; fi )
  Log directory:             $(if [[ $(echo $pgLogDir |cut -c1) == "/" ]]; then echo "${green}$pgLogDir${reset}"; else echo "${red}$pgDataDir/$pgLogDir${reset}"; fi)
  Recovery?                  $pgRecoveryStatus
  Replica count:             $pgReplicaCount
  NUMA policy:               $(if [[ -n $numaCurPolicy ]]; then if [[ $numaCurPolicy == "interleave" ]]; then echo "${green}$numaCurPolicy${reset}"; else echo "${red}$numaCurPolicy${reset}"; fi; \
else echo "numa_maps not found"; fi)
"
sleep 0.1
echo -e "${yellow}PostgreSQL: log file${reset}"
answer=""
while [[ $answer != "y" &&  $answer != "n" ]]
  do
    sleep 0.1
    echo -n "${yellow}Parse postgresql log and print summary information? [y/n]: ${reset}"
    read answer
  done
if [[ $answer == "y" ]]; then
  if [[ $(echo $pgLogDir |cut -c1) == "/" ]]; then      # this is an absolute path
      pgCompleteLogPath="$pgLogDir/$pgLogFile"
  else                                                        # this is a relative path
      pgCompleteLogPath="$pgDataDir/$pgLogDir/$pgLogFile"
  fi
  while [[ ! -f $pgCompleteLogPath ]]
    do
       # Ubuntu/Debian workaround. By default logging isn't configured adequate there.
       echo -n "${red}Logfile not found on its location. ${yellow}Enter another location: ${reset}"
       read pgCompleteLogPath
    done
  ls -l $pgCompleteLogPath

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

  if [[ $answer == "y" ]]; then	      # we are ready to parse log
    tempPgLog=$(mktemp /tmp/pg.XXXXXX.out)
    if [[ $pvUtil == true ]]; then      # handle log with pv
        pv --progress --timer --eta --bytes --width 100 --rate-limit $pvLimit $pgCompleteLogPath |grep -oE '(ERROR|WARNING|FATAL|PANIC).*' > $tempPgLog
    else                                # do it without pv
	echo "answer: $answer"
        grep -oE '(ERROR|WARNING|FATAL|PANIC).*' $pgCompleteLogPath > $tempPgLog
    fi

    nPanic=$(grep -c ^PANIC $tempPgLog); nFatal=$(grep -c ^FATAL $tempPgLog); nError=$(grep -c ^ERROR $tempPgLog); nWarning=$(grep -c ^WARNING $tempPgLog)
    echo -e "  PANIC: total $nPanic (print all)"
    grep -wE ^PANIC $tempPgLog |sort |uniq -c |sort -rnk1
    echo -e "  FATAL: total $nFatal (print all)"
    grep -wE ^FATAL $tempPgLog |sort |uniq -c |sort -rnk1
    echo -e "  ERROR: total $nError (print top10)"
    grep -wE ^ERROR $tempPgLog |sort |uniq -c |sort -rnk1 |head -n 10
    echo -e "  WARNING: total $nWarning (print top10)"
    grep -wE ^WARNING $tempPgLog |sort |uniq -c |sort -rnk1 |head -n 10
    [[ -f $tempPgLog ]] && rm -f $tempPgLog
    echo ""
  fi
fi
#######

echo -e "${yellow}PostgreSQL: content${reset}
  Tablespaces count:           $pgTblSpcNum
  Tablespaces by size (top-5): $pgTblSpcList
  Databases count:             $pgDbNum
  Databases by size (top-5):   $pgDbList
"

# print uncommented options from postgresql.conf
answer=""
while [[ $answer != "y" &&  $answer != "n" ]]
  do
    echo -n "${yellow}Print uncommented options from postgresql.conf? [y/n]: ${reset}"
    read answer
  done
if [[ $answer == "y" ]]; then
    echo "${yellow}$pgConfigFile${reset}"
    grep -oE "^[a-z_\.]+ = ('.*'|[a-z0-9A-Z\._-]+)" $pgConfigFile |sed -e 's/^/  /g'
    echo ""
    hardLineCnt=$(grep -c -oE "^[a-z_\.]+ = ('.*'|[a-z0-9A-Z\._-]+)" $pgConfigFile)
    softLineCnt=$(grep -c -oE "^[a-z]+" $pgConfigFile)
    if [[ $hardLineCnt -ne $softLineCnt ]]; then
        echo "${red}  Don't trust me here. Regexp failure: lines found $softLineCnt, lines printed $hardLineCnt.${reset}"
    fi
fi
}

doSingleDbAudit() {
local psqlCmd2="$psqlCmd -d $targetDb"
pgGetDbProperties="SELECT d.datname,
       pg_catalog.pg_get_userbyid(d.datdba),
       pg_catalog.pg_encoding_to_char(d.encoding),
       d.datcollate, d.datctype,
       CASE WHEN pg_catalog.has_database_privilege(d.datname, 'CONNECT')
            THEN pg_catalog.pg_size_pretty(pg_catalog.pg_database_size(d.datname))
            ELSE 'No Access'
       END,
       t.spcname
       FROM pg_catalog.pg_database d
       JOIN pg_catalog.pg_tablespace t on d.dattablespace = t.oid
       WHERE d.datname = '$targetDb';"
pgGetLargestRels="SELECT n.nspname ||'.'||c.relname,
       pg_catalog.pg_size_pretty(pg_catalog.pg_table_size(c.oid))
       FROM pg_catalog.pg_class c
       LEFT JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
       WHERE c.relkind IN ('r','')
       AND n.nspname NOT IN ('pg_catalog', 'information_schema') AND n.nspname !~ '^pg_toast'
       AND pg_catalog.pg_table_is_visible(c.oid)
       ORDER BY pg_catalog.pg_table_size(c.oid) DESC LIMIT 5;"
pgGetNspList="SELECT nspname FROM pg_catalog.pg_namespace WHERE nspname NOT IN ('pg_catalog', 'information_schema') AND nspname !~ '^(pg_toast|pg_temp)'"
pgGetInheritanceInfo="SELECT count(name),coalesce(sum(cnt),0) FROM (SELECT
       nmsp_parent.nspname||'.'||parent.relname as name,
       COUNT(*) cnt
       FROM pg_inherits
       JOIN pg_class parent            ON pg_inherits.inhparent = parent.oid
       JOIN pg_class child             ON pg_inherits.inhrelid   = child.oid
       JOIN pg_namespace nmsp_parent   ON nmsp_parent.oid  = parent.relnamespace
       JOIN pg_namespace nmsp_child    ON nmsp_child.oid   = child.relnamespace
       GROUP BY 1) s;"
pgGetIndexTypes="SELECT
       CASE
           WHEN (indexdef ~'USING btree') THEN 'btree'
           WHEN (indexdef ~'USING hash') then 'hash'
           WHEN (indexdef ~'USING gin') then 'gin'
           WHEN (indexdef ~'USING gist') then 'gist'
           ELSE 'unknown'
       END, count(*)
       FROM pg_indexes GROUP BY 1 ORDER BY 2"
pgGetFuncTypes="SELECT l.lanname,count(*)
       FROM pg_proc p
       LEFT JOIN pg_language l ON p.prolang = l.oid
       LEFT JOIN pg_namespace n ON n.oid = p.pronamespace
       WHERE n.nspname NOT IN ('information_schema','pg_catalog','pg_toast') GROUP BY 1 ORDER BY 2 DESC;"

pgDbProperties=$($psqlCmd2 -c "$pgGetDbProperties" |awk -F: '{print $1" (owner: "$2", encoding: "$3", collate: "$4", ctype: "$5", size: "$6", tablespace: "$7");"}' |xargs echo |sed -e 's/;$/\./g')
pgDbGetNspNum=$($psqlCmd2 -c "SELECT count(1) FROM pg_catalog.pg_namespace WHERE nspname !~ '^pg_' AND nspname <> 'information_schema'")
pgGetNspList=$($psqlCmd2 -c "$pgGetNspList" |awk -F: '{print $1"; "}' |xargs echo |sed -e 's/;$/\./g')
pgDbGetRelNum=$($psqlCmd2 -c "SELECT count(1) FROM pg_catalog.pg_stat_user_tables")
pgLargestRelsList=$($psqlCmd2 -c "$pgGetLargestRels" |awk -F: '{print $1" (size: "$2");"}' |xargs echo |sed -e 's/;$/\./g')
pgGetIdxNum=$($psqlCmd2 -c "SELECT count(1) FROM pg_catalog.pg_stat_user_indexes")
pgGetIdxTypesList=$($psqlCmd2 -c "$pgGetIndexTypes" |awk -F: '{print $1" "$2";"}' |xargs echo |sed -e 's/;$/\./g')
pgGetFuncNum=$($psqlCmd2 -c "SELECT count(1) FROM pg_catalog.pg_stat_user_functions")
pgGetFuncList=$($psqlCmd2 -c "$pgGetFuncTypes" |awk -F: '{print $1" "$2";"}' |xargs echo |sed -e 's/;$/\./g')
pgGetInhNum=$($psqlCmd2 -c "$pgGetInheritanceInfo" |awk -F: '{print $1" parent tables with "$2" child tables."}' |xargs echo)

echo -e "  Target database:    $pgDbProperties
  Namespaces count:   total $pgDbGetNspNum. $pgGetNspList
  Tables count:       total $pgDbGetRelNum. $pgLargestRelsList
  Indexes count:      total $pgGetIdxNum. $pgGetIdxTypesList
  Functions count:    total $pgGetFuncNum. $pgGetFuncList
  Inheritance:        $pgGetInhNum
  "
}

doDbAudit() {
  answer=""
  while [[ $answer != "n" ]]
    do
      sleep 0.1
      echo -n "${yellow}Do an audit of the particular database? [y/n]: ${reset}"
      read answer
      dbexists=""
      while [[ $dbexists != "1" && $answer == 'y' ]]
        do
          if [[ $answer == "y" ]]; then
            echo -n "${yellow}Enter database name: ${reset}"
            read targetDb
          fi
          dbexists=$($psqlCmd -c "select count(1) from pg_database where datname = '$targetDb'")
          [[ $dbexists -eq 0 ]] && echo -n "${red}Database doesn't exists. ${reset}"
        done
      if [[ $dbexists -eq 1 && $answer == 'y' ]]; then doSingleDbAudit; fi
  done
}

main() {
  echo "Gathering information:"
  echo -n "  hardware..."; getHardwareData; echo -e "\tdone"
  echo -n "  software..."; getOsData; echo -e "\tdone"
  echo -n "  packages..."; getPkgInfo; echo -e "\tdone"
  echo -n "  postqresql..."; getPostgresCommonData; if [[ $pgcheck_success == 0 ]]; then echo -e "\tcan't connect to postgres, skip checks" ; else echo -e "\tdone"; fi
  echo "Report:"
  printSummary
  doDbAudit
  echo "${green}Finished.${reset}"
}

main
