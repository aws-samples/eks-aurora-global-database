#!/bin/bash

if [[ ! -f /etc/pgbouncer/userlist.txt ]]; then
    dbpass=`echo -n "${DBPASSWD}${DBUSER}" | md5sum | awk '{print $1}'`
    echo \"${DBUSER}\" \"md5${dbpass}\" > /etc/pgbouncer/userlist.txt
fi

if [[ ! -f /etc/pgbouncer/pgbouncer.ini ]]; then
    echo "
[databases]
${DBALIAS} = host=${DBDNSRW} port=${DBPORT} dbname=${DBNAME}
${DBALIAS}-ro = host=${DBDNSRO} port=${DBPORT} dbname=${DBNAME}
[pgbouncer]
logfile = /tmp/pgbouncer.log
pidfile = /tmp/pgbouncer.pid
listen_addr = *
listen_port = ${PGBOUNCERPORT}
auth_type = ${auth_type:-md5}
auth_file = /etc/pgbouncer/userlist.txt
auth_user = ${DBUSER}
stats_users = stats, root, pgbouncer
pool_mode = ${pool_mode:-transaction}
max_client_conn = ${max_client_conn:-100}
default_pool_size = ${default_pool_size:-20}
tcp_keepalive = 1
tcp_keepidle = 1
tcp_keepintvl = 11
tcp_keepcnt = 3
tcp_user_timeout = 12500" > /etc/pgbouncer/pgbouncer.ini
fi

echo "Start PgBouncer: $*"
exec "$@"
