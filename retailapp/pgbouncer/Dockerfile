FROM amazonlinux:2

ENV PGBOUNCER_VERSION="1.17.0"
ENV DBUSER=${DBUSER:-postgres}
ENV DBPASSWD=${DBPASSWD:-postgres}
ENV DBPORT=${DBPORT:-5432}
ENV DBNAME=${DBNAME:-oktank}
ENV DBDNSRW=${DBDNSRW:-postgres}
ENV DBDNSRO=${DBDNSRO:-"postgres-ro"}
ENV DBALIAS=${DBALIAS:-oktank}
ENV PGBOUNCERPORT=${PGBOUNCERPORT:-6432}

RUN yum -y update && \
    yum -y install git tar gcc openssl-devel openssl-perl openssl-static libevent-devel pam pam-devel wget

RUN wget -O pgbouncer.tar.gz https://www.pgbouncer.org/downloads/files/$PGBOUNCER_VERSION/pgbouncer-${PGBOUNCER_VERSION}.tar.gz && \
    tar -xvxf pgbouncer.tar.gz && \
    cd pgbouncer-${PGBOUNCER_VERSION} && \
    ./configure --prefix=/usr/local --with-pam && \
    make && \
    make install && \
    cd .. && \
    rm -rf pgbouncer.tar.gz pgbouncer-${PGBOUNCER_VERSION}

COPY config/pgbouncer.sample.ini /etc/pgbouncer/pgbouncer.sample.ini
COPY prepare_config.sh /tmp/

RUN groupadd -g 101 pguser && \
    useradd -g 101 -G 101 -s /bin/bash pguser && \
    chown -hR pguser:pguser /etc/pgbouncer && \
    chmod +x /tmp/prepare_config.sh

USER pguser

ENTRYPOINT ["/tmp/prepare_config.sh"]

CMD ["/usr/local/bin/pgbouncer", "-v", "/etc/pgbouncer/pgbouncer.ini"]

