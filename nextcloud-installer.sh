#!/bin/bash
#
# https://github.com/heyitsak/nextcloud-ubuntu/
#
# Copyright (c) 2020 Heyitsak. Released under the MIT License.

# Detect Debian users running the script with "sh" instead of bash
if readlink /proc/$$/exe | grep -q "dash"; then
	echo 'This installer needs to be run with "bash", not "sh".'
	exit
fi

# Discard stdin. Needed when running from a one-liner which includes a newline
read -N 999999 -t 0.001

# Detect OpenVZ 6
if [[ $(uname -r | cut -d "." -f 1) -eq 2 ]]; then
	echo "The system is running an old kernel, which is incompatible with this installer."
	exit
fi

# Detect OS
# $os_version variables aren't always in use, but are kept here for convenience
if grep -qs "ubuntu" /etc/os-release; then
	os="ubuntu"
	os_version=$(grep 'VERSION_ID' /etc/os-release | cut -d '"' -f 2 | tr -d '.')
	group_name="nogroup"
elif [[ -e /etc/debian_version ]]; then
	os="debian"
	os_version=$(grep -oE '[0-9]+' /etc/debian_version | head -1)
	group_name="nogroup"
else
	echo "This installer seems to be running on an unsupported distribution.
Supported distributions are Ubuntu, Debian, CentOS, and Fedora."
	exit
fi

if [[ "$os" == "ubuntu" && "$os_version" -lt 1804 ]]; then
	echo "Ubuntu 18.04 or higher is required to use this installer.
This version of Ubuntu is too old and unsupported."
	exit
fi

if [[ "$os" == "debian" && "$os_version" -lt 9 ]]; then
	echo "Debian 9 or higher is required to use this installer.
This version of Debian is too old and unsupported."
	exit
fi

# Detect environments where $PATH does not include the sbin directories
if ! grep -q sbin <<< "$PATH"; then
	echo '$PATH does not include sbin. Try using "su -" instead of "su".'
	exit
fi

if [[ "$EUID" -ne 0 ]]; then
	echo "This installer needs to be run with superuser privileges."
	exit
fi


# Update the software sources as follows
sudo apt-get update -y

# Install Apache webserver & extensions

sudo apt install apache2 mariadb-server libapache2-mod-php7.4 -y
sudo apt install php7.4-gd php7.4-mysql php7.4-curl php7.4-mbstring php7.4-intl -y
sudo apt install php7.4-gmp php7.4-bcmath php-imagick php7.4-xml php7.4-zip -y

sudo systemctl start apache2
sudo systemctl enable apache2

echo "Enabling the Apache php7.4 module then restart Apache Web server."
sudo a2enmod php7.4
sudo systemctl restart apache2

# Download and install Nextcloud
sudo https://download.nextcloud.com/server/releases/nextcloud-21.0.2.zip
sudo mv nextcloud-21.0.2.zip /var/www/html
cd /var/www/html
sudo unzip -q nextcloud-21.0.2.zip
grep VersionString nextcloud/version.php
sudo chown -R www-data:www-data /var/www/html/nextcloud

# Datadir for cloud
sudo mkdir -p /var/nextcloud/data
sudo chown -R www-data:www-data /var/nextcloud/data
sudo chmod 750 /var/nextcloud/data

sudo /usr/bin/mysql_secure_installation

mysql -u root -pPASSWORD << EOF
create database nextcloud;
create user ncuser;
set password for ncuser = password("raindrop");
grant all PRIVILEGES on nextcloud.* to ncuser@localhost identified by 'raindrop';
flush privileges;
EOF

echo "Cretaing Virtual host entry for NextCLoud...."
echo "Creating /etc/apache2/sites-available/nextcloud.conf "
cat << EOF >> /etc/apache2/sites-available/nextcloud.conf

<VirtualHost *:80>
        DocumentRoot "/var/www/nextcloud"
        ServerName nextcloud.example.com

        ErrorLog ${APACHE_LOG_DIR}/nextcloud.error
        CustomLog ${APACHE_LOG_DIR}/nextcloud.access combined

        <Directory /var/www/nextcloud/>
            Require all granted
            Options FollowSymlinks MultiViews
            AllowOverride All

           <IfModule mod_dav.c>
               Dav off
           </IfModule>

        SetEnv HOME /var/www/nextcloud
        SetEnv HTTP_HOME /var/www/nextcloud
        Satisfy Any

       </Directory>

</VirtualHost>

EOF

echo "Done."
echo "Enabling nextcloud.conf virtual host.."
sudo a2ensite nextcloud.conf

echo "Enabling required Apache modules.."
sudo a2enmod rewrite headers env dir mime setenvif ssl

echo "Testing Apache configurations.."
sudo apache2ctl -t

echo "If the syntax is OK, reloading Apache for the changes to take effect...."
sudo systemctl restart apache2
sudo service apache2 restart

echo "Installing Apache SSL."
sudo apt install certbot python3-certbot-apache -y

# Find the existing ServerName and ServerAlias lines. If all good then proceed

echo "Obtaining SSL"
echo ""
echo "This script will prompt you to answer a series of questions in order to configure your SSL certificate. First, it will ask you for a valid e-mail address. This email will be used for renewal notifications and security notices:"
echo""
sudo certbot --apache

echo "Verifying Certbot Auto-Renewal"
sudo systemctl start certbot.timer
sudo systemctl enable certbot.timer

echo "testing the renewal process, you can do a dry run with certbot"
sudo certbot renew --dry-run



