# TL;DR 
case study, we have two nodes of postgresql,     
master.postgresql.domain (as master) replicated to slave.postgresql.domain (as slave),    
and then if master.postgresql.domain goes down. slave.postgresql.domain will be promoted as master.    
so when the master of postgres down,the slave would be promoted       
to master soon. so the backend service still can running well.

Some essential notes about my research can be read [here](#notes)

and here is the discussion of the [repmgr](https://news.ycombinator.com/item?id=15307372)

for make deployment easy and faster, I already wrote bash script. this script will build the image also     
but KEEP IN MIND, check the variable first before run the script. some variable you might want to check are :
- exposed port
- container name
- image name
- volume path
- master node
- backup command
- configuration template on the script

Table of Contents
=================

   * [TL;DR](#tldr)
   * [Table of Contents](#table-of-contents)
   * [Build the docker image](#build-the-docker-image)
   * [Start from begining ( just do this if you init the cluster or re-init the cluster)](#start-from-begining--just-do-this-if-you-init-the-cluster-or-re-init-the-cluster)
      * [create user and database repmgr just once at begin](#create-user-and-database-repmgr-just-once-at-begin)
      * [add configuration nodes for slave to master node](#add-configuration-nodes-for-slave-to-master-node)
      * [check the master accessible from the slave](#check-the-master-accessible-from-the-slave)
      * [config on the master node](#config-on-the-master-node)
      * [add master to the cluster](#add-master-to-the-cluster)
      * [add slave node to cluster](#add-slave-node-to-cluster)
      * [check the replication process](#check-the-replication-process)
   * [the autofailover](#the-autofailover)
   * [Additional information](#additional-information)
      * [Repmgr daemon configuration](#repmgr-daemon-configuration)
      * [Enabling log file for repmgr](#enabling-log-file-for-repmgr)
      * [Checking instance slave or master](#checking-instance-slave-or-master)
      * [Manage the cluster](#manage-the-cluster)
      * [Cannot modify or create on the slave node](#cannot-modify-or-create-on-the-slave-node)
      * [Backup the database](#backup-the-database)
   * [Error Notes](#error-notes)
   * [Behaviour of the postgresl replication and autofailover](#behaviour-of-the-postgresl-replication-and-autofailover)

Created by [gh-md-toc](https://github.com/ekalinin/github-markdown-toc)

# Build the docker image   
for deploy postgresql master and slave, we need to build our own images since we use few plugins or extension,   
e.g postgis, postgres-plpython, kmeans, bgw_replstatus and wal-e. to build this image, just clone the repository,
enter the root project, and then execute :   
```
docker build -t kahidna/postgres:9.6 .
```

the tage name is important, because this will ease us when build bash script or any automation for postgresql database.


# Start from begining ( just do this if you init the cluster or re-init the cluster)

here is the path, environment or variable used when deployed replication for postgresql inside the container
```
postgresql : /var/lib/postgresql/data
repmgr: /etc/repmgr
wal-e : /etc/wal-e.d
ports : 5433, 5400
postgresql : 9.6.(15) version
repmgr : 4.0.(6) version
```
notes :
the latest version of repmgr is 4.4, but seem the service not running well/cannot managed by service command from inside postgresql container
I obtain this binary from [here](https://github.com/paunin/PostDock/blob/master/src/Postgres-9.6-Repmgr-4.0.Dockerfile
)

## create user and database repmgr just once at begin
create user and the repmgr database for replication on the master node
```
docker exec -it mypostgresql su postgres -c "createuser -s repmgr"
docker exec -it mypostgresql su postgres -c "createdb repmgr -O repmgr"
```

## add configuration nodes for slave to master node
add the ip address of the slaves to pg_hba.conf file on master node. in these case, we will add slave.postgresql.domain ip address
```
    local   replication   repmgr                              trust
    host    replication   repmgr      127.0.0.1/32            trust
    host    replication   repmgr      [secondary_ip_here]/24          trust

    local   repmgr        repmgr                              trust
    host    repmgr        repmgr      127.0.0.1/32            trust
    host    repmgr        repmgr      [secondary_ip_here]/24          trust
```

## check the master accessible from the slave
before deploy the postgresql instance, check the postgresql master connection from the slave node. use following command
```
docker run -it --rm kahidna/postgres:9.6 su postgres -c "psql 'host=master.postgresql.domain user=repmgr dbname=repmgr connect_timeout=2 port=5433'"
```
command above should return following :

```
psql (9.6.9, server 9.6.15)
SSL connection (protocol: TLSv1.2, cipher: ECDHE-RSA-AES256-GCM-SHA384, bits: 256, compression: off)
Type "help" for help.

repmgr=#
```

## config on the master node
add following config to the master node `repmgr.conf` file 
```
# replication node information
node_id=1
node_name=node1
conninfo='host=master.postgresql.domain port=5433 user=repmgr dbname=repmgr connect_timeout=2'
data_directory='/var/lib/postgresql/data'

# monitoring and logging configuration
monitoring_history=yes
monitor_interval_secs=2
log_level=INFO
log_file='/var/log/repmgrd.log'
```

## add master to the cluster
following command is to add master node into the cluster, execute this on master node
```
docker exec -it mypostgresql su postgres -c "repmgr -f /etc/repmgr/repmgr.conf primary register"
```
command above should return something like this
```
INFO: connecting to primary database...
NOTICE: attempting to install extension "repmgr"
NOTICE: "repmgr" extension successfully installed
NOTICE: primary node record (ID: 1) registered
```
you can check the cluster status using the command, execute this on master node :
```
docker exec -it mypostgresql su postgres -c "repmgr -f /etc/repmgr/repmgr.conf cluster show"
```
here is the return when the cluster already initiated
```
 ID | Name  | Role    | Status    | Upstream | Location | Priority | Timeline | Connection string
----+-------+---------+-----------+----------+----------+----------+----------+--------------------------------------------------------------------------------
 1  | node1 | primary | * running |          | default  | 100      | 10       | host=master.postgresql.domain port=5433 user=repmgr dbname=repmgr connect_timeout=2
```

## add slave node to cluster
to add slave node, create repmgr.conf file configuration on the slave node, and use following command
```
node_id=2
node_name=node2
conninfo='host=slave.postgresql.domain port=5433 user=repmgr dbname=repmgr connect_timeout=2'
data_directory='/var/lib/postgresql/data'

# monitoring and logging configuration
monitoring_history=yes
monitor_interval_secs=2
log_level=INFO
log_file='/var/log/repmgrd.log'

# autofailover and how attempt it when its failed.
failover=automatic
reconnect_attempts=3 # the default is 6
reconnect_interval=10
promote_command='/usr/bin/repmgr standby promote -f /etc/repmgr/repmgr.conf --log-to-file'
follow_command='/usr/bin/repmgr standby follow -f /etc/repmgr/repmgr.conf --log-to-file --upstream-node-id=%n'
```
the first section about the base configuration for the postgres on node itself. the second is behaviour of the repmgrd logging, 
and third section is about the repmgr configuration for autofailover. in those configuration above, the slave node will check 3 times
with interval 10 seconds. so its about 30 seconds, if the master node cannot response the checker from the slave node, then repmgr will promote 
the slave node became master node. more about the [autofailover](#the-autofailover)

after that, test the connection from the slave node, using following command
```
docker run -it --rm kahidna/postgres:9.6 \
su postgres -c \
"repmgr -h master.postgresql.domain -U repmgr \
-d repmgr -f /etc/repmgr/repmgr.conf standby clone --dry-run"
```
following is the sample return when we do test or dry run command 
```
NOTICE: destination directory "/var/lib/postgresql/data" provided
INFO: connecting to source node
DETAIL: connection string is: host=master.postgresql.domain port=5433 user=repmgr dbname=repmgr
DETAIL: current installation size is 33 GB
INFO: parameter "max_wal_senders" set to 10
NOTICE: checking for available walsenders on the source node (2 required)
INFO: sufficient walsenders available on the source node
DETAIL: 2 required, 10 available
NOTICE: checking replication connections can be made to the source server (2 required)
INFO: required number of replication connections could be made to the source server
DETAIL: 2 replication connections required
NOTICE: standby will attach to upstream node 1
HINT: consider using the -c/--fast-checkpoint option
INFO: all prerequisites for "standby clone" are met
```

if there is no error report, then we can start clone the database and add node to the cluster using following command (this could take sometime)
```
docker run -it --rm \
--name postgres_temporary \
-v $POSTGRESBASEPATH/repmgr:/etc/repmgr \
-v $POSTGRESBASEPATH/repmgr/repmgrd:/etc/default/repmgrd \
-v $POSTGRESBASEPATH/wal-e.d:/etc/wal-e.d \
-v $POSTGRESBASEPATH/data:/var/lib/postgresql/data \
$POSTGRESIMAGENAME su postgres -c "repmgr -p 5433 -h master.postgresql.domain -U repmgr -d repmgr -f /etc/repmgr/repmgr.conf standby clone"
```
this command should returned output something like this.

```
NOTICE: destination directory "/var/lib/postgresql/data" provided
INFO: connecting to source node
DETAIL: connection string is: port=5433 host=master.postgresql.domain user=repmgr dbname=repmgr
DETAIL: current installation size is 33 GB
NOTICE: checking for available walsenders on the source node (2 required)
NOTICE: checking replication connections can be made to the source server (2 required)
INFO: checking and correcting permissions on existing directory "/var/lib/postgresql/data"
NOTICE: starting backup (using pg_basebackup)...
HINT: this may take some time; consider using the -c/--fast-checkpoint option
INFO: executing:
  pg_basebackup -l "repmgr base backup"  -D /var/lib/postgresql/data -h master.postgresql.domain -p 5433 -U repmgr -X stream
NOTICE: standby clone (using pg_basebackup) complete
NOTICE: you can now start your PostgreSQL server
HINT: for example: pg_ctl -D /var/lib/postgresql/data start
HINT: after starting the server, you need to register this standby with "repmgr standby register"
```
after this, we have to add the node into cluster. before do that, start the postgresql slave, we can use following command
```
docker run -d --hostname $CONTAINERHOSTNAME \
--name $CONTAINERNAME \
-v $POSTGRESBASEPATH/repmgr:/etc/repmgr \
-v $POSTGRESBASEPATH/repmgr/repmgrd:/etc/default/repmgrd \
-v $POSTGRESBASEPATH/wal-e.d:/etc/wal-e.d \
-v $POSTGRESBASEPATH/data:/var/lib/postgresql/data \
-p $POSTGRESPORT:5432 \
-p $REPGMRPORT:5400 \
$POSTGRESIMAGENAME
```

and then execute following command to add node to the cluster
```
docker exec -it -u postgres $CONTAINERNAME repmgr -f /etc/repmgr/repmgr.conf standby register
```

check the status of the cluster from node master
```
root@b:/cache/alfin/postgresql-replication-autofailover/mypostgresql/volume/repmgr# docker exec -it mypostgresql su postgres -c "repmgr -f /etc/repmgr/repmgr.conf cluster show"
 ID | Name  | Role    | Status    | Upstream | Location | Priority | Timeline | Connection string
----+-------+---------+-----------+----------+----------+----------+----------+--------------------------------------------------------------------------------
 1  | node1 | primary | * running |          | default  | 100      | 10       | host=master.postgresql.domain port=5433 user=repmgr dbname=repmgr connect_timeout=2
 2  | node2 | standby |   running | node1    | default  | 100      | 10       | host=slave.postgresql.domain port=5433 user=repmgr dbname=repmgr connect_timeout=2
```

## check the replication process
after start the slave node, we can check the replication process from the master node, following is command to check 
```
docker run -it --rm \
--name postgres_temporary \
-v $POSTGRESBASEPATH/repmgr:/etc/repmgr \
-v $POSTGRESBASEPATH/repmgr/repmgrd:/etc/default/repmgrd \
-v $POSTGRESBASEPATH/wal-e.d:/etc/wal-e.d \
-v $POSTGRESBASEPATH/data:/var/lib/postgresql/data \
$POSTGRESIMAGENAME psql -U postgres -d repmgr -c "SELECT * FROM pg_stat_replication;"
```
this should return the replication process
```
 pid | usesysid | usename | application_name | client_addr  |                 client_hostname                  | client_port |         backend_start         | backend_xmin |   state   | sent_location | write_location | flush_location | replay_location | sync_priority | sync_state
-----+----------+---------+------------------+--------------+--------------------------------------------------+-------------+-------------------------------+--------------+-----------+---------------+----------------+----------------+-----------------+---------------+------------
 178 |  5974107 | repmgr  | node2            | 52.209.218.6 | ec2-52-209-218-6.eu-west-1.compute.amazonaws.com |       47880 | 2019-09-10 09:50:23.336882+00 |              | streaming | 21B/D9000498  | 21B/D9000498   | 21B/D9000498   | 21B/D9000498    |             0 | async
(1 row)
```
and then you can try create table and insert into the table from **master node**.

# the autofailover
autofailover using repmgr handled by repmgrd service. so if you want setup autofailover, you have to make sure the configuration have proper values, 
and make sure autofailover service running. you can check it using service command 
```
service repgmgrd status
```

other operation for repmgrd service is
```
service repmgrd {start|stop|restart|force-reload|status}
```
if you need to check repmgrd version, you can use command
```
dpkg -l | grep repmgr
```

following is the output sample when the autofailover happen
```
[2019-09-11 12:55:56] [DETAIL] attempted to connect using:
  user=repmgr connect_timeout=2 dbname=repmgr host=slave.postgresql.domain port=5433 fallback_application_name=repmgr
[2019-09-11 13:14:29] [INFO] connecting to database "host=slave.postgresql.domain port=5433 user=repmgr dbname=repmgr connect_timeout=2"
[2019-09-11 13:14:29] [NOTICE] starting monitoring of node "node2" (ID: 2)
[2019-09-11 13:14:29] [INFO] monitoring connection to upstream node "node1" (node ID: 1)
[2019-09-11 13:19:30] [INFO] node "node2" (node ID: 2) monitoring upstream node "node1" (node ID: 1) in normal state
[2019-09-11 13:21:45] [WARNING] unable to connect to upstream node "node1" (node ID: 1)
[2019-09-11 13:21:45] [INFO] checking state of node 1, 1 of 3 attempts
[2019-09-11 13:21:45] [INFO] sleeping 10 seconds until next reconnection attempt
[2019-09-11 13:21:55] [INFO] checking state of node 1, 2 of 3 attempts
[2019-09-11 13:21:55] [INFO] sleeping 10 seconds until next reconnection attempt
[2019-09-11 13:22:05] [INFO] checking state of node 1, 3 of 3 attempts
[2019-09-11 13:22:05] [WARNING] unable to reconnect to node 1 after 3 attempts
[2019-09-11 13:22:05] [NOTICE] this node is the only available candidate and will now promote itself
[2019-09-11 13:22:05] [NOTICE] redirecting logging output to "/var/log/repmgrd.log"

[2019-09-11 13:22:05] [NOTICE] promoting standby to primary
[2019-09-11 13:22:05] [DETAIL] promoting server "node2" (ID: 2) using "pg_ctl  -w -D '/var/lib/postgresql/data' promote"
[2019-09-11 13:22:06] [NOTICE] STANDBY PROMOTE successful
[2019-09-11 13:22:06] [DETAIL] server "node2" (ID: 2) was successfully promoted to primary
[2019-09-11 13:22:06] [INFO] switching to primary monitoring mode
[2019-09-11 13:22:06] [NOTICE] monitoring cluster primary "node2" (node ID: 2)
[2019-09-11 13:27:08] [INFO] monitoring primary node "node2" (node ID: 2) in normal state
[2019-09-11 13:32:09] [INFO] monitoring primary node "node2" (node ID: 2) in normal state
```

if you done till the section above, then you already done replicate the postgresql. 


# Additional information
following are additional information which I provide in case we need to know something about replication manager 
e.g configure the repmgrd at first time etc
  
## Repmgr daemon configuration
repmgr can run manually, we can run it manually by execute this command : 
```
su postgres -c "repmgrd -f /etc/repmgr/repmgr.conf --pid-file /tmp/repmgrd.pid --daemonize"
```

and for repmgr daemon, first we need to edit the daemon file which located at __/etc/default/repmgrd__.   
change the configuration into this one :
```
# default settings for repmgrd. This file is source by /bin/sh from
# /etc/init.d/repmgrd

# disable repmgrd by default so it won't get started upon installation
# valid values: yes/no
REPMGRD_ENABLED=yes

# configuration file (required)
REPMGRD_CONF="/etc/repmgr/repmgr.conf"

# additional options
#REPMGRD_OPTS=""

# user to run repmgrd as
REPMGRD_USER=postgres

# repmgrd binary
REPMGRD_BIN=/usr/bin/repmgrd

# pid file
REPMGRD_PIDFILE=/var/run/repmgrd.pid
```

after configure those file, check it by run following command :
```
root@mypostgresql:/var/lib/postgresql/data# service repmgrd status
[FAIL] repmgrd is not running ... failed!
```

and then we can start it by run :
```
root@mypostgresql:/var/lib/postgresql/data# service repmgrd start
[ ok ] Starting PostgreSQL replication management and monitoring daemon: repmgrd.
```
just reminder, in this note I use repmgr 4.0

## Enabling log file for repmgr
by default repmgrd have no log file. so we need to enable this log file. first, add this configuration to __repmgr.conf__ :

```
monitoring_history=yes
monitor_interval_secs=2
```

next follow this steps :
- first create log file, in this case, I create it on /var/log/repmgrd.log, so create it using command :
```
touch /var/log/repmgrd.log
```
- after that, change the permission to postgres user :
```
chown postgres:postgres /var/log/repmgrd.log
```
- and then restart repmgr service :
```
service repmgrd restart
```

## Checking instance slave or master   
this is just additional option but usefull.   
to check which instance that run postgres master or postgres slave. you can execute command :
```
nc [postgres.hostname] 5400
```
those command should return string __MASTER__ or __STANDBY__.


## Manage the cluster
more about the [command](https://repmgr.org/docs/4.0/repmgr-command-reference.html)

check the cluster status
```
docker exec -it mypostgresql su postgres -c "repmgr -f /etc/repmgr/repmgr.conf cluster show"
```

check node status (show overview of a node's basic information and replication status)
```
docker exec -it mypostgresql su postgres -c "repmgr -f /etc/repmgr/repmgr.conf node status"
```

check node role (performs some health checks on a node from a replication perspective)
```
docker exec -it mypostgresql su postgres -c "repmgr  -f /etc/repmgr/repmgr.conf node check --role"
```
unregisters an inactive primary node from the repmgr metadata. 
This is typically when the primary has failed and is being removed from the cluster after a new primary has been promoted. 
```
docker exec -it mypostgresql su postgres -c "repmgr -f /etc/repmgr/repmgr.conf primary unregister --node-id=[node_id]"
```
Unregisters a standby with repmgr. This command does not affect the actual replication, just removes the standby's entry from the repmgr metadata. 
```
[from the node]
docker exec -it mypostgresql su postgres -c "repmgr standby unregister -f /etc/repmgr/repmgr.conf"

[from any active node]
docker exec -it mypostgresql su postgres -c "repmgr standby unregister -f /etc/repmgr/repmgr.conf --node-id=[node_id]"
```
Attaches the standby to a new primary. This command requires a valid repmgr.conf file for the standby, either specified explicitly with -f/--config-file or located in a default location; no additional arguments are required.
This command will force a restart of the standby server, which must be running. It can only be used to attach an active standby to the current primary node (and not to another standby).
To re-add an inactive node to the replication cluster, see repmgr node rejoin 
```
docker exec -it mypostgresql su postgres -c "repmgr -f /etc/repmgr/repmgr.conf standby follow"
```
promote standby to primary, execute this from the node itself
```
docker exec -it mypostgresql su postgres -c "repmgr -f /etc/repmgr/repmgr.conf standby promote"
```
to follow back slave node from failure (not yet test it)
```
docker exec -it mypostgresql su postgres -c "repmgr -f /etc/repmgr/repmgr.conf repmgr standby follow"
```

## Cannot modify or create on the slave node
as note, we cannot modify or create on the slave node, following is sample output when try create table on slave node
```
ubuntu@a2:~$ psql -U postgres -p 5433 -h localhost
psql (9.6.13, server 9.6.15)
SSL connection (protocol: TLSv1.2, cipher: ECDHE-RSA-AES256-GCM-SHA384, bits: 256, compression: off)
Type "help" for help.

postgres=# \dt
              List of relations
 Schema |       Name       | Type  |  Owner
--------+------------------+-------+----------
 public | guestbook        | table | postgres
 public | pgbench_accounts | table | postgres
 public | pgbench_branches | table | postgres
 public | pgbench_history  | table | postgres
 public | pgbench_tellers  | table | postgres
(5 rows)

postgres=# CREATE TABLE account(
postgres(#    user_id serial PRIMARY KEY,
postgres(#    username VARCHAR (50) UNIQUE NOT NULL,
postgres(#    password VARCHAR (50) NOT NULL,
postgres(#    email VARCHAR (355) UNIQUE NOT NULL,
postgres(#    created_on TIMESTAMP NOT NULL,
postgres(#    last_login TIMESTAMP
postgres(# );
ERROR:  cannot execute CREATE TABLE in a read-only transaction
postgres=#
```

## Backup the database
for daily backup postgresql, only performed by master node, the cronjob able to detect is it slave node or master node, 
```
root@mypostgresql:/var/lib/postgresql/data# su postgres
postgres@mypostgresql:~$ crontab -l
# Edit this file to introduce tasks to be run by cron.
#
# Each task to run has to be defined through a single line
# indicating with different fields when the task will be run
# and what command to run for the task
#
# To define the time you can provide concrete values for
# minute (m), hour (h), day of month (dom), month (mon),
# and day of week (dow) or use '*' in these fields (for 'any').#
# Notice that tasks will be started based on the cron's system
# daemon's notion of time and timezones.
#
# Output of the crontab jobs (including errors) is sent through
# email to the user the crontab file belongs to (unless redirected).
#
# For example, you can run a backup of all your user accounts
# at 5 a.m every week with:
# 0 5 * * 1 tar -zcf /var/backups/home.tgz /home/
#
# For more information see the manual pages of crontab(5) and cron(8)
#
# m h  dom mon dow   command
0 2 * * * bash /usr/bin/backup-postgresql >> /tmp/wal-e.log 2>&1
postgres@mypostgresql:~$ bash /usr/bin/backup-postgresql

backup script for containerized postgresql
this script will detect wheter this container need to push
the wal backup to s3 bucket or not by execute 'nc localhost 5400'

checking status on instance. . . .

its a . . . . . . . . . [STANDBY]

this instance doesn't need to push backup
```

# Error Notes
following notes about error message perhaps can help you fix error when deploying the replication :
- installed extension obsolote. can be fix by connect to `repmgr` database, and then run `ALTER EXTENSION repmgr UPDATE`
```
root@mypostgresql:/var/lib/postgresql/data# su postgres -c "repmgr -f /etc/repmgr/repmgr.conf primary register"
INFO: connecting to primary database...
ERROR: an older version of the "repmgr" extension is installed
DETAIL: version 4.0 is installed but newer version 4.4 is available
HINT: update the installed extension version by executing "ALTER EXTENSION repmgr UPDATE"
root@mypostgresql:/var/lib/postgresql/data# cat /etc/repmgr/repmgr.conf
```

- ip address not added yet on pg_hba.conf file at master node
```
ERROR: connection to database failed
DETAIL:
FATAL:  no pg_hba.conf entry for replication connection from host "52.209.218.6", user "repmgr", SSL on
FATAL:  no pg_hba.conf entry for replication connection from host "52.209.218.6", user "repmgr", SSL off
```
- the database not ready for accept connection, so wait a moment, and then try again 
```
ERROR: connection to database failed
DETAIL:
FATAL:  the database system is starting up
FATAL:  the database system is starting up
```

# Behaviour of the postgresl replication and autofailover
From the documentation above, following are conclusion behaviour of the postgresql replication and auto failover. but in short 
- slave node cannot execute query for create or modifying
- backup database only performed by master node
- auto failover configuration should configured at slave node not master node
- dont configure autofailover less than 3 round with interval 10 seconds, because restarting postgres required almost 30s
- repmgr should be run on each node
- when a slave node promoted to master. the repmgr.conf on those node will change/replaced with configuration of old-master
- changing pg_hba.conf on master, will not change pg_hba.conf on slave node, so make sure the pg_hba fixed at first
- further about pg_hba, you need to restart the service to reload the configuration
- if the slave's repmgr down, and you want to start repmgr service, you have to make sure repmgr on the master running. because slave's wont start until master's repmgr ready
