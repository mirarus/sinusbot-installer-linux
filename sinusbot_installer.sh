#!/bin/bash
# SinusBot installer by Philipp Eßwein - DAThosting.eu philipp.esswein@dathosting.eu

# Vars

MACHINE=$(uname -m)
Instversion="1.6"

USE_SYSTEMD=true

# Functions

function greenMessage() {
  echo -e "\\033[32;1m${*}\\033[0m"
}

function magentaMessage() {
  echo -e "\\033[35;1m${*}\\033[0m"
}

function cyanMessage() {
  echo -e "\\033[36;1m${*}\\033[0m"
}

function redMessage() {
  echo -e "\\033[31;1m${*}\\033[0m"
}

function yellowMessage() {
  echo -e "\\033[33;1m${*}\\033[0m"
}

function errorQuit() {
  errorExit 'Exit now!'
}

function errorExit() {
  redMessage "${@}"
  exit 1
}

function errorContinue() {
  redMessage "Invalid option."
  return
}

function makeDir() {
  if [ -n "$1" ] && [ ! -d "$1" ]; then
    mkdir -p "$1"
  fi
}

err_report() {
  FAILED_COMMAND=$(wget -q -O - https://raw.githubusercontent.com/mirarus/sinusbot-installer-linux/master/sinusbot_installer.sh | sed -e "$1q;d")
  FAILED_COMMAND=${FAILED_COMMAND/ -qq}
  FAILED_COMMAND=${FAILED_COMMAND/ -q}
  FAILED_COMMAND=${FAILED_COMMAND/ -s}
  FAILED_COMMAND=${FAILED_COMMAND/ 2\>\/dev\/null\/}
  FAILED_COMMAND=${FAILED_COMMAND/ 2\>&1}
  FAILED_COMMAND=${FAILED_COMMAND/ \>\/dev\/null}
  if [[ "$FAILED_COMMAND" == "" ]]; then
    redMessage "Failed command: https://github.com/mirarus/sinusbot-installer-linux/blob/master/sinusbot_installer.sh#L""$1"
  else
    redMessage "Command which failed was: \"${FAILED_COMMAND}\". Please try to exfecute it manually and attach the output to the bug report in the forum thread."
  fi
  exit 1
}

trap 'err_report $LINENO' ERR

# Check if the script was run as root user. Otherwise exit the script
if [ "$(id -u)" != "0" ]; then
  errorExit "Change to root account required!"
fi

# Update notify

redMessage "Checking for the latest installer version"
if [[ -f /etc/centos-release ]]; then
  yum -y -q install wget
else
  apt-get -qq install wget -y
fi

# Detect if systemctl is available then use systemd as start script. Otherwise use init.d
if [[ $(command -v systemctl) == "" ]]; then
  USE_SYSTEMD=false
fi

# If the linux distribution is not debian and centos, then exit
if [ ! -f /etc/debian_version ] && [ ! -f /etc/centos-release ]; then
  errorExit "Not supported linux distribution. Only Debian and CentOS are currently supported"!
fi

cyanMessage "Installer by Mirarus"
sleep 1
yellowMessage "You're using installer $Instversion"

# selection menu if the installer should install, update, remove or pw reset the SinusBot
redMessage "What should the installer do?"
OPTIONS=("Install" "Update" "Remove" "PW Reset" "Quit")
select OPTION in "${OPTIONS[@]}"; do
  case "$REPLY" in
  1 | 2 | 3 | 4) break ;;
  5) errorQuit ;;
  *) errorContinue ;;
  esac
done

if [ "$OPTION" == "Install" ]; then
  INSTALL="Inst"
elif [ "$OPTION" == "Update" ]; then
  INSTALL="Updt"
elif [ "$OPTION" == "Remove" ]; then
  INSTALL="Rem"
elif [ "$OPTION" == "PW Reset" ]; then
  INSTALL="Res"
fi

# PW Reset

