#!/bin/ksh
##############################################################################
## check_iostat.ksh
## Author: Brian Eugley
## Version: 1.0, 1/7/2014
##
## check_iostat.ksh is a Nagios plugin to monitor disk I/O.
## Monitored I/O metrics:
##    KB-read/second:
##    KB-written/second:
## Metrics are compared with warning/critical thresholds.
## Return codes:
##    0 (Success)
##    1 (Warning threshold exceeded for 1 or more monitored devices)
##    2 (Critical threshold exceeded for 1 or more monitored devices)
##
## Arguments:
##    -d [devices]
##       A comma-separated list of devices to be monitored
##       Example: -d sda,dm-2,dm-15
##    -p [paths]
##       A comma-separated list of mounted paths to be monitored
##       Example: -p /home,/prod
##    -w readKB,writeKB
##       Warning thresholds for each monitored metric.  Default is 1000,5000.
##       Example: -w 800,3000
##    -c readKB,writeKB
##       Critical thresholds for each monitored metric.  Default is 2000,10000.
##       Example: -w 3000,15000
##    -i interval
##       The time interval for which I/O rates are measured, in seconds.  This
##       must not exceed the max time that Nagios waits for plugins to execute.
##       Default is 8 seconds
##       Example: -i 5
##    -h
##       Displays the usage string
##############################################################################

set +u
SUCCESS=0
WARNING=1
CRITICAL=2
typeset -i INTERVAL=8           # I/O measurement interval in seconds
typeset -i rkb_WARN=1000        # WARNING read-KB/second
typeset -i wkb_WARN=5000        # WARNING write-KB/second
typeset -i rkb_CRIT=2000        # CRITICAL read-KB/second
typeset -i wkb_CRIT=10000       # CRITICAL write-KB/second

function Usage
{
	USAGE="`basename $0` (-d devices &| -p paths) [-i interval] [-w readKB,writeKB -c readKB,writeKB]"
	print -u2 "$USAGE"
	print -u2 " -d devices"
	print -u2 "    A comma-separated list of devices to be monitored."
	print -u2 "    Example: -d sda,dm-2,dm-15"
	print -u2 " -p paths"
	print -u2 "    A comma-separated list of mounted paths to be monitored."
	print -u2 "    Example: -p /home,/prod"
	print -u2 " -w readKB,writeKB"
	print -u2 "    Warning thresholds for each monitored metric.  Default is 1000,5000."
	print -u2 "    Example: -w 800,3000"
	print -u2 " -c readKB,writeKB"
	print -u2 "    Critical thresholds for each monitored metric.  Default is 2000,10000."
	print -u2 "    Example: -w 3000,15000"
	print -u2 " -i interval"
	print -u2 "    The time interval for which I/O rates are measured, in seconds.  This"
	print -u2 "    must not exceed the max time that Nagios waits for plugins to execute."
	print -u2 "    Default is 8 seconds."
	print -u2 "    Example: -i 5"
	print -u2 " -h"
	print -u2 "    Displays usage information."
	exit $SUCCESS
}

export PATH=/bin:/usr/bin:/sbin:/usr/sbin

##
## Parse arguments.
##
while getopts :d:p:i:w:c:h ARG
do
	case $ARG in
		h)  HELP=1;;
		d)  DEVICES=$OPTARG;;
		p)  PATHS=$OPTARG;;
		i)  INTERVAL=$OPTARG;;
		w)  WARN_THRESH=$OPTARG;;
		c)  CRIT_THRESH=$OPTARG;;
		:)  print -u2 "ERROR: switch -$OPTARG requires an argument"
		    Usage;;
		\?) print -u2 "ERROR: switch -$OPTARG unexpected"
		    Usage;;
	esac
done

if [[ -n $HELP ]]
then
	Usage
fi

##
## Verify that no option value begins with "-".  If any does, then that means
## that one or more switches are missing their value.
##
if [[ $DEVICES =~ ^- || $PATHS =~ ^- || $INTERVAL =~ ^- ||
      $WARN_THRESH =~ ^- || $CRIT_THRESH =~ ^- ]]
