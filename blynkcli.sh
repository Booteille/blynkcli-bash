#!/usr/bin/env bash
set -euo pipefail # Ces instructions activent le mode strict non-officiel:
IFS=$'\n\t'       # http://redsymbol.net/articles/unofficial-bash-strict-mode/

#/ Description:
#/              Petit utilitaire aidant à la gestion d'un serveur Blynk
#/ Usage:
#/              Tout d'abord, installez l'utilitaire et le serveur
#/              avec `./blynkcli.sh install`.
#/              Ensuite, vous pourrez utiliser le raccouci `blynkcli` pour accéder
#/              aux différentes commandes.
#/ Examples:
#/              blynkcli start # Exécute le serveur
#/              blynkcli stop # Arrête le serveur
#/              blynkcli backup # Sauvegarde le dossier data
#/              blynkcli restore 2017-05-16_00-30-57 # Restaure le dossier data en fonction d'une sauvegarde faite au préalable
#/ Options:
#/              install: Installe le serveur et l'utilitaire blynkcli
#/
#/              uninstall: Désinstalle le serveur
#/
#/              update: Met à jour le serveur
#/
#/              start: Lance le serveur
#/
#/              status: Affiche l'état du serveur
#/
#/              stop: Arrête le serveur
#/
#/              backup: Fait une sauvegarde du dossier "data"
#/
#/              restore: Restaure une sauvegarde en fonction de son nom
#/
#/              version: Affiche la version de blynkcli
#/
usage() { grep '^#/' "$0" | cut -c4- ; exit 0 ; }

DATETIME=$(date +"%d %h %Y %H:%M:%S")
CURRENT_DIR=$(readlink -f "$(dirname "$0")")

BLYNKCLI_VERSION="0.0.1"
BLYNKCLI_EXECUTABLE="/usr/bin/blynkcli"
BLYNKCLI_FOLDER="/opt/blynkcli"
BLYNK_FOLDER="/var/blynk"
BLYNK_DATA="$BLYNK_FOLDER/data"
BLYNK_SERVER_CONFIG="$BLYNK_FOLDER/server.properties"

readonly LOG_FILE="/tmp/$(basename "$0").log"
info()    { echo -e "\e[32m[INFO]\e[0m    $DATETIME - $*" | tee -a "$LOG_FILE" >&2 ; }
warning() { echo -e "\e[33m[WARNING]\e[0m $DATETIME - $*" | tee -a "$LOG_FILE" >&2 ; }
error()   { echo -e "\e[31m[ERROR]\e[0m   $DATETIME - $*" | tee -a "$LOG_FILE" >&2 ; }
fatal()   { echo -e "\e[1;31m[FATAL]\e[0m $DATETIME - $*" | tee -a "$LOG_FILE" >&2 ; exit 1 ; }


