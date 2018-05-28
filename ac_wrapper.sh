#!/bin/bash
if [ $# -lt 1 ];then
        echo "Usage: $0 </path/to/asset/list/file>"
        exit 1
fi
BASEDIR=`dirname $0`
ASSET_LIST_FILE=$1
if [ -z "$MAX_CONCUR_PROCS" ];then
    MAX_CONCUR_PROCS=7
fi
while read LINE ;do
        CUR_XVFV=`ps fax|grep Xvfb|grep -v grep -c`
        while [ $CUR_XVFV -gt $MAX_CONCUR_PROCS ];do
                echo "Have $CUR_XVFV running so I'll sleep a bit"
                sleep 60
                CUR_XVFV=`ps fax|grep Xvfb|grep -v grep -c`
        done
        CATEGORY_NAME=`echo $LINE|awk -F "," '{print $2}'|sed 's@"@@g'`
        MEETING_NAME=`echo $LINE|awk -F "," '{print $3}'|sed 's@"@@g'`
        MEETING_ID=`echo $LINE|awk -F "," '{print $4}'|sed 's@/@@g'`
        MEETING_DURATION=`echo $LINE|awk -F "," '{print $5}'`
        export CATEGORY_NAME MEETING_NAME MEETING_ID MEETING_DURATION
        nohup sh -c "$BASEDIR/get_ac_audio.sh $MEETING_ID && xvfb-run-safe -s \"-auth /tmp/xvfb.auth -ac -screen 0 1280x720x24\" $BASEDIR/ac_new.rb " > /tmp/ac_$MEETING_ID.log 2>&1 &
done < $ASSET_LIST_FILE

