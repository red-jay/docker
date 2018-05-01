FROM redjays/xenial:bootable
MAINTAINER RJ <rbergero@gmail.com>

ADD scripts /scripts

ADD all-console-setup/addcons.service /etc/systemd/system/addcons.service
ADD all-console-setup/startcons.sh    /usr/local/sbin/startcons.sh

RUN ln -s /etc/systemd/system/addcons.service /etc/systemd/system/multi-user.target.wants/addcons.service
