# Adobe Connect to Kaltura

## Abstract
This code generates MKV files out of AC recordings and ingests them onto Kaltura.

## General flow
- Download the ZIP archive and concat the audio FLVs into one MP3 using FFmpeg
- Using Selenium and Mozilla's Geckodriver, launch Firefox with Xvfb and navigate to the recording's URL so that it plays using the Adobe SWF
- Use FFmpeg's x11grab option to capture the screen display
- Once done, use FFmpeg's scene detector feature to determine when the recording had actually started [this is needed because their app takes a long time to load and there's no other way to determine how long it actually took]
- Merge the audio and video files and use the Kaltura API to ingest the resulting file

## Pre-requisites
- cURL CLI
- unzip
- xvfb
- Firefox with the Flash plugin loaded [tested with 60.0.1 but other recent versions should work as well]
- Ruby [2.3 and 2.5 were tested]
- Ruby Gems: `adobe_connect`, `selenium-webdriver`, `open3`, `kaltura-client`, `test-unit`, `shellwords`, `logger`
- FFmpeg [with x11grab support, tested with 2.8.14 and 3.4.2 as available by installing Ubuntu's `ffmpeg` package]
- The Mozilla [Geckodriver](https://github.com/mozilla/geckodriver/releases) [tested with v0.20.1]:

## Configuration

### ENV vars
Set the needed values in ac.rc and make sure it is sourced before running the wrapper as the
various scripts rely on the ENV vars it exports. You can just add:
```sh
. /path/to/ac.rc
```
to `~/.bashrc`, `/etc/profile` or place it under `/etc/profile.d`

In the event you'd like to use `ffmpeg` and `ffprobe` binaries from alt locations [i.e: not what's first in PATH], you can export:
```sh
FFMPEG_BIN=/path/to/ffmpeg
FFPROBE_BIN=/path/to/ffprobe
```

### Generate recording input list
`generate_recording_list.rb` can be used to generate a CSV containing the recordings metadata.
It accepts a text file with all the SCO IDs, separated by newlines; i.e one SCO ID per line, makes the needed AC API calls and outputs the data in the following format:
```csv
SCO-ID, SCO-FOLDER-NAME, SCO-NAME, PATH-URL
```

To generate a list of recordings to process, run:
```sh
$ ./generate_recording_list.rb /path/to/sco/ids/file > /path/to/asset/list/csv
```

### Parallel processing
This code is capable of processing multiple recordings concurrently and the only real limitation is HW resources [namely: CPU, RAM].

In order to process several recordings simultaneously, a wrapper around `xvfb-run` is needed. 
`xvfb-run-safe` needs to be placed somewhere in PATH or else, you can change `ac_wrapper.sh` so
that it looks for it elsewhere.
The number of concurrent jobs to run is determined in `ac_wrapper.sh` based on the value of the `MAX_CONCUR_PROCS` ENV var.

### Running
Once ready, run:
```sh
$ ac_wrapper.sh </path/to/asset/list/csv>
``` 

Where `</path/to/asset/list/csv>` is the path to a CSV file in the format described above.



## Output
The resulting KMVs will be placed under `$OUTDIR/$RECORDING_ID.full.mkv`.
Where `$RECORDING_ID` is the relative path for the given recording; i.e: `//sco//url-path` - the last field in the input CSV file.

If the `KALTURA_.*` ENV vars are set, `$OUTDIR/$RECORDING_ID.full.mkv` will then be uploaded to Kaltura.
Full logs are written to `/tmp/ac_$RECORDING_ID.log`. If there's a problem, start by looking there.
