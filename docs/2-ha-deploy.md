# 二、高可用集群部署
## 1. CA证书（任意节点）
#### 1.1 安装cfssl
cfssl是非常好用的CA工具，我们用它来生成证书和秘钥文件
安装过程比较简单，如下：
```bash
# 下载
$ mkdir -p ~/bin
$ wget https://pkg.cfssl.org/R1.2/cfssl_linux-amd64 -O ~/bin/cfssl
$ wget https://pkg.cfssl.org/R1.2/cfssljson_linux-amd64 -O ~/bin/cfssljson

# 修改为可执行权限
$ chmod +x ~/bin/cfssl ~/bin/cfssljson

# 设置PATH
$ vi ~/.bash_profile
$ source ~/.bash_profile

# 验证
$ cfssl version
```
#### 1.2 生成根证书
根证书是集群所有节点共享的，只需要创建一个 CA 证书，后续创建的所有证书都由它签名。
```bash
# 生成证书和私钥
$ cd target/pki
$ cfssl gencert -initca ca-csr.json | cfssljson -bare ca

# 生成完成后会有以下文件（我们最终想要的就是ca-key.pem和ca.pem，一个秘钥，一个证书）
$ ls
ca-config.json  ca.csr  ca-csr.json  ca-key.pem  ca.pem

# 创建目录
$ ssh <user>@<node-ip> "mkdir -p /etc/kubernetes/pki/"

# 分发到每个主节点
$ scp ca*.pem <user>@<node-ip>:/etc/kubernetes/pki/

```
## 2. 部署etcd集群（master节点）
#### 2.1 下载etcd
如果你是从网盘下载的二进制可以跳过这一步（网盘中已经包含了etcd，不需要另外下载）。
没有从网盘下载bin文件的话需要自己下载etcd
```bash
$ wget https://github.com/coreos/etcd/releases/download/v3.2.18/etcd-v3.2.18-linux-amd64.tar.gz
```
#### 2.2 生成证书和私钥
```bash
# 生成证书、私钥
$ cd target/pki/etcd
$ cfssl gencert -ca=../ca.pem \
    -ca-key=../ca-key.pem \
    -config=../ca-config.json \
    -profile=kubernetes etcd-csr.json | cfssljson -bare etcd

# 分发到每个etcd节点
$ scp etcd*.pem <user>@<node-ip>:/etc/kubernetes/pki/
```
#### 2.3 创建service文件
```bash
# scp配置文件到每个master节点
$ scp target/<node-ip>/services/etcd.service <node-ip>:/etc/systemd/system/

# 创建数据和工作目录
$ ssh <user>@<node-ip> "mkdir -p /var/lib/etcd"
```
#### 2.4 启动服务
etcd 进程首次启动时会等待其它节点的 etcd 加入集群，命令 systemctl start etcd 会卡住一段时间，为正常现象。
```bash
#启动服务
$ systemctl daemon-reload && systemctl enable etcd && systemctl restart etcd

#查看状态
$ service etcd status

#查看启动日志
$ journalctl -f -u etcd
```


## 3. 部署api-server（master节点）
#### 3.1 生成证书和私钥
```bash
# 生成证书、私钥
$ cd target/pki/apiserver
$ cfssl gencert -ca=../ca.pem \
  -ca-key=../ca-key.pem \
  -config=../ca-config.json \
  -profile=kubernetes kubernetes-csr.json | cfssljson -bare kubernetes

# 分发到每个master节点
$ scp kubernetes*.pem <user>@<node-ip>:/etc/kubernetes/pki/
```

#### 3.2 创建service文件
```bash
# scp配置文件到每个master节点
$ scp target/<node-ip>/services/kube-apiserver.service <user>@<node-ip>:/etc/systemd/system/

# 创建日志目录
$ ssh <user>@<node-ip> "mkdir -p /var/log/kubernetes"
```
#### 3.3 启动服务
```bash
#启动服务
$ systemctl daemon-reload && systemctl enable kube-apiserver && systemctl restart kube-apiserver

#查看运行状态
$ service kube-apiserver status

#查看日志
$ journalctl -f -u kube-apiserver

#检查监听端口
$ netstat -ntlp
```

