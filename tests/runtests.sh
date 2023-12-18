#!/bin/bash

for test in `find tests -type d`
do
    echo "RUNNING TEST: ${test}"
    echo "---------------------"
    ${test}/runtest.sh
done
