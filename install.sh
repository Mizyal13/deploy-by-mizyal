#!/bin/bash

####################################################
#
#          DEPLOY BY MIZYAL
#
# Production PHP Deployment Installer
#
# Ubuntu 22.04 / 24.04
#
####################################################


set -e


VERSION="1.0.0"


clear


echo "
================================================

        🚀 DEPLOY BY MIZYAL

        Production Deployment System

        Version $VERSION

================================================
"



####################################
# ROOT CHECK
####################################


if [ "$EUID" -ne 0 ]
then

echo "Please run as root"

exit 1

fi



####################################
# INPUT
####################################


read -p "
Project Name:
> " PROJECT



read -p "
GitHub Repository:
> " REPO



read -p "
Git Branch(default main):
> " BRANCH


BRANCH=${BRANCH:-main}



echo "

Deployment Mode

1. Domain
2. IP Address


"



read -p "
Choose:
> " MODE




if [ "$MODE" == "1" ]

then


read -p "
Domain:
> " DOMAIN



SSL=true


else


DOMAIN="_"

SSL=false


fi




echo "

Database Configuration

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




WEB_ROOT="/var/www/$PROJECT"

BACKUP="/backup/$PROJECT"




####################################
# SYSTEM UPDATE
####################################


echo "

[1/10] Updating system

"


apt update

apt upgrade -y




####################################
# INSTALL PACKAGE
####################################


echo "

[2/10] Installing packages

"



apt install -y \

apache2 \
mysql-server \
git \
curl \
wget \
unzip \
composer \
ufw \
fail2ban \
certbot \
python3-certbot-apache \
software-properties-common




####################################
# PHP INSTALL
####################################


echo "

[3/10] Installing PHP

"



apt install -y \

php \
php-fpm \
php-cli \
php-common \
php-mysql \
php-curl \
php-gd \
php-mbstring \
php-xml \
php-zip \
php-intl \
php-bcmath \
php-opcache




####################################
# PHP OPTIMIZATION
####################################


echo "

[4/10] Optimizing PHP

"



PHP_VERSION=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')



cat >> /etc/php/$PHP_VERSION/fpm/php.ini <<EOF


opcache.enable=1
opcache.memory_consumption=256
opcache.max_accelerated_files=20000
opcache.revalidate_freq=60

EOF



systemctl restart php$PHP_VERSION-fpm





####################################
# DOWNLOAD PROJECT
####################################


echo "

[5/10] Cloning project

"



mkdir -p /var/www



if [ -d "$WEB_ROOT" ]

then

rm -rf $WEB_ROOT

fi



git clone \
-b $BRANCH \
$REPO \
$WEB_ROOT




####################################
# DATABASE
####################################


echo "

[6/10] Creating database

"



mysql <<MYSQL


CREATE DATABASE IF NOT EXISTS $DB_NAME;


CREATE USER IF NOT EXISTS '$DB_USER'@'localhost'
IDENTIFIED BY '$DB_PASS';


GRANT ALL PRIVILEGES
ON $DB_NAME.*
TO '$DB_USER'@'localhost';


FLUSH PRIVILEGES;


MYSQL




####################################
# APACHE CONFIG
####################################


echo "

[7/10] Configuring Apache

"



a2enmod rewrite proxy_fcgi setenvif



a2enconf php$PHP_VERSION-fpm




cat > /etc/apache2/sites-available/$PROJECT.conf <<EOF


<VirtualHost *:80>


ServerName $DOMAIN


DocumentRoot $WEB_ROOT



<Directory $WEB_ROOT>

AllowOverride All

Require all granted


</Directory>



<FilesMatch \.php$>

SetHandler "proxy:unix:/run/php/php$PHP_VERSION-fpm.sock|fcgi://localhost/"

</FilesMatch>



ErrorLog \${APACHE_LOG_DIR}/$PROJECT-error.log

CustomLog \${APACHE_LOG_DIR}/$PROJECT-access.log combined



</VirtualHost>

EOF




a2dissite 000-default.conf || true


a2ensite $PROJECT.conf



systemctl restart apache2





####################################
# PERMISSION
####################################


echo "

[8/10] Setting permission

"



chown -R www-data:www-data $WEB_ROOT


find $WEB_ROOT -type d -exec chmod 755 {} \;

find $WEB_ROOT -type f -exec chmod 644 {} \;




####################################
# LARAVEL CHECK
####################################



if [ -f "$WEB_ROOT/artisan" ]

then


echo "

Laravel detected

"



cd $WEB_ROOT



composer install \
--no-dev \
--optimize-autoloader



php artisan key:generate || true


php artisan storage:link || true


php artisan config:cache || true


fi





####################################
# FIREWALL
####################################


echo "

[9/10] Security setup

"



ufw allow OpenSSH

ufw allow "Apache Full"

ufw --force enable



systemctl enable fail2ban





####################################
# SSL
####################################


if [ "$SSL" = true ]

then


echo "

Installing SSL

"


certbot --apache \
-d $DOMAIN \
--agree-tos \
--non-interactive \
-m admin@$DOMAIN || true



fi






####################################
# BACKUP
####################################



mkdir -p $BACKUP



cat > /usr/local/bin/backup-$PROJECT.sh <<EOF


#!/bin/bash


mysqldump $DB_NAME > $BACKUP/database-\$(date +%F).sql


EOF



chmod +x /usr/local/bin/backup-$PROJECT.sh





####################################
# FINISH
####################################



SERVER_IP=$(hostname -I | awk '{print $1}')



clear


echo "

================================================

        🎉 DEPLOY SUCCESS


Project:

$PROJECT



Location:

$WEB_ROOT



Database:

$DB_NAME



Access:


"



if [ "$SSL" = true ]

then

echo "https://$DOMAIN"

else

echo "http://$SERVER_IP"

fi



echo "

================================================


        Deploy by Mizyal 🚀


================================================

"
