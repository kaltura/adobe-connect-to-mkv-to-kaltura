#!/bin/bash
set -e
if [ $# -lt 1 ]; then
    echo "Usage $0 <recording ID>"
    exit 1
fi
ID="$1"
TMP=$ID/tmp
if [ -z "$OUTDIR" ]; then
    OUTDIR=/tmp/ac_output
fi
mkdir -p $OUTDIR
cd $OUTDIR
rm -rf $ID
mkdir -p $TMP
COOKIE=`curl -I "$AC_ENDPOINT/api/xml?action=login&login=$AC_USERNAME&password=$AC_PASSWD" | grep "Set-Cookie:" | awk -F " " '{print $2}'`
if [ ! -r $ID.zip ]; then
    curl -q -b "$COOKIE" "$AC_ENDPOINT/$ID/output/$ID.zip?download=zip" > $ID.zip
fi

unzip -o -d $TMP $ID.zip

if ls $TMP/cameraVoip*.flv > /dev/null 2>&1; then
    VOIP=($(ls $TMP/cameraVoip*.flv | sort --version-sort -f))
elif ls $TMP/ftvoice*.flv > /dev/null 2>&1; then
    VOIP=($(ls $TMP/ftvoice*.flv | sort --version-sort -f))
elif ls $TMP/ftstage*.flv > /dev/null 2>&1; then
    VOIP=($(ls $TMP/ftstage*.flv | sort --version-sort -f))
fi

if [ -z "$VOIP" ]; then
    echo "$ID.zip does contains neither cameraVoip*.flv nor ftvoice*.flv files. Exiting:("
    exit 2
fi

for i in "${!VOIP[@]}"; do
    if ffprobe -v error -show_entries stream=codec_type ${VOIP[$i]} | grep -m1 -q audio; then
        FILENAME=$(printf "%0*d" 4 $i)
        ffmpeg -nostdin -i "${VOIP[$i]}" -y $ID/$FILENAME.mp3
    fi
done
rm -f $ID.list
for f in $ID/*.mp3; do echo "file '$PWD/$f'" >> $ID.list; done

OUTPUT_FILE="$OUTDIR/$ID.mp3"
ffmpeg -nostdin -f concat -safe 0 -i $ID.list -c copy -y $OUTPUT_FILE
if [ ! -r $OUTPUT_FILE ]; then
    echo "Failed to generate $OUTPUT_FILE."
    exit 3
fi
echo "Final output saved to $OUTPUT_FILE"
