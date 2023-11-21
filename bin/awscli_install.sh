#!/bin/bash

curl https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -o /tmp/awscliv2.zip && \
    cd /tmp && unzip awscli2.zip && \
    ./aws/install

export PATH=${PATH}:/usr/local/bin
aws --version

