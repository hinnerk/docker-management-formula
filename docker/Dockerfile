FROM ubuntu:14.04

ENV DOCKER_VERSION 1.3.3

RUN \
    apt-get update && \
    apt-get -y install apt-transport-https && \
    add-apt-repository ppa:saltstack/salt && \
    apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 36A1D7869245C8950F966E92D8576A8BA88D21E9 && \
    echo deb https://get.docker.com/ubuntu docker main > /etc/apt/sources.list.d/docker.list && \
    apt-get update && \
    apt-get -y install salt-minion lxc-docker-${DOCKER_VERSION} python-pip iptables && \
    pip install docker-py==0.5.0 jsonpickle python-dateutil && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

ENV HOME /root

# Define working directory.
WORKDIR /

EXPOSE 4505 4506

# files are defined in pillar, to keep keys out of the git repository.
ADD minion.pub /etc/salt/pki/minion/minion.pub
ADD minion.pem /etc/salt/pki/minion/minion.pem
ADD minion /etc/salt/minion

CMD [ "/usr/bin/salt-minion" ]

