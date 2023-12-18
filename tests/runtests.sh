#!/bin/bash

for test in `find tests -type d`
do
    echo "RUNNING TEST: ${test}"
    echo "---------------------"
    ./tests/${test}/runtest.sh
done
