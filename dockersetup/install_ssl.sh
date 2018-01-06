#!/bin/bash

# set variables
# set root domain to use in domain variable
rootdomain=$1
subdomain=$2
leaccountemailimport=$3
subfolder=$4
pathtofiles=$5

# all domain names for cert request as list
# e.g. sub.$rootdomain sub2.$rootdomain www.$rootdomain
domains="$subdomain.$rootdomain"
leaccountemail=$leaccountemailimport
letsencrypttest=false

####################################################

# Write Let's Encrypt test setting if variable was set.
if [[ "$letsencrypttest" == "true" ]]; then
     echo "# Let's Encrypt test mode activated."
     letsencrypttestpar=" --test"
elif [[ "$letsencrypttest" == "false" ]]; then
     echo "# Let's Encrypt productive mode activated."
     letsencrypttestpar=
else
     echo "# Let's Encrypt test mode activated. Set to true or false."
     letsencrypttestpar=" --test"
fi


function dhparamtgeneration {

# create dhparams.pem
if [ ! -f /etc/nginx/dhparams.pem ]
then

echo "# Compiling dhparam file..."
openssl dhparam -out /etc/nginx/dhparams.pem 4096
chown www-data. /etc/nginx/dhparams.pem

fi

}

function dependencies {

# installs nginx and some otherstuff
  function check_prog {
    # get updates
    apt-get update
    # check the progs
    if hash $1 2>/dev/null; then
      echo "#" $1 "installed."
    else
      echo "#" $1 "not installed. Trying to install."
      apt-get install -q -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" $1
    fi
  }
  echo "# Starting generic core setup..."
  export DEBIAN_FRONTEND=noninteractive
  for p in nginx nginx-extras dnsutils curl haveged; do check_prog $p ; done
}