if [[ $INSTALL == "Res" ]]; then

  LOCATION=/opt/sinusbot
  LOCATIONex=$LOCATION/sinusbot

  if [[ ! -f $LOCATION/sinusbot ]]; then
    errorExit "SinusBot wasn't found at $LOCATION. Exiting script."
  fi

  PW=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 8 | head -n 1)
  SINUSBOTUSER=$(ls -ld $LOCATION | awk '{print $3}')

  greenMessage "Please login to your SinusBot webinterface as admin and '$PW'"
  yellowMessage "After that change your password under Settings->User Accounts->admin->Edit. The script restart the bot with init.d or systemd."

  if [[ -f /lib/systemd/system/sinusbot.service ]]; then
    if [[ $(systemctl is-active sinusbot >/dev/null && echo UP || echo DOWN) == "UP" ]]; then
      service sinusbot stop
    fi
  elif [[ -f /etc/init.d/sinusbot ]]; then
    if [ "$(/etc/init.d/sinusbot status | awk '{print $NF; exit}')" == "UP" ]; then
      /etc/init.d/sinusbot stop
    fi
  fi

  log="/tmp/sinusbot.log"
  match="USER-PATCH [admin] (admin) OK"

  su -c "$LOCATIONex --override-password $PW" $SINUSBOTUSER >"$log" 2>&1 &
  sleep 3

  while true; do
    echo -ne '(Waiting for password change!)\r'

    if grep -Fq "$match" "$log"; then
      pkill -INT -f $PW
      rm $log

      greenMessage "Successfully changed your admin password."

      if [[ -f /lib/systemd/system/sinusbot.service ]]; then
        service sinusbot start
        greenMessage "Started your bot with systemd."
      elif [[ -f /etc/init.d/sinusbot ]]; then
        /etc/init.d/sinusbot start
        greenMessage "Started your bot with initd."
      else
        redMessage "Please start your bot normally"!
      fi
      exit 0
    fi
  done

fi

# Check which OS

if [ "$INSTALL" != "Rem" ]; then

  if [[ -f /etc/centos-release ]]; then
    greenMessage "Installing redhat-lsb! Please wait."
    yum -y -q install redhat-lsb
    greenMessage "Done"!

    yellowMessage "You're running CentOS. Which firewallsystem are you using?"

    OPTIONS=("IPtables" "Firewalld")
    select OPTION in "${OPTIONS[@]}"; do
      case "$REPLY" in
      1 | 2) break ;;
      *) errorContinue ;;
      esac
    done

    if [ "$OPTION" == "IPtables" ]; then
      FIREWALL="ip"
    elif [ "$OPTION" == "Firewalld" ]; then
      FIREWALL="fd"
    fi
  fi

  if [[ -f /etc/debian_version ]]; then
    greenMessage "Check if lsb-release and debconf-utils is installed..."
    apt-get -qq update
    apt-get -qq install debconf-utils -y
    apt-get -qq install lsb-release -y
    greenMessage "Done"!
  fi

  # Functions from lsb_release

  OS=$(lsb_release -i 2>/dev/null | grep 'Distributor' | awk '{print tolower($3)}')
  OSBRANCH=$(lsb_release -c 2>/dev/null | grep 'Codename' | awk '{print $2}')
  OSRELEASE=$(lsb_release -r 2>/dev/null | grep 'Release' | awk '{print $2}')
  VIRTUALIZATION_TYPE=""

  # Extracted from the virt-what sourcecode: http://git.annexia.org/?p=virt-what.git;a=blob_plain;f=virt-what.in;hb=HEAD
  if [[ -f "/.dockerinit" ]]; then
    VIRTUALIZATION_TYPE="docker"
  fi
  if [ -d "/proc/vz" -a ! -d "/proc/bc" ]; then
    VIRTUALIZATION_TYPE="openvz"
  fi

  if [[ $VIRTUALIZATION_TYPE == "openvz" ]]; then
    redMessage "Warning, your server is running OpenVZ! This very old container system isn't well supported by newer packages."
  elif [[ $VIRTUALIZATION_TYPE == "docker" ]]; then
    redMessage "Warning, your server is running Docker! Maybe there are failures while installing."
  fi

