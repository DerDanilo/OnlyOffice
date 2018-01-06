#!/usr/bin/env bash

# Path where you checked out the repo
# NO trailing / or the setup will fail ! !
# /dockersetup at the end is the subfolder of the repo
pathtofiles=< PATH TO WHERE YOU CHECKOUT OUT THE FILES >/dockersetup

sshport=< YOUR SSH PORT >
rootdomain=< YOUR ROOT DOMAIN >
subdomain=< YOUR OnlyOffice Server SUB DOMAIN >
subfolder=< YOUR OnlyOffice Server SUB FOLDER, no slash ! , yes correct, SUB DOMAIN + SUB FOLDER >
leaccountemail=< YOUR E-Mail for Let's Encrypt notifications >

##############################
##############################

# wait for valid network
until ping -c 1 google.com > /dev/null; do sleep 2; done
# wait for a valid user
until id root > /dev/null; do sleep 2; done

# check if we are root
if [[ ${EUID} -ne 0 ]] ; then
  echo "Aborting because you are not root" ; exit 1
fi

# SSH port change
sed -i 's/Port 22/Port '$sshport'/' /etc/ssh/sshd_config
sed -i 's/ssh\t\t22/ssh\t\t'$sshport'/' /etc/services
systemctl restart sshd

# Firewall setup
apt-get update
apt-get install -q -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" \
fail2ban ufw curl apt-transport-https ca-certificates software-properties-common

ufw allow ssh
ufw allow http
ufw allow https
echo "y" | ufw enable

# Add package repositories + keys
sh -c "echo 'deb http://nginx.org/packages/ubuntu/ '$(lsb_release -cs)' nginx' > /etc/apt/sources.list.d/NginxStable.list"
curl -fsSL http://nginx.org/keys/nginx_signing.key | sudo apt-key add -

# Add Docker’s official GPG key
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
add-apt-repository \
   "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
   $(lsb_release -cs) \
   stable"

# System upgrade
apt-get update
apt-get upgrade -q -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"
apt-get dist-upgrade -q -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"
# Install rest of packages
apt-get install -q -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" \
htop iftop iotop nmon haveged time whois nmap fping \
docker-ce nginx

# Add docker restart cron job - once a day at 1:19 AM
echo "1 19 * * * docker restart oods >/dev/null 2>&1" > /etc/cron.d/dockerrestart
chmod 700 /etc/cron.d/dockerrestart

# Add docker update cron job every Saturday at 4 AM
echo "0 4 * * 6 /bin/bash $pathtofiles/dockerimageupgrade.sh >/dev/null 2>&1" > /etc/cron.d/dockerupdate
chmod 700 /etc/cron.d/dockerupdate.sh

# Setup ACME and issue certificate
bash $pathtofiles/install_ssl.sh $rootdomain $subdomain $leaccountemail $subfolder $pathtofiles

# Dowload and run OnlyOffice image
bash $pathtofiles/dockerimageupgrade.sh

