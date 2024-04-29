#!/usr/bin/env bash
unknown_os ()
{
  echo "Unfortunately, your operating system distribution and version are not supported by Jacker."
  echo
  echo "You can override the OS detection by setting os= and dist= prior to running this script."
  echo
  echo "For example, to force Ubuntu Trusty: os=ubuntu dist=trusty ./setup.sh"
  exit 1
}

gpg_check ()
{
  echo "Checking for gpg..."
  if command -v gpg > /dev/null; then
    echo "Detected gpg..."
  else
    echo "Installing gnupg for GPG verification..."
    apt-get install -y gnupg
    if [ "$?" -ne "0" ]; then
      echo "Unable to install GPG! Your base system has a problem; please check your default OS's package repositories because GPG should work."
      echo "Repository installation aborted."
      exit 1
    fi
  fi
}

curl_check ()
{
  echo "Checking for curl..."
  if command -v curl > /dev/null; then
    echo "Detected curl..."
  else
    echo "Installing curl..."
    apt-get install -q -y curl
    if [ "$?" -ne "0" ]; then
      echo "Unable to install curl! Your base system has a problem; please check your default OS's package repositories because curl should work."
      echo "Repository installation aborted."
      exit 1
    fi
  fi
}

install_debian_keyring ()
{
  if [ "${os,,}" = "debian" ]; then
    echo "Installing debian-archive-keyring which is needed for installing "
    echo "apt-transport-https on many Debian systems."
    apt-get install -y debian-archive-keyring &> /dev/null
  fi
}


detect_os ()
{
  if [[ ( -z "${os}" ) && ( -z "${dist}" ) ]]; then
    # some systems dont have lsb-release yet have the lsb_release binary and
    # vice-versa
    if [ -e /etc/lsb-release ]; then
      . /etc/lsb-release

      if [ "${ID}" = "raspbian" ]; then
        os=${ID}
        dist=`cut --delimiter='.' -f1 /etc/debian_version`
      else
        os=${DISTRIB_ID}
        dist=${DISTRIB_CODENAME}

        if [ -z "$dist" ]; then
          dist=${DISTRIB_RELEASE}
        fi
      fi

    elif [ `which lsb_release 2>/dev/null` ]; then
      dist=`lsb_release -c | cut -f2`
      os=`lsb_release -i | cut -f2 | awk '{ print tolower($1) }'`

    elif [ -e /etc/debian_version ]; then
      # some Debians have jessie/sid in their /etc/debian_version
      # while others have '6.0.7'
      os=`cat /etc/issue | head -1 | awk '{ print tolower($1) }'`
      if grep -q '/' /etc/debian_version; then
        dist=`cut --delimiter='/' -f1 /etc/debian_version`
      else
        dist=`cut --delimiter='.' -f1 /etc/debian_version`
      fi

    else
      unknown_os
    fi
  fi

  if [ -z "$dist" ]; then
    unknown_os
  fi

  # remove whitespace from OS and dist name
  os="${os// /}"
  dist="${dist// /}"

  echo "Detected operating system as $os/$dist."
}

detect_apt_version ()
{
  apt_version_full=`apt-get -v | head -1 | awk '{ print $2 }'`
  apt_version_major=`echo $apt_version_full | cut -d. -f1`
  apt_version_minor=`echo $apt_version_full | cut -d. -f2`
  apt_version_modified="${apt_version_major}${apt_version_minor}0"

  echo "Detected apt version as ${apt_version_full}"
}

