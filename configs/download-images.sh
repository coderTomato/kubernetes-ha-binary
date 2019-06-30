#!/bin/bash

docker pull registry.cn-hangzhou.aliyuncs.com/liuyi01/calico-node:v3.1.3
docker tag registry.cn-hangzhou.aliyuncs.com/liuyi01/calico-node:v3.1.3 quay.io/calico/node:v3.1.3
docker rmi registry.cn-hangzhou.aliyuncs.com/liuyi01/calico-node:v3.1.3

docker pull registry.cn-hangzhou.aliyuncs.com/liuyi01/calico-cni:v3.1.3
docker tag registry.cn-hangzhou.aliyuncs.com/liuyi01/calico-cni:v3.1.3 quay.io/calico/cni:v3.1.3
docker rmi registry.cn-hangzhou.aliyuncs.com/liuyi01/calico-cni:v3.1.3

docker pull registry.cn-hangzhou.aliyuncs.com/liuyi01/pause-amd64:3.1
docker tag registry.cn-hangzhou.aliyuncs.com/liuyi01/pause-amd64:3.1 k8s.gcr.io/pause-amd64:3.1
docker rmi registry.cn-hangzhou.aliyuncs.com/liuyi01/pause-amd64:3.1

docker pull registry.cn-hangzhou.aliyuncs.com/liuyi01/calico-typha:v0.7.4
docker tag registry.cn-hangzhou.aliyuncs.com/liuyi01/calico-typha:v0.7.4 quay.io/calico/typha:v0.7.4
docker rmi registry.cn-hangzhou.aliyuncs.com/liuyi01/calico-typha:v0.7.4

docker pull registry.cn-hangzhou.aliyuncs.com/liuyi01/coredns:1.1.3
docker tag registry.cn-hangzhou.aliyuncs.com/liuyi01/coredns:1.1.3 k8s.gcr.io/coredns:1.1.3
docker rmi registry.cn-hangzhou.aliyuncs.com/liuyi01/coredns:1.1.3

docker pull registry.cn-hangzhou.aliyuncs.com/liuyi01/kubernetes-dashboard-amd64:v1.8.3
docker tag registry.cn-hangzhou.aliyuncs.com/liuyi01/kubernetes-dashboard-amd64:v1.8.3 k8s.gcr.io/kubernetes-dashboard-amd64:v1.8.3
docker rmi registry.cn-hangzhou.aliyuncs.com/liuyi01/kubernetes-dashboard-amd64:v1.8.3
