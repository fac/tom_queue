FROM rabbitmq:management

COPY entrypoint.sh /entrypoint.sh
COPY cluster.sh /cluster.sh

EXPOSE 5672 15672 25672 4369 9100 9101 9102 9103 9104 9105

ENTRYPOINT ["/entrypoint.sh"]
CMD ["/cluster.sh"]