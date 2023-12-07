#!/bin/bash


# IMAGEID is defined to have UEFI and TPM support
# SGNAME is defined to have ssh access.

export IMAGEID=${IMAGEID:-ami-025d6a3788eadba52}
export KEYNAME=${KEYNAME:-george_aws_keypair}
export SGNAME=${SGNAME:-sg-05863e2cac3b4e3ea}
export INSTANCETYPE=${INSTANCETYPE:-t3.medium}

# #############################################################
# utility: install helm locally
# (not in use because the github action docker container has helm installed)
# #############################################################

function helm_install() {
    curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
    chmod 700 get_helm.sh
    ./get_helm.sh
}

# #############################################################
# utility: install awscli
# (not in use because the github action docker container has awscli installed)
# #############################################################

function awscli_install() {
    if ! curl https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -o /tmp/awscliv2.zip
    then
        echo "Failed to download awscli. Exiting."
        exit -1
    fi
    (cd /tmp && unzip awscliv2.zip && ./aws/install --update)
    export PATH=${PATH}:/usr/local/bin
    aws --version
}

# #############################################################
# configure AWS CLI for operation:
# copy github action secrets into local environment
# requires AWS_KEYPAIR (the private key or keypair corresponding to AWS key named ${KEYNAME})
# requires AWS_ACCESS_KEY_ID and AWS_ACCESS_KEY_SECRET for authenticating awscli
# #############################################################

function awscli_config() {
    echo "awscli_config: creating AWS/SSH configuration and credentials"
    # check whether secrets exist as env vars
    if [[ "${AWS_KEYPAIR}" == "" ]]
    then
        echo "ERROR: AWS keypair secret undefined. Exiting."
        exit -1
    fi
    
    if [[ "${AWS_ACCESS_KEY_ID}" == "" ]]
    then
        echo "ERROR: AWS access key ID undefined. Exiting."
        exit -1
    fi
    
    if [[ "${AWS_ACCESS_KEY_SECRET}" == "" ]]
    then
        echo "ERROR: AWS secret undefined. Exiting."
        exit -1
    fi
    
    # create ssh configuration and credentials
    mkdir ~/.ssh
    cat > ~/.ssh/config <<EOF
StrictHostKeyChecking=no
UserKnownHostsFile=/dev/null
LogLevel=ERROR
EOF
    echo "${AWS_KEYPAIR}" > ~/.ssh/aws.pem
    chmod 600 ~/.ssh/aws.pem

    # create AWS CLI configuration and credentials
    mkdir ~/.aws
    cat > ~/.aws/config <<EOF
[default]
region = us-east-1
EOF
    chmod 0600 ~/.aws/config
    cat > ~/.aws/credentials <<EOF
[default]
aws_access_key_id = ${AWS_ACCESS_KEY_ID}
aws_secret_access_key = ${AWS_ACCESS_KEY_SECRET}
EOF
    chmod 0600 ~/.aws/credentials
    return 0
}

# #############################################################
# Launch an AWS instance with TPM support.
# * IMAGEID is a pre-created AWS image with UEFI and TPM support
# * KEYNAME is a pre-created AWS keypair for accessing the VM
# * SGNAME is a pre-creates AWS security group with port 22 opened
# * INSTANCETYPE describes the AWS EC2 instance type, currently t3.medium
# * TODO add configurable disk size
# #############################################################
# \param vmname -- the name of the virtual machine to create.
# \returns instance ID in AWS EC2 format, or nonzero exit code.
# #############################################################