# enable tls for default domain
enableTls(){

# Download and install ACME.sh
if [ ! -f /root/.acme.sh/acme.sh ]
then

echo "# Starting ACME.sh setup..."
# Install into root folder
cd /root
#curl https://get.acme.sh | sh
git clone https://github.com/Neilpang/acme.sh.git /root/acme.sh
cd /root/acme.sh
echo "# Installing acme.sh..."
#/root/acme/acme.sh --install --home "/root/.acme.sh/" --accountemail "$leaccountemail"
/root/acme.sh/acme.sh --install --home "/root/.acme.sh" --accountemail "$leaccountemail" --config-home "/root/.acme.sh/data" --certhome "/root/.acme.sh/data/certs"
echo "# Enable auto-upgrade for acme.sh"
/root/.acme.sh/acme.sh --upgrade --auto-upgrade --home "/root/.acme.sh"

fi

# create dir for certs and config
mkdir /etc/ssl/private/$firstdomain
mkdir /etc/nginx/global
mkdir /var/www/letsencrypt
chown www-data. /var/www/letsencrypt -R


# create redirect config with lets encrypt location
if [ ! -f /etc/nginx/global/letsencrypt.conf ]
then

echo "# Writing nginx pre-ssl config..."
# This works as global redirect conf
cat <<EOF> /etc/nginx/global/letsencrypt.conf
location /.well-known/acme-challenge {
        root /var/www/letsencrypt;
        default_type "text/plain";
        try_files \$uri =404;
}

EOF

chmod 0644 /etc/nginx/global/letsencrypt.conf
chown www-data. /etc/nginx/global/letsencrypt.conf

fi

# Create the first tls certificate
# Keep config for doc to serve content on port 80 while dhparm consumes a lot time
rm /etc/nginx/sites-enabled/default.conf
rm /etc/nginx/conf.d/*.conf
rm /etc/nginx/conf.d/default

cat <<EOF> /etc/nginx/conf.d/default.conf
server {
    server_tokens off;
    listen 80 default_server;
    server_name _;

    index index.html;
    include /etc/nginx/global/letsencrypt.conf; # Let's Encrypt global redirect
}
EOF

systemctl restart nginx

echo "# Issuing certificate..."
# issue certs
# we need to define
cd /root/.acme.sh
/root/.acme.sh/acme.sh $letsencrypttestpar --home "/root/.acme.sh" --issue $domainsforlecertrequest -w /var/www/letsencrypt
/root/.acme.sh/acme.sh $letsencrypttestpar --home "/root/.acme.sh" -k ec-256 --install-cert -d $firstdomain --key-file /etc/ssl/private/$firstdomain/privkey.pem --capath /etc/ssl/private/$firstdomain/leca.pem --fullchain-file /etc/ssl/private/$firstdomain/fullchain.pem --reloadcmd "systemctl restart nginx"

echo "# Removing old Nginx config..."
# Remove all old config files, to make sure that nginx fails to start if something is wrong with the new files.
rm /etc/nginx/conf.d/*.conf

echo "# Writing nginx ssl config..."

cat <<EOF> /etc/nginx/nginx.conf
user  www-data;
worker_processes  auto;

error_log  /var/log/nginx/error.log warn;
pid        /var/run/nginx.pid;


events {
    worker_connections  1024;
}


http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;

    log_format  main  '\$remote_addr - \$remote_user [\$time_local] "\$request" '
                      '\$status $body_bytes_sent "\$http_referer" '
                      '"\$http_user_agent" "\$http_x_forwarded_for"';

    access_log  /var/log/nginx/access.log  main;

    sendfile        on;
    #tcp_nopush     on;
    client_body_timeout 12;
    client_header_timeout 12;
    keepalive_timeout  15;
    send_timeout 10;

    gzip  off;

    include /etc/nginx/conf.d/*.conf;

EOF

# Now rewrite nginx config with ssl

cat <<EOF> /etc/nginx/conf.d/oods.conf
map \$http_host \$this_host {
     "" \$host;
     default \$http_host;
}

map \$http_x_forwarded_proto \$the_scheme {
     default \$http_x_forwarded_proto;
     "" \$scheme;
}

map \$http_x_forwarded_host \$the_host {
     default \$http_x_forwarded_host;
     "" \$this_host;
}

map \$http_upgrade \$proxy_connection {
    default upgrade;
    "" close;
}

proxy_set_header Upgrade \$http_upgrade;
proxy_set_header Connection \$proxy_connection;
proxy_set_header X-Forwarded-Host \$the_host/$subfolder;
proxy_set_header X-Forwarded-Proto \$the_scheme;
proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
proxy_set_header X-Forwarded-For \$remote_addr;

server {
  listen        80;
  server_name   $firstdomain;
  server_tokens off;

  include /etc/nginx/global/letsencrypt.conf; # Let's Encrypt global redirect

  location / {
    return 301 https://\$host\$request_uri; # enforce https
  }

}

server {
  listen 443 ssl http2;
  # enable if you want to use IPv6
  # listen [::]:443 ssl http2;

  ssl_certificate /etc/ssl/private/$firstdomain/fullchain.pem;
  ssl_certificate_key /etc/ssl/private/$firstdomain/privkey.pem;
  ssl_trusted_certificate /etc/ssl/private/$firstdomain/leca.pem;
  include /etc/nginx/global/ssl.conf;

  server_name $firstdomain;
  server_tokens off;

  location /$subfolder/ {
        proxy_pass http://localhost:88/;
        proxy_http_version 1.1;
        client_max_body_size 100M; # Limit Document size to 100MB
        proxy_read_timeout 3600s;
        proxy_connect_timeout 3600s;

    }
}

EOF



# Setup nginx ssl settings
if [ ! -f /etc/nginx/global/ssl.conf ]
then

cat <<EOF> /etc/nginx/global/ssl.conf
ssl_dhparam /etc/nginx/dhparams.pem;
ssl_session_timeout 1d;
ssl_session_cache shared:SSL:50m;
ssl_session_tickets off;
ssl_protocols TLSv1.2;
ssl_ciphers HIGH+kEECDH+AESGCM:HIGH+kEECDH:HIGH+kEDH:HIGH:!aNULL;
ssl_prefer_server_ciphers on;
ssl_stapling on;
ssl_stapling_verify on;
ssl_ecdh_curve secp384r1;
add_header Content-Security-Policy "default-src https: data: 'unsafe-inline' 'unsafe-eval'" always;
add_header Strict-Transport-Security "max-age=15768000; includeSubDomains; preload";
add_header X-Xss-Protection "1; mode=block" always;
add_header X-Content-Type-Options "nosniff" always;
add_header X-Frame-Options "ALLOW-FROM https://$firstdomain/" always;

EOF

chmod 0644 /etc/nginx/global/ssl.conf
chown www-data. /etc/nginx/global/ssl.conf

fi

# check for dhparam file (usually build already when nginx is configures without ssl)
dhparamtgeneration

echo "# Restarting nginx..."
systemctl restart nginx

# The cronjob has to be created initially, to avoid problems with mailfunctioning checks.
echo "# Creating cron job for SSL nginx config to run every 15 minutes..."
# create cron job to run script every 15min until DNS records is valid
cat <<EOF> /etc/cron.d/install_ssl
*/15 * * * * root /bin/bash $pathtofiles/install_ssl.sh
EOF
chmod 700 /etc/cron.d/install_ssl

echo "# Check nginx config and remove cronjob if working..."
# remove cron job that runs setup_nginx.sh (this script) every 5 minutes
# This is not required anymore once the certificate will be issued
# systemctl is-active nginx >/dev/null 2>&1 && echo YES || echo NO
# First check if nginx config is valid, then check if nginx service is still running
# If both is true, remove the cron job. We should be good to go.
nginx -t && systemctl is-active nginx && rm -f /etc/cron.d/install_ssl.sh

}

