#!/bin/bash

. util/util_ao.sh

ao_clone      . attestation-operator || exit -1
ao_build      ./attestation-operator || exit -1
ao_clean      ./attestation-operator || exit -1
ao_deploy     ./attestation-operator ./tests/scenario1/values.yml || exit -1
ao_simpletest ./attestation-operator || exit -1
ao_clean      ./attestation-operator
