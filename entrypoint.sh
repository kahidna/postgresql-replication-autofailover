#!/bin/bash

CRONSETUPFILE=/var/lib/postgresql/data/enable-cron-for-backup.conf
ISPRODUCTION=$(cat $CRONSETUPFILE|head -c1)

echo ""
echo "entrypoint for postgresql replication"
echo ""
echo "change ownership crontab file for postgres"
chown -v postgres:crontab /var/spool/cron/crontabs/postgres

echo ""
echo "add log file for replication manager (repmgrd)"
touch /var/log/repmgrd.log && chown postgres.postgres /var/log/repmgrd.log

case $ISPRODUCTION in
	0) echo ""
	   echo "start container with cron disabled"
	   service cron stop
		;;
	1) echo ""
	   echo "start container with cron enabled"
	   service cron start
		;;

	*) echo "seems $CRONSETUPFILE not exists or the value is not properly setup"
	   echo "please create the file and fill only number, 0 for disable or 1 for enable"
	   echo "container will exited"
	   exit 20
		;;
esac

echo ""
echo " start syslog-ng, cron, repmgr daemon and run postgres service on foreground"
service syslog-ng start && \
service repmgrd start && su postgres -c "/usr/lib/postgresql/9.6/bin/postgres"