if [[ "${BASH_SOURCE[0]}" = "$0" ]]; then
  if [[ -z ${1+x} ]]; then
    usage
  else
    if [[ $1 == "install" ]]; then
      if which blynkcli >> /dev/null; then
        info "Le serveur Blynk est déjà installé"
      else
        info "Installation du serveur Blynk..."

        # Installe les dépendances
        set +e # Empêche temporairement le programme de se fermer si exit a une
               # autre valeur que zéro
        dpkg -l libxrender &> /dev/null || true
        lib_exists=$?
        set -e

        if ! which java >> /dev/null || [[ $lib_exists -eq 1 ]]; then          sudo apt update;
          sudo apt update
          sudo apt install oracle-java8-jdk libxrender1
        fi

        if [[ ! -d $BLYNKCLI_FOLDER ]]; then
          sudo mkdir -p $BLYNKCLI_FOLDER
        fi

        if [[ ! -d $BLYNK_FOLDER ]]; then
          sudo mkdir -p $BLYNK_FOLDER
        fi

        # Créé l'utilisateur
        if ! id "blynk" >/dev/null 2>&1; then
          sudo adduser --system --no-create-home --disabled-login --group --quiet blynk
        fi

        # Récupère les informations du fichier
        serverFile="$(curl -s "https://api.github.com/repos/blynkkk/blynk-server/releases/latest" | grep 'browser_' | cut -d\" -f4)"
        jar="$BLYNK_FOLDER/$(basename "$serverFile")"

        # Télécharge le fichier
        sudo wget -c -q --show-progress "$serverFile" -O "$jar"

        # Copie le script et permet de l'exécuter
        sudo cp "$CURRENT_DIR/blynkcli.sh" $BLYNKCLI_FOLDER
        sudo chmod a+x "$BLYNKCLI_FOLDER/blynkcli.sh"
        sudo ln -sf "$BLYNKCLI_FOLDER/blynkcli.sh" "$BLYNKCLI_EXECUTABLE"

        # Met à jour la configuration par défaut.
        printf "admin.email=admin@blynk.cc\nadmin.pass=fablab\nlogs.folder=%s/logs" "$BLYNK_FOLDER" | sudo tee "$BLYNK_SERVER_CONFIG" > /dev/null

        echo "BLYNK_JAR=$jar" > "/tmp/blynkcli.cfg"
        sudo mv "/tmp/blynkcli.cfg" "$BLYNKCLI_FOLDER/blynkcli.cfg"

        # Met à jour les droits
        sudo chown -R blynk:blynk "$BLYNK_FOLDER"
        sudo chmod -R g+w "$BLYNK_FOLDER"

        # Lance automatiquement Blynk lors de la connexion de l'utilisateur
        last_line=$(grep -n '^exit 0' /etc/rc.local | tail -1 | cut -d: -f1)
        sudo sed -i "$last_line c \
                 # Added by Blynk CLI\nif which blynkcli >> /dev/null; then\n\tblynkcli start >> /dev/null\nfi\n\nexit 0" /etc/rc.local

      fi
    elif [[ $1 == "uninstall" ]]; then
      if which blynkcli >> /dev/null; then
        blynkcli stop

        info "Désinstallation du serveur Blynk..."

        if [[ -f "$BLYNKCLI_EXECUTABLE" ]]; then
          sudo rm "$BLYNKCLI_EXECUTABLE"
        fi

        if [[ -d "$BLYNKCLI_FOLDER" ]]; then
          sudo rm -R "$BLYNKCLI_FOLDER"
        fi

        if [[ -d "$BLYNK_FOLDER" ]]; then
          sudo rm -R "$BLYNK_FOLDER"
        fi

        # Désactive le lancement automatique lors de la connexion de l'utilisateur
        first_line=$(grep -nr "# Added by Blynk CLI" /etc/rc.local | cut -d : -f 1 )
        last_line=$((first_line + 4))
        sudo sed -i "$first_line,$last_line d" "/etc/rc.local"
      else
        warning "Le serveur Blynk n'est pas installé"
      fi
    elif [[ $1 == "start" ]]; then
      if which blynkcli >> /dev/null; then
        if [[ ! -f "/tmp/blynk.pid" ]]; then
          # shellcheck source=/opt/blynkcli/blynkcli.cfg
          # shellcheck disable=SC1091
          source "$BLYNKCLI_FOLDER/blynkcli.cfg"

          if [[ ! -z ${BLYNK_JAR+x} ]]; then
            info "Lancement du serveur..."
            sudo -u blynk echo "Asking for password.." >> /dev/null
            nohup sudo -u blynk java -jar "$BLYNK_JAR" -dataFolder $BLYNK_DATA -serverConfig $BLYNK_SERVER_CONFIG > /tmp/blynkcli.log 2>&1 &
            echo $! > "/tmp/blynk.pid"
          else
            error "Votre fichier de configuration doit contenir la variable \$BLYNK_JAR"
          fi
        else
          warning "Le serveur est déjà lancé"
        fi
      else
        warning "Le serveur Blynk n'est pas installé"
      fi
    elif [[ $1 == "status" ]]; then
      if [[ -f "/tmp/blynk.pid" ]]; then
        if ps -p "$(cat /tmp/blynk.pid)" -ge 1 > /dev/null; then
          info "Le serveur est en route"
        else
          warning "Le serveur est arrêté"
        fi
      else
        warning "Le serveur est arrêté"
      fi
    elif [[ $1 == "stop" ]]; then
      if [[ -f "/tmp/blynk.pid" ]]; then
        blynk_pid="$(cat /tmp/blynk.pid)"
        if ps -p "$blynk_pid" -ge 1 > /dev/null; then
          info "Arrêt du serveur..."
          sudo kill -USR1 "$blynk_pid"
          rm "/tmp/blynk.pid"
        else
          warning "Le serveur est déjà arrêté"
        fi
      else
        warning "Le serveur est déjà arrêté"
      fi
    elif [[ $1 == "update" ]]; then
      if which blynkcli >> /dev/null; then
        # shellcheck source=/opt/blynkcli/blynkcli.cfg
        # shellcheck disable=SC1091
        source "$BLYNKCLI_FOLDER/blynkcli.cfg"

        latest=$(curl -s "https://api.github.com/repos/blynkkk/blynk-server/releases/latest" | grep 'browser_' | cut -d\" -f4)
        new_jar=$(basename "$latest")
        new_path="$BLYNK_FOLDER/$new_jar"

        if [[ $new_jar  == "$(basename "$BLYNK_JAR")" ]]; then
          info "Aucune mise à jour disponible"
        else
          info "Téléchargement de la mise à jour..."
          sudo wget -c -nv --show-progress "$latest" -O "$new_path"

          info "Application de la mise à jour..."
          sudo sed -i -e "s#BLYNK_JAR=$BLYNK_JAR#BLYNK_JAR=$new_path#g" "$BLYNKCLI_FOLDER/blynkcli.cfg"

          sudo rm "$BLYNK_JAR"
        fi
      else
          warning "Le serveur Blynk n'est pas installé"
      fi
    elif [[ $1 == "backup" ]]; then
      if which blynkcli >> /dev/null; then
        if [[ ! -d "$BLYNK_FOLDER/backup" ]]; then
          sudo -u blynk mkdir "$BLYNK_FOLDER/backup"
        fi

        if [[ -d "$BLYNK_DATA" ]]; then
          info "Sauvegarde des fichiers en cours..."

          backup_folder="$BLYNK_FOLDER/backup/$(date +"%Y-%m-%d_%H-%M-%S")"

          sudo -u blynk cp -R "$BLYNK_DATA" "$backup_folder"

          info "Les fichiers ont été sauvegardés à l'emplacement $backup_folder"
        else
          warning "Il n'y a aucune donnée à sauvegarder.
          Veuillez lancez une première fois le serveur avant d'exécuter une sauvegarde."
        fi
      else
        warning "Le serveur Blynk n'est pas installé"
      fi
    elif [[ $1 == "restore" ]]; then
      if [[ -z ${2+x} ]]; then
        error "Vous devez fournir le nom du dossier à restaurer.
        Example: blynkcli restore 2017-05-16_00-30-54"
      else
        target_folder="$BLYNK_FOLDER/backup/$2"

        if [[ -d $target_folder ]]; then
          blynkcli stop

          info "Restauration de la sauvegarde..."
          sudo -u blynk rm -R "$BLYNK_DATA"
          sudo -u blynk cp -R "$target_folder" "$BLYNK_DATA"

          blynkcli start
        else
          error "Le dossier $target_folder n'existe pas."
        fi
      fi
    elif [[ $1 == "version" ]]; then
      echo "$BLYNKCLI_VERSION";
    else
      usage
    fi
  fi
fi