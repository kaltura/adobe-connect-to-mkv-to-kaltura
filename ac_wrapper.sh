#!/bin/bash
if [ $# -lt 1 ]; then
    echo "Usage: $0 </path/to/asset/list/file>"
    exit 1
fi

if [ -z "$OUTDIR" ]; then
    OUTDIR=/tmp/ac_output
fi

for UTIL in pidof xvfb-run xvfb-run-safe curl unzip dos2unix; do
    if [ ! -x "`which $UTIL 2> /dev/null`" ]; then
        echo "Need to install $UTIL."
        exit 2
    fi
done
if ! pulseaudio --check;then 
	Xvfb :1 -screen 0 1280x720x24 2>/dev/null &
	DISPLAY=:1 pulseaudio --start --disallow-exit -vvv --log-target=newfile:"/var/tmp/mypulseaudio.log"
fi

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
    : "${XVFB_LOCKDIR:=$HOME/.xvfb-locks}"
    # since xvfb-run-safe can be used for multiple purposes, it doesn't make sense for it to know what MEETING_ID is as it's specific to this AC code.. so let's assign MEETING_ID to X_SESSION_NAME which is what it can now accept as an ENV var:
    X_SESSION_NAME=$MEETING_ID
    # remove previous locks with that MEETING_ID
    rm -f $XVFB_LOCKDIR/${MEETING_ID}_*
    export SCO_ID CATEGORY_NAME MEETING_NAME DESCRIPTION MEETING_ID ORIG_CREATED_AT USER_ID DURATION X_SESSION_NAME
    nohup sh -c "xvfb-run-safe -s \"-auth /tmp/xvfb.auth -ac -screen 0 1280x720x24\" $BASEDIR/ac_new.rb " > /tmp/ac_$MEETING_ID.log 2>&1 &
    # let's wait until xvfb-run-safe starts the X server
    X_SERVER_DISPLAY_NUM=`ls $XVFB_LOCKDIR/${MEETING_ID}_* 2>/dev/null |awk -F "_" '{print $2}'`
    while [ -z "$X_SERVER_DISPLAY_NUM" ];do
	sleep 1
    	X_SERVER_DISPLAY_NUM=`ls $XVFB_LOCKDIR/${MEETING_ID}_* 2>/dev/null |awk -F "_" '{print $2}'`
    done
    while ! pacmd list-sink-inputs |grep -q "window.x11.display = \":$X_SERVER_DISPLAY_NUM\"" ;do
    	    echo "Recording $MEETING_ID is launching - audio sink will be available shortly."
    	    sleep 2
    done
    $BASEDIR/capture_audio.sh $MEETING_ID
done 3< $ASSET_LIST_FILE
