#!/bin/sh

RV=0
cd test
if [ $# -eq 0 ]; then
    for S in ./test-*.sh
    do
        echo $S
        $S
        B=$(basename $S .sh)
        if [ ! -f $B.good ]; then
            echo "No $B.good to compare with."
            continue
        fi
        ./compare $B.good $B.res
        if [ $? -eq 0 ]; then
            echo "Comparison ok."
        else
            RV=1
        fi
    done
else
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
fi
exit $RV
