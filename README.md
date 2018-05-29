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
- pidof [provided by the `sysvinit-utils` package in Debian/Ubuntu and by `sysvinit-tools` in RHEL/CentOS/FC]
- Firefox with the Flash plugin loaded [tested with 60.0.1 but other recent versions should work as well]
- Ruby [2.3 and 2.5 were tested]
- Ruby Gems: `adobe_connect`, `selenium-webdriver`, `open3`, `kaltura-client`, `test-unit`, `shellwords`, `logger`
- FFmpeg [with x11grab support, tested with 2.8.14 and 3.4.2 as available by installing Ubuntu's `ffmpeg` package]
- The Mozilla [Geckodriver](https://github.com/mozilla/geckodriver/releases) [tested with v0.20.1]:

## Configuration

### ENV vars
Set the needed values in `ac.rc` and make sure it is sourced before running the wrapper as the
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

**IMPORTANT NOTE: these vars need to be set GLOBALLY [for the user you intend to run this with, that is]. Setting them in your interactive shell and running `ac_wrapper.sh` will not work. Start a new interactive session and make sure they are set BEFORE running the wrapper.**


### The `AC_LOGIN_REQUIRED` ENV var
If your AC instance does not require the user to login in order to play the recording, you can set the value of `AC_LOGIN_REQUIRED` to false to skip that step.
The code in `ac_new.rb` assumes that the user and passwd text field IDs are `name` and `pwd` respectively and that the submit button ID is `login-button`.
If that's not the case in your AC I/F, you will need to change the code accordingly.

The code further assumes the login URL is:
```ruby
@base_url + "/system/login?logintype=oldstyle&next=/admin"
```

You may need to adjust that as well.

### Generating the recording list to process
`generate_recording_list.rb` can be used to generate a CSV containing the recordings metadata.
It accepts a text file with all the SCO IDs, separated by newlines; i.e one SCO ID per line, makes the needed AC API calls and outputs the data in the following format:
```csv
SCO-ID,SCO-FOLDER-NAME,SCO-NAME,PATH-URL
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

## Running
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


## Contributing
* Use the repository issue tracker to report bugs or submit feature requests
* Read [Contributing Code to the Kaltura Platform](https://github.com/kaltura/platform-install-packages/blob/master/doc/Contributing-to-the-Kaltura-Platform.md)
* Pull requests are very welcome:) Please be sure to sign [Kaltura Contributor License Agreement](https://agentcontribs.kaltura.org/) when submitting them.

## Where to get help
* Join the [Kaltura Community Forums](https://forum.kaltura.org/) to ask questions or start discussions
* Read the [Code of conduct](https://forum.kaltura.org/faq) and be patient and respectful

## Get in touch
You can learn more about Kaltura and start a free trial at: http://corp.kaltura.com    
Contact us via Twitter [@Kaltura](https://twitter.com/Kaltura) or email: community@kaltura.com  
We'd love to hear from you!

## License and Copyright Information
All code in this project is released under the [AGPLv3 license](http://www.gnu.org/licenses/agpl-3.0.html) unless a different license for a particular library is specified in the applicable library path.   

Copyright © Kaltura Inc. All rights reserved.   
Authors and contributors: See [GitHub contributors list](https://github.com/kaltura/adobe-connect-to-mkv-to-kaltura/graphs/contributors).  
