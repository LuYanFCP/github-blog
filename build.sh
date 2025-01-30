#!/bin/bash  
set -ex

git submodule update --init --recursive
cp ./_config_theme.yml ./themes/minima/_config.yml

npm install
npx hexo clean
npx hexo generate