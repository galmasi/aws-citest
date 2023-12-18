#!/bin/bash

. util/util_ao.sh

ao_clone      . attestation-operator
ao_build      ./attestation-operator
ao_clean      ./attestation-operator
ao_deploy     ./attestation-operator ./tests/scenario1/values.yml
ao_simpletest ./attestation-operator
ao_clean      ./attestation-operator
