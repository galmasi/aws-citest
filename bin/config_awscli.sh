#!/bin/bash

# check whether proper environment variables exist

if [[ "${AWS_KEYPAIR}" == "" ]]
then
    echo "AWS keypair not defined. Exiting."
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

# copy into place ssh configuration and credentials

echo "==> Creating AWS/SSH configuration and credentials"
mkdir ~/.ssh
cp config/ssh/config ~/.ssh
echo "${AWS_KEYPAIR}" > ~/.ssh/aws.pem
chmod 600 ~/.ssh/aws.pem

# copy in to place AWS configuration and credentials

echo "==> Creating AWSCLI configuration and credentials"
mkdir ~/.aws
cp config/aws/config ~/.aws
chmod 0600 ~/.aws/config
cat config/aws/credentials.in | \
    sed "s/%%AWS_ACCESS_KEY_ID%%/${AWS_ACCESS_KEY_ID}/" | \
    sed "s/%%AWS_ACCESS_KEY_SECRET%%/${AWS_ACCESS_KEY_SECRET/" > \
	~/.aws/credentials
chmod 0600 ~/.aws/credentials