## 4. 部署keepalived - apiserver高可用（master节点）
#### 4.1 安装keepalived
```bash
# 在两个主节点上安装keepalived（一主一备）
$ yum install -y keepalived
```
#### 4.2 创建keepalived配置文件
```bash
# 创建目录
$ ssh <user>@<master-ip> "mkdir -p /etc/keepalived"
$ ssh <user>@<backup-ip> "mkdir -p /etc/keepalived"

# 分发配置文件
$ scp target/configs/keepalived-master.conf <user>@<master-ip>:/etc/keepalived/keepalived.conf
$ scp target/configs/keepalived-backup.conf <user>@<backup-ip>:/etc/keepalived/keepalived.conf

# 分发监测脚本
$ scp target/configs/check-apiserver.sh <user>@<master-ip>:/etc/keepalived/
$ scp target/configs/check-apiserver.sh <user>@<backup-ip>:/etc/keepalived/
```

#### 4.3 启动keepalived
```bash
# 分别在master和backup上启动服务
$ systemctl enable keepalived && service keepalived start

# 检查状态
$ service keepalived status

# 查看日志
$ journalctl -f -u keepalived

# 访问测试
$ curl --insecure https://<master-vip>:6443/
```

## 5. 部署kubectl（任意节点）
kubectl 是 kubernetes 集群的命令行管理工具，它默认从 ~/.kube/config 文件读取 kube-apiserver 地址、证书、用户名等信息。
#### 5.1 创建 admin 证书和私钥
kubectl 与 apiserver https 安全端口通信，apiserver 对提供的证书进行认证和授权。
kubectl 作为集群的管理工具，需要被授予最高权限。这里创建具有最高权限的 admin 证书。
```bash
# 创建证书、私钥
$ cd target/pki/admin
$ cfssl gencert -ca=../ca.pem \
  -ca-key=../ca-key.pem \
  -config=../ca-config.json \
  -profile=kubernetes admin-csr.json | cfssljson -bare admin
```
#### 5.2 创建kubeconfig配置文件
kubeconfig 为 kubectl 的配置文件，包含访问 apiserver 的所有信息，如 apiserver 地址、CA 证书和自身使用的证书
```bash
# 设置集群参数
$ kubectl config set-cluster kubernetes \
  --certificate-authority=../ca.pem \
  --embed-certs=true \
  --server=https://<MASTER_VIP>:6443 \
  --kubeconfig=kube.config

# 设置客户端认证参数
$ kubectl config set-credentials admin \
  --client-certificate=admin.pem \
  --client-key=admin-key.pem \
  --embed-certs=true \
  --kubeconfig=kube.config

# 设置上下文参数
$ kubectl config set-context kubernetes \
  --cluster=kubernetes \
  --user=admin \
  --kubeconfig=kube.config
  
# 设置默认上下文
$ kubectl config use-context kubernetes --kubeconfig=kube.config

# 分发到目标节点
$ scp kube.config <user>@<node-ip>:~/.kube/config
```
#### 5.3 授予 kubernetes 证书访问 kubelet API 的权限
在执行 kubectl exec、run、logs 等命令时，apiserver 会转发到 kubelet。这里定义 RBAC 规则，授权 apiserver 调用 kubelet API。
```bash
$ kubectl create clusterrolebinding kube-apiserver:kubelet-apis --clusterrole=system:kubelet-api-admin --user kubernetes
```

#### 5.4 小测试
```bash
# 查看集群信息
$ kubectl cluster-info
$ kubectl get all --all-namespaces
$ kubectl get componentstatuses
```

## 6. 部署controller-manager（master节点）
controller-manager启动后将通过竞争选举机制产生一个 leader 节点，其它节点为阻塞状态。当 leader 节点不可用后，剩余节点将再次进行选举产生新的 leader 节点，从而保证服务的可用性。
#### 6.1 创建证书和私钥
```bash
# 生成证书、私钥
$ cd target/pki/controller-manager
$ cfssl gencert -ca=../ca.pem \
  -ca-key=../ca-key.pem \
  -config=../ca-config.json \
  -profile=kubernetes controller-manager-csr.json | cfssljson -bare controller-manager
# 分发到每个master节点
$ scp controller-manager*.pem <user>@<node-ip>:/etc/kubernetes/pki/
```

#### 6.2 创建controller-manager的kubeconfig
```bash
# 创建kubeconfig
$ kubectl config set-cluster kubernetes \
  --certificate-authority=../ca.pem \
  --embed-certs=true \
  --server=https://<MASTER_VIP>:6443 \
  --kubeconfig=controller-manager.kubeconfig

$ kubectl config set-credentials system:kube-controller-manager \
  --client-certificate=controller-manager.pem \
  --client-key=controller-manager-key.pem \
  --embed-certs=true \
  --kubeconfig=controller-manager.kubeconfig

$ kubectl config set-context system:kube-controller-manager \
  --cluster=kubernetes \
  --user=system:kube-controller-manager \
  --kubeconfig=controller-manager.kubeconfig

$ kubectl config use-context system:kube-controller-manager --kubeconfig=controller-manager.kubeconfig

# 分发controller-manager.kubeconfig
$ scp controller-manager.kubeconfig <user>@<node-ip>:/etc/kubernetes/

```
#### 6.3 创建service文件
```bash
# scp配置文件到每个master节点
$ scp target/services/kube-controller-manager.service <user>@<node-ip>:/etc/systemd/system/
```
#### 6.4 启动服务
```bash
# 启动服务
$ systemctl daemon-reload && systemctl enable kube-controller-manager && systemctl restart kube-controller-manager

# 检查状态
$ service kube-controller-manager status

# 查看日志
$ journalctl -f -u kube-controller-manager

# 查看leader
$ kubectl get endpoints kube-controller-manager --namespace=kube-system -o yaml
```