function awscli_launch() {
    echo "awscli_launch: creating EC2 VM with UEFI boot and TPM support"
    local vmname=${1:-citest}
    local output=$(aws ec2 run-instances \
		       --count 1 \
		       --image-id ${IMAGEID} \
		       --key-name ${KEYNAME} \
		       --security-group-ids ${SGNAME} \
		       --instance-type ${INSTANCETYPE} \
                       --block-device-mappings '[{"DeviceName": "/dev/xvda", "Ebs": {"VolumeSize": 25}}]' )
    if [[ $? != 0 ]]
    then
	echo "ERROR: EC2 launch failed"
	exit -1
    fi
    local instanceid=$(echo "${output}" | jq -r .Instances[0].InstanceId -)
    aws ec2 create-tags --resources ${instanceid} --tags="Key=Name,Value=${vmname}-$$"  >/dev/null 2>&1    
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
    echo -n "awscli_wait_run: waiting for ${instanceid} to run: "
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
        echo "ERROR: Timed out"
        exit -1
    else
        local t1=$(date +%s)
        echo "done, $((t1-t0)) seconds"
    fi

    # step 2: wait for instance to have a public IP
    local ipcmd="aws ec2 describe-instances | jq -r '.Reservations[].Instances[] | select(.InstanceId==\"${instanceid}\") | .PublicIpAddress'"
    echo -n "awscli_wait_run: waiting for ${instanceid} IP address: "
    while [[ $(date +%s) < $tend ]]
    do
        local ipaddr=$(eval ${ipcmd})
        if [[ ${ipaddr} != "" ]] ; then break ; fi
        echo -n "."
        sleep 10
    done
    if [[ ${ipaddr} == "" ]]
    then
        echo "ERROR: Timed out"
        exit -1
    else
        local t1=$(date +%s)
        echo "${ipaddr}, took $((t1-t0)) seconds"
    fi

    # step 3: test public IP
    echo -n "awscli_wait_run: performing uptime test: "
    while [[ $(date +%s) < $tend ]]
    do
        if ssh -i ~/.ssh/aws.pem ubuntu@${ipaddr} uptime > /dev/null 2>&1
        then
            local t1=$(date +%s)
            echo "done, $((t1-t0)) total seconds to launch"
            return 0
        fi
        echo -n "."
        sleep 10
    done
    echo "ERROR: Timed out"
    return -1
}

# #############################################################
# Terminate an AWS instance.
# #############################################################

function awscli_terminate() {
    echo "awscli_terminate: destroying EC2 VM ID ${1}"
    aws ec2 terminate-instances --instance-ids "${1}" > /dev/null 2>&1
}

# #############################################################
# install minikube on the AWS instance
# #############################################################

function awscli_start_minikube() {
    echo "awscli_start_minikube (on IP=${1})"
    local ipaddr=${1}
    # install docker
    ssh -i ~/.ssh/aws.pem ubuntu@${ipaddr} <<EOF
sudo apt-get update
sudo apt-get install -y docker.io
sudo usermod -aG docker ubuntu
EOF
    # install and start minikube
    ssh -i ~/.ssh/aws.pem ubuntu@${ipaddr} <<EOF    
curl https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64 -o /tmp/minikube-linux-amd64
sudo mv /tmp/minikube-linux-amd64 /usr/local/bin/minikube
sudo chmod 755 /usr/local/bin/minikube
/usr/local/bin/minikube start
/usr/local/bin/minikube kubectl get nodes
EOF
}


# #############################################################
# access minikube from the github action container
# * copy credentials from EC2 VM with scp
# * fix up kube configuration
# * create a ssh tunnel on local port 8443
# * use tunnel to check minikube function
# #############################################################

function awscli_access_minikube() {
    echo "awscli_checking minikube access (on IP=${1})"
    local ipaddr=${1}
    mkdir -p ${HOME}/.kube
    scp -i ~/.ssh/aws.pem ubuntu@${ipaddr}:.kube/config ${HOME}/.kube/config && \
    scp -i ~/.ssh/aws.pem ubuntu@${ipaddr}:.minikube/ca.crt ${HOME}/.kube/ca.crt && \
    scp -i ~/.ssh/aws.pem ubuntu@${ipaddr}:.minikube/profiles/minikube/client.crt ${HOME}/.kube/client.crt && \
    scp -i ~/.ssh/aws.pem ubuntu@${ipaddr}:.minikube/profiles/minikube/client.key ${HOME}/.kube/client.key
    if [[ $? != 0 ]]
    then
        echo "failed to copy credentials from EC2 VM"
        exit -1
    fi

    local serverip=$(yq -r .clusters[0].cluster.server .kube/config | sed "s%https://%%" | sed "s/:.*//")

    # change the kube configuration
    sed -i "s%certificate-authority:.*%certificate-authority: ${HOME}/.kube/ca.crt%" ${HOME}/.kube/config
    sed -i "s%client-certificate:.*%client-certificate: ${HOME}/.kube/client.crt%" ${HOME}/.kube/config
    sed -i "s%client-key:.*%client-key: ${HOME}/.kube/client.key%" ${HOME}/.kube/config
    sed -i "s%server:.*%server: https://127.0.0.1:8443%" ${HOME}/.kube/config
    
    # we don't need to worry about cleaning up this connection,
    # because the last step of any GH action is to remove the target VM itself.
    nohup ssh -N -L 0.0.0.0:8443:${serverip}:8443 -i ~/.ssh/aws.pem ubuntu@${ipaddr} &

    # test
    sleep 5
    kubectl get nodes
}