enableNoTls(){

cat <<EOF> /etc/nginx/conf.d/default.conf
server {
    server_tokens off;
    listen 80 default_server;
    server_name _;

    index index.html;
}
EOF

systemctl restart nginx

}

function dnsandcerts {

# set value to false before test
dnsvalidated=false

echo "# Checking DNS record for the following domains: '$domains'"
ourIP="$(curl https://v4.ifconfig.co/)"

# check if we have working a-records
# if yes, we can enable tls; else not
# Check given list of domains and verify DNS entries

for domain in $domains;
do
    # check DNS record for domain
    ourArecord="$(host $domain | cut -d" " -f4)"
        if [ "$ourArecord" == "$ourIP" ]; then
          # Add domain to list of validated dns entries
          domainsvalidated+=" $domain"
          # Set to true since at least one DNS entry is valid.
          dnsvalidated=true
          # Clean variable to avoid errors with following list items
          ourArecord=''
          echo "# DNS record for '$domain' found, added to Let's Encrypt cert request list."
        fi
done

if [ "$dnsvalidated" == "true" ]; then
  echo "# DNS record found for the following domains, that were added to cert request."
  echo "$domainsvalidated"
  # convert to acme.sh/let's encrypt valid list of domains with option command
  # counter to pick first list item for cert name
  counter=0
  for vdomain in $domainsvalidated;
  do
  domainsforlecertrequest+=" -d $vdomain"
      # Pick the first (main) domain out of list
      until [ $counter -eq 1 ]; do
      echo "First (main) domain:" "$vdomain"
      firstdomain="$vdomain"
      counter=1
      done
  done

  # Now activate SSL
  enableTls
else
  echo "# No valid DNS record found, configuring Nginx without SSL."
  echo "# Cronjob activated to check every 15 minutes if SSL can be used."
  enableNoTls
echo "# Creating cron job for SSL nginx config to run every 5 minutes..."
# create cron job to run script every 15min until DNS records is valid
cat <<EOF> /etc/cron.d/install_ssl
*/15 * * * * root /bin/bash $pathtofiles/install_ssl.sh
EOF
chmod 700 /etc/cron.d/install_ssl
fi

}



######################################
####### The action starts here #######
######################################

# wait for a valid network configuration
until ping -c 1 google.com; do sleep 5; done

# First let's make sure we have all packages we need
dependencies
# let's build the dhparamfile in advance since this usually takes a veeeery long time
dhparamtgeneration
# Validate DNS records and build cert request string with valid records
dnsandcerts

echo "# Finished generic core setup."

echo "# Installing system updates now..."
apt-get upgrade -q -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"
apt-get dist-upgrade -q -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"
echo "# Finished installing system updates."
