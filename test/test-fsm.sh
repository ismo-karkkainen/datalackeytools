#!/bin/sh

FSM=
D="datalackey-fsm"
for C in $(pwd)/$D $(pwd)/../$D $(pwd)/../../$D $1
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
$FSM -m --stderr -f 4 fsm/set-print.state
$FSM -m --stderr -f 5 fsm/run-exit.state
$FSM -m --stderr -f 5 fsm/launch-signal.state
$FSM -m --stderr -f 5 fsm/launch-terminate.state
$FSM -m --stderr -f 5 fsm/launch-wait.state
$FSM -m --stderr -f 5 fsm/feed-test.state
$FSM -m --stderr -f 4 fsm/ruby.state
$FSM -m --stderr -f 4 fsm/shell.state
$FSM -m --stderr -f 4 fsm/rename-delete.state
$FSM -m --stderr -f 4 fsm/assert_var.state
$FSM -m --stderr -f 4 fsm/default.state
$FSM -m --stderr -f 4 fsm/include-delete.state
$FSM -m --stderr -f 4 fsm/include-loop.state
$FSM -m --stderr -f 4 --warn fsm/include-overwrite.state
$FSM -m --stderr -f 4 --error fsm/include-overwrite.state
$FSM -m --stderr -f 4 fsm/file-not-found
$FSM -m --stderr -f 4 fsm/bad-file
$FSM -m --stderr -f 4 fsm/first-multi.state
$FSM -m --stderr -f 4 fsm/include-ignore.state
$FSM -m --stderr -f 4 fsm/multi.state
$FSM -m --stderr -f 4 fsm/extend.state
$FSM -m --stderr -f 4 fsm/extend-load.state
$FSM -m --stderr -f 4 fsm/jump.state
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
