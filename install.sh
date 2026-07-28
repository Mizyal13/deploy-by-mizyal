#!/bin/bash

#####################################################
#
#        DEPLOY BY MIZYAL
#
# Universal Ubuntu PHP Deployment System
#
# Version 2.0
#
# Support:
# Ubuntu 20.04+
# AMD64 / ARM64
#
#####################################################


set -Eeuo pipefail


VERSION="2.0"


#############################################
# ERROR HANDLER
#############################################

error_exit(){

echo "
======================================

ERROR:

$1

======================================
"

exit 1

}



#############################################
# ROOT CHECK
#############################################

if [ "$EUID" -ne 0 ]
then
error_exit "Please run as root"
fi



#############################################
# SYSTEM INFO
#############################################


clear


echo "

======================================

🚀 DEPLOY BY MIZYAL

Universal Production Installer

Version $VERSION

======================================

"



OS=$(lsb_release -is 2>/dev/null || echo Ubuntu)

VERSION_ID=$(lsb_release -rs 2>/dev/null || echo unknown)

ARCH=$(dpkg --print-architecture)



echo "

System detected:

OS      : $OS
Version : $VERSION_ID
Arch    : $ARCH

"



#############################################
# INPUT
#############################################


read -p "
Project Name:
> " PROJECT



read -p "
Git Repository:
> " REPO



read -p "
Branch(default main):
> " BRANCH


BRANCH=${BRANCH:-main}



echo "

Deployment Type:

1. Domain
2. IP Address


"



read -p "Choose:
> " MODE



if [ "$MODE" = "1" ]
then

read -p "
Domain:
> " DOMAIN

USE_SSL=true


else

DOMAIN="_"

USE_SSL=false


fi




echo "

Database

"



read -p "
Database Name:
> " DB_NAME



read -p "
Database User:
> " DB_USER



read -s -p "
Database Password:
> " DB_PASS

echo



WEB="/var/www/$PROJECT"



#############################################
# UPDATE SYSTEM
#############################################


echo "

[1/12]
Updating system

"



apt update -y || error_exit "apt update failed"



apt upgrade -y || true




#############################################
# BASE PACKAGE
#############################################


echo "

[2/12]
Installing base package

"



apt install -y \
software-properties-common \
apt-transport-https \
ca-certificates \
curl \
wget \
git \
unzip \
gnupg \
lsb-release \
ufw \
fail2ban \
cron \
|| error_exit "Base package failed"



#############################################
# APACHE
#############################################


echo "

[3/12]
Installing Apache

"



apt install -y apache2 \
|| error_exit "Apache installation failed"



command -v apache2 \
|| error_exit "Apache not found"



systemctl enable apache2



#############################################
# PHP
#############################################


echo "

[4/12]
Installing PHP

"



apt install -y \
php \
php-cli \
php-common \
php-fpm \
php-mysql \
php-curl \
php-gd \
php-mbstring \
php-xml \
php-zip \
php-intl \
php-bcmath \
|| error_exit "PHP installation failed"




PHP_VERSION=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')



echo "

PHP Version:

$PHP_VERSION

"




systemctl enable php${PHP_VERSION}-fpm || true



#############################################
# MYSQL
#############################################


echo "

[5/12]
Installing MySQL

"



apt install -y mysql-server \
|| error_exit "MySQL install failed"



systemctl enable mysql

systemctl start mysql





#############################################
# COMPOSER
#############################################


echo "

[6/12]
Installing Composer

"



if ! command -v composer >/dev/null
then


php -r "copy('https://getcomposer.org/installer','composer-setup.php');"


php composer-setup.php \
--install-dir=/usr/local/bin \
--filename=composer


rm composer-setup.php


fi





#############################################
# CLONE PROJECT
#############################################


echo "

[7/12]
Downloading Project

"



mkdir -p /var/www



if [ -d "$WEB" ]
then

rm -rf "$WEB"

fi



git clone \
--branch "$BRANCH" \
"$REPO" \
"$WEB" \
|| error_exit "Git clone failed"





#############################################
# DATABASE
#############################################


echo "

[8/12]
Creating Database

"



mysql <<MYSQL


CREATE DATABASE IF NOT EXISTS \`$DB_NAME\`;

CREATE USER IF NOT EXISTS '$DB_USER'@'localhost'
IDENTIFIED BY '$DB_PASS';


GRANT ALL PRIVILEGES
ON \`$DB_NAME\`.*
TO '$DB_USER'@'localhost';


FLUSH PRIVILEGES;


MYSQL






#############################################
# APACHE CONFIG
#############################################


echo "

[9/12]
Configuring Apache

"



a2enmod rewrite proxy_fcgi setenvif



cat > /etc/apache2/sites-available/$PROJECT.conf <<EOF


<VirtualHost *:80>


ServerName $DOMAIN


DocumentRoot $WEB



<Directory $WEB>

AllowOverride All

Require all granted

</Directory>



<FilesMatch "\.php$">

SetHandler "proxy:unix:/run/php/php$PHP_VERSION-fpm.sock|fcgi://localhost/"

</FilesMatch>



ErrorLog \${APACHE_LOG_DIR}/$PROJECT-error.log

CustomLog \${APACHE_LOG_DIR}/$PROJECT-access.log combined



</VirtualHost>

EOF




a2dissite 000-default.conf || true

a2ensite $PROJECT.conf



systemctl reload apache2





#############################################
# PERMISSION
#############################################


echo "

[10/12]
Permission Setup

"



chown -R www-data:www-data "$WEB"


find "$WEB" -type d -exec chmod 755 {} \;


find "$WEB" -type f -exec chmod 644 {} \;





#############################################
# FRAMEWORK DETECT
#############################################


echo "

[11/12]
Framework Detection

"



cd "$WEB"



if [ -f artisan ]
then


echo "Laravel detected"


composer install \
--no-dev \
--optimize-autoloader || true


php artisan key:generate || true


php artisan storage:link || true


php artisan config:cache || true



elif [ -f composer.json ]
then


echo "PHP Composer Project"


composer install || true



else


echo "PHP Native detected"



fi





#############################################
# SECURITY
#############################################


echo "

[12/12]
Security Setup

"



ufw allow OpenSSH

ufw allow "Apache Full"

ufw --force enable



systemctl enable fail2ban





#############################################
# SSL
#############################################


if [ "$USE_SSL" = true ]
then


echo "

Installing SSL

"



apt install -y certbot python3-certbot-apache



certbot --apache \
-d "$DOMAIN" \
--agree-tos \
--non-interactive \
-m admin@$DOMAIN \
|| true



fi






#############################################
# FINISH
#############################################



IP=$(hostname -I | awk '{print $1}')



echo "

=============================================

🎉 DEPLOYMENT SUCCESS


Project:

$PROJECT


Location:

$WEB


Database:

$DB_NAME


URL:

"



if [ "$USE_SSL" = true ]
then

echo "https://$DOMAIN"

else

echo "http://$IP"

fi



echo "

=============================================

Deploy by Mizyal 🚀

=============================================

"
