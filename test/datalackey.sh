#!/bin/sh

set -eu
cd $1

apt-get update
apt-get install -y nlohmann-json3-dev

mkdir build
cd build
CXX=clang++ cmake -G "Unix Makefiles" -DCMAKE_BUILD_TYPE=Release ../datalackey
make -j 2
mv datalackey ../exe
cd ..
rm -rf build datalackey
mv exe datalackey
