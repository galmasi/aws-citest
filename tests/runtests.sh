#!/bin/bash

passed=0
failed=0
total=0
for test in `find tests -type d | sort`
do
    echo "RUNNING TEST: ${test}"
    echo "---------------------"
    if ${test}/runtest.sh
    then
        passed=$((passed+1))
    else
        failed=$((failed+1))
    fi
    total=$((total+1))
done

echo "======================================"
printf "| Summary: %2d/%2d/%2d total/pass/fail |" ${total} ${passed} ${failed}
echo "======================================"

exit ${failed}
