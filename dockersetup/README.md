# OnlyOffice


- Script is in BETA !
- Written and tested for Ubuntu 16.04

## How to

- Set the DNS record of your subdomain to your servers IPv4

- Check out the repo into your root folder
`git clone https://github.com/DerDanilo/OnlyOffice.git`

- Place your settings in `init_setup.sh`
```
# Path where you checked out the repo
# NO trailing / or the setup will fail ! !
# /dockersetup at the end is the subfolder of the repo
pathtofiles=< PATH TO WHERE YOU CHECKOUT OUT THE FILES >/dockersetup

sshport=< YOUR SSH PORT >
rootdomain=< YOUR ROOT DOMAIN >
subdomain=< YOUR OnlyOffice Server SUB DOMAIN >
subfolder=< YOUR OnlyOffice Server SUB FOLDER, no slash ! , yes correct, SUB DOMAIN + SUB FOLDER >
leaccountemail=< YOUR E-Mail for Let's Encrypt notifications >
```

- Run the script with bash as root user
`/bin/bash /root/init_setup.sh`

