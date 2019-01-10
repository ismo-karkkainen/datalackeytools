#!/bin/sh

cd test
if [ $# -eq 0 ]; then
    for S in ./test-*.sh
    do
        echo $S
        $S
    done
else
    for S in "$@"
    do
        C="./test-$S.sh"
        echo $C
        $C
    done
fi
