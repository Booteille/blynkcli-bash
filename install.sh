#!/usr/bin/env bash

set -euo pipefail # Unofficial Bash Strict Mode
IFS=$'\n\t'       # http://redsymbol.net/articles/unofficial-bash-strict-mode/

#/  Blynk CLI
#/
#/  Description: A short utility to manage Blynk server from CLI
#/
#/ Usage:
#/    Type `blinkcli` to show this help message.
#/
#/ Examples:
#/    blynkcli server install   # install the latest release of blynk server
#/    blynkcli server start     # start the server
#/    blynkcli server status    # check status of the server
#/    blynkcli server stop      # stop the server
#/
#/    blynkcli server backup my-backup-name                       # make a backup of the server
#/    blynkcli server restore my-backup-name_2017-05-01_00-30-28  # restore from backup
#/
#/ Options:
#/    remove          - uninstall blynkcli
#/
#/    setup           - install blynkcli
#/
#/    self-update     - check if an update is available for Blynk CLI
#/
#/    version         - print version of blynkcli
#/
#/    server [OPTION]
#/        install               - install latest blynk server release
#/
#/        uninstall             - uninstall blynk server
#/
#/        start                 - start blynk server
#/
#/        stop                  - stop blynk server
#/
#/        restart               - restart blynk server
#/
#/        status                - print whether the server is online or offline
#/
#/        update                - update the server to latest release available
#/
#/        backup                - make a backup of blynk server's data folder
#/
#/        restore [BACKUP]      - restore blynk server's data folder from backup
#/
usage() { grep '^#/' "$0" | cut -c4- ; exit 0 ; }

DATETIME=$(date +"%d %h %Y %H:%M:%S")

BLYNKCLI_VERSION="v0.2.1"
BLYNKCLI_EXECUTABLE="/usr/bin/blynkcli"
BLYNK_JAR=""
BLYNK_FOLDER="/var/blynk"
BLYNK_DATA="$BLYNK_FOLDER/data"
BLYNK_BACKUP_FOLDER="$BLYNK_FOLDER/backup"
BLYNK_SERVER_CONFIG="$BLYNK_FOLDER/server.properties"
BLYNK_PID_PATH="/run/blynk.pid"

readonly LOG_FILE="/tmp/$(basename "$0").log"
info()    { echo -e "\e[32m[INFO]\e[0m    $DATETIME - $*" | tee -a "$LOG_FILE" >&2 ; }
warning() { echo -e "\e[33m[WARNING]\e[0m $DATETIME - $*" | tee -a "$LOG_FILE" >&2 ; }
error()   { echo -e "\e[31m[ERROR]\e[0m   $DATETIME - $*" | tee -a "$LOG_FILE" >&2 ; }
fatal()   { echo -e "\e[1;31m[FATAL]\e[0m $DATETIME - $*" | tee -a "$LOG_FILE" >&2 ; exit 1 ; }


