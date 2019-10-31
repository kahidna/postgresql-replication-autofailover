# a custom postgres for replication and autofailover
FROM postgres:9.6.9

MAINTAINER alfin hidayat <kahid.na@gmail.com>

ENV DEBIAN_FRONTEND=noninteractive 
ENV TERM=xterm
ENV AWS_REGION=eu-west-1
ENV AWS_DEFAULT_REGION=eu-west-1

RUN sed 's/\/home\/postgres/\/var\/lib\/postgresql\/data/g' /etc/passwd --in-place && \
OLDSTRING=$(cat /etc/passwd| grep postgres) && \
NEWSTRING="$OLDSTRING/bin/bash" && \
sed "s|$OLDSTRING|$NEWSTRING|g" /etc/passwd --in-place

RUN apt-get update && apt-get install -y \
git wget curl nano apt-utils netcat \
apt-transport-https lzop pv syslog-ng \
build-essential \
postgresql-contrib-9.6 \
postgresql-9.6-postgis-scripts \
postgresql-server-dev-9.6 \
postgresql-9.6-postgis \
postgresql-9.6-postgis-2.5 \
postgresql-9.6-postgis-2.4 \
postgresql-9.6-postgis-2.3 \
postgresql-9.6-bgw-replstatus \
postgresql-plpython-9.6 \
python-setuptools \
python-dev \
build-essential \
python-netcdf4 \
postgresql-9.6-repmgr

RUN easy_install pip; pip install wal-e===0.8.0 envdir xarray

RUN ln -s /usr/local/bin/envdir /usr/bin/envdir

WORKDIR /tmp

RUN git clone --recursive https://github.com/umitanuki/kmeans-postgresql.git

RUN cd kmeans-postgresql; make && make install

COPY conf/postgres-crontab /tmp/kmeans-postgresql/

COPY deb /tmp/deb

RUN cd /tmp/deb && dpkg -i *.deb && rm -rvf /tmp/deb

RUN crontab -u postgres /tmp/kmeans-postgresql/postgres-crontab; rm -rvf /tmp/kmeans-postgresql

RUN touch /var/lib/postgresql/data/backup-postgresql && ln -s /var/lib/postgresql/data/backup-postgresql /usr/bin/backup-postgresql

RUN usermod -u 111 postgres && groupmod -g 120 postgres

WORKDIR /var/lib/postgresql/data

EXPOSE 5432 5400

COPY entrypoint.sh /root

CMD ["/root/entrypoint.sh"]
