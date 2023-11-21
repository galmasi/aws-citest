#!/bin/bash


export IMAGEID=${IMAGEID:-ami-025d6a3788eadba52}
export KEYNAME=${KEYNAME:-george_aws_keypair}

function launch() {
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

function terminate() {
    aws ec2 terminate-instances --instance-ids "${1}"
}

function wait_run() {
    local instanceid=${1}
    local timeout=${2:-300}
    local statuscmd="aws ec2 describe-instances | jq -r '.Reservations[].Instances[] | select(.InstanceId==\"${instanceid}\") | .State.Name'"
    local t0=$(date +%s)
    local tend=$((t0+timeout))
    echo -n "Waiting for ${instanceid}: "
    while [[ $(date +%s) < $tend ]]
    do
	local status=$(eval ${statuscmd})
	if [[ ${status} == "running" ]]
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

function get_ipaddr() {
    local instanceid=${1}
    local statuscmd="aws ec2 describe-instances | jq -r '.Reservations[].Instances[] | select(.InstanceId==\"${instanceid}\") | .PublicIpAddress'"
    eval ${statuscmd}
}

#instanceid=$(launch)
#wait_run ${instanceid}
#ip=$(get_ipaddr ${instanceid})
#echo "${ip}"







