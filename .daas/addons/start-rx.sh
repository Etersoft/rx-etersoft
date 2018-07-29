#!/bin/sh

serv sshd start
serv rx-etersoft start

ip a

tail -f /var/log/nxserver.log

/bin/bash
