#!/bin/bash

cat <<-EOF > /etc/rabbitmq/conf.d/cluster.conf
  cluster_formation.peer_discovery_backend = classic_config
  loopback_users = none
EOF

i=0
for host in $RMQ_CLUSTER; do
  ((i=i+1))

  cat <<-EOF >> /etc/rabbitmq/conf.d/cluster.conf
    cluster_formation.classic_config.nodes.${i} = $host
EOF
done

if [ ! -z "$RMQ_FAST_STARTUP" ]; then
  cat <<-EOF > /etc/rabbitmq/conf.d/cluster-time.conf
    cluster_formation.discovery_retry_limit = 1
    cluster_formation.discovery_retry_interval = 500
    cluster_formation.randomized_startup_delay_range.min = 0
    cluster_formation.randomized_startup_delay_range.max = 2
EOF
else
  cat <<-EOF > /etc/rabbitmq/conf.d/cluster-time.conf
    cluster_formation.discovery_retry_limit = 50
    cluster_formation.discovery_retry_interval = 2000
    cluster_formation.randomized_startup_delay_range.min = 15
    cluster_formation.randomized_startup_delay_range.max = 30
EOF
fi

rabbitmq-server
