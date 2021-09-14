#!/bin/sh

STATE=
D="bin/datalackey-state"
for C in $(pwd)/$D $(pwd)/../$D $(pwd)/../../$D $1
do
    if [ -x $C ]; then
        STATE=$C
        break
    fi
done
if [ -z "$STATE" ]; then
    echo "datalackey-state not found, pass it as first parameter."
    exit 1
fi
if [ "$1" = "$STATE" ]; then
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
$STATE -m --stderr -f 4 state/set-print.state
$STATE -m --stderr -f 4 state/run-exit.state
$STATE -m --stderr -f 4 state/launch-signal.state
$STATE -m --stderr -f 4 state/launch-terminate.state
$STATE -m --stderr -f 4 state/launch-wait.state
$STATE -m --stderr -f 5 state/feed-test.state
$STATE -m --stderr -f 5 state/feed-error.state
$STATE -m --stderr -f 4 state/ruby.state
$STATE -m --stderr -f 4 state/shell.state
$STATE -m --stderr -f 4 state/rename-delete.state
$STATE -m --stderr -f 4 state/assert_var.state
$STATE -m --stderr -f 4 state/default.state
$STATE -m --stderr -f 4 state/include-delete.state
$STATE -m --stderr -f 4 state/include-loop.state
$STATE -m --stderr -f 4 --warn state/include-overwrite.state
$STATE -m --stderr -f 4 --error state/include-overwrite.state
$STATE -m --stderr -f 4 state/file-not-found
$STATE -m --stderr -f 4 state/bad-file
$STATE -m --stderr -f 4 state/first-multi.state
$STATE -m --stderr -f 4 state/include-ignore.state
$STATE -m --stderr -f 4 state/multi.state
$STATE -m --stderr -f 4 state/extend.state
$STATE -m --stderr -f 4 state/extend-load.state
$STATE -m --stderr -f 4 state/jump.state
$STATE -m --stderr -f 4 state/stack-jump.state
$STATE -m --stderr -f 4 state/label2signal.state
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
    cat $$.out | sed "s#$(pwd)/##g" | sed "s#$(pwd)##g" >> $RESULTS
    echo "####ERR" >> $RESULTS
    cat $$.err | sed "s#$(pwd)/##g" | sed "s#$(pwd)##g" >> $RESULTS
    rm -f $$.out $$.err
done

cleanup 0