fi

# Go on

if [ "$INSTALL" != "Rem" ]; then
  if [ -z "$OS" ]; then
    errorExit "Error: Could not detect OS. Currently only Debian, Ubuntu and CentOS are supported. Aborting"!
  elif [ -z "$OS" ] && ([ "$(cat /etc/debian_version | awk '{print $1}')" == "7" ] || [ $(cat /etc/debian_version | grep "7.") ]); then
    errorExit "Debian 7 isn't supported anymore"!
  fi

  if [ -z "$OSBRANCH" ] && [ -f /etc/centos-release ]; then
    errorExit "Error: Could not detect branch of OS. Aborting"
  fi

  if [ "$MACHINE" == "x86_64" ]; then
    ARCH="amd64"
  else
    errorExit "$MACHINE is not supported"!
  fi
fi

if [[ "$INSTALL" != "Rem" ]]; then
  if [[ "$USE_SYSTEMD" == true ]]; then
    yellowMessage "Automatically chosen system.d for your startscript"!
  else
    yellowMessage "Automatically chosen init.d for your startscript"!
  fi
fi

LOCATION=/opt/sinusbot
makeDir $LOCATION
LOCATIONex=$LOCATION/sinusbot

if [[ $INSTALL == "Inst" ]]; then

  if [[ -f $LOCATION/sinusbot ]]; then
      INSTALL="Updt"
  else
    greenMessage "SinusBot isn't installed yet. Installer goes on."
  fi

elif [ "$INSTALL" == "Rem" ] || [ "$INSTALL" == "Updt" ]; then
  if [ ! -d $LOCATION ]; then
    errorExit "SinusBot isn't installed"!
  else
    greenMessage "SinusBot is installed. Installer goes on."
  fi
fi

# Remove SinusBot

if [ "$INSTALL" == "Rem" ]; then

  SINUSBOTUSER=$(ls -ld $LOCATION | awk '{print $3}')

  if [[ -f /usr/local/bin/yt-dlp ]]; then
      if [[ -f /usr/local/bin/yt-dlp ]]; then
        rm /usr/local/bin/yt-dlp
      fi

      if [[ -f /etc/cron.d/ytdlp ]]; then
        rm /etc/cron.d/ytdlp
      fi
      greenMessage "Removed YT-DLP successfully"!
  fi

  if [[ -z $SINUSBOTUSER ]]; then
    errorExit "No SinusBot found. Exiting now."
  fi

  redMessage "SinusBot will now be removed completely from your system"!

  greenMessage "Your SinusBot user is \"$SINUSBOTUSER\"? The directory which will be removed is \"$LOCATION\". After select Yes it could take a while."

  OPTIONS=("Yes" "No")
  select OPTION in "${OPTIONS[@]}"; do
    case "$REPLY" in
    1) break ;;
    2) errorQuit ;;
    *) errorContinue ;;
    esac
  done

  if [ "$(ps ax | grep sinusbot | grep SCREEN)" ]; then
    ps ax | grep sinusbot | grep SCREEN | awk '{print $1}' | while read PID; do
      kill $PID
    done
  fi

  if [ "$(ps ax | grep ts3bot | grep SCREEN)" ]; then
    ps ax | grep ts3bot | grep SCREEN | awk '{print $1}' | while read PID; do
      kill $PID
    done
  fi

  if [[ -f /lib/systemd/system/sinusbot.service ]]; then
    if [[ $(systemctl is-active sinusbot >/dev/null && echo UP || echo DOWN) == "UP" ]]; then
      service sinusbot stop
      systemctl disable sinusbot
    fi
    rm /lib/systemd/system/sinusbot.service
  elif [[ -f /etc/init.d/sinusbot ]]; then
    if [ "$(/etc/init.d/sinusbot status | awk '{print $NF; exit}')" == "UP" ]; then
      su -c "/etc/init.d/sinusbot stop" $SINUSBOTUSER
      su -c "screen -wipe" $SINUSBOTUSER
      update-rc.d -f sinusbot remove >/dev/null
    fi
    rm /etc/init.d/sinusbot
  fi

  if [[ -f /etc/cron.d/sinusbot ]]; then
    rm /etc/cron.d/sinusbot
  fi

  if [ "$LOCATION" ]; then
    rm -R $LOCATION >/dev/null
    greenMessage "Files removed successfully"!
  else
    redMessage "Error while removing files."
  fi

  if [[ $SINUSBOTUSER != "root" ]]; then
    redMessage "Remove user \"$SINUSBOTUSER\"? (User will be removed from your system)"

    OPTIONS=("Yes" "No")
    select OPTION in "${OPTIONS[@]}"; do
      case "$REPLY" in
      1 | 2) break ;;
      *) errorContinue ;;
      esac
    done

    if [ "$OPTION" == "Yes" ]; then
      userdel -r -f $SINUSBOTUSER >/dev/null

      if [ "$(id $SINUSBOTUSER 2>/dev/null)" == "" ]; then
        greenMessage "User removed successfully"!
      else
        redMessage "Error while removing user"!
      fi
    fi
  fi

  greenMessage "SinusBot removed completely including all directories."

  exit 0
