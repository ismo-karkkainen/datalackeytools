#!/bin/sh

(
echo "####COMMAND Empty unpack"
echo '{}' | ../object2files
echo "####CODE $?"
echo "####OUT"
echo "####ERR"

echo "####COMMAND Straight unpack"
echo '{"x-a":"a"}' | ../object2files && test -f x-a
echo "####CODE $?"
echo "####OUT"
cat x-a
echo
echo "####ERR"

echo "####COMMAND Rename and unpack"
echo '{"x-a":"a"}' | ../object2files x-a x-b && test -f x-b
echo "####CODE $?"
echo "####OUT"
cat x-b
echo
echo "####ERR"

echo "####COMMAND Empty pack"
../files2object > x1 2> x2
echo "####CODE $?"
echo "####OUT"
cat x1
echo "####ERR"
cat x2

echo "####COMMAND Pack rename"
../files2object x-a2 x-a x-b2 x-b > x1 2> x2
echo "####CODE $?"
echo "####OUT"
cat x1
echo "####ERR"
cat x2

echo "####COMMAND Unused names in unpack"
echo '{"x-a":"a"}' | ../object2files x-a x-b x-c x-d && test -f x-b && test ! -f x-c && test ! -f x-d
echo "####CODE $?"
echo "####OUT"
echo "####ERR"

echo "####COMMAND Literal packed"
../files2object x-e ':"b"' > x1 2> x2 && test -f x-e
echo "####CODE $?"
echo "####OUT"
cat x1
echo "####ERR"
cat x2

echo "####COMMAND Unpack to subdirectory"
echo '{"x-f/f":"c"}' | ../object2files && test -d x-f && test -f x-f/f
echo "####CODE $?"
echo "####OUT"
cat x-f/f
echo
echo "####ERR"

echo "####COMMAND Pack from subdirectory"
../files2object x-g x-f/f > x1 2> x2
echo "####CODE $?"
echo "####OUT"
cat x1
echo "####ERR"
cat x2
) > $(basename $0 .sh).res

rm -rf x1 x2 x-*
