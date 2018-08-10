#!/bin/bash
if [ $# -lt 1 ]; then
    echo "Usage: $0 </path/to/asset/list/file>"
    exit 1
fi

for UTIL in pidof xvfb-run xvfb-run-safe curl unzip dos2unix; do
    if [ ! -x "`which $UTIL 2> /dev/null`" ]; then
        echo "Need to install $UTIL."
        exit 2
    fi
done

BASEDIR=`dirname $0`
ASSET_LIST_FILE=$1
if [ -z "$MAX_CONCUR_PROCS" ]; then
    MAX_CONCUR_PROCS=7
fi
if [ -x "`which dos2unix 2> /dev/null`" ]; then
    dos2unix $ASSET_LIST_FILE
fi
while IFS=, read -r SCO_ID CATEGORY_NAME MEETING_NAME DESCRIPTION MEETING_ID ORIG_CREATED_AT USER_ID LOGIN USER_NAME DURATION <&3 ;do
    set -o nounset
    CUR_XVFB=`pidof Xvfb | wc -w`
    while [ ! $CUR_XVFB -lt $MAX_CONCUR_PROCS ]; do
        echo "Have $CUR_XVFB running so I'll take a short nap..."
        sleep 60
        CUR_XVFB=`pidof Xvfb | wc -w`
    done
    CATEGORY_NAME=`echo $CATEGORY_NAME | sed 's^"^^g'`
    MEETING_NAME=`echo $MEETING_NAME | sed 's^"^^g'`
    DESCRIPTION=`echo $DESCRIPTION | sed 's^"^^g'`
    export SCO_ID CATEGORY_NAME MEETING_NAME DESCRIPTION MEETING_ID ORIG_CREATED_AT USER_ID DURATION
    nohup sh -c "xvfb-run-safe -s \"-auth /tmp/xvfb.auth -ac -screen 0 1280x720x24\" $BASEDIR/ac_new.rb " > /tmp/ac_$MEETING_ID.log 2>&1 &
    sleep 2
done 3< $ASSET_LIST_FILE
