FROM quay.io/orgsync/clojure:2.5.3
WORKDIR /code
ADD . /code/

RUN lein uberjar \
    && mkdir /opt/arion \
    && mv /code/target/arion.jar /opt/arion/arion.jar \
    && rm -Rf /code \
    && rm -Rf /root/.m2

WORKDIR /opt/arion

ENV HEAP_SIZE 200m
ENV MAX_PAUSE 100
ENV ARION_PORT 80
ENV ARION_IDLE_TIMEOUT 15
ENV ARION_QUEUE_PATH /var/arion
ENV ARION_MAX_MESSAGE_SIZE 1000000
ENV ARION_FSYNC_PUT true
ENV ARION_FSYNC_TAKE true
ENV ARION_FSYNC_THRESHOLD=
ENV ARION_FSYNC_INTERVAL=
ENV ARION_SLAB_SIZE 67108864
ENV KAFKA_BOOTSTRAP localhost:9092
ENV STATSD_HOST localhost
ENV STATSD_PORT 8125
ENV JMX_PORT 3333
ENV JMX_HOSTNAME arion

EXPOSE 80
VOLUME [ "/var/arion" ]

CMD exec java \
    -server \
    -XX:+UseG1GC \
    -Xmx${HEAP_SIZE} \
    -Xms${HEAP_SIZE} \
    -XX:MaxGCPauseMillis=${MAX_PAUSE} \
    -XX:+AggressiveOpts \
    -Dcom.sun.management.jmxremote.port=${JMX_PORT} \
    -Dcom.sun.management.jmxremote.rmi.port=${JMX_PORT} \
    -Dcom.sun.management.jmxremote.ssl=false \
    -Dcom.sun.management.jmxremote.authenticate=false \
    -Dcom.sun.management.jmxremote.local.only=false \
    -Djava.rmi.server.hostname=${JMX_HOSTNAME} \
    -XX:+DisableAttachMechanism \
    -jar arion.jar