fi

  greenMessage "Updating the system in a few seconds"!
  sleep 1
  redMessage "This could take a while. Please wait up to 10 minutes"!
  sleep 3

  if [[ -f /etc/centos-release ]]; then
    yum -y -q update
    yum -y -q upgrade
  else
    apt-get -qq update
    apt-get -qq upgrade
  fi

# TeamSpeak3-Client latest check

  greenMessage "Searching latest TS3-Client build for hardware type $MACHINE with arch $ARCH."

  VERSION="3.5.3"

  DOWNLOAD_URL_VERSION="https://files.teamspeak-services.com/releases/client/$VERSION/TeamSpeak3-Client-linux_$ARCH-$VERSION.run"
  STATUS=$(wget --server-response -L $DOWNLOAD_URL_VERSION 2>&1 | awk '/^  HTTP/{print $2}')
    if [ "$STATUS" == "200" ]; then
      DOWNLOAD_URL=$DOWNLOAD_URL_VERSION
    fi

  if [ "$STATUS" == "200" -a "$DOWNLOAD_URL" != "" ]; then
    greenMessage "Detected latest TS3-Client version as $VERSION"
  else
    errorExit "Could not detect latest TS3-Client version"
  fi

  # Install necessary aptitudes for sinusbot.

  magentaMessage "Installing necessary packages. Please wait..."

  if [[ -f /etc/centos-release ]]; then
    yum -y -q install screen xvfb libxcursor1 ca-certificates bzip2 psmisc libglib2.0-0 less cron-apt ntp python python3 iproute which dbus libnss3 libegl1-mesa x11-xkb-utils libasound2 libxcomposite-dev libxi6 libpci3 libxslt1.1 libxkbcommon0 libxss1 >/dev/null
    update-ca-trust extract >/dev/null
  else
    # Detect if systemctl is available then use systemd as start script. Otherwise use init.d
    if [ "$OSRELEASE" == "18.04" ] && [ "$OS" == "ubuntu" ]; then
      apt-get -y install chrony >/dev/null
    else
      apt-get -y install ntp >/dev/null
    fi
    apt-get -y -qq install libfontconfig libxtst6 screen xvfb libxcursor1 ca-certificates bzip2 psmisc libglib2.0-0 less cron-apt python python3 iproute2 dbus libnss3 libegl1-mesa x11-xkb-utils libasound2 libxcomposite-dev libxi6 libpci3 libxslt1.1 libxkbcommon0 libxss1 >/dev/null
    update-ca-certificates >/dev/null
  fi