if [[ "${BASH_SOURCE[0]}" = "$0" ]]; then
  if [[ "$0" != "$BLYNKCLI_EXECUTABLE" ]]; then
    if which blynkcli >> /dev/null; then
      blynkcli self-update
    else
      info "Installing Blynk CLI"
      sudo cp "$0" $BLYNKCLI_EXECUTABLE

      info "Installation complete"
      info "Use \`blynkcli\` to get help."
    fi
  else
    if [[ -z ${1+x} ]]; then
      usage
    else
      if [[ $1 == "server" ]]; then
        if [[ -z ${2+x} ]]; then
          usage
        else
          if [[ $2 == "install" ]]; then
            if [[ ! -f $BLYNK_JAR ]]; then
              info "Installing Blynk server"
              set +e # Disallow temporary the programm to exit if an error occurs
              dpkg -l libxrender &> /dev/null || true
              lib_exists=$?
              set -e

              if ! which java >> /dev/null || [[ $lib_exists -eq 1 ]]; then
                info "Installing dependencies"
                sudo apt update
                sudo apt install oracle-java8-jdk libxrender1
              fi

              if [[ ! -d $BLYNK_FOLDER ]]; then
                sudo mkdir -p $BLYNK_FOLDER
              fi

              if ! id "blynk" >/dev/null 2>&1; then
                info "Creating Blynk user"
                sudo adduser --system --no-create-home --disabled-login --group --quiet blynk
              fi

              # Update blynk user rights for the blynk folder
              sudo chown -R blynk:blynk $BLYNK_FOLDER
              sudo chmod -R g+w $BLYNK_FOLDER

              # Retrieve server's release informations
              serverFile="$(curl -s "https://api.github.com/repos/blynkkk/blynk-server/releases/latest" | grep 'browser_' | cut -d\" -f4 | head -n 1)"
              jar="$BLYNK_FOLDER/$(basename "$serverFile")"

              info "Downloading latest server release: $(basename "$serverFile")"
              sudo wget -c -q --show-progress "$serverFile" -O "$jar"
              sudo sed -i -e "s#^BLYNK_JAR=\".*\"#BLYNK_JAR=\"$jar\"#" $BLYNKCLI_EXECUTABLE

              # Update default settings for enhanced security
              printf "admin.email=admin@blynk.cc\nadmin.pass=fablab\nlogs.folder=%s/logs" $BLYNK_FOLDER | sudo -u blynk tee "$BLYNK_SERVER_CONFIG" >> /dev/null

              info "Setting Blynk server to launch on startup"
              last_line=$(grep -n '^exit 0' /etc/rc.local | tail -1 | cut -d: -f1)
              sudo sed -i "$last_line c \
                       # Added by Blynk CLI\nif which blynkcli >> /dev/null; then\n\tblynkcli server start >> /dev/null\nfi\n\nexit 0" /etc/rc.local
              info "Blynk successfully installed"
            else
              error "Blynk server already installed"
            fi
          elif [[ $2 == "uninstall" ]]; then
            blynkcli server stop

            info "Uninstalling Blynk server"

            if [[ -d $BLYNK_FOLDER ]]; then
              sudo rm -R $BLYNK_FOLDER
            fi

            sudo sed -i -e "s#^BLYNK_JAR=\".*\"#BLYNK_JAR=\"\"#" $BLYNKCLI_EXECUTABLE

            # Désactive le lancement automatique lors de la connexion de l'utilisateur
            first_line=$(grep -nr "# Added by Blynk CLI" /etc/rc.local | cut -d : -f 1 )
            last_line=$((first_line + 4))
            sudo sed -i "$first_line,$last_line d" "/etc/rc.local"
          elif [[ $2 == "update" ]]; then
            info "Check for Blynk server update"

            # Retrieve last server release informations
            latest=$(curl -s "https://api.github.com/repos/blynkkk/blynk-server/releases/latest" | grep 'browser_' | cut -d\" -f4 | head -n 1)
            new_jar=$(basename "$latest")
            new_path="$BLYNK_FOLDER/$new_jar"

            if [[ ! -z $BLYNK_JAR ]] && [[ $new_jar  == "$(basename "$BLYNK_JAR")" ]]; then
              warning "No update available for Blynk server"
            else
              info "An update is available"
              info "Downloading new version ($new_jar)"
              sudo -u blynk wget -c -q --show-progress "$latest" -O "$new_path"

              if [[ -f "$BLYNK_JAR" ]]; then
                sudo -u blynk rm "$BLYNK_JAR"
              fi

              # Replace old server
              sudo sed -i -e "s#^BLYNK_JAR=\".*\"#BLYNK_JAR=\"$new_jar\"#" $BLYNKCLI_EXECUTABLE

              info "Update complete."
            fi
          elif [[ $2 == "start" ]]; then
            if [[ ! -f $BLYNK_PID_PATH ]]; then
              if [[ -f $BLYNK_JAR ]]; then
                info "Starting server"
                sudo -u blynk echo "Asking for password" >> /dev/null
                nohup sudo -u blynk java -jar "$BLYNK_JAR" -dataFolder $BLYNK_DATA -serverConfig $BLYNK_SERVER_CONFIG > /tmp/blynkcli.log 2>&1 &
                echo $! | sudo tee $BLYNK_PID_PATH >> /dev/null
              else
                error "Server must be installed first. Run \`blynkcli server install\` first"
              fi
            else
              error "Server already running"
            fi
          elif [[ $2 == "stop" ]]; then
            info "Stopping server"
            if [[ -f $BLYNK_PID_PATH ]] && ps -p "$(cat /run/blynk.pid)" -ge 1 > /dev/null; then
              sudo kill -USR1 "$(cat /run/blynk.pid)"
              sudo rm $BLYNK_PID_PATH
            else
              error "Server is already offline"
            fi
          elif [[ $2 == "restart" ]]; then
            blynkcli server stop
            blynkcli server start
          elif [[ $2 == "status" ]]; then
            if [[ -f $BLYNK_PID_PATH ]] && ps -p "$(cat /run/blynk.pid)" -ge 1 > /dev/null; then
              info "Server is \e[32monline\e[0m"
            else
              info "Server is \e[31moffline\e[0m"
            fi
          elif [[ $2 == "backup" ]]; then
            if [[ ! -d "$BLYNK_BACKUP_FOLDER" ]]; then
              sudo -u blynk mkdir "$BLYNK_BACKUP_FOLDER"
            fi

            if [[ -d "$BLYNK_DATA" ]]; then
              if [[ -z ${3+x} ]]; then
                echo -n "Enter the backup name: "
                read -r -e backup_name
              else
                backup_name="$3"
              fi

              if [[ "$backup_name" =~ ^[a-zA-Z0-9-]+$ ]]; then
                info "Backing up data folder"
                backup_folder="$BLYNK_BACKUP_FOLDER/${backup_name}_$(date +"%Y-%m-%d_%H-%M-%S")"

                sudo -u blynk cp -R "$BLYNK_DATA" "$backup_folder"

                info "Backup $backup_name saved as $backup_folder"
              else
                error "Invalid name. Only alphanumeric characters and hyphen -are supported."
              fi
            else
              error "There are no data to save. You must run the server once first before making a backup"
            fi
          elif [[ $2 == "restore" ]]; then
            if [[ -z ${3+x} ]]; then
              error "You must provide the name of a backup.
              Examples:
                blynkcli restore my-backup-name
                blynkcli restore my-backup-name_2017-05-16_00-30-54"
            else
              if [[ $3 =~ .*_?[0-9]{4}(-[0-9]{2}){2}_([0-9]{2}-){2}[0-9]{2}$ ]]; then
                target_folder="$BLYNK_BACKUP_FOLDER/$3"
              else
                backup_count=$(find $BLYNK_BACKUP_FOLDER -name "$3*" | wc -l)
                if [[ $backup_count == 1 ]]; then
                  target_folder=$(find $BLYNK_BACKUP_FOLDER -name "$3*")
                elif [[ $backup_count == 0 ]]; then
                  error "There is no backup using this name."
                  exit 1
                else
                  error "There are more than one backup following this name. Use the full name instead"
                  exit 1
                fi

                blynkcli server stop

                info "Restoring from backup $target_folder"
                sudo -u blynk rm -R "$BLYNK_DATA"
                sudo -u blynk cp -R "$target_folder" "$BLYNK_DATA"

                blynkcli server start
              fi
            fi
          else
            usage
          fi
        fi
      elif [[ $1 == "remove" ]]; then
        sudo rm $BLYNKCLI_EXECUTABLE
      elif [[ $1 == "self-update" ]]; then
        info "Updating Blynk CLI"
        latest="$(curl -s "https://api.github.com/repos/booteille/blynkcli/releases/latest" | grep 'browser_' | cut -d\" -f4 | head -n 1)"
        version=$(echo "$latest" | cut -d / -f8)

        if [[ "$(blynkcli version)" == "$version" ]]; then
          warning "No update available."
        else
          info "New version available. Updating to $version"
          sudo wget -c -q --show-progress "$latest" -O /tmp/blynkcli
          sudo mv /tmp/blynkcli $BLYNKCLI_EXECUTABLE
          sudo chmod +x $BLYNKCLI_EXECUTABLE

          info "Update complete."
        fi
      elif [[ $1 == "version" ]]; then
        echo $BLYNKCLI_VERSION
      else
        usage
      fi
    fi
  fi
fi