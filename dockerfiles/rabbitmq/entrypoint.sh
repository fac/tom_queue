#!/bin/bash
set -e

mkdir -p /var/lib/rabbitmq

echo "Setting cookie"

COOKIE='/var/lib/rabbitmq/.erlang.cookie'
echo "abcdefg" > ${COOKIE} #obviously, this is only for development purposes !
chmod 600 ${COOKIE}
chown rabbitmq ${COOKIE}

chown rabbitmq:rabbitmq /var/lib/rabbitmq
exec gosu rabbitmq /usr/local/bin/docker-entrypoint.sh "$@"
