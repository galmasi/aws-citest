#!/bin/bash

. util/util_ao.sh

ao_clone      . attestation-operator patches || exit -1
ao_patch      ./attestation-operator ./patches
ao_build      ./attestation-operator || exit -1
ao_clean      ./attestation-operator || exit -1
ao_deploy     ./attestation-operator ${PWD}/tests/2_privilegedagent/values.yml || exit -1
ao_wait       ./attestation-operator || exit -1
ao_simpletest ./attestation-operator || exit -1
ao_clean      ./attestation-operator
