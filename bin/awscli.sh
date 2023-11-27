#!/bin/bash


export IMAGEID=${IMAGEID:-ami-025d6a3788eadba52}
export KEYNAME=${KEYNAME:-george_aws_keypair}


# #############################################################
# configure AWS CLI for operation:
# copy github action secrets into local environment
# #############################################################

function awscli_config() {
    # check whether secrets exist as env vars
    if [[ "${AWS_KEYPAIR}" == "" ]]
    then
        echo "AWS keypair secret undefined. Exiting."
        exit -1
    fi
    
    if [[ "${AWS_ACCESS_KEY_ID}" == "" ]]
    then
        echo "AWS access key ID undefined. Exiting."
        exit -1
    fi
    
    if [[ "${AWS_ACCESS_KEY_SECRET}" == "" ]]
    then
        echo "AWS secret undefined. Exiting."
        exit -1
    fi
    
    # copy ssh configuration and credentials
    echo "==> Creating AWS/SSH configuration and credentials"
    mkdir ~/.ssh
    cp config/ssh/config ~/.ssh
    echo "${AWS_KEYPAIR}" > ~/.ssh/aws.pem
    chmod 600 ~/.ssh/aws.pem

    # copy AWS CLI configuration and credentials
    echo "==> Creating AWSCLI configuration and credentials"
    mkdir ~/.aws
    cp config/aws/config ~/.aws
    chmod 0600 ~/.aws/config
    cat config/aws/credentials.in | \
        sed "s/%%AWS_ACCESS_KEY_ID%%/${AWS_ACCESS_KEY_ID}/" | \
        sed "s^%%AWS_ACCESS_KEY_SECRET%%^${AWS_ACCESS_KEY_SECRET}^" > \
	    ~/.aws/credentials
    chmod 0600 ~/.aws/credentials
    return 0
}

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
    aws ec2 create-tags --resources --tags="Key=Name,Value=citest-$$"  >/dev/null 2>&1    
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
    local t0=$(date +%s)
    local tend=$((t0+timeout))

    # step 1: wait for instance to reach "running" state
    echo -n "Waiting for ${instanceid} to reach run state: "    
    local running=0
    while [[ $(date +%s) < $tend ]]
    do
	local status=$(eval ${statuscmd})
	if [[ ${status} == "running" ]]
        then
            running=1
            break
        fi
        echo -n "."
        sleep 10
    done
    if [[ ${running} == 0 ]]
    then
        echo "Timed out"
        exit -1
    else
        echo "Done"
    fi

    # step 2: wait for instsance to have a public IP
    local ipcmd="aws ec2 describe-instances | jq -r '.Reservations[].Instances[] | select(.InstanceId==\"${instanceid}\") | .PublicIpAddress'"
    echo -n "Waiting for ${instanceid} IP address: "
    while [[ $(date +%s) < $tend ]]
    do
        local ipaddr=$(eval ${ipcmd})
        if [[ ${ipaddr} != "" ]] ; then break ; fi
        echo -n "."
        sleep 10
    done
    if [[ ${ipaddr} == "" ]]
    then
        echo "Timed out"
        exit -1
    else
        echo ${ipaddr}
    fi

    # step 3: test public IP
    echo -n "Performing uptime test: "
    while [[ $(date +%s) < $tend ]]
    do
        if ssh -i ~/.ssh/aws.pem ${ipaddr} uptime > /dev/null 2>&1
        then
            echo "done"
            return 0
        fi
        echo -n "."
        sleep 10
    done
    echo "Timed out"
    return -1
}

# #############################################################
# Terminate an ASW instance.
# #############################################################

function awscli_terminate() {
    aws ec2 terminate-instances --instance-ids "${1}"
}
