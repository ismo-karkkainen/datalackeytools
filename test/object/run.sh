#!/bin/sh

F2O=$1
shift
O2F=$1
shift

C=0
F=
I=
for A in $*
do
    if [ -f $A ]; then
        cp $A a$C
    fi
    F=$(echo $F a$C $A)
    I=$(echo $I a$C ba$C)
    C=$(expr $C + 1)
done
$F2O $F
RC=$?
if [ $RC -ne 0 ]; then
    echo "files2object failure."
    exit $RC
fi
$F2O $F | $O2F $I
RC=$?
if [ $RC -ne 0 ]; then
    echo "object2files failure."
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
