#!/bin/bash

if curl -s --output /dev/null localhost:5672; then
  echo "RabbitMQ is already running."
  while :; do sleep 60; done
else
  rabbitmq-server
fi
