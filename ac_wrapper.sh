#!/bin/bash
if [ $# -lt 1 ];then
        echo "Usage: $0 </path/to/asset/list/file>"
        exit 1
fi

for UTIL in pidof xvfb-run xvfb-run-safe curl unzip;do
        if [ ! -x "`which $UTIL 2>/dev/null`" ];then
                echo "Need to install $UTIL."
                exit 2
        fi
done

BASEDIR=`dirname $0`
ASSET_LIST_FILE=$1
if [ -z "$MAX_CONCUR_PROCS" ];then
    MAX_CONCUR_PROCS=7
fi
while read LINE ;do
        CUR_XVFB=`pidof Xvfb |wc -w`
        while [ ! $CUR_XVFB -lt $MAX_CONCUR_PROCS ];do
                echo "Have $CUR_XVFB running so I'll sleep a bit..."
                sleep 60
                CUR_XVFB=`pidof Xvfb |wc -w`
        done
        CATEGORY_NAME=`echo $LINE|awk -F "," '{print $2}'|sed 's@"@@g'`
        MEETING_NAME=`echo $LINE|awk -F "," '{print $3}'|sed 's@"@@g'`
        MEETING_ID=`echo $LINE|awk -F "," '{print $4}'|sed 's@/@@g'`
        MEETING_DURATION=`echo $LINE|awk -F "," '{print $5}'`
        export CATEGORY_NAME MEETING_NAME MEETING_ID MEETING_DURATION
        xvfb-run-safe -s "-auth /tmp/xvfb.auth -ac -screen 0 1280x720x24" $BASEDIR/ac_new.rb > /tmp/ac_$MEETING_ID.log 2>&1 &
	sleep 2
done < $ASSET_LIST_FILE

