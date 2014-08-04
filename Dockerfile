#Baseline
FROM ubuntu:14.04

MAINTAINER Tatsunori Hashimoto <thashim@mit.edu>

RUN sudo apt-get update
RUN sudo apt-get -q -y install r-base openssh-client python-pip
RUN sudo pip install awscli
RUN sudo apt-get install samtools parallel

RUN mkdir /kmm

ADD run.onestrand.r /kmm/run.onestrand.r
ADD run.cluster.onestrand.r /kmm/run.cluster.onestrand.r
ADD standalone.template.txt /kmm/standalone.template.txt
ADD user-data.txt /kmm/user-data.txt

RUN chmod +x /kmm/run.onestrand.r
RUN chmod -R 777 /kmm


#launch me with
#docker build -t thashim/kmm-launcher .
#docker run --rm -v /cluster:/cluster -i thashim/kmm-launcher /kmm/run.onestrand.r /cluster/thashim/docker/kmm-launcher/example/nrf.list /cluster/ec2/auth.txt
