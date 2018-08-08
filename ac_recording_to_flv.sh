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
COOKIE=$(curl -I "$AC_ENDPOINT/api/xml?action=login&login=$AC_USERNAME&password=$AC_PASSWD" | grep "Set-Cookie:" | awk -F " " '{print $2}')
if [ ! -r $ID.zip ]; then
    curl -q -b "$COOKIE" "$AC_ENDPOINT/$ID/output/$ID.zip?download=zip" > $ID.zip
fi

unzip -o -d $TMP $ID.zip

VOIP=($(ls $TMP/cameraVoip*.flv | sort --version-sort -f))
SCREENSHARE=($(ls $TMP/screenshare*.flv | sort --version-sort -f))

for i in "${!VOIP[@]}"; do
    FILENAME=$(printf "%0*d" 4 $i)
    if [ -n "$SCREENSHARE" ]; then
        ffmpeg -i "${VOIP[$i]}" -i "${SCREENSHARE[$i]}" -vcodec copy -acodec copy -y $ID/$FILENAME.flv
    else
        ffmpeg -i "${VOIP[$i]}" -vcodec copy -acodec copy -y $ID/$FILENAME.flv
    fi
done
rm -f $ID.list
for f in $ID/*.flv; do echo "file '$PWD/$f'" >> $ID.list; done
OUTPUT_FILE=$OUTDIR/$ID.flv
ffmpeg -f concat -safe 0 -i $ID.list -c copy -y $OUTPUT_FILE
echo "Final output saved to $OUTPUT_FILE"
