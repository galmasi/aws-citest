#!/bin/bash

# #########################
# step 1: clone AO
# #########################

if ! test -d attestation-operator
then
    echo "Checking out AO"
    git clone https://github.com/keylime/attestation-operator > /tmp/ao-clone.log 2>&1
    if [[ $? != 0 ]]
    then
        echo "ERROR: failed to checkout AO. Attaching log."
        cat /tmp/ao-clone.log
        exit -1
    fi
    echo "  done"
fi
cd attestation-operator

# #########################
# step 2: build the helm chart
# #########################

echo -n "Building the helm chart ..."
make helm-build > /tmp/helm-build.log 2>&1
if [[ $? != 0 ]]
then
    echo "\nERROR: helm build failed. Attaching log."
    cat /tmp/helm-build.log
    exit -1
fi
echo "done"

# #########################
# step 3: create configuration for a minimal deployment
# #########################

echo -n "Creating keylime configuration ... "
cat > values.yaml <<EOF
tags:
  init: true
  registrar: true
  verifier: true
  agent: false
  tenant: true

global:
  service:
    registrar:
      type: NodePort
    verifier:
      type: NodePort
EOF
echo "done"

# #########################
# step 4: do away with any previous deployments
# #########################

echo -n "Removing any previous deployments of keylime ... "
make helm-undeploy > /dev/null 2>&1
echo "done"


# #########################
# step 5: deploy keylime
# #########################

echo -n "Deploying keylime with helm ... "
make helm-keylime-deploy > /tmp/helm-deploy.log 2>&1
if [[ $? != 0 ]]
then
    echo "\nERROR: helm deploy failed. Attaching log."
    cat /tmp/helm-deploy.log
    exit -1
fi
echo "done"


# #########################
# step 6: wait until pods are running
# #########################

t0=$(date +%s)
for comp in registrar tenant verifier
do
    echo -n "Waiting for ${comp} to be in run state: "
    while ! kubectl get pods -n keylime --no-headers | grep ${comp} | grep Run > /dev/null 2>&1
    do
        if [[ ${t1} -gt $((t0+300)) ]]
        then
            echo "\nTIMED OUT."
            exit -1
        fi
        echo -n "."
        sleep 5
        t1=$(date +%s)
    done
    echo "done"
done

# #########################
# step 7: test deployment with AO test script
# #########################

echo -n "testing keylime function ... "
make helm-keylime-test > /tmp/keylime-test.log 2>&1
if [[ $? != 0 ]]
then
    echo "\nERROR: test failed. Attaching log."
    cat /tmp/keylime-test.log
    exit -1
fi
echo "done"
echo


