#!/bin/sh

FSM=
D="datalackey-fsm"
for C in $1 $(pwd)/$D $(pwd)/../$D $(pwd)/../../$D
do
    if [ -x $C ]; then
        FSM=$C
        break
    fi
done
if [ -z "$FSM" ]; then
    echo "datalackey-fsm not found, pass it as first parameter."
    exit 1
fi
if [ "$1" = "$FSM" ]; then
    shift
fi

RUN=
D="datalackey-run"
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

function cleanup {
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
$RUN -m $FSM --stdout -f 4 fsm/set-print.state
$RUN -m $FSM --stdout -f 4 fsm/run-exit.state
$RUN -m $FSM --stdout -f 4 fsm/launch-signal.state
$RUN -m $FSM --stdout -f 4 fsm/launch-terminate.state
$RUN -m $FSM --stdout -f 4 fsm/launch-wait.state
$RUN -m $FSM --stdout -f 5 fsm/feed-test.state
$RUN -m $FSM --stdout -f 4 fsm/ruby.state
$RUN -m $FSM --stdout -f 4 fsm/shell.state
$RUN -m $FSM --stdout -f 4 fsm/rename-delete.state
$RUN -m $FSM --stdout -f 4 fsm/assert_var.state
$RUN -m $FSM --stdout -f 4 fsm/default.state
$RUN -m $FSM --stdout -f 4 fsm/include-delete.state
$RUN -m $FSM --stdout -f 4 fsm/include-loop.state
$RUN -m $FSM --stdout -f 4 --warn fsm/include-overwrite.state
$RUN -m $FSM --stdout -f 4 --error fsm/include-overwrite.state
$RUN -m $FSM --stdout -f 4 fsm/file-not-found
$RUN -m $FSM --stdout -f 4 fsm/bad-file
$RUN -m $FSM --stdout -f 4 fsm/first-multi.state
$RUN -m $FSM --stdout -f 4 fsm/include-ignore.state
$RUN -m $FSM --stdout -f 4 fsm/multi.state
$RUN -m $FSM --stdout -f 4 fsm/extend.state
$RUN -m $FSM --stdout -f 4 fsm/extend-load.state
$RUN -m $FSM --stdout -f 4 fsm/jump.state
$RUN -m $FSM --stdout -f 4 fsm/stack-jump.state
$RUN -m $FSM --stdout -f 4 fsm/label2signal.state
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
        elif [ "$P" = "$FSM" ]; then
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
    cat $$.out | sed "s#$(pwd)/##" >> $RESULTS
    echo "####ERR" >> $RESULTS
    cat $$.err | sed "s#$(pwd)/##" >> $RESULTS
    rm -f $$.out $$.err
done

cleanup 0