then
	Usage
fi

##
## DEVICES and/or PATHS must be specified.
##
if [[ -z "$DEVICES" && -z "$PATHS" ]]
then
	print -u2 "ERROR: -d and/or -p switches are required!"
	Usage
fi

if ((INTERVAL <= 0))
then
	print -u2 "ERROR: -i interval must be > 0!"
	Usage
fi

##
## WARN_THRESH and CRIT_THRESH must both be specified, or neither.
##
if [[ -z $WARN_THRESH && -n $CRIT_THRESH ]] ||
   [[ -n $WARN_THRESH && -z $CRIT_THRESH ]]
then
	print -u2 "ERROR: -w and -c switches must both be specified, or neither!"
	Usage
elif [[ -n $WARN_THRESH && -n $CRIT_THRESH ]]
then
	rkb_WARN=`echo $WARN_THRESH | cut -d',' -f1`
	wkb_WARN=`echo $WARN_THRESH | cut -d',' -f2`
	rkb_CRIT=`echo $CRIT_THRESH | cut -d',' -f1`
	wkb_CRIT=`echo $CRIT_THRESH | cut -d',' -f2`
	if ((rkb_WARN <= 0 || wkb_WARN <= 0 || rkb_CRIT <= 0 || wkb_CRIT <= 0))
	then
		print -u2 "ERROR: -w and -c options must be > 0!"
		Usage
	fi
fi

##
## Show all arguments (for debugging).
##
#print "DEVICES = '$DEVICES'"
#print "PATHS = '$PATHS'"
#print "INTERVAL = '$INTERVAL'"
#print "rkb_WARN = '$rkb_WARN'"
#print "wkb_WARN = '$wkb_WARN'"
#print "rkb_CRIT = '$rkb_CRIT'"
#print "wkb_CRIT = '$wkb_CRIT'"
#exit 0

##
## Get a list of all devices.
##
SAVE_IFS=$IFS
IFS=","
for device in $DEVICES
do
	ALL_DEVICES="$device $ALL_DEVICES"
done
for path in $PATHS
do
	# Get the device name for each path.
	device=`grep -P " $path " /etc/mtab | awk '{print $1}'`
	if [[ -z $device ]]
	then
		print "CRITICAL - '$path' is not a mounted path"
		exit $CRITICAL
	fi
	ALL_DEVICES="$device $ALL_DEVICES"
done
IFS=$SAVE_IFS

##
## Check I/O on all devices.
##
iostat $ALL_DEVICES -d -k -y $INTERVAL 1 | grep -v '^$' |\
	awk -v rkb_WARN=$rkb_WARN -v wkb_WARN=$wkb_WARN \
	    -v rkb_CRIT=$rkb_CRIT -v wkb_CRIT=$wkb_CRIT \
	    -v SUCCESS=$SUCCESS -v WARNING=$WARNING -v CRITICAL=$CRITICAL \
	'BEGIN {found=0;msg="";msgperf="";rc=SUCCESS;status="OK";} {
	if (found == 1)
		{
		rkb_sec = $3;
		wkb_sec = $4;
		#printf("%s\n", $0);
		msg = sprintf("%s [%s: %s,%s]",msg,$1,rkb_sec,wkb_sec);
		msgperf = sprintf("%s rkbs_%s=%s",msgperf,$1,rkb_sec);
		msgperf = sprintf("%s wkbs_%s=%s",msgperf,$1,wkb_sec);
		if (rkb_sec >= rkb_CRIT || wkb_sec >= wkb_CRIT)
			{
			status = "CRITICAL";
			rc = CRITICAL;
			}
		else if (rkb_sec >= rkb_WARN || wkb_sec >= wkb_WARN)
			{
			if (rc < WARNING)
				{
				status = "WARNING";
				rc = WARNING;
				}
			}
		}
	if ($1 == "Device:")
		{
		found = 1;
		}
	} END {
		printf("%s -%s |%s\n",status,msg,msgperf);
		exit rc;
	}'
RC=$?
exit $RC