## 7. 部署scheduler（master节点）
scheduler启动后将通过竞争选举机制产生一个 leader 节点，其它节点为阻塞状态。当 leader 节点不可用后，剩余节点将再次进行选举产生新的 leader 节点，从而保证服务的可用性。
#### 7.1 创建证书和私钥
```bash
# 生成证书、私钥
$ cd target/pki/scheduler
$ cfssl gencert -ca=../ca.pem \
  -ca-key=../ca-key.pem \
  -config=../ca-config.json \
  -profile=kubernetes scheduler-csr.json | cfssljson -bare kube-scheduler
```

#### 7.2 创建scheduler的kubeconfig
```bash
# 创建kubeconfig
$ kubectl config set-cluster kubernetes \
  --certificate-authority=../ca.pem \
  --embed-certs=true \
  --server=https://<MASTER_VIP>:6443 \
  --kubeconfig=kube-scheduler.kubeconfig

$ kubectl config set-credentials system:kube-scheduler \
  --client-certificate=kube-scheduler.pem \
  --client-key=kube-scheduler-key.pem \
  --embed-certs=true \
  --kubeconfig=kube-scheduler.kubeconfig

$ kubectl config set-context system:kube-scheduler \
  --cluster=kubernetes \
  --user=system:kube-scheduler \
  --kubeconfig=kube-scheduler.kubeconfig

$ kubectl config use-context system:kube-scheduler --kubeconfig=kube-scheduler.kubeconfig

# 分发kubeconfig
$ scp kube-scheduler.kubeconfig <user>@<node-ip>:/etc/kubernetes/
```
#### 7.3 创建service文件
```bash
# scp配置文件到每个master节点
$ scp target/services/kube-scheduler.service <user>@<node-ip>:/etc/systemd/system/
```
#### 7.4 启动服务
```bash
# 启动服务
$ systemctl daemon-reload && systemctl enable kube-scheduler && systemctl restart kube-scheduler

# 检查状态
$ service kube-scheduler status

# 查看日志
$ journalctl -f -u kube-scheduler

# 查看leader
$ kubectl get endpoints kube-scheduler --namespace=kube-system -o yaml
```

## 8. 部署kubelet（worker节点）
#### 8.1 预先下载需要的镜像
```bash
# 预先下载镜像到所有节点（由于镜像下载的速度过慢，我给大家提供了阿里云仓库的镜像）
$ scp target/configs/download-images.sh <user>@<node-ip>:~

# 在目标节点上执行脚本下载镜像
$ sh ~/download-images.sh
```
#### 8.2 创建bootstrap配置文件
```bash
# 创建 token
$ cd target/pki/admin
$ export BOOTSTRAP_TOKEN=$(kubeadm token create \
      --description kubelet-bootstrap-token \
      --groups system:bootstrappers:worker \
      --kubeconfig kube.config)
      
# 设置集群参数
$ kubectl config set-cluster kubernetes \
      --certificate-authority=../ca.pem \
      --embed-certs=true \
      --server=https://<MASTER_VIP>:6443 \
      --kubeconfig=kubelet-bootstrap.kubeconfig

# 设置客户端认证参数
$ kubectl config set-credentials kubelet-bootstrap \
      --token=${BOOTSTRAP_TOKEN} \
      --kubeconfig=kubelet-bootstrap.kubeconfig

# 设置上下文参数
$ kubectl config set-context default \
      --cluster=kubernetes \
      --user=kubelet-bootstrap \
      --kubeconfig=kubelet-bootstrap.kubeconfig

# 设置默认上下文
$ kubectl config use-context default --kubeconfig=kubelet-bootstrap.kubeconfig

# 把生成的配置copy到每个worker节点上
$ scp kubelet-bootstrap.kubeconfig <user>@<node-ip>:/etc/kubernetes/kubelet-bootstrap.kubeconfig

# 先在worker节点上创建目录
$ mkdir -p /etc/kubernetes/pki

# 把ca分发到每个worker节点
$ scp target/pki/ca.pem <user>@<node-ip>:/etc/kubernetes/pki/
```
#### 8.3 kubelet配置文件
把kubelet配置文件分发到每个worker节点上
```bash
$ scp target/worker-<node-ip>/kubelet.config.json <user>@<node-ip>:/etc/kubernetes/
```
#### 8.4 kubelet服务文件
把kubelet服务文件分发到每个worker节点上
```bash
$ scp target/worker-<node-ip>/kubelet.service <user>@<node-ip>:/etc/systemd/system/
```
#### 8.5 启动服务
kublet 启动时查找配置的 --kubeletconfig 文件是否存在，如果不存在则使用 --bootstrap-kubeconfig 向 kube-apiserver 发送证书签名请求 (CSR)。
kube-apiserver 收到 CSR 请求后，对其中的 Token 进行认证（事先使用 kubeadm 创建的 token），认证通过后将请求的 user 设置为 system:bootstrap:，group 设置为 system:bootstrappers，这就是Bootstrap Token Auth。

