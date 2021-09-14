#!/bin/sh
set -eu
sudo apt-get update
sudo apt-get install -y -q cmake make clang ruby rake >/dev/null
git clone --branch master --depth 1 https://github.com/nlohmann/json.git >/dev/null
cd json
cmake . >/dev/null
make >/dev/null
sudo make install >/dev/null
cd ..
git clone --branch master --depth 1 https://github.com/ismo-karkkainen/datalackey.git >/dev/null
mkdir dlbuild
cd dlbuild
CXX=clang++ cmake -G "Unix Makefiles" -DCMAKE_BUILD_TYPE=Release ../datalackey >/dev/null
make -j 3 >/dev/null
sudo make install >/dev/null
cd ..
cd $1
rake test
