#!/bin/sh -e
if [ $# -lt 2 ]; then
    echo "Usage: $0 <meeting ID> <entry name>"
    exit 1
fi
BASEDIR=`dirname $0`
MEETING_ID=$1
ENTRY_NAME=$2
echo "1.000000" > $OUTDIR/imgs/scenes3_$MEETING_ID
ffprobe -show_frames -of compact=p=0 -f lavfi "movie=$OUTDIR/$MEETING_ID.final.mkv,select=gt(scene\,0.03) " | sed -r 's/.*pkt_pts_time=([0-9.]{8,})\|.*/\1/' >> $OUTDIR/imgs/scenes3_$MEETING_ID
rm -rf $OUTDIR/imgs/$MEETING_ID $OUTDIR/slides/$MEETING_ID
mkdir -p $OUTDIR/imgs/$MEETING_ID $OUTDIR/slides/$MEETING_ID
I=0
while read SCENE_TIME; do
    echo $OUTDIR/imgs/$MEETING_ID/${I}_${SCENE_TIME}.jpg
    ffmpeg -nostdin -ss "$SCENE_TIME" -i $OUTDIR/$MEETING_ID.full.mkv -vframes 1 -q:v 2 -y $OUTDIR/imgs/$MEETING_ID/${I}_${SCENE_TIME}.jpg 2> /tmp/log
    I=`expr $I + 1`
done < $OUTDIR/imgs/scenes3_$MEETING_ID
#$BASEDIR/get_ac_vid_aud.sh $MEETING_ID
for IMG in $OUTDIR/imgs/$MEETING_ID/*jpg; do
    $BASEDIR/capture_slide $IMG $OUTDIR/slides/$MEETING_ID/`basename $IMG`
done
$BASEDIR/kaltura_process_cue_points.rb $MEETING_ID $OUTDIR/$MEETING_ID.mp3 /tmp/${MEETING_ID}_srchdata.xml $OUTDIR/slides/$MEETING_ID "$ENTRY_NAME"
