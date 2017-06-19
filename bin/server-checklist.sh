#!/usr/bin/env bash
# Description:	Check and print server system parameters
# Licence:      BSD
# Author:       Lesovsky Alexey, lesovsky@gmail.com

export PATH="/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin"
red=$(tput setaf 1)
green=$(tput setaf 2)
yellow=$(tput setaf 3)
reset=$(tput sgr0)

main() {
echo "${yellow}Tuning target: CPU scheduler${reset}"
sysctl -e kernel.sched_migration_cost_ns kernel.sched_migration_cost kernel.sched_autogroup_enabled

echo "${yellow}Tuning target: Virtual memory and NUMA${reset}"
echo "$(grep -E "^(Mem|Swap)Total:" /proc/meminfo)"
sysctl -e vm.dirty_background_bytes vm.dirty_bytes vm.dirty_background_ratio vm.dirty_ratio vm.dirty_expire_centisecs vm.swappiness vm.overcommit_memory vm.overcommit_ratio vm.min_free_kbytes

echo "NUMA node(s) available: $(ls -1d /sys/devices/system/node/node* |wc -l)"
sysctl -e vm.zone_reclaim_mode kernel.numa_balancing

echo "${yellow}Tuning target: Huge pages${reset}"
echo "/sys/kernel/mm/transparent_hugepage/enabled: $(cat /sys/kernel/mm/transparent_hugepage/enabled)
/sys/kernel/mm/transparent_hugepage/defrag: $(cat /sys/kernel/mm/transparent_hugepage/defrag)"
sysctl -e vm.hugetlb_shm_group vm.hugepages_treat_as_movable vm.nr_hugepages vm.nr_overcommit_hugepages

echo "${yellow}Tuning target: File systems${reset}"
mount |grep -w -E 'ext(3|4)|reiserfs|xfs|rootfs' |column -t

echo "${yellow}Tuning target: Storage IO${reset}"
if [ -d /sys/block/ ]
  then
    for i in $(ls -1 /sys/block/ | grep -oE 'sd[a-z]');
      do
        echo "$i: rotational: $(cat /sys/block/$i/queue/rotational); \
        scheduler: $(cat /sys/block/$i/queue/scheduler); \
        nr_requests: $(cat /sys/block/$i/queue/nr_requests); \
        rq_affinity: $(cat /sys/block/$i/queue/rq_affinity); \
        read_ahead_kb: $(cat /sys/block/$i/queue/read_ahead_kb)";
      done #| awk '!(NR%2){print p "\t\t\t" $0}{p=$0}'
    else
      echo "/sys/block directory not found."
fi

echo "${yellow}Tuning target: Networking${reset}"
sysctl -e net.ipv4.ip_local_port_range net.core.busy_poll net.core.busy_read net.ipv4.tcp_fastopen net.core.somaxconn net.core.netdev_max_backlog net.core.rmem_max net.core.wmem_max net.ipv4.tcp_rmem net.ipv4.tcp_wmem net.ipv4.tcp_max_syn_backlog net.ipv4.tcp_slow_start_after_idle net.ipv4.tcp_tw_reuse net.ipv4.tcp_abort_on_overflow

echo "${yellow}Tuning target: OS limits${reset}"
sysctl -e fs.file-max fs.inotify.max_user_watches
echo "open files limit (ulimit -n): $(ulimit -n)"

echo "${yellow}Tuning target: Clocksource${reset}"
echo "/sys/devices/system/clocksource/clocksource0/available_clocksource: $(cat /sys/devices/system/clocksource/clocksource0/available_clocksource)
/sys/devices/system/clocksource/clocksource0/current_clocksource: $(cat /sys/devices/system/clocksource/clocksource0/current_clocksource)"

echo "${yellow}Tuning target: Power saving policy${reset}"
sysctl -e vm.laptop_mode
if [ -d /sys/devices/system/cpu/cpu0/cpufreq/ ]
  then
    echo "current kernel version: $(uname -r)"
    for i in $(ls -1 /sys/devices/system/cpu/ | grep -oE 'cpu[0-9]+');
      do
        echo "$i: $(cat /sys/devices/system/cpu/$i/cpufreq/scaling_governor) (driver: $(cat /sys/devices/system/cpu/$i/cpufreq/scaling_driver))";
      done | awk '!(NR%2){print p "\t\t\t" $0}{p=$0}'
    else
      echo "cpufreq directory not found, invoke lscpu: "
      lscpu |grep -E '^(Model|Vendor|CPU( min| max)? MHz)'
fi

echo "${yellow}Tuning target: Services${reset}"
if which ntpd &>/dev/null
  then 
    if [[ $(ps ho comm -C ntpd) == *ntpd* ]]
       then echo "1. Ntpd found and running."
       else echo "1. Ntpd found, but not running."
    fi
  else echo "1. Ntpd not found."
fi

if pgrep pgbouncer &>/dev/null
  then
    echo "2. Pgbouncer"
      for i in $(pgrep pgbouncer); do 
        echo "  pid: $i open files limit: $(awk '/Max open files/{print "soft: " $4 " hard: " $5}' /proc/$i/limits)"
      done
  else echo "2. Pgbouncer not running, skip."
fi

echo "${yellow}Tuning target: Miscellaneous${reset}"
if [[ $(lsmod |grep edac) ]]
  then
    echo "1. Error Detection and Correction Module (EDAC)."
    for i in $(ls /sys/devices/system/edac/mc/mc*/*e_count);
      do echo "$i - $(cat $i)";
    done
  else
    echo "1. Error Detection and Correction Module (EDAC) modules not loaded"
fi
}

main 
