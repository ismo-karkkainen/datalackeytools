#!/bin/sh
set -eu
sudo yum install -y -q cmake make clang ruby rake
git clone --branch master --depth 1 https://github.com/nlohmann/json.git
cd json
cmake .
make
sudo make install
cd ..
git clone --branch master --depth 1 https://github.com/ismo-karkkainen/datalackey.git
mkdir dlbuild
cd dlbuild
CXX=clang++ cmake -G "Unix Makefiles" -DCMAKE_BUILD_TYPE=Release ../datalackey
make -j 3
sudo make install
cd ..
cd $1
rake build
rake testgem
sudo rake install testgem
rake test