create_env_files()
{
  source .env.defaults

  # Create .env from template
  export PUID=`id -u $USER`
  export PGID=`id -g $USER`
  export TZ=`cat /etc/timezone`
  export USERDIR=`eval echo ~$user`
  export DOCKERDIR=`eval pwd`
  export DATADIR=$DOCKERDIR/data

  read -r -p "Enter your Host Name (e.g. mybox): " response
  export HOSTNAME=$response
  read -r -p "Enter your Domain Name (e.g. example.com): " response
  export DOMAINNAME=$response
  export PUBLIC_FQDN=$HOSTNAME.$DOMAINNAME
  export LOCAL_IPS=$LOCAL_IPS
  export CODE_TRAEFIK_SUBNET_IP=$CODE_TRAEFIK_SUBNET_IP
  export DOCKER_DEFAULT_SUBNET=$DOCKER_DEFAULT_SUBNET
  export SOCKET_PROXY_SUBNET=$SOCKET_PROXY_SUBNET
  export SOCKET_PROXY_IP=$SOCKET_PROXY_IP
  export TRAEFIK_PROXY_SUBNET=$TRAEFIK_PROXY_SUBNET
  export TRAEFIK_PROXY_IP=$TRAEFIK_PROXY_IP

  response=`stat -c '%U' /proc`
  [ "$response" = "root" ] && export HOST_IS_VM=true || export HOST_IS_VM=false

  export UFW_ALLOW_FROM=$UFW_ALLOW_FROM
  read -r -p "Enter comma separated ports from host that want to ufw allow (e.g. 22,3306): " response
  [ "$response" != "" ] && export UFW_ALLOW_PORTS=$UFW_ALLOW_PORTS,$response || export UFW_ALLOW_PORTS=$UFW_ALLOW_PORTS
  
  read -r -p "Enter comma separated networks/hosts that you want to ufw allow SSH connections to this host (e.g. 1.1.1.1,2.2.2.0/24): " response
  [ "$response" != "" ] && export UFW_ALLOW_SSH=$UFW_ALLOW_SSH,$response || export UFW_ALLOW_SSH=$UFW_ALLOW_SSH

  export OAUTH_COOKIE_LIFETIME=$OAUTH_COOKIE_LIFETIME
  
  echo "Configure Google OAuth2 Service as shown in https://jacker.jacar.es/first-steps/prepare/#step-2-configure-google-oauth2-service"
  read -r -p "Enter your OAuth client ID: " response
  export OAUTH_CLIENT_ID=$response
  read -r -p "Enter your OAuth client secret: " response
  export OAUTH_CLIENT_SECRET=$response
  export OAUTH_SECRET=`openssl rand -hex 16`
  read -r -p "Enter comma separated emails whick will get access to all your SSO applications (e.g. a@example.com,b@example.com): " response
  export OAUTH_WHITELIST=$response

  read -r -p "Enter Email address for Let's Encrypt SSL Certificates: " response
  export LETSENCRYPT_EMAIL=$response

  export CROWDSEC_API_PORT=$CROWDSEC_API_PORT
  export CROWDSEC_TRAEFIK_BOUNCER_API_KEY=`openssl rand -hex 64`
  export CROWDSEC_IPTABLES_BOUNCER_API_KEY=`openssl rand -hex 64`
  export CROWDSEC_API_LOCAL_PASSWORD=`openssl rand -hex 36`
  export MYSQL_ROOT_PASSWORD=`openssl rand -hex 24`
  export MYSQL_DATABASE=$MYSQL_DATABASE
  export MYSQL_USER=$MYSQL_USER
  export MYSQL_PASSWORD=`openssl rand -hex 24`

  # Create .env file
  envsubst < .env.template > .env

  # Configure Traefik's logrotate
  envsubst < assets/templates/traefik.logrotate.template > assets/templates/traefik
  sudo mv assets/templates/traefik /etc/logrotate.d/
  sudo chown root.root /etc/logrotate.d/traefik
  sudo chmod 644 /etc/logrotate.d/traefik
  sudo logrotate /etc/logrotate.conf

  # Configure Crowdsec to use mysql databaes
  mkdir -p data/crowdsec/config
  envsubst < assets/templates/config.yaml.local.template > data/crowdsec/config/config.yaml.local

  # Configure Traefik Forward OAuth Secret
  mkdir -p secrets
  envsubst < assets/templates/traefik_forward_oauth.template > secrets/traefik_forward_oauth

  # Configure systemd services
  envsubst < assets/templates/jacker-compose-reload.service.template > assets/templates/jacker-compose-reload.service
  envsubst < assets/templates/jacker-compose-reload.timer.template > assets/templates/jacker-compose-reload.timer
  envsubst < assets/templates/jacker-compose.service.template > assets/templates/jacker-compose.service

  # Change Permissions
  touch data/traefik/acme.json
  chmod 600 data/traefik/acme.json
  chmod +x assets/*.sh
}

execute_assets ()
{
  assets/01-tune_system.sh
  assets/02-install_docker.sh
  assets/03-setup_ufw.sh
  assets/04-install_assets.sh
  assets/05-install_iptables-bouncer.sh
}

first_round()
{
  detect_os
  curl_check
  gpg_check
  detect_apt_version

  if [ -f ".env" ]; then
    read -r -p "Existing .env file. Reinstall Jacker? (.env will be moved to .env.bak) [y/N] " response
    case $response in
      [yY][eE][sS]|[yY])
        mv .env .env.bak
      ;;
      *)
        exit -1
      ;;
    esac
  fi

  create_env_files
  execute_assets

  # Execute second round after reboot
  SCRIPT_PATH=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" && pwd )/$(basename "$0") 
  echo $SCRIPT_PATH | tee -a ~/.bashrc &> /dev/null
  touch .FIRST_ROUND

  echo "System needs to be restarted. You can safe say N and do it manually after saving other works."
  read -r -p "Jacker Setup will continue when you login back. Do you want to reboot your system NOW [y/N] " response
  case $response in
    [yY][eE][sS]|[yY])
      sudo reboot
    ;;
    *)
      exit 1
    ;;
  esac
  sudo reboot
}

second_round ()
{
  echo "Jacker Setup will continue now ..."

  source .env
  export CROWDSEC_IPTABLES_BOUNCER_API_KEY=$CROWDSEC_IPTABLES_BOUNCER_API_KEY
  envsubst < assets/templates/crowdsec-firewall-bouncer.yaml.template > assets/templates/crowdsec-firewall-bouncer.yaml
  sudo mv assets/templates/crowdsec-firewall-bouncer.yaml /etc/crowdsec/bouncers/crowdsec-firewall-bouncer.yaml.local

  echo "Setting up Jacker Stack"

  docker compose up -d &> /dev/null

  sleep 10
  echo "Crowdsec: Registering traefik-bouncer"
  cscli bouncers add traefik-bouncer --key $CROWDSEC_TRAEFIK_BOUNCER_API_KEY &> /dev/null
  echo "Crowdsec: Registering iptables-bouncer"
  cscli bouncers add iptables-bouncer --key $CROWDSEC_IPTABLES_BOUNCER_API_KEY &> /dev/null
  echo "Crowdsec: Setting local api password"
  cscli machines add $HOSTNAME -p $CROWDSEC_API_LOCAL_PASSWORD --force &> /dev/null
  
  # cscli completion
  echo "Crowdsec: Installing cscli bash completion"
  cscli completion bash | sudo tee /etc/bash_completion.d/cscli &> /dev/null

  sudo cp assets/templates/crowdsec-custom-whitelists.yaml data/crowdsec/config/parsers/s02-enrich/custom-whitelists.yaml
  sudo cp assets/templates/crowdsec-acquis.yaml data/crowdsec/config/acquis.yaml
  sudo systemctl enable crowdsec-firewall-bouncer.service 
  sudo systemctl restart crowdsec-firewall-bouncer.service 
  docker compose down &> /dev/null
  docker image prune -a -f &> /dev/null

  SCRIPT_PATH=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" && pwd )/$(basename "$0")
  sed -i -e "\|$SCRIPT_PATH|d" ~/.bashrc
  rm .FIRST_ROUND

  sudo mv assets/templates/jacker-compose-reload.service assets/templates/jacker-compose-reload.timer assets/templates/jacker-compose.service /etc/systemd/system
  sudo systemctl daemon-reload
  sudo systemctl enable --now jacker-compose.service jacker-compose-reload.timer

  echo "done ..."
}

main ()
{
  if [ ! -f ".FIRST_ROUND" ]; then
    first_round
  else
    second_round
  fi
}

cd "$(dirname "$0")"
main
