#!/bin/sh

F2O="../bin/files2object"
O2F="../bin/object2files"

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

cd ../test_object
rm -f a* b*
RESULTS="../test/$(basename $0 .sh).res"
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
