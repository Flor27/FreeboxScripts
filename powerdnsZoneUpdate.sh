#!/bin/sh
cd /usr/local/sbin

./pdnsCfgFiles.pl

service pdns restart

exit
