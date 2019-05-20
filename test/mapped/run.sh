#!/bin/sh

F2M=$1
shift
I2M=$1
shift

C=0
F=
I=
for A in $*
do
    cp $A a$C
    F=$(echo $F $A a$C)
    I=$(echo $I a$C ba$C)
    C=$(expr $C + 1)
done
$F2M $F
RC=$?
if [ $RC -ne 0 ]; then
    echo "files2mapped failure."
    exit $RC
fi
$F2M $F | $I2M $I
RC=$?
if [ $RC -ne 0 ]; then
    echo "input2mapped failure."
    rm -f a* ba*
    exit $RC
fi
for A in a*
do
    B=b$A
    ./cmpjson $A $B
    if [ $? -ne 0 ]; then
        echo "$A and $B differ."
        RC=1
    else
        rm -f $A $B
    fi
done
exit $RC
