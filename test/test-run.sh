#!/bin/sh

STATE=
D="bin/datalackey-state"
for C in $1 $(pwd)/$D $(pwd)/../$D $(pwd)/../../$D
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

RUN=
D="bin/datalackey-run"
for C in $1 $(pwd)/$D $(pwd)/../$D $(pwd)/../../$D
do
    if [ -x $C ]; then
        RUN=$C
        break
    fi
done
if [ -z "$RUN" ]; then
    echo "datalackey-run not found, pass it as first or second parameter."
    exit 1
fi
if [ "$1" = "$RUN" ]; then
    shift
fi


trap cleanup 1 2 3 6 15

CMDS=$(mktemp)

cleanup () {
    rm -f $CMDS $$.out $$.err
    exit ${1:-0}
}

if [ $# -gt 0 ]; then
    for L in "$@"
    do
        echo $L > $CMDS
    done
else
    cat > $CMDS << EOF
$RUN -m $STATE --stdout -f 4 state/set-print.state
$RUN -m $STATE --stdout -f 4 state/run-exit.state
$RUN -m $STATE --stdout -f 4 state/launch-signal.state
$RUN -m $STATE --stdout -f 4 state/launch-terminate.state
$RUN -m $STATE --stdout -f 4 state/launch-wait.state
$RUN -m $STATE --stdout -f 5 state/feed-test.state
$RUN -m $STATE --stdout -f 4 state/ruby.state
$RUN -m $STATE --stdout -f 4 state/shell.state
$RUN -m $STATE --stdout -f 4 state/rename-delete.state
$RUN -m $STATE --stdout -f 4 state/assert_var.state
$RUN -m $STATE --stdout -f 4 state/default.state
$RUN -m $STATE --stdout -f 4 state/include-delete.state
$RUN -m $STATE --stdout -f 4 state/include-loop.state
$RUN -m $STATE --stdout -f 4 --warn state/include-overwrite.state
$RUN -m $STATE --stdout -f 4 --error state/include-overwrite.state
$RUN -m $STATE --stdout -f 4 state/file-not-found
$RUN -m $STATE --stdout -f 4 state/bad-file
$RUN -m $STATE --stdout -f 4 state/first-multi.state
$RUN -m $STATE --stdout -f 4 state/include-ignore.state
$RUN -m $STATE --stdout -f 4 state/multi.state
$RUN -m $STATE --stdout -f 4 state/extend.state
$RUN -m $STATE --stdout -f 4 state/extend-load.state
$RUN -m $STATE --stdout -f 4 state/jump.state
$RUN -m $STATE --stdout -f 4 state/stack-jump.state
$RUN -m $STATE --stdout -f 4 state/label2signal.state
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
            # Program full name substituted with basename.
            B=$(basename $P)
        elif [ "$P" = "$STATE" ]; then
            B="$B $(basename $P)"
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
