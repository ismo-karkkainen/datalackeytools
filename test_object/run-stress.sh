#!/bin/sh

./make-stress $1 $2 |
(
read A
read B
$3 $A | $4 $B
)
RC=0
for A in a?*
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
