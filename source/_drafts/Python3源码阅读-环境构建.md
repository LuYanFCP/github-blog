---
title: Python3源码阅读-环境构建
tags: 
- Python3
- 源码阅读
---

首先下载Python3.7 解压并

```bash
wget https://www.python.org/ftp/python/3.7.0/Python-3.7.0.tgz
tar -xvf tar -xvf Python-3.7.0.tgz
```

环境准备


编译与安装

```bash
./configure --prefix=$PWD/build/py37 # prefix后面放的是目录
make -j 6
make install
```

