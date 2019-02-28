#!/bin/bash
set -e
if [ $# -lt 1 ]; then
    echo "Usage $0 <recording ID>"
    exit 1
fi
REC_ID=$1
if [ -z "$OUTDIR" ]; then
    OUTDIR=/tmp/ac_output
fi
rm -f $OUTDIR/steam_${REC_ID}.ogg $OUTDIR/steam_${REC_ID}.pid  
OLD_SINK_ID=`pactl list short modules|grep "sink_name=steam_${REC_ID}"|awk -F " " '{print $1}'|xargs` 
if [ -n "$OLD_SINK_ID" ];then
	pactl unload-module $OLD_SINK_ID
fi

LAST_INDEX=`pacmd list-sink-inputs|grep "^\s*index:"|awk -F ": " '{print $2}' |tail -1`
SINK_ID=`pactl load-module module-null-sink sink_name=steam_${REC_ID}`
echo $SINK_ID
pactl move-sink-input $LAST_INDEX steam_${REC_ID}
# uncomment one of these if you wish to debug the audio while Firefox is running
#nohup sh -c "parec -d steam_${REC_ID}.monitor | oggenc -b 192 -o $OUTDIR/steam_${REC_ID}.ogg --raw -" &
#nohup sh -c "parec -d steam_${REC_ID}.monitor | sox -t raw -b 16 -e signed -c 2 -r 44100 - $OUTDIR/steam_${REC_ID}.wav" &
echo $! > $OUTDIR/steam_${REC_ID}.pid
