#!/bin/bash
set -e
if [ $# -lt 1 ]; then
    echo "Usage $0 <recording ID>"
    exit 1
fi
BASEDIR=$PWD
ID="$1"
TMP=$ID/tmp
if [ -z "$OUTDIR" ]; then
    OUTDIR=/tmp/ac_output
fi
mkdir -p $OUTDIR
OUTPUT_FILE="$OUTDIR/$ID.mp3"
cd $OUTDIR
rm -rf $ID
mkdir -p $TMP
COOKIE=`curl -I "$AC_ENDPOINT/api/xml?action=login&login=$AC_USERNAME&password=$AC_PASSWD" | grep "Set-Cookie:" | awk -F " " '{print $2}'`
if [ ! -r $ID.zip ]; then
    curl -q -b "$COOKIE" "$AC_ENDPOINT/$ID/output/$ID.zip?download=zip" > $ID.zip
fi

unzip -o -d $TMP $ID.zip

if ls $TMP/*.mp3 > /dev/null 2>&1; then
   VOIP=($(ls $TMP/*.mp3 | sort --version-sort -f))
   echo 'Found ready mp3 file. There should only be 1'
   mv ${VOIP[0]} $OUTPUT_FILE
   exit 0;
else
    ITEMS=(cameraVoip*.flv cameraVoip*.mp4 ftvoice*.flv ftstage*.flv)
    for i in "${!ITEMS[@]}"; do
        if ls $TMP/${ITEMS[$i]} > /dev/null 2>&1; then
            LIST=($(ls $TMP/${ITEMS[$i]} | sort --version-sort -f))
        else
            echo 'No items of type ${ITEMS[$i]} found'
            continue
        fi
        for j in "${!LIST[@]}"; do
            if ffprobe -v error -show_entries stream=codec_type ${LIST[$j]} | grep -m1 -q audio; then
                VOIP=($(ls $TMP/${ITEMS[$i]} | sort --version-sort -f))
                break
            fi
        done
    done
fi

if [ -z "$VOIP" ]; then
    echo "$ID.zip does contains no cameraVoip*.flv/cameraVoip*.mp4/ftvoice*.flv/ftstage*.flv files. Exiting:("
    exit 2
fi

rm -f $ID.list
for i in "${!VOIP[@]}"; do
    if ffprobe -v error -show_entries stream=codec_type ${VOIP[$i]} | grep -m1 -q audio; then
        FILE=${VOIP[$i]}
        EXTENSION=${FILE#*.}
        FILENAME=`basename "${FILE%%.*}" .$EXTENSION`

        if [ $EXTENSION != 'mp4' ]; then
            ffmpeg -nostdin -i "${VOIP[$i]}" -y $ID/$FILENAME.mp3
            EXTENSION=mp3
        else
            cp ${VOIP[$i]} $ID/
        fi
        echo "$OUTDIR/$ID/$FILENAME.$EXTENSION" >> $ID.list;
    fi
done

FILTER_COMPLEX=`$BASEDIR/generate_audio_manifest.rb $ID.list`
ID_LIST=`while read LINE;do echo -n " -i $LINE"; done < $ID.list`

OUTPUT_FILE="$OUTDIR/$ID.mp3"
ffmpeg -nostdin $ID_LIST -filter_complex $FILTER_COMPLEX $OUTPUT_FILE
if [ ! -r $OUTPUT_FILE ]; then
    echo "Failed to generate $OUTPUT_FILE."
    exit 3
fi

echo "Final output saved to $OUTPUT_FILE"
