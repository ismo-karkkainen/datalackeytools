#!/bin/sh

RV=0
cd test
for S in "$@"
do
    C="./test-$S.sh"
    echo $C
    $C
    if [ ! -f test-$S.good ]; then
        echo "No test-$S.good to compare with."
        continue
    fi
    ./compare test-$S.good test-$S.res
    if [ $? -eq 0 ]; then
        echo "Comparison ok."
    else
        RV=1
    fi
done
exit $RV