greenMessage "Packages installed"!

# Setting server time

if [[ $VIRTUALIZATION_TYPE == "openvz" ]]; then
  redMessage "You're using OpenVZ virtualization. You can't set your time, maybe it works but there is no guarantee. Skipping this part..."
else
  if [[ -f /etc/centos-release ]] || [ $(cat /etc/*release | grep "DISTRIB_ID=" | sed 's/DISTRIB_ID=//g') ]; then
    if [ "$OSRELEASE" == "18.04" ] && [ "$OS" == "ubuntu" ]; then
      systemctl start chronyd
      if [[ $(chronyc -a 'burst 4/4') == "200 OK" ]]; then
        TIME=$(date)
      else
        errorExit "Error while setting time via chrony"!
      fi
    else
      if [[ -f /etc/centos-release ]]; then
       service ntpd stop
      else
       service ntp stop
      fi
      ntpd -s 0.pool.ntp.org
      if [[ -f /etc/centos-release ]]; then
       service ntpd start
      else
       service ntp start
      fi
      TIME=$(date)
    fi
    greenMessage "Automatically set time to" $TIME!
  else
    if [[ $(command -v timedatectl) != "" ]]; then
      service ntp restart
      timedatectl set-ntp yes
      timedatectl
      TIME=$(date)
      greenMessage "Automatically set time to" $TIME!
    else
      redMessage "Unable to configure your date automatically, the installation will still be attempted."
    fi
  fi
fi

USERADD=$(which useradd)
GROUPADD=$(which groupadd)
ipaddress=$(ip route get 8.8.8.8 | awk {'print $7'} | tr -d '\n')

# Create/check user for sinusbot.

if [ "$INSTALL" == "Updt" ]; then
  SINUSBOTUSER=$(ls -ld $LOCATION | awk '{print $3}')
  sed -i "s|TS3Path = \"\"|TS3Path = \"$LOCATION/teamspeak3-client/ts3client_linux_amd64\"|g" $LOCATION/config.ini && greenMessage "Added TS3 Path to config." || redMessage "Error while updating config"
else
  SINUSBOTUSER=sinusbot

  if [ "$(id $SINUSBOTUSER 2>/dev/null)" == "" ]; then
    if [ -d /home/$SINUSBOTUSER ]; then
      $GROUPADD $SINUSBOTUSER
      $USERADD -d /home/$SINUSBOTUSER -s /bin/bash -g $SINUSBOTUSER $SINUSBOTUSER
    else
      $GROUPADD $SINUSBOTUSER
      $USERADD -m -b /home -s /bin/bash -g $SINUSBOTUSER $SINUSBOTUSER
    fi
  else
    greenMessage "User \"$SINUSBOTUSER\" already exists."
  fi

chmod 750 -R $LOCATION
chown -R $SINUSBOTUSER:$SINUSBOTUSER $LOCATION

fi

# Create dirs or remove them.

ps -u $SINUSBOTUSER | grep ts3client | awk '{print $1}' | while read PID; do
  kill $PID
done
if [[ -f $LOCATION/ts3client_startscript.run ]]; then
  rm -rf $LOCATION/*
fi

  makeDir $LOCATION/teamspeak3-client

  chmod 750 -R $LOCATION
  chown -R $SINUSBOTUSER:$SINUSBOTUSER $LOCATION
  cd $LOCATION/teamspeak3-client

  # Downloading TS3-Client files.

  if [[ -f CHANGELOG ]] && [ $(cat CHANGELOG | awk '/Client Release/{ print $4; exit }') == $VERSION ]; then
    greenMessage "TS3 already latest version."
  else

    greenMessage "Downloading TS3 client files."
    su -c "wget -q $DOWNLOAD_URL" $SINUSBOTUSER

    if [[ ! -f TeamSpeak3-Client-linux_$ARCH-$VERSION.run && ! -f ts3client_linux_$ARCH ]]; then
      errorExit "Download failed! Exiting now"!
    fi
  fi

  # Installing TS3-Client.

  if [[ -f TeamSpeak3-Client-linux_$ARCH-$VERSION.run ]]; then
    greenMessage "Installing the TS3 client."
    redMessage "Read the eula"!
    sleep 1
    yellowMessage 'Do the following: Press "ENTER" then press "q" after that press "y" and accept it with another "ENTER".'
    sleep 2

    chmod 777 ./TeamSpeak3-Client-linux_$ARCH-$VERSION.run

    su -c "./TeamSpeak3-Client-linux_$ARCH-$VERSION.run" $SINUSBOTUSER

    cp -R ./TeamSpeak3-Client-linux_$ARCH/* ./
    sleep 2
    rm ./ts3client_runscript.sh
    rm ./TeamSpeak3-Client-linux_$ARCH-$VERSION.run
    rm -R ./TeamSpeak3-Client-linux_$ARCH

    greenMessage "TS3 client install done."
fi

# Downloading latest SinusBot.

cd $LOCATION

greenMessage "Downloading latest SinusBot."

su -c "wget -q https://www.sinusbot.com/dl/sinusbot.current.tar.bz2" $SINUSBOTUSER
if [[ ! -f sinusbot.current.tar.bz2 && ! -f sinusbot ]]; then
  errorExit "Download failed! Exiting now"!
fi

# Installing latest SinusBot.

greenMessage "Extracting SinusBot files."
su -c "tar -xjf sinusbot.current.tar.bz2" $SINUSBOTUSER
rm -f sinusbot.current.tar.bz2

if [ ! -d teamspeak3-client/plugins/ ]; then
  mkdir teamspeak3-client/plugins/
fi

# Copy the SinusBot plugin into the teamspeak clients plugin directory
cp $LOCATION/plugin/libsoundbot_plugin.so $LOCATION/teamspeak3-client/plugins/

if [[ -f teamspeak3-client/xcbglintegrations/libqxcb-glx-integration.so ]]; then
  rm teamspeak3-client/xcbglintegrations/libqxcb-glx-integration.so
fi

chmod 755 sinusbot

if [ "$INSTALL" == "Inst" ]; then
  greenMessage "SinusBot installation done."
elif [ "$INSTALL" == "Updt" ]; then
  greenMessage "SinusBot update done."
fi

if [[ "$USE_SYSTEMD" == true ]]; then

  greenMessage "Starting systemd installation"

  if [[ -f /etc/systemd/system/sinusbot.service ]]; then
    service sinusbot stop
    systemctl disable sinusbot
    rm /etc/systemd/system/sinusbot.service
  fi

  cd /lib/systemd/system/

  wget -q https://raw.githubusercontent.com/Sinusbot/linux-startscript/master/sinusbot.service

  if [ ! -f sinusbot.service ]; then
    errorExit "Download failed! Exiting now"!
  fi

  sed -i 's/User=YOUR_USER/User='$SINUSBOTUSER'/g' /lib/systemd/system/sinusbot.service
  sed -i 's!ExecStart=YOURPATH_TO_THE_BOT_BINARY!ExecStart='$LOCATIONex'!g' /lib/systemd/system/sinusbot.service
  sed -i 's!WorkingDirectory=YOURPATH_TO_THE_BOT_DIRECTORY!WorkingDirectory='$LOCATION'!g' /lib/systemd/system/sinusbot.service

  systemctl daemon-reload
  systemctl enable sinusbot.service

  cyanMessage 'Installed systemd file to start the SinusBot with "service sinusbot {start|stop|status|restart}"'

elif [[ "$USE_SYSTEMD" == false ]]; then

  greenMessage "Starting init.d installation"

  cd /etc/init.d/

  wget -q https://raw.githubusercontent.com/Sinusbot/linux-startscript/obsolete-init.d/sinusbot

  if [ ! -f sinusbot ]; then
    errorExit "Download failed! Exiting now"!
  fi

  sed -i 's/USER="mybotuser"/USER="'$SINUSBOTUSER'"/g' /etc/init.d/sinusbot
  sed -i 's!DIR_ROOT="/opt/ts3soundboard/"!DIR_ROOT="'$LOCATION'/"!g' /etc/init.d/sinusbot

  chmod +x /etc/init.d/sinusbot

  if [[ -f /etc/centos-release ]]; then
    chkconfig sinusbot on >/dev/null
  else
    update-rc.d sinusbot defaults >/dev/null
  fi

  greenMessage 'Installed init.d file to start the SinusBot with "/etc/init.d/sinusbot {start|stop|status|restart|console|update|backup}"'
fi

cd $LOCATION

if [ "$INSTALL" == "Inst" ]; then
    if [[ ! -f $LOCATION/config.ini ]]; then
      echo 'ListenPort = 8087
      ListenHost = "0.0.0.0"
      TS3Path = "'$LOCATION'/teamspeak3-client/ts3client_linux_amd64"
      YoutubeDLPath = ""' >>$LOCATION/config.ini
      greenMessage "config.ini created successfully."
    else
      redMessage "config.ini already exists or creation error"!
    fi
fi

#if [[ -f /etc/cron.d/sinusbot ]]; then
#  redMessage "Cronjob already set for SinusBot updater"!
#else
#  greenMessage "Installing Cronjob for automatic SinusBot update..."
#  echo "0 0 * * * $SINUSBOTUSER $LOCATION/sinusbot -update >/dev/null" >>/etc/cron.d/sinusbot
#  greenMessage "Installing SinusBot update cronjob successful."
#fi

# Installing YT-DLP.
  greenMessage "Installing YT-Downloader now"!
  if [ "$(cat /etc/cron.d/ytdlp)" == "0 0 * * * $SINUSBOTUSER yt-dlp -U --restrict-filename >/dev/null" ]; then
        rm /etc/cron.d/ytdlp
        yellowMessage "Deleted old YT-DLP cronjob. Generating new one in a second."
  fi
  if [[ -f /etc/cron.d/ytdlp ]] && [ "$(grep -c 'youtube' /etc/cron.d/ytdlp)" -ge 1 ]; then
    redMessage "Cronjob already set for YT-DLP updater"!
  else
    greenMessage "Installing Cronjob for automatic YT-DLP update..."
    echo "0 0 * * * $SINUSBOTUSER PATH=$PATH:/usr/local/bin; yt-dlp -U --restrict-filename >/dev/null" >>/etc/cron.d/ytdlp
    greenMessage "Installing Cronjob successful."
  fi

  sed -i 's/YoutubeDLPath = \"\"/YoutubeDLPath = \"\/usr\/local\/bin\/yt-dlp\"/g' $LOCATION/config.ini

  if [[ -f /usr/local/bin/yt-dlp ]]; then
    rm /usr/local/bin/yt-dlp
  fi

  greenMessage "Downloading YT-DLP now..."
  wget -q -O /usr/local/bin/yt-dlp https://github.com/yt-dlp/yt-dlp/releases/download/2022.08.08/yt-dlp

  if [ ! -f /usr/local/bin/yt-dlp ]; then
    errorExit "Download failed! Exiting now"!
  else
    greenMessage "Download successful"!
  fi

  chmod a+rx /usr/local/bin/yt-dlp

  #yt-dlp -U --restrict-filename

# Delete files if exists

if [[ -f /tmp/.sinusbot.lock ]]; then
  rm /tmp/.sinusbot.lock
  greenMessage "Deleted /tmp/.sinusbot.lock"
fi

if [ -e /tmp/.X11-unix/X40 ]; then
  rm /tmp/.X11-unix/X40
  greenMessage "Deleted /tmp/.X11-unix/X40"
fi

# Starting SinusBot first time!

if [ "$INSTALL" != "Updt" ]; then
  greenMessage 'Starting the SinusBot. For first time.'
  chown -R $SINUSBOTUSER:$SINUSBOTUSER $LOCATION
  cd $LOCATION

  # Password variable

  export Q=$(su $SINUSBOTUSER -c './sinusbot --initonly')
  password=$(export | awk '/password/{ print $10 }' | tr -d "'")
  if [ -z "$password" ]; then
    errorExit "Failed to read password, try a reinstall again."
  fi

  chown -R $SINUSBOTUSER:$SINUSBOTUSER $LOCATION

  # Starting bot
  greenMessage "Starting SinusBot again."
fi

if [[ "$USE_SYSTEMD" == true ]]; then
  service sinusbot start
elif [[ "$USE_SYSTEMD" == false ]]; then
  /etc/init.d/sinusbot start
fi
yellowMessage "Please wait... This will take some seconds"!
chown -R $SINUSBOTUSER:$SINUSBOTUSER $LOCATION

if [[ "$USE_SYSTEMD" == true ]]; then
  sleep 5
elif [[ "$USE_SYSTEMD" == false ]]; then
  sleep 10
fi

if [[ -f /etc/centos-release ]]; then
  if [ "$FIREWALL" == "ip" ]; then
    iptables -A INPUT -p tcp -m state --state NEW -m tcp --dport 8087 -j ACCEPT
  elif [ "$FIREWALL" == "fs" ]; then
    if rpm -q --quiet firewalld; then
      zone=$(firewall-cmd --get-active-zones | awk '{print $1; exit}')
      firewall-cmd --zone=$zone --add-port=8087/tcp --permanent >/dev/null
      firewall-cmd --reload >/dev/null
    fi
  fi
fi

# If startup failed, the script will start normal sinusbot without screen for looking about errors. If startup successed => installation done.
IS_RUNNING=false
if [[ "$USE_SYSTEMD" == true ]]; then
  if [[ $(systemctl is-active sinusbot >/dev/null && echo UP || echo DOWN) == "UP" ]]; then
    IS_RUNNING=true
  fi
elif [[ "$USE_SYSTEMD" == false ]]; then
  if [[ $(/etc/init.d/sinusbot status | awk '{print $NF; exit}') == "UP" ]]; then
     IS_RUNNING=true
  fi
fi

if [[ "$IS_RUNNING" == true ]]; then
  if [[ $INSTALL == "Inst" ]]; then
    greenMessage "Install done"!
  elif [[ $INSTALL == "Updt" ]]; then
    greenMessage "Update done"!
  fi

  if [[ $INSTALL == "Updt" ]]; then
    if [[ -f /lib/systemd/system/sinusbot.service ]]; then
      service sinusbot restart
      greenMessage "Restarted your bot with systemd."
    fi
    if [[ -f /etc/init.d/sinusbot ]]; then
      /etc/init.d/sinusbot restart
      greenMessage "Restarted your bot with initd."
    fi
    greenMessage "All right. Everything is updated successfully. SinusBot is UP on '$ipaddress:8087' :)"
  else
    greenMessage "All right. Everything is installed successfully. SinusBot is UP on '$ipaddress:8087' :) Your user = 'admin' and password = '$password'"
  fi
  if [[ "$USE_SYSTEMD" == true ]]; then
    redMessage 'Stop it with "service sinusbot stop".'
  elif [[ "$USE_SYSTEMD" == false ]]; then
    redMessage 'Stop it with "/etc/init.d/sinusbot stop".'
  fi
  greenMessage "Thank you for using this script! :)"

else
  redMessage "SinusBot could not start! Starting it directly. Look for errors"!
  su -c "$LOCATION/sinusbot" $SINUSBOTUSER
fi

exit 0
