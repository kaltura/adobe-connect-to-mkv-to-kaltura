#!/bin/bash -
#===============================================================================
#          FILE: ac_setup_debian_ubuntu.sh
#         USAGE: ./ac_setup_debian_ubuntu.sh
#   DESCRIPTION: Installs all needed deps for running the code on Debian/Ubuntu 64bit
#       OPTIONS: Path to base dir as optional first arg [default is /opt]
#  REQUIREMENTS: A modern version of Debian/Ubuntu [tested with Ubuntu 16.04]
#          BUGS: ---
#         NOTES: ---
#        AUTHOR: Jess Portnoy <jess.portnoy@kaltura.com>
#  ORGANIZATION: Kaltura, inc.
#       CREATED: 07/19/2018 04:49:12 PM PDT
#      REVISION:  ---
#===============================================================================

#set -o nounset                              # Treat unset variables as an error

if [ -n "$1" ]; then
    AC_BASE_PREFIX=$1
else
    AC_BASE_PREFIX=/opt
fi

GECKODRIVER_VER=v0.24.0
apt update
apt install -y lsb-release software-properties-common
DISTRO=`lsb_release -s -i`
CODENAME=`lsb_release -c -s`
if [ "$DISTRO" = 'Ubuntu' ]; then
    add-apt-repository "deb http://archive.canonical.com/ubuntu $CODENAME partner"
    add-apt-repository ppa:jonathonf/ffmpeg-4
fi
apt update
apt install -y sysvinit-utils curl unzip firefox adobe-flashplugin ffmpeg ruby ruby-dev libffi-dev xvfb zlib1g-dev libxml2-dev dos2unix build-essential patch wget vorbis-tools pulseaudio-utils pulseaudio
gem install adobe_connect selenium-webdriver kaltura-client test-unit logger
wget https://github.com/mozilla/geckodriver/releases/download/$GECKODRIVER_VER/geckodriver-$GECKODRIVER_VER-linux64.tar.gz -O /tmp/geckodriver-$GECKODRIVER_VER-linux64.tar.gz
tar zxvf /tmp/geckodriver-${GECKODRIVER_VER}-linux64.tar.gz -C /usr/local/bin
wget https://github.com/kaltura/adobe-connect-to-mkv-to-kaltura/archive/master.zip -O /tmp/adobe-connect-to-mkv-to-kaltura.zip
unzip -qoo /tmp/adobe-connect-to-mkv-to-kaltura.zip -d /tmp
mv /tmp/adobe-connect-to-mkv-to-kaltura-master $AC_BASE_PREFIX/adobe-connect-to-mkv-to-kaltura

# or, if you prefer to clone, comment the 2 lines above and uncomment these:
#cd $AC_BASE_PREFIX
#git clone https://github.com/kaltura/adobe-connect-to-mkv-to-kaltura.git
cd $AC_BASE_PREFIX/adobe-connect-to-mkv-to-kaltura
cp xvfb-run-safe /usr/local/bin
cp ac.rc /etc/profile.d/ac.sh
# run the pulseaudio daemon on DISPLAY 1 [never used by ac_wrapper as it starts assigning displayed from 99 and above]
# pulseaudio will be used for recording the audio streams using ffmpeg x11grab in ac_new.rb
Xvfb :1 -screen 0 1280x720x24 &
DISPLAY=:1 pulseaudio --start --disallow-exit -vvv --log-target=newfile:"/var/tmp/mypulseaudio.log"