```bash
# bootstrap附权
$ kubectl create clusterrolebinding kubelet-bootstrap --clusterrole=system:node-bootstrapper --group=system:bootstrappers

# 启动服务
$ mkdir -p /var/lib/kubelet
$ systemctl daemon-reload && systemctl enable kubelet && systemctl restart kubelet

# 在master上Approve bootstrap请求
$ kubectl get csr
$ kubectl certificate approve <name> 

# 查看服务状态
$ service kubelet status

# 查看日志
$ journalctl -f -u kubelet
```

## 9. 部署kube-proxy（worker节点）
#### 9.1 创建证书和私钥
```bash
$ cd target/pki/proxy
$ cfssl gencert -ca=../ca.pem \
  -ca-key=../ca-key.pem \
  -config=../ca-config.json \
  -profile=kubernetes  kube-proxy-csr.json | cfssljson -bare kube-proxy
```
#### 9.2 创建和分发 kubeconfig 文件
```bash
# 创建kube-proxy.kubeconfig
$ kubectl config set-cluster kubernetes \
  --certificate-authority=../ca.pem \
  --embed-certs=true \
  --server=https://<master-vip>:6443 \
  --kubeconfig=kube-proxy.kubeconfig
$ kubectl config set-credentials kube-proxy \
  --client-certificate=kube-proxy.pem \
  --client-key=kube-proxy-key.pem \
  --embed-certs=true \
  --kubeconfig=kube-proxy.kubeconfig
$ kubectl config set-context default \
  --cluster=kubernetes \
  --user=kube-proxy \
  --kubeconfig=kube-proxy.kubeconfig
$ kubectl config use-context default --kubeconfig=kube-proxy.kubeconfig

# 分发kube-proxy.kubeconfig
$ scp kube-proxy.kubeconfig <user>@<node-ip>:/etc/kubernetes/
```
#### 9.3 分发kube-proxy.config
```bash
$ scp target/worker-<node-ip>/kube-proxy.config.yaml <user>@<node-ip>:/etc/kubernetes/
```

#### 9.4 分发kube-proxy服务文件
```bash
$ scp target/services/kube-proxy.service <user>@<node-ip>:/etc/systemd/system/
```

#### 9.5 启动服务
```bash
# 创建依赖目录
$ mkdir -p /var/lib/kube-proxy && mkdir -p /var/log/kubernetes

# 启动服务
$ systemctl daemon-reload && systemctl enable kube-proxy && systemctl restart kube-proxy

# 查看状态
$ service kube-proxy status

# 查看日志
$ journalctl -f -u kube-proxy
```

## 10. 部署CNI插件 - calico
我们使用calico官方的安装方式来部署。
```bash
# 创建目录（在配置了kubectl的节点上执行）
$ mkdir -p /etc/kubernetes/addons

# 上传calico配置到配置好kubectl的节点（一个节点即可）
$ scp target/addons/calico* <user>@<node-ip>:/etc/kubernetes/addons/

# 部署calico
$ kubectl create -f /etc/kubernetes/addons/calico-rbac-kdd.yaml
$ kubectl create -f /etc/kubernetes/addons/calico.yaml

# 查看状态
$ kubectl get pods -n kube-system
```

## 11. 部署DNS插件 - coredns
```bash
# 上传配置文件
$ scp target/addons/coredns.yaml <user>@<node-ip>:/etc/kubernetes/addons/

# 部署coredns
$ kubectl create -f /etc/kubernetes/addons/coredns.yaml
```
