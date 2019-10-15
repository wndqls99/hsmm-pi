#!/usr/bin/env sh

#
# File: install.sh
# Authors: Scott Kidder, Clayton Smith
# Purpose: This script will configure a newly-imaged Raspberry Pi running
#   Raspbian Stretch Lite with the dependencies and HSMM-Pi components.
#

# 쉘 스크립트가 실행될 때 모든 라인의 실행 결과를 검사해서 실패할 경우는 바로 스크립트 실행을 종료한다.
# http://blog.woosum.net/archives/1032
set -e


if [ "$(id -u)" = "0" ]
  then echo "Please do not run as root, HTTP interface will not work"
  exit 1
fi

PROJECT_HOME=${HOME}/hsmm-pi

cd ${HOME}

# Update list of packages
sudo apt-get update

# Install Web Server deps
# https://packages.ubuntu.com/ 참조
sudo apt-get install -y \ # -y는 모든 질문을 표시하지 않고 예라고 대답하기
    apache2 \ # Http 웹 서버
    php \ # 웹 서버 프로그래밍 언어
    sqlite \ # 응용 프로그램 내장 가능한 오픈소스 데이터베이스
    php-mcrypt \ # 양방향 암호화 mcrypt_encrypt함수 모듈
    php-sqlite3 \ # SQLite3 module for PHP
    dnsmasq \ # dnsmasq는 1000 클라이언트 이하의 로컬 네트워크에서 활용하 수 있는 간단한 DHCP/DNS 서버입니다. 핵심 특징으로는 쉬운 설정과 소규모 시스템을 꼽을 수 있습니다. IPv6를 지원하기도 합니다.
    sysv-rc-conf \ # 터미널 런레벨 편집기로 시스템 시작시 네트워크 서비스 자동시작관리가 가능함
    make \ # 개발시 각 부분(모듈&파일)에서 서로 함수로 엮여있을때 한 부분만 수정되도 알아서 연동되고 컴파일 되게 해주는 유틸리티 / make는 파일간 의존도를 파악&조사한다 / http://blog.jinbo.net/ubuntu/34
    bison \ #  yacc의 기능을 개선한 GNU 파서를 생성해주는 파서 생성기이다. LALR 방식으로 작성된 문법을 처리하고 해석해서 C 코드로 만들어 준다.
    flex \ # lex의 기능을 개선한 어휘분석기를 생성해주는 소프트웨어이다. flex를 이용하면 c로 구문 분석 코드를 만들 수 있다.
    gpsd \ # gpsd는 GPS 수신기에서 데이터를 수신하고 Kismet 또는 GPS 네비게이션 소프트웨어와 같은 여러 애플리케이션에 데이터를 다시 제공하는 데몬입니다.
    libnet-gpsd3-perl \ # Perl interface to the gpsd server daemon protocol version 3 (JSON)
    ntp # Network Time Protocol daemon and utility programs / 지연이 있을 수 있는 네트워크 상에서, 컴퓨터와 컴퓨터간의 시간을 동기화 하기 위한 네트워크 프로토콜이다.

# Remove ifplugd if present, as it interferes with olsrd
sudo apt-get remove -y ifplugd


# On Ubuntu 13.04 systems this file is a symbolic link to a file in the /run/
# directory structure.  Remove the symbolic link and replace with a file that
# can be managed by HSMM-Pi.
if [ -L /etc/resolv.conf ]; then
    rm -f /etc/resolv.conf
    touch /etc/resolv.conf
fi

sudo bash -c "echo 'nameserver 8.8.8.8' > /etc/resolv.conf"
sudo chgrp www-data /etc/resolv.conf
sudo chmod g+w /etc/resolv.conf

# Checkout the HSMM-Pi project
if [ ! -e ${PROJECT_HOME} ]; then
    git clone https://github.com/urlgrey/hsmm-pi.git
else
    cd ${PROJECT_HOME}
    git pull
fi

# Set symlink to webapp
if [ -d /var/www/html ]; then
    cd /var/www/html
else
    cd /var/www
fi
if [ ! -d hsmm-pi ]; then
    sudo ln -s ${PROJECT_HOME}/src/var/www/hsmm-pi
fi
sudo rm -f index.html
sudo ln -s ${PROJECT_HOME}/src/var/www/index.html

# Create temporary directory used by HSMM-PI webapp, granting write priv's to www-data
cd ${PROJECT_HOME}/src/var/www/hsmm-pi
mkdir -p tmp/cache/models
mkdir -p tmp/cache/persistent
mkdir -p tmp/logs
mkdir -p tmp/persistent
sudo chgrp -R www-data tmp
sudo chmod -R 775 tmp

