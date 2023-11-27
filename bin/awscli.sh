#!/bin/bash


export IMAGEID=${IMAGEID:-ami-025d6a3788eadba52}
export KEYNAME=${KEYNAME:-george_aws_keypair}

# #############################################################
# Launch an AWS instance with TPM support.
# #############################################################

function awscli_launch() {
    output=$(aws ec2 run-instances \
		 --count 1 \
		 --image-id ${IMAGEID} \
		 --key-name ${KEYNAME} \
		 --security-group-ids "sg-05863e2cac3b4e3ea" \
		 --instance-type t3.medium)
    if [[ $? != 0 ]]
    then
	echo "Launch failed"
	return 1
    fi
    local instanceid=$(echo "${output}" | jq -r .Instances[0].InstanceId -)
    echo ${instanceid}
    return 0
}

# #############################################################
# retrieve the public IP of an AWS instance
# #############################################################

function awscli_get_ipaddr() {
    local instanceid=${1}
    local statuscmd="aws ec2 describe-instances | jq -r '.Reservations[].Instances[] | select(.InstanceId==\"${instanceid}\") | .PublicIpAddress'"
    eval ${statuscmd}
}

# #############################################################
# wait for a launched AWS instance to reach "running" state.
# once in running state we try to attach to the VM with ssh.
# input:
# * instanceid: the EC2 instance identifier
# * timeout: (optional) how many seconds to wait for the VM to reach running state
# output:
# * returns "0" if instance is in the desired state
# * returns -1 if instance access times out
# #############################################################

function awscli_wait_run() {
    local instanceid=${1}
    local timeout=${2:-300}
    local statuscmd="aws ec2 describe-instances | jq -r '.Reservations[].Instances[] | select(.InstanceId==\"${instanceid}\") | .State.Name'"
    local ipcmd="aws ec2 describe-instances | jq -r '.Reservations[].Instances[] | select(.InstanceId==\"${instanceid}\") | .PublicIpAddress'"
    local t0=$(date +%s)
    local tend=$((t0+timeout))
    echo -n "Waiting for ${instanceid}: "
    while [[ $(date +%s) < $tend ]]
    do
	local status=$(eval ${statuscmd})
	local ipaddr=$(eval ${ipcmd})
	if [[ ${status} == "running" ]] && \
	       [[ ${ipaddr} != "" ]] &&
	       ssh -i ~/.ssh/aws.pem ${ipaddr} uptime > /dev/null 2>&1
	then
	    echo "Done"
	    return 0
	fi
	echo -n "."
	sleep 10
    done
    echo "Timed out"
    return 1
}

# #############################################################
# Terminate an ASW instance.
# #############################################################

function awscli_terminate() {
    aws ec2 terminate-instances --instance-ids "${1}"
}
