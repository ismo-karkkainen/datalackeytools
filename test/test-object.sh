#!/bin/sh

F2O=
D="files2object"
for C in $(pwd)/$D $(pwd)/../$D $(pwd)/../../$D $1
do
    if [ -x $C ]; then
        F2O=$C
        break
    fi
done
if [ -z "$F2O" ]; then
    echo "files2object not found, pass it as first parameter."
    exit 1
fi
if [ "$1" = "$F2O" ]; then
    shift
fi

O2F=
D="object2files"
for C in $(pwd)/$D $(pwd)/../$D $(pwd)/../../$D $1
do
    if [ -x $C ]; then
        O2F=$C
        break
    fi
done
if [ -z "$O2F" ]; then
    echo "object2files not found, pass it as first/second parameter."
    exit 1
fi
if [ "$1" = "$O2F" ]; then
    shift
fi

trap cleanup 1 2 3 6 15

CMDS=$(mktemp)

cleanup () {
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
./run.sh $F2O $O2F missing
./run.sh $F2O $O2F tf1.json
./run.sh $F2O $O2F tfstr.json
./run.sh $F2O $O2F tfarray.json
./run.sh $F2O $O2F tfobject.json
./run.sh $F2O $O2F tfinvalid.json
./run.sh $F2O $O2F tf1.json tfstr.json tfarray.json tfobject.json
./wait.sh $F2O $O2F missing
./wait.sh $F2O $O2F tfstr.json
./wait.sh $F2O $O2F tf1.json tfstr.json tfarray.json tfobject.json
./run-stress.sh 10 1000 $F2O $O2F
./run-stress.sh 100 10000 $F2O $O2F
./run-stress.sh 200 5000000 $F2O $O2F
EOF
fi

cd object
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
    cat $$.out | sed "s#$(pwd)/##g" >> $RESULTS
    echo "####ERR" >> $RESULTS
    cat $$.err | sed "s#$(pwd)/##g" >> $RESULTS
    rm -f $$.out $$.err
done

cleanup 0