# Set permissions on system files to give www-data group write priv's
for file in /etc/hosts /etc/hostname /etc/resolv.conf /etc/network/interfaces /etc/rc.local /etc/ntp.conf /etc/default/gpsd /etc/dhcp/dhclient.conf; do
    sudo chgrp www-data ${file}
    sudo chmod g+w ${file}
done

sudo chgrp www-data /etc/dnsmasq.d
sudo chmod 775 /etc/dnsmasq.d

# Copy scripts into place
if [ ! -e /usr/local/bin/read_gps_coordinates.pl ]; then
    sudo cp ${PROJECT_HOME}/src/usr/local/bin/read_gps_coordinates.pl /usr/local/bin/read_gps_coordinates.pl
    sudo chgrp www-data /usr/local/bin/read_gps_coordinates.pl
    sudo chmod 775 /usr/local/bin/read_gps_coordinates.pl
fi

# Install Composer
php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"
php composer-setup.php
php -r "unlink('composer-setup.php');"

# Install CakePHP with Composer
php composer.phar install

sudo mkdir -p /var/data/hsmm-pi
sudo chown root.www-data /var/data/hsmm-pi
sudo chmod 775 /var/data/hsmm-pi
if [ ! -e /var/data/hsmm-pi/hsmm-pi.sqlite ]; then
    sudo Console/cake schema create -y
    sudo chown root.www-data /var/data/hsmm-pi/hsmm-pi.sqlite
    sudo chmod 664 /var/data/hsmm-pi/hsmm-pi.sqlite
fi

# enable port 8080 on the Apache server
if ! grep "Listen 8080" /etc/apache2/ports.conf; then
    sudo bash -c "echo 'Listen 8080' >> /etc/apache2/ports.conf"
fi

# allow the www-data user to run the WiFi scanning program, iwlist
if ! sudo grep "www-data" /etc/sudoers; then
    sudo bash -c "echo 'www-data ALL=(ALL) NOPASSWD: /sbin/iwlist' >> /etc/sudoers"
    sudo bash -c "echo 'www-data ALL=(ALL) NOPASSWD: /sbin/shutdown' >> /etc/sudoers"
fi

# enable apache mod-rewrite
sudo a2enmod rewrite
if [ -d /etc/apache2/conf.d ]; then
    sudo cp ${PROJECT_HOME}/src/etc/apache2/conf.d/hsmm-pi.conf /etc/apache2/conf.d/hsmm-pi.conf
elif [ -d /etc/apache2/conf-available ]; then
    sudo cp ${PROJECT_HOME}/src/etc/apache2/conf-available/hsmm-pi.conf /etc/apache2/conf-available/hsmm-pi.conf
    sudo a2enconf hsmm-pi
fi
sudo service apache2 restart

# Download and build olsrd
cd /var/tmp
git clone --branch v0.6.8.1 --depth 1 https://github.com/OLSR/olsrd.git
cd olsrd

# patch the Makefile configuration to produce position-independent code (PIC)
# applies only to ARM architecture (i.e. Beaglebone/Beagleboard)
if uname -m | grep -q arm -; then
  printf "CFLAGS +=\t-fPIC\n" >> Makefile.inc
fi

# build the OLSRD core
make
sudo make install

# build the OLSRD plugins (libs)
make libs
sudo make libs_install

sudo mkdir -p /etc/olsrd
sudo chgrp -R www-data /etc/olsrd
sudo chmod g+w -R /etc/olsrd

sudo cp ${PROJECT_HOME}/src/etc/init.d/olsrd /etc/init.d/olsrd
sudo chmod +x /etc/init.d/olsrd

sudo mkdir -p /etc/default
sudo cp ${PROJECT_HOME}/src/etc/default/olsrd /etc/default/olsrd

cd /var/tmp
rm -rf /var/tmp/olsrd

sudo rm -f /etc/olsrd.conf
sudo ln -fs /etc/olsrd/olsrd.conf /etc/olsrd.conf
sudo ln -fs /usr/local/sbin/olsrd /usr/sbin/

# enable services
sudo sysv-rc-conf --level 2345 olsrd on
sudo sysv-rc-conf --level 2345 dnsmasq on
sudo sysv-rc-conf --level 2345 gpsd on

# fix the priority for the olsrd service during bootup
sudo update-rc.d olsrd defaults 02

# install CRON jobs
sudo cp ${PROJECT_HOME}/src/etc/cron.d/* /etc/cron.d/

# print success message if we make it this far
printf "\n\n---- SUCCESS ----\n\nLogin to the web console to configure the node\n"
