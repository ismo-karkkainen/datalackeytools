#!/bin/sh

MAKE=
D="datalackey-make"
for C in $(pwd)/$D $(pwd)/../$D $(pwd)/../../$D $1
do
    if [ -x $C ]; then
        MAKE=$C
        break
    fi
done
if [ -z "$MAKE" ]; then
    echo "datalackey-make not found, pass it as first parameter."
    exit 1
fi
if [ "$1" = "$MAKE" ]; then
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
        echo $L > $CMDS
    done
else
    cat > $CMDS << EOF
$MAKE -m --stderr --follow 4
$MAKE -m --stderr --follow 4 tgt
$MAKE -m --stderr --follow 4 --rules make/empty.rules tgt
$MAKE -m --stderr --follow 4 --rules make/invalid.rules tgt
$MAKE -m --stderr --follow 4 --rules make/req-list-types.rules a
$MAKE -m --stderr --follow 4 --rules make/req-list-types.rules b
$MAKE -m --stderr --follow 4 --rules make/req-list-types.rules c
$MAKE -m --stderr --follow 4 --rules make/overwrite.rules a
$MAKE -m --stderr --follow 4 --warn --rules make/overwrite.rules a
$MAKE -m --stderr --follow 4 --error --rules make/overwrite.rules a
EOF
fi

RESULTS="$(basename $0 .sh).res"
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
            B="$B $P"
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
