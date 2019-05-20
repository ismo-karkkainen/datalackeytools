#!/bin/sh

F2M=
D="files2mapped"
for C in $(pwd)/$D $(pwd)/../$D $(pwd)/../../$D $1
do
    if [ -x $C ]; then
        F2M=$C
        break
    fi
done
if [ -z "$F2M" ]; then
    echo "files2mapped not found, pass it as first parameter."
    exit 1
fi
if [ "$1" = "$F2M" ]; then
    shift
fi

I2M=
D="input2mapped"
for C in $(pwd)/$D $(pwd)/../$D $(pwd)/../../$D $1
do
    if [ -x $C ]; then
        I2M=$C
        break
    fi
done
if [ -z "$I2M" ]; then
    echo "input2mapped not found, pass it as first/second parameter."
    exit 1
fi
if [ "$1" = "$I2M" ]; then
    shift
fi

trap cleanup 1 2 3 6 15

CMDS=$(mktemp)

function cleanup {
    rm -f $CMDS $$.out $$.err
    exit ${1:-0}
}

if [ $# -gt 1 ]; then
    for L in "$@"
    do
        echo $L >> $CMDS
    done
else
    cat > $CMDS << EOF
./run.sh $F2M $I2M missing
./run.sh $F2M $I2M tf1.json
./run.sh $F2M $I2M tfstr.json
./run.sh $F2M $I2M tfarray.json
./run.sh $F2M $I2M tfobject.json
./run.sh $F2M $I2M tfinvalid.json
./run.sh $F2M $I2M tf1.json tfstr.json tfarray.json tfobject.json
./wait.sh $F2M $I2M missing
./wait.sh $F2M $I2M tfstr.json
./wait.sh $F2M $I2M tf1.json tfstr.json tfarray.json tfobject.json
./run-stress.sh 10 1000 $F2M $I2M
./run-stress.sh 100 10000 $F2M $I2M
./run-stress.sh 200 5000000 $F2M $I2M
EOF
fi

cd mapped
rm -f a* b*
RESULTS="../$(basename $0 .sh).res"
rm -f $RESULTS

cat $CMDS |
while read C
do
    B=
    for P in $C
    do
        if [ -z "$B" ]; then
            B=$(basename $P)
        else
            B="$B $(basename $P)"
        fi
    done
    echo "####COMMAND $B" >> $RESULTS
    $C > $$.out 2> $$.err
    R=$?
    echo "$R $B"
    echo "####CODE $R" >> $RESULTS
    echo "####OUT" >> $RESULTS
    cat $$.out | sed "s#$(pwd)/##" >> $RESULTS
    echo "####ERR" >> $RESULTS
    cat $$.err | sed "s#$(pwd)/##" >> $RESULTS
    rm -f $$.out $$.err
done

cleanup 0
