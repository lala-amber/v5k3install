# 0.背景

在写完上一篇文章后发现，其实V5k3的组合也可以使用。Verilator v5.x 系列版本完全支持本项目的编译与仿真。
不同于 v3 版本，Verilator v5 引入了更严格的访问控制机制：要从 Verilator 生成的 C++ 仿真模型中访问内部信号或变量，必须在 Verilog 源码中显式声明为 public。

在 Verilator v5 中，这种声明需使用如下语法：

```
(* verilator public_flat_rw *) reg [127:0] Drg;
(* verilator public_flat_rw *) wire [127:0] Dnext_debug;
```

这将使信号可以通过 Verilator 生成的 C++ 模型中的 rootp->AES_ENC__DOT__Drg 等方式访问，从而配合 KLEE 等符号执行引擎进行断言验证与调试。

如果未显式声明，Verilator 将不会导出对应变量的访问接口，导致编译或链接阶段出现 undefined reference 或访问失败的情况。

# 搭建

在经过大量测试之后，编写了一个懒人安装v5k3组合的脚本，可以将代码复制保存为.sh，赋予可执行权限后运行即可。

```
#!/bin/bash
set -e

step() {
    echo -e "\n\033[1;36m🔷 Step $1: $2\033[0m"
    sleep 0.5
}
run() {
    echo -e "   \033[90m$@\033[0m"
    sleep 0.2
    eval "$@"
}

INSTALL_SCRIPT=install_verilator.sh

step "0" "生成容器内 Verilator 安装脚本 ${INSTALL_SCRIPT}"
cat << EOF > ${INSTALL_SCRIPT}
#!/bin/bash
set -e

step() {
    echo -e "\n\033[1;36m🔷 Step \$1: \$2\033[0m"
    sleep 0.5
}
run() {
    echo -e "   \033[90m\$@\033[0m"
    sleep 0.2
    eval "\$@"
}

step "1" "导入 Kitware GPG 公钥（解决 NO_PUBKEY 报错）"
if command -v apt-key &>/dev/null; then
    run "apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 16FAAD7AF99A65E2 || true"
else
    run "curl -fsSL https://apt.kitware.com/keys/kitware-archive-latest.asc | gpg --dearmor -o /usr/share/keyrings/kitware-archive-keyring.gpg"
fi

step "2" "更新软件包索引"
run "apt update"

step "3" "安装构建工具与依赖库"
run "apt-get install -y git help2man perl python3 make g++ flex bison ccache autoconf automake libtool"
run "apt-get install -y libgoogle-perftools-dev numactl perl-doc"
run "apt-get install -y libfl2 libfl-dev zlib1g zlib1g-dev"

step "4" "克隆并切换到 verilator v5.032"
run "rm -rf verilator"
run "git clone https://github.com/verilator/verilator"
run "cd verilator"
run "git fetch --all --tags"
run "git checkout v5.032"

step "5" "构建并安装 Verilator"
run "autoconf"
run "./configure"
run "make -j\$(nproc)"
run "make install"

step "6" "验证 Verilator 安装"
run "verilator --version"
echo -e "\n\033[1;32m✅ Verilator v5.032 安装成功！\033[0m"
EOF

chmod +x ${INSTALL_SCRIPT}

step "1" "检查是否已存在 klee/klee 镜像"
if sudo docker images | grep -q '^klee/klee'; then
    echo -e "   ✅ 已存在 klee/klee 镜像，跳过拉取"
else
    step "1.1" "拉取 KLEE 官方镜像"
    run "sudo docker pull klee/klee"
fi

step "2" "检查是否已存在容器 v5k3"
if sudo docker ps -a --format '{{.Names}}' | grep -q '^v5k3$'; then
    echo -e "   ✅ 容器 v5k3 已存在，跳过创建"
else
    step "2.1" "启动后台容器 v5k3"
    run "sudo docker run -itd --name v5k3 klee/klee tail -f /dev/null"
fi

step "3" "复制安装脚本到容器 /root/"
run "sudo docker cp ${INSTALL_SCRIPT} v5k3:/root/"

step "4" "赋权并执行安装脚本（以 root 用户）"
run "sudo docker exec --user root -it v5k3 chmod +x /root/${INSTALL_SCRIPT}"
run "sudo docker exec --user root -it v5k3 bash /root/${INSTALL_SCRIPT}"

step "5" "验证 Verilator 与 KLEE 版本"
run "sudo docker exec --user root -it v5k3 verilator --version"
run "sudo docker exec -it v5k3 klee --version"
step "6" "自动进入容器 v5k3 交互终端"
run "sudo docker exec -it v5k3 /bin/bash"
```

```
┌──(hx㉿orz)-[~]
└─$ ./installv5k3.sh
```


![](https://files.mdnice.com/user/53928/79bccc75-a777-4d45-b657-f76b768fb179.png)

![](https://files.mdnice.com/user/53928/397741bd-c492-44b0-8695-1b961890a7c6.png)

# 2.安装日志

```
┌──(hx㉿orz)-[~]
└─$ ./installv5k3.sh

🔷 Step 0: 生成容器内 Verilator 安装脚本 install_verilator.sh

🔷 Step 1: 检查是否已存在 klee/klee 镜像
   ✅ 已存在 klee/klee 镜像，跳过拉取

🔷 Step 2: 检查是否已存在容器 v5k3

🔷 Step 2.1: 启动后台容器 v5k3
   sudo docker run -itd --name v5k3 klee/klee tail -f /dev/null
20df274bfc6432687b7ca526bed56b066e5c404460d9dce3fea090d48f17e6e4

🔷 Step 3: 复制安装脚本到容器 /root/
   sudo docker cp install_verilator.sh v5k3:/root/
Successfully copied 3.07kB to v5k3:/root/

🔷 Step 4: 赋权并执行安装脚本（以 root 用户）
   sudo docker exec --user root -it v5k3 chmod +x /root/install_verilator.sh
   sudo docker exec --user root -it v5k3 bash /root/install_verilator.sh

🔷 Step 1: 导入 Kitware GPG 公钥（解决 NO_PUBKEY 报错）
   apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 16FAAD7AF99A65E2 || true
Warning: apt-key is deprecated. Manage keyring files in trusted.gpg.d instead (see apt-key(8)).
Executing: /tmp/apt-key-gpghome.3MhklnngfX/gpg.1.sh --keyserver keyserver.ubuntu.com --recv-keys 16FAAD7AF99A65E2
gpg: key A65337CCA8A748B8: public key "Kitware Apt Archive Automatic Signing Key (2025) <debian@kitware.com>" imported
gpg: Total number processed: 1
gpg:               imported: 1

🔷 Step 2: 更新软件包索引
   apt update
Get:1 http://archive.ubuntu.com/ubuntu jammy InRelease [270 kB]                             
Get:2 http://security.ubuntu.com/ubuntu jammy-security InRelease [129 kB]                            
Get:3 https://apt.kitware.com/ubuntu jammy InRelease [15.5 kB]                                                
Get:4 http://archive.ubuntu.com/ubuntu jammy-updates InRelease [128 kB]                             
Get:5 http://archive.ubuntu.com/ubuntu jammy-backports InRelease [127 kB]
Get:6 https://apt.kitware.com/ubuntu jammy/main amd64 Packages [68.7 kB]     
Get:7 http://security.ubuntu.com/ubuntu jammy-security/main amd64 Packages [2788 kB]   
Get:8 http://archive.ubuntu.com/ubuntu jammy/universe amd64 Packages [17.5 MB]            
Get:9 http://security.ubuntu.com/ubuntu jammy-security/universe amd64 Packages [1243 kB]          
Get:10 http://security.ubuntu.com/ubuntu jammy-security/multiverse amd64 Packages [47.7 kB]                                            
Get:11 http://security.ubuntu.com/ubuntu jammy-security/restricted amd64 Packages [4000 kB]                                            
Get:12 http://archive.ubuntu.com/ubuntu jammy/restricted amd64 Packages [164 kB]                                                       
Get:13 http://archive.ubuntu.com/ubuntu jammy/main amd64 Packages [1792 kB]                                                            
Get:14 http://archive.ubuntu.com/ubuntu jammy/multiverse amd64 Packages [266 kB]                                                       
Get:15 http://archive.ubuntu.com/ubuntu jammy-updates/multiverse amd64 Packages [55.7 kB]                                              
Get:16 http://archive.ubuntu.com/ubuntu jammy-updates/restricted amd64 Packages [4246 kB]                                              
Get:17 http://archive.ubuntu.com/ubuntu jammy-updates/universe amd64 Packages [1542 kB]                                                
Get:18 http://archive.ubuntu.com/ubuntu jammy-updates/main amd64 Packages [3140 kB]                                                    
Get:19 http://archive.ubuntu.com/ubuntu jammy-backports/main amd64 Packages [82.7 kB]                                                  
Get:20 http://archive.ubuntu.com/ubuntu jammy-backports/universe amd64 Packages [35.2 kB]                                              
Fetched 37.6 MB in 22s (1733 kB/s)                                                                                                     
Reading package lists... Done
Building dependency tree... Done
Reading state information... Done
140 packages can be upgraded. Run 'apt list --upgradable' to see them.
W: https://apt.kitware.com/ubuntu/dists/jammy/InRelease: Key is stored in legacy trusted.gpg keyring (/etc/apt/trusted.gpg), see the DEPRECATION section in apt-key(8) for details.

🔷 Step 3: 安装构建工具与依赖库
   apt-get install -y git help2man perl python3 make g++ flex bison ccache autoconf automake libtool
Reading package lists... Done
Building dependency tree... Done
Reading state information... Done
g++ is already the newest version (4:11.2.0-1ubuntu1).
g++ set to manually installed.
make is already the newest version (4.3-4.1build1).
make set to manually installed.
The following additional packages will be installed:
  autotools-dev git-man less libcbor0.8 liberror-perl libfido2-1 libfl-dev libfl2 libhiredis0.14 liblocale-gettext-perl libltdl-dev
  libperl5.34 libpython3-stdlib libsigsegv2 libxmuu1 m4 openssh-client perl-base perl-modules-5.34 python3-minimal xauth
Suggested packages:
  autoconf-archive gnu-standards autoconf-doc gettext bison-doc distcc | icecc flex-doc gettext-base git-daemon-run
  | git-daemon-sysvinit git-doc git-email git-gui gitk gitweb git-cvs git-mediawiki git-svn libtool-doc gfortran | fortran95-compiler
  gcj-jdk m4-doc keychain libpam-ssh monkeysphere ssh-askpass perl-doc libterm-readline-gnu-perl | libterm-readline-perl-perl
  libtap-harness-archive-perl python3-doc python3-tk python3-venv
Recommended packages:
  netbase
The following NEW packages will be installed:
  autoconf automake autotools-dev bison ccache flex git git-man help2man less libcbor0.8 liberror-perl libfido2-1 libfl-dev libfl2
  libhiredis0.14 liblocale-gettext-perl libltdl-dev libsigsegv2 libtool libxmuu1 m4 openssh-client xauth
The following packages will be upgraded:
  libperl5.34 libpython3-stdlib perl perl-base perl-modules-5.34 python3 python3-minimal
7 upgraded, 24 newly installed, 0 to remove and 133 not upgraded.
Need to get 18.5 MB of archives.
After this operation, 37.1 MB of additional disk space will be used.
Get:1 http://archive.ubuntu.com/ubuntu jammy-updates/main amd64 libperl5.34 amd64 5.34.0-3ubuntu1.4 [4820 kB]
Get:2 http://archive.ubuntu.com/ubuntu jammy-updates/main amd64 perl amd64 5.34.0-3ubuntu1.4 [232 kB]
Get:3 http://archive.ubuntu.com/ubuntu jammy-updates/main amd64 perl-base amd64 5.34.0-3ubuntu1.4 [1759 kB]
Get:4 http://archive.ubuntu.com/ubuntu jammy-updates/main amd64 perl-modules-5.34 all 5.34.0-3ubuntu1.4 [2977 kB]
Get:5 http://archive.ubuntu.com/ubuntu jammy/main amd64 liblocale-gettext-perl amd64 1.07-4build3 [17.1 kB]
Get:6 http://archive.ubuntu.com/ubuntu jammy-updates/main amd64 python3-minimal amd64 3.10.6-1~22.04.1 [24.3 kB]
Get:7 http://archive.ubuntu.com/ubuntu jammy-updates/main amd64 python3 amd64 3.10.6-1~22.04.1 [22.8 kB]
Get:8 http://archive.ubuntu.com/ubuntu jammy-updates/main amd64 libpython3-stdlib amd64 3.10.6-1~22.04.1 [6812 B]
Get:9 http://archive.ubuntu.com/ubuntu jammy/main amd64 libsigsegv2 amd64 2.13-1ubuntu3 [14.6 kB]
Get:10 http://archive.ubuntu.com/ubuntu jammy/main amd64 m4 amd64 1.4.18-5ubuntu2 [199 kB]
Get:11 http://archive.ubuntu.com/ubuntu jammy/main amd64 flex amd64 2.6.4-8build2 [307 kB]
Get:12 http://archive.ubuntu.com/ubuntu jammy-updates/main amd64 less amd64 590-1ubuntu0.22.04.3 [142 kB]
Get:13 http://archive.ubuntu.com/ubuntu jammy/main amd64 libcbor0.8 amd64 0.8.0-2ubuntu1 [24.6 kB]
Get:14 http://archive.ubuntu.com/ubuntu jammy/main amd64 libfido2-1 amd64 1.10.0-1 [82.8 kB]
Get:15 http://archive.ubuntu.com/ubuntu jammy/main amd64 libxmuu1 amd64 2:1.1.3-3 [10.2 kB]
Get:16 http://archive.ubuntu.com/ubuntu jammy-updates/main amd64 openssh-client amd64 1:8.9p1-3ubuntu0.11 [903 kB]
Get:17 http://archive.ubuntu.com/ubuntu jammy/main amd64 xauth amd64 1:1.1-1build2 [27.5 kB]                                           
Get:18 http://archive.ubuntu.com/ubuntu jammy/main amd64 autoconf all 2.71-2 [338 kB]                                                  
Get:19 http://archive.ubuntu.com/ubuntu jammy/main amd64 autotools-dev all 20220109.1 [44.9 kB]                                        
Get:20 http://archive.ubuntu.com/ubuntu jammy/main amd64 automake all 1:1.16.5-1.3 [558 kB]                                            
Get:21 http://archive.ubuntu.com/ubuntu jammy/main amd64 bison amd64 2:3.8.2+dfsg-1build1 [748 kB]                                     
Get:22 http://archive.ubuntu.com/ubuntu jammy/universe amd64 libhiredis0.14 amd64 0.14.1-2 [32.8 kB]                                   
Get:23 http://archive.ubuntu.com/ubuntu jammy/universe amd64 ccache amd64 4.5.1-1 [495 kB]                                             
Get:24 http://archive.ubuntu.com/ubuntu jammy/main amd64 liberror-perl all 0.17029-1 [26.5 kB]                                         
Get:25 http://archive.ubuntu.com/ubuntu jammy-updates/main amd64 git-man all 1:2.34.1-1ubuntu1.12 [955 kB]                             
Get:26 http://archive.ubuntu.com/ubuntu jammy-updates/main amd64 git amd64 1:2.34.1-1ubuntu1.12 [3165 kB]                              
Get:27 http://archive.ubuntu.com/ubuntu jammy/universe amd64 help2man amd64 1.49.1 [186 kB]                                            
Get:28 http://archive.ubuntu.com/ubuntu jammy/main amd64 libfl2 amd64 2.6.4-8build2 [10.7 kB]                                          
Get:29 http://archive.ubuntu.com/ubuntu jammy/main amd64 libfl-dev amd64 2.6.4-8build2 [6236 B]                                        
Get:30 http://archive.ubuntu.com/ubuntu jammy/main amd64 libltdl-dev amd64 2.4.6-15build2 [169 kB]                                     
Get:31 http://archive.ubuntu.com/ubuntu jammy/main amd64 libtool all 2.4.6-15build2 [164 kB]                                           
Fetched 18.5 MB in 8s (2291 kB/s)                                                                                                      
debconf: delaying package configuration, since apt-utils is not installed
(Reading database ... 31181 files and directories currently installed.)
Preparing to unpack .../libperl5.34_5.34.0-3ubuntu1.4_amd64.deb ...
Unpacking libperl5.34:amd64 (5.34.0-3ubuntu1.4) over (5.34.0-3ubuntu1.3) ...
Preparing to unpack .../perl_5.34.0-3ubuntu1.4_amd64.deb ...
Unpacking perl (5.34.0-3ubuntu1.4) over (5.34.0-3ubuntu1.3) ...
Preparing to unpack .../perl-base_5.34.0-3ubuntu1.4_amd64.deb ...
Unpacking perl-base (5.34.0-3ubuntu1.4) over (5.34.0-3ubuntu1.3) ...
Setting up perl-base (5.34.0-3ubuntu1.4) ...
(Reading database ... 31181 files and directories currently installed.)
Preparing to unpack .../perl-modules-5.34_5.34.0-3ubuntu1.4_all.deb ...
Unpacking perl-modules-5.34 (5.34.0-3ubuntu1.4) over (5.34.0-3ubuntu1.3) ...
Selecting previously unselected package liblocale-gettext-perl.
Preparing to unpack .../liblocale-gettext-perl_1.07-4build3_amd64.deb ...
Unpacking liblocale-gettext-perl (1.07-4build3) ...
Preparing to unpack .../python3-minimal_3.10.6-1~22.04.1_amd64.deb ...
Unpacking python3-minimal (3.10.6-1~22.04.1) over (3.10.6-1~22.04) ...
Setting up python3-minimal (3.10.6-1~22.04.1) ...
(Reading database ... 31195 files and directories currently installed.)
Preparing to unpack .../00-python3_3.10.6-1~22.04.1_amd64.deb ...
running python pre-rtupdate hooks for python3.10...
Unpacking python3 (3.10.6-1~22.04.1) over (3.10.6-1~22.04) ...
Preparing to unpack .../01-libpython3-stdlib_3.10.6-1~22.04.1_amd64.deb ...
Unpacking libpython3-stdlib:amd64 (3.10.6-1~22.04.1) over (3.10.6-1~22.04) ...
Selecting previously unselected package libsigsegv2:amd64.
Preparing to unpack .../02-libsigsegv2_2.13-1ubuntu3_amd64.deb ...
Unpacking libsigsegv2:amd64 (2.13-1ubuntu3) ...
Selecting previously unselected package m4.
Preparing to unpack .../03-m4_1.4.18-5ubuntu2_amd64.deb ...
Unpacking m4 (1.4.18-5ubuntu2) ...
Selecting previously unselected package flex.
Preparing to unpack .../04-flex_2.6.4-8build2_amd64.deb ...
Unpacking flex (2.6.4-8build2) ...
Selecting previously unselected package less.
Preparing to unpack .../05-less_590-1ubuntu0.22.04.3_amd64.deb ...
Unpacking less (590-1ubuntu0.22.04.3) ...
Selecting previously unselected package libcbor0.8:amd64.
Preparing to unpack .../06-libcbor0.8_0.8.0-2ubuntu1_amd64.deb ...
Unpacking libcbor0.8:amd64 (0.8.0-2ubuntu1) ...
Selecting previously unselected package libfido2-1:amd64.
Preparing to unpack .../07-libfido2-1_1.10.0-1_amd64.deb ...
Unpacking libfido2-1:amd64 (1.10.0-1) ...
Selecting previously unselected package libxmuu1:amd64.
Preparing to unpack .../08-libxmuu1_2%3a1.1.3-3_amd64.deb ...
Unpacking libxmuu1:amd64 (2:1.1.3-3) ...
Selecting previously unselected package openssh-client.
Preparing to unpack .../09-openssh-client_1%3a8.9p1-3ubuntu0.11_amd64.deb ...
Unpacking openssh-client (1:8.9p1-3ubuntu0.11) ...
Selecting previously unselected package xauth.
Preparing to unpack .../10-xauth_1%3a1.1-1build2_amd64.deb ...
Unpacking xauth (1:1.1-1build2) ...
Selecting previously unselected package autoconf.
Preparing to unpack .../11-autoconf_2.71-2_all.deb ...
Unpacking autoconf (2.71-2) ...
Selecting previously unselected package autotools-dev.
Preparing to unpack .../12-autotools-dev_20220109.1_all.deb ...
Unpacking autotools-dev (20220109.1) ...
Selecting previously unselected package automake.
Preparing to unpack .../13-automake_1%3a1.16.5-1.3_all.deb ...
Unpacking automake (1:1.16.5-1.3) ...
Selecting previously unselected package bison.
Preparing to unpack .../14-bison_2%3a3.8.2+dfsg-1build1_amd64.deb ...
Unpacking bison (2:3.8.2+dfsg-1build1) ...
Selecting previously unselected package libhiredis0.14:amd64.
Preparing to unpack .../15-libhiredis0.14_0.14.1-2_amd64.deb ...
Unpacking libhiredis0.14:amd64 (0.14.1-2) ...
Selecting previously unselected package ccache.
Preparing to unpack .../16-ccache_4.5.1-1_amd64.deb ...
Unpacking ccache (4.5.1-1) ...
Selecting previously unselected package liberror-perl.
Preparing to unpack .../17-liberror-perl_0.17029-1_all.deb ...
Unpacking liberror-perl (0.17029-1) ...
Selecting previously unselected package git-man.
Preparing to unpack .../18-git-man_1%3a2.34.1-1ubuntu1.12_all.deb ...
Unpacking git-man (1:2.34.1-1ubuntu1.12) ...
Selecting previously unselected package git.
Preparing to unpack .../19-git_1%3a2.34.1-1ubuntu1.12_amd64.deb ...
Unpacking git (1:2.34.1-1ubuntu1.12) ...
Selecting previously unselected package help2man.
Preparing to unpack .../20-help2man_1.49.1_amd64.deb ...
Unpacking help2man (1.49.1) ...
Selecting previously unselected package libfl2:amd64.
Preparing to unpack .../21-libfl2_2.6.4-8build2_amd64.deb ...
Unpacking libfl2:amd64 (2.6.4-8build2) ...
Selecting previously unselected package libfl-dev:amd64.
Preparing to unpack .../22-libfl-dev_2.6.4-8build2_amd64.deb ...
Unpacking libfl-dev:amd64 (2.6.4-8build2) ...
Selecting previously unselected package libltdl-dev:amd64.
Preparing to unpack .../23-libltdl-dev_2.4.6-15build2_amd64.deb ...
Unpacking libltdl-dev:amd64 (2.4.6-15build2) ...
Selecting previously unselected package libtool.
Preparing to unpack .../24-libtool_2.4.6-15build2_all.deb ...
Unpacking libtool (2.4.6-15build2) ...
Setting up libcbor0.8:amd64 (0.8.0-2ubuntu1) ...
Setting up less (590-1ubuntu0.22.04.3) ...
Setting up perl-modules-5.34 (5.34.0-3ubuntu1.4) ...
Setting up autotools-dev (20220109.1) ...
Setting up libsigsegv2:amd64 (2.13-1ubuntu3) ...
Setting up libfl2:amd64 (2.6.4-8build2) ...
Setting up git-man (1:2.34.1-1ubuntu1.12) ...
Setting up libfido2-1:amd64 (1.10.0-1) ...
Setting up libxmuu1:amd64 (2:1.1.3-3) ...
Setting up liblocale-gettext-perl (1.07-4build3) ...
Setting up libpython3-stdlib:amd64 (3.10.6-1~22.04.1) ...
Setting up libhiredis0.14:amd64 (0.14.1-2) ...
Setting up libperl5.34:amd64 (5.34.0-3ubuntu1.4) ...
Setting up libtool (2.4.6-15build2) ...
Setting up openssh-client (1:8.9p1-3ubuntu0.11) ...
update-alternatives: using /usr/bin/ssh to provide /usr/bin/rsh (rsh) in auto mode
update-alternatives: warning: skip creation of /usr/share/man/man1/rsh.1.gz because associated file /usr/share/man/man1/ssh.1.gz (of link group rsh) doesn't exist
update-alternatives: using /usr/bin/slogin to provide /usr/bin/rlogin (rlogin) in auto mode
update-alternatives: warning: skip creation of /usr/share/man/man1/rlogin.1.gz because associated file /usr/share/man/man1/slogin.1.gz (of link group rlogin) doesn't exist
update-alternatives: using /usr/bin/scp to provide /usr/bin/rcp (rcp) in auto mode
update-alternatives: warning: skip creation of /usr/share/man/man1/rcp.1.gz because associated file /usr/share/man/man1/scp.1.gz (of link group rcp) doesn't exist
Setting up ccache (4.5.1-1) ...
Updating symlinks in /usr/lib/ccache ...
Setting up m4 (1.4.18-5ubuntu2) ...
Setting up python3 (3.10.6-1~22.04.1) ...
running python rtupdate hooks for python3.10...
running python post-rtupdate hooks for python3.10...
Setting up perl (5.34.0-3ubuntu1.4) ...
Setting up autoconf (2.71-2) ...
Setting up xauth (1:1.1-1build2) ...
Setting up bison (2:3.8.2+dfsg-1build1) ...
update-alternatives: using /usr/bin/bison.yacc to provide /usr/bin/yacc (yacc) in auto mode
update-alternatives: warning: skip creation of /usr/share/man/man1/yacc.1.gz because associated file /usr/share/man/man1/bison.yacc.1.gz (of link group yacc) doesn't exist
Setting up automake (1:1.16.5-1.3) ...
update-alternatives: using /usr/bin/automake-1.16 to provide /usr/bin/automake (automake) in auto mode
update-alternatives: warning: skip creation of /usr/share/man/man1/automake.1.gz because associated file /usr/share/man/man1/automake-1.16.1.gz (of link group automake) doesn't exist
update-alternatives: warning: skip creation of /usr/share/man/man1/aclocal.1.gz because associated file /usr/share/man/man1/aclocal-1.16.1.gz (of link group automake) doesn't exist
Setting up flex (2.6.4-8build2) ...
Setting up libfl-dev:amd64 (2.6.4-8build2) ...
Setting up help2man (1.49.1) ...
Setting up liberror-perl (0.17029-1) ...
Setting up libltdl-dev:amd64 (2.4.6-15build2) ...
Setting up git (1:2.34.1-1ubuntu1.12) ...
Processing triggers for libc-bin (2.35-0ubuntu3.1) ...
Processing triggers for install-info (6.8-4build1) ...
   apt-get install -y libgoogle-perftools-dev numactl perl-doc
Reading package lists... Done
Building dependency tree... Done
Reading state information... Done
The following additional packages will be installed:
  libgoogle-perftools4 liblzma-dev libnuma1 libtcmalloc-minimal4 libunwind-dev
Suggested packages:
  liblzma-doc man-browser groff-base
The following NEW packages will be installed:
  libgoogle-perftools-dev libgoogle-perftools4 liblzma-dev libnuma1 libtcmalloc-minimal4 libunwind-dev numactl perl-doc
0 upgraded, 8 newly installed, 0 to remove and 133 not upgraded.
Need to get 10.7 MB of archives.
After this operation, 27.3 MB of additional disk space will be used.
Get:1 http://archive.ubuntu.com/ubuntu jammy/main amd64 libnuma1 amd64 2.0.14-3ubuntu2 [22.5 kB]
Get:2 http://archive.ubuntu.com/ubuntu jammy/main amd64 libtcmalloc-minimal4 amd64 2.9.1-0ubuntu3 [98.2 kB]
Get:3 http://archive.ubuntu.com/ubuntu jammy/main amd64 libgoogle-perftools4 amd64 2.9.1-0ubuntu3 [212 kB]
Get:4 http://archive.ubuntu.com/ubuntu jammy/main amd64 liblzma-dev amd64 5.2.5-2ubuntu1 [159 kB]
Get:5 http://archive.ubuntu.com/ubuntu jammy-updates/main amd64 libunwind-dev amd64 1.3.2-2build2.1 [1883 kB]
Get:6 http://archive.ubuntu.com/ubuntu jammy/main amd64 libgoogle-perftools-dev amd64 2.9.1-0ubuntu3 [470 kB]
Get:7 http://archive.ubuntu.com/ubuntu jammy/main amd64 numactl amd64 2.0.14-3ubuntu2 [36.8 kB]
Get:8 http://archive.ubuntu.com/ubuntu jammy-updates/main amd64 perl-doc all 5.34.0-3ubuntu1.4 [7816 kB]
Fetched 10.7 MB in 11s (1000 kB/s)                                                                                                     
debconf: delaying package configuration, since apt-utils is not installed
Selecting previously unselected package libnuma1:amd64.
(Reading database ... 32935 files and directories currently installed.)
Preparing to unpack .../0-libnuma1_2.0.14-3ubuntu2_amd64.deb ...
Unpacking libnuma1:amd64 (2.0.14-3ubuntu2) ...
Selecting previously unselected package libtcmalloc-minimal4:amd64.
Preparing to unpack .../1-libtcmalloc-minimal4_2.9.1-0ubuntu3_amd64.deb ...
Unpacking libtcmalloc-minimal4:amd64 (2.9.1-0ubuntu3) ...
Selecting previously unselected package libgoogle-perftools4:amd64.
Preparing to unpack .../2-libgoogle-perftools4_2.9.1-0ubuntu3_amd64.deb ...
Unpacking libgoogle-perftools4:amd64 (2.9.1-0ubuntu3) ...
Selecting previously unselected package liblzma-dev:amd64.
Preparing to unpack .../3-liblzma-dev_5.2.5-2ubuntu1_amd64.deb ...
Unpacking liblzma-dev:amd64 (5.2.5-2ubuntu1) ...
Selecting previously unselected package libunwind-dev:amd64.
Preparing to unpack .../4-libunwind-dev_1.3.2-2build2.1_amd64.deb ...
Unpacking libunwind-dev:amd64 (1.3.2-2build2.1) ...
Selecting previously unselected package libgoogle-perftools-dev:amd64.
Preparing to unpack .../5-libgoogle-perftools-dev_2.9.1-0ubuntu3_amd64.deb ...
Unpacking libgoogle-perftools-dev:amd64 (2.9.1-0ubuntu3) ...
Selecting previously unselected package numactl.
Preparing to unpack .../6-numactl_2.0.14-3ubuntu2_amd64.deb ...
Unpacking numactl (2.0.14-3ubuntu2) ...
Selecting previously unselected package perl-doc.
Preparing to unpack .../7-perl-doc_5.34.0-3ubuntu1.4_all.deb ...
Adding 'diversion of /usr/bin/perldoc to /usr/bin/perldoc.stub by perl-doc'
Unpacking perl-doc (5.34.0-3ubuntu1.4) ...
Setting up libtcmalloc-minimal4:amd64 (2.9.1-0ubuntu3) ...
Setting up perl-doc (5.34.0-3ubuntu1.4) ...
Setting up liblzma-dev:amd64 (5.2.5-2ubuntu1) ...
Setting up libnuma1:amd64 (2.0.14-3ubuntu2) ...
Setting up libgoogle-perftools4:amd64 (2.9.1-0ubuntu3) ...
Setting up libunwind-dev:amd64 (1.3.2-2build2.1) ...
Setting up numactl (2.0.14-3ubuntu2) ...
Setting up libgoogle-perftools-dev:amd64 (2.9.1-0ubuntu3) ...
Processing triggers for libc-bin (2.35-0ubuntu3.1) ...
   apt-get install -y libfl2 libfl-dev zlib1g zlib1g-dev
Reading package lists... Done
Building dependency tree... Done
Reading state information... Done
libfl-dev is already the newest version (2.6.4-8build2).
libfl-dev set to manually installed.
libfl2 is already the newest version (2.6.4-8build2).
libfl2 set to manually installed.
zlib1g is already the newest version (1:1.2.11.dfsg-2ubuntu9.2).
zlib1g-dev is already the newest version (1:1.2.11.dfsg-2ubuntu9.2).
0 upgraded, 0 newly installed, 0 to remove and 133 not upgraded.

🔷 Step 4: 克隆并切换到 verilator v5.032
   rm -rf verilator
   git clone https://github.com/verilator/verilator
Cloning into 'verilator'...
remote: Enumerating objects: 93530, done.
remote: Counting objects: 100% (759/759), done.
remote: Compressing objects: 100% (260/260), done.
remote: Total 93530 (delta 592), reused 499 (delta 499), pack-reused 92771 (from 4)
Receiving objects: 100% (93530/93530), 63.24 MiB | 1.52 MiB/s, done.
Resolving deltas: 100% (78462/78462), done.
   cd verilator
   git fetch --all --tags
Fetching origin
   git checkout v5.032
Note: switching to 'v5.032'.

You are in 'detached HEAD' state. You can look around, make experimental
changes and commit them, and you can discard any commits you make in this
state without impacting any branches by switching back to a branch.

If you want to create a new branch to retain commits you create, you may
do so (now or later) by using -c with the switch command. Example:

  git switch -c <new-branch-name>

Or undo this operation with:

  git switch -

Turn off this advice by setting config variable advice.detachedHead to false

HEAD is now at 8ff77e9d4 Version bump

🔷 Step 5: 构建并安装 Verilator
   autoconf
   ./configure
configuring for Verilator 5.032 2025-01-01
checking whether to perform partial static linking of Verilator binary... yes
checking whether to use tcmalloc... check
checking whether to build for coverage collection... no
checking whether to use hardcoded paths... yes
checking whether to show and stop on compilation warnings... no
checking whether to run long tests... no
checking for z3... no
checking for cvc5... no
checking for cvc4... no
checking for SMT solver... no
compiler CXX inbound is set to... 
checking for gcc... gcc
checking whether the C compiler works... yes
checking for C compiler default output file name... a.out
checking for suffix of executables... 
checking whether we are cross compiling... no
checking for suffix of object files... o
checking whether the compiler supports GNU C... yes
checking whether gcc accepts -g... yes
checking for gcc option to enable C11 features... none needed
checking for g++... g++
checking whether the compiler supports GNU C++... yes
checking whether g++ accepts -g... yes
checking for g++ option to enable C++11 features... none needed
checking for a BSD-compatible install... /usr/bin/install -c
compiler g++ --version = g++ (Ubuntu 11.4.0-1ubuntu1~22.04) 11.4.0
checking that C++ compiler can compile simple program... yes
checking for ar... ar
checking for perl... perl
checking for python3... python3
python3 --version = Python 3.10.12
checking for flex... flex
flex --version = flex 2.6.4
checking for bison... bison
bison --version = bison (GNU Bison) 3.8.2
checking for ccache... ccache
objcache is ccache --version = ccache version 4.5.1
checking for stdio.h... yes
checking for stdlib.h... yes
checking for string.h... yes
checking for inttypes.h... yes
checking for stdint.h... yes
checking for strings.h... yes
checking for sys/stat.h... yes
checking for sys/types.h... yes
checking for unistd.h... yes
checking for size_t... yes
checking for size_t... (cached) yes
checking for inline... inline
checking whether g++ accepts -pg... yes
checking whether g++ accepts -std=gnu++17... yes
checking whether g++ accepts -Wextra... yes
checking whether g++ accepts -Wfloat-conversion... yes
checking whether g++ accepts -Wlogical-op... yes
checking whether g++ accepts -Wthread-safety... no
checking whether coroutines are supported by g++... no
checking whether coroutines are supported by g++ with -fcoroutines-ts... no
checking whether coroutines are supported by g++ with -fcoroutines... yes
checking whether g++ accepts -Qunused-arguments... no
checking whether g++ accepts -faligned-new... yes
checking whether g++ accepts -Wno-unused-parameter... yes
checking whether g++ accepts -Wno-shadow... yes
checking whether g++ accepts -Wno-char-subscripts... yes
checking whether g++ accepts -Wno-null-conversion... no
checking whether g++ accepts -Wno-parentheses-equality... no
checking whether g++ accepts -Wno-unused... yes
checking whether g++ accepts -Og... yes
checking whether g++ accepts -ggdb... yes
checking whether g++ accepts -gz... yes
checking whether g++ linker accepts -gz... yes
checking whether g++ accepts -faligned-new... yes
checking whether g++ accepts -fbracket-depth=4096... no
checking whether g++ accepts -fcf-protection=none... yes
checking whether g++ accepts -mno-cet... no
checking whether g++ accepts -Qunused-arguments... no
checking whether g++ accepts -Wno-bool-operation... yes
checking whether g++ accepts -Wno-c++11-narrowing... no
checking whether g++ accepts -Wno-constant-logical-operand... no
checking whether g++ accepts -Wno-non-pod-varargs... no
checking whether g++ accepts -Wno-parentheses-equality... no
checking whether g++ accepts -Wno-shadow... yes
checking whether g++ accepts -Wno-sign-compare... yes
checking whether g++ accepts -Wno-tautological-bitwise-compare... no
checking whether g++ accepts -Wno-tautological-compare... yes
checking whether g++ accepts -Wno-uninitialized... yes
checking whether g++ accepts -Wno-unused-but-set-parameter... yes
checking whether g++ accepts -Wno-unused-but-set-variable... yes
checking whether g++ accepts -Wno-unused-parameter... yes
checking whether g++ accepts -Wno-unused-variable... yes
checking whether g++ linker accepts -mt... no
checking whether g++ linker accepts -pthread... yes
checking whether g++ linker accepts -lpthread... yes
checking whether g++ linker accepts -latomic... yes
checking whether g++ linker accepts -fuse-ld=mold... no
checking whether g++ linker accepts -fuse-ld=mold... no
checking whether g++ linker accepts -static-libgcc... yes
checking whether g++ linker accepts -static-libstdc++... yes
checking whether g++ linker accepts -Xlinker -gc-sections... yes
checking whether g++ linker accepts -lpthread... yes
checking whether g++ linker accepts -latomic... yes
checking whether g++ linker accepts -lbcrypt... no
checking whether g++ linker accepts -lpsapi... no
checking whether g++ linker accepts -l:libtcmalloc_minimal.a... yes
checking whether g++ accepts -fno-builtin-malloc... yes
checking whether g++ accepts -fno-builtin-calloc... yes
checking whether g++ accepts -fno-builtin-realloc... yes
checking whether g++ accepts -fno-builtin-free... yes
checking whether g++ supports C++14... yes
checking for g++ precompile header include option... -include
checking for struct stat.st_mtim.tv_nsec... yes
checking whether SystemC is found (in system path)... no
configure: creating ./config.status
config.status: creating Makefile
config.status: creating src/Makefile
config.status: creating src/Makefile_obj
config.status: creating include/verilated.mk
config.status: creating include/verilated_config.h
config.status: creating verilator.pc
config.status: creating verilator-config.cmake
config.status: creating verilator-config-version.cmake
config.status: creating src/config_package.h

Now type 'make' (or sometimes 'gmake') to build Verilator.

   make -j8
pod2man bin/verilator verilator.1
pod2man bin/verilator_coverage verilator_coverage.1
help2man --no-info --no-discard-stderr --version-string=- bin/verilator_gantt -o verilator_gantt.1
------------------------------------------------------------
help2man --no-info --no-discard-stderr --version-string=- bin/verilator_profcfunc -o verilator_profcfunc.1
making verilator in src
make -C src 
make[1]: Entering directory '/home/klee/verilator/src'
mkdir -p obj_dbg
python3 ./config_rev . >config_rev.h
mkdir -p obj_opt
make -C obj_dbg -j 1  TGT=../../bin/verilator_bin_dbg VL_DEBUG=1 -f ../Makefile_obj serial
make -C obj_dbg       TGT=../../bin/verilator_coverage_bin_dbg VL_DEBUG=1 VL_VLCOV=1 -f ../Makefile_obj serial_vlcov
make -C obj_opt -j 1  TGT=../../bin/verilator_bin -f ../Makefile_obj serial
make[2]: Entering directory '/home/klee/verilator/src'
make[2]: warning: -j1 forced in submake: resetting jobserver mode.
make[2]: Entering directory '/home/klee/verilator/src'
make[2]: warning: -j1 forced in submake: resetting jobserver mode.
python3 ../astgen -I .. --astdef V3AstNodeDType.h --astdef V3AstNodeExpr.h --astdef V3AstNodeOther.h --dfgdef V3DfgVertices.h --classes
make[2]: Entering directory '/home/klee/verilator/src/obj_dbg'
python3 ../vlcovgen --srcdir ..
python3 ../astgen -I .. --astdef V3AstNodeDType.h --astdef V3AstNodeExpr.h --astdef V3AstNodeOther.h --dfgdef V3DfgVertices.h --classes
touch vlcovgen.d
make[2]: Leaving directory '/home/klee/verilator/src/obj_dbg'
make -C obj_dbg       TGT=../../bin/verilator_coverage_bin_dbg VL_DEBUG=1 VL_VLCOV=1 -f ../Makefile_obj
make[2]: Entering directory '/home/klee/verilator/src/obj_dbg'
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -c ../VlcMain.cpp -o VlcMain.o
      Compile flags:  g++ -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC="" -DDEFENV_SYSTEMC_ARCH="" -DDEFENV_SYSTEMC_INCLUDE="" -DDEFENV_SYSTEMC_LIBDIR="" -DDEFENV_VERILATOR_ROOT="/usr/local/share/verilator"
If you get errors from verilog.y below, try upgrading bison to version 1.875 or newer.
python3 ../bisonpre --yacc bison -d -v -o V3ParseBison.c  ../verilog.y
If you get errors from verilog.y below, try upgrading bison to version 1.875 or newer.
python3 ../bisonpre --yacc bison -d -v -o V3ParseBison.c  ../verilog.y
  edit ../verilog.y V3ParseBison_pretmp.y
  edit ../verilog.y V3ParseBison_pretmp.y
  bison -d -v --report=itemset --report=lookahead -b V3ParseBison_pretmp -o V3ParseBison_pretmp.c V3ParseBison_pretmp.y
  bison -d -v --report=itemset --report=lookahead -b V3ParseBison_pretmp -o V3ParseBison_pretmp.c V3ParseBison_pretmp.y
  edit V3ParseBison_pretmp.output V3ParseBison.output
  edit V3ParseBison_pretmp.output V3ParseBison.output
      Linking ../../bin/verilator_coverage_bin_dbg...
g++ -gz -static-libgcc -static-libstdc++ -Xlinker -gc-sections -o ../../bin/verilator_coverage_bin_dbg VlcMain.o   -l:libtcmalloc_minimal.a   -lpthread -latomic -lm
make[2]: Leaving directory '/home/klee/verilator/src/obj_dbg'
  edit V3ParseBison_pretmp.c V3ParseBison.c
  edit V3ParseBison_pretmp.c V3ParseBison.c
  edit V3ParseBison_pretmp.h V3ParseBison.h
make[2]: Leaving directory '/home/klee/verilator/src/obj_dbg'
make -C obj_dbg       TGT=../../bin/verilator_bin_dbg VL_DEBUG=1 -f ../Makefile_obj
make[2]: Entering directory '/home/klee/verilator/src/obj_dbg'
python3 ../astgen -I .. --astdef V3AstNodeDType.h --astdef V3AstNodeExpr.h --astdef V3AstNodeOther.h --dfgdef V3DfgVertices.h V3Const.cpp
  edit V3ParseBison_pretmp.h V3ParseBison.h
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -c ../V3Error.cpp -o V3Error.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -c ../V3FileLine.cpp -o V3FileLine.o
      Compile flags:  g++ -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC="" -DDEFENV_SYSTEMC_ARCH="" -DDEFENV_SYSTEMC_INCLUDE="" -DDEFENV_SYSTEMC_LIBDIR="" -DDEFENV_VERILATOR_ROOT="/usr/local/share/verilator"
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -c ../V3Graph.cpp -o V3Graph.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -c ../V3GraphAcyc.cpp -o V3GraphAcyc.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -c ../V3GraphAlg.cpp -o V3GraphAlg.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -c ../V3GraphPathChecker.cpp -o V3GraphPathChecker.o
make[2]: Leaving directory '/home/klee/verilator/src/obj_opt'
make -C obj_opt       TGT=../../bin/verilator_bin -f ../Makefile_obj
make[2]: Entering directory '/home/klee/verilator/src/obj_opt'
      Compile flags:  g++ -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC="" -DDEFENV_SYSTEMC_ARCH="" -DDEFENV_SYSTEMC_INCLUDE="" -DDEFENV_SYSTEMC_LIBDIR="" -DDEFENV_VERILATOR_ROOT="/usr/local/share/verilator"
python3 ../astgen -I .. --astdef V3AstNodeDType.h --astdef V3AstNodeExpr.h --astdef V3AstNodeOther.h --dfgdef V3DfgVertices.h V3Const.cpp
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -c ../V3GraphTest.cpp -o V3GraphTest.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -c ../V3Error.cpp -o V3Error.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -c ../V3Hash.cpp -o V3Hash.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -c ../V3OptionParser.cpp -o V3OptionParser.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -c ../V3Os.cpp -o V3Os.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -Wno-char-subscripts -Wno-unused -c ../V3ParseGrammar.cpp -o V3ParseGrammar.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -Wno-char-subscripts -Wno-unused -c ../V3ParseImp.cpp -o V3ParseImp.o
flex --version
flex 2.6.4
flex -d -oV3Lexer_pregen.yy.cpp ../verilog.l
flex --version
flex 2.6.4
flex -d -oV3PreLex_pregen.yy.cpp ../V3PreLex.l
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -c ../V3PreShell.cpp -o V3PreShell.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -c ../V3String.cpp -o V3String.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -c ../V3FileLine.cpp -o V3FileLine.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -c ../V3ThreadPool.cpp -o V3ThreadPool.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -c ../V3Waiver.cpp -o V3Waiver.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -c ../Verilator.cpp -o Verilator.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -x c++-header -c ../V3PchAstMT.h -o V3PchAstMT.h.gch
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -x c++-header -c ../V3PchAstNoMT.h -o V3PchAstNoMT.h.gch
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -c ../V3Graph.cpp -o V3Graph.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -c V3Const__gen.cpp -o V3Const__gen.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -c ../V3GraphAcyc.cpp -o V3GraphAcyc.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -c ../V3GraphAlg.cpp -o V3GraphAlg.o
python3 ../flexfix V3Lexer <V3Lexer_pregen.yy.cpp >V3Lexer.yy.cpp
python3 ../flexfix V3PreLex <V3PreLex_pregen.yy.cpp >V3PreLex.yy.cpp
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -c ../V3GraphPathChecker.cpp -o V3GraphPathChecker.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -Wno-char-subscripts -Wno-unused -c ../V3ParseLex.cpp -o V3ParseLex.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -c ../V3GraphTest.cpp -o V3GraphTest.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -c ../V3Hash.cpp -o V3Hash.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -c ../V3OptionParser.cpp -o V3OptionParser.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -c ../V3Os.cpp -o V3Os.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -Wno-char-subscripts -Wno-unused -c ../V3ParseGrammar.cpp -o V3ParseGrammar.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -Wno-char-subscripts -Wno-unused -c ../V3PreProc.cpp -o V3PreProc.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -Wno-char-subscripts -Wno-unused -c ../V3ParseImp.cpp -o V3ParseImp.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstMT.h -c ../V3Ast.cpp -o V3Ast.o
flex --version
flex 2.6.4
flex -d -oV3Lexer_pregen.yy.cpp ../verilog.l
flex --version
flex 2.6.4
flex -d -oV3PreLex_pregen.yy.cpp ../V3PreLex.l
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -c ../V3PreShell.cpp -o V3PreShell.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -c ../V3String.cpp -o V3String.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstMT.h -c ../V3AstNodes.cpp -o V3AstNodes.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstMT.h -c ../V3Broken.cpp -o V3Broken.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstMT.h -c ../V3Config.cpp -o V3Config.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -c ../V3ThreadPool.cpp -o V3ThreadPool.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstMT.h -c ../V3EmitCBase.cpp -o V3EmitCBase.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -c ../V3Waiver.cpp -o V3Waiver.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -c ../Verilator.cpp -o Verilator.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -x c++-header -c ../V3PchAstMT.h -o V3PchAstMT.h.gch
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstMT.h -c ../V3EmitCConstPool.cpp -o V3EmitCConstPool.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstMT.h -c ../V3EmitCFunc.cpp -o V3EmitCFunc.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstMT.h -c ../V3EmitCHeaders.cpp -o V3EmitCHeaders.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstMT.h -c ../V3EmitCImp.cpp -o V3EmitCImp.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -x c++-header -c ../V3PchAstNoMT.h -o V3PchAstNoMT.h.gch
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstMT.h -c ../V3EmitCInlines.cpp -o V3EmitCInlines.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstMT.h -c ../V3EmitCPch.cpp -o V3EmitCPch.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstMT.h -c ../V3EmitV.cpp -o V3EmitV.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstMT.h -c ../V3File.cpp -o V3File.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstMT.h -c ../V3FuncOpt.cpp -o V3FuncOpt.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstMT.h -c ../V3Global.cpp -o V3Global.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstMT.h -c ../V3Hasher.cpp -o V3Hasher.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstMT.h -c ../V3Number.cpp -o V3Number.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstMT.h -c ../V3Options.cpp -o V3Options.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -c V3Const__gen.cpp -o V3Const__gen.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstMT.h -c ../V3Stats.cpp -o V3Stats.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstMT.h -c ../V3StatsReport.cpp -o V3StatsReport.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstMT.h -c ../V3VariableOrder.cpp -o V3VariableOrder.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3Active.cpp -o V3Active.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3ActiveTop.cpp -o V3ActiveTop.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3Assert.cpp -o V3Assert.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3AssertPre.cpp -o V3AssertPre.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3Begin.cpp -o V3Begin.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3Branch.cpp -o V3Branch.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3CCtors.cpp -o V3CCtors.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3CUse.cpp -o V3CUse.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3Case.cpp -o V3Case.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3Cast.cpp -o V3Cast.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3Class.cpp -o V3Class.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3Clean.cpp -o V3Clean.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3Clock.cpp -o V3Clock.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3Combine.cpp -o V3Combine.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3Common.cpp -o V3Common.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3Coverage.cpp -o V3Coverage.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3CoverageJoin.cpp -o V3CoverageJoin.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3Dead.cpp -o V3Dead.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3Delayed.cpp -o V3Delayed.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3Depth.cpp -o V3Depth.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3DepthBlock.cpp -o V3DepthBlock.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3Descope.cpp -o V3Descope.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3Dfg.cpp -o V3Dfg.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3DfgAstToDfg.cpp -o V3DfgAstToDfg.o
python3 ../flexfix V3Lexer <V3Lexer_pregen.yy.cpp >V3Lexer.yy.cpp
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3DfgCache.cpp -o V3DfgCache.o
python3 ../flexfix V3PreLex <V3PreLex_pregen.yy.cpp >V3PreLex.yy.cpp
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstMT.h -c ../V3Ast.cpp -o V3Ast.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3DfgDecomposition.cpp -o V3DfgDecomposition.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstMT.h -c ../V3AstNodes.cpp -o V3AstNodes.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3DfgDfgToAst.cpp -o V3DfgDfgToAst.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3DfgOptimizer.cpp -o V3DfgOptimizer.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3DfgPasses.cpp -o V3DfgPasses.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3DfgPeephole.cpp -o V3DfgPeephole.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstMT.h -c ../V3Broken.cpp -o V3Broken.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3DfgRegularize.cpp -o V3DfgRegularize.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3DupFinder.cpp -o V3DupFinder.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstMT.h -c ../V3Config.cpp -o V3Config.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3EmitCMain.cpp -o V3EmitCMain.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3EmitCMake.cpp -o V3EmitCMake.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3EmitCModel.cpp -o V3EmitCModel.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3EmitCSyms.cpp -o V3EmitCSyms.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3EmitMk.cpp -o V3EmitMk.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3EmitXml.cpp -o V3EmitXml.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3ExecGraph.cpp -o V3ExecGraph.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3Expand.cpp -o V3Expand.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3Force.cpp -o V3Force.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3Fork.cpp -o V3Fork.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3Gate.cpp -o V3Gate.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3HierBlock.cpp -o V3HierBlock.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3Inline.cpp -o V3Inline.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3Inst.cpp -o V3Inst.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3InstrCount.cpp -o V3InstrCount.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstMT.h -c ../V3EmitCBase.cpp -o V3EmitCBase.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstMT.h -c ../V3EmitCConstPool.cpp -o V3EmitCConstPool.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstMT.h -c ../V3EmitCFunc.cpp -o V3EmitCFunc.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstMT.h -c ../V3EmitCHeaders.cpp -o V3EmitCHeaders.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstMT.h -c ../V3EmitCImp.cpp -o V3EmitCImp.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstMT.h -c ../V3EmitCInlines.cpp -o V3EmitCInlines.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstMT.h -c ../V3EmitCPch.cpp -o V3EmitCPch.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3Interface.cpp -o V3Interface.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstMT.h -c ../V3EmitV.cpp -o V3EmitV.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstMT.h -c ../V3File.cpp -o V3File.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstMT.h -c ../V3FuncOpt.cpp -o V3FuncOpt.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3Life.cpp -o V3Life.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstMT.h -c ../V3Global.cpp -o V3Global.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstMT.h -c ../V3Hasher.cpp -o V3Hasher.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstMT.h -c ../V3Number.cpp -o V3Number.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstMT.h -c ../V3Options.cpp -o V3Options.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstMT.h -c ../V3Stats.cpp -o V3Stats.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3LifePost.cpp -o V3LifePost.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstMT.h -c ../V3StatsReport.cpp -o V3StatsReport.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstMT.h -c ../V3VariableOrder.cpp -o V3VariableOrder.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3LinkCells.cpp -o V3LinkCells.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3LinkDot.cpp -o V3LinkDot.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3Active.cpp -o V3Active.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3LinkInc.cpp -o V3LinkInc.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3ActiveTop.cpp -o V3ActiveTop.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3Assert.cpp -o V3Assert.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3AssertPre.cpp -o V3AssertPre.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3Begin.cpp -o V3Begin.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3Branch.cpp -o V3Branch.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3LinkJump.cpp -o V3LinkJump.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3CCtors.cpp -o V3CCtors.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3LinkLValue.cpp -o V3LinkLValue.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3CUse.cpp -o V3CUse.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3Case.cpp -o V3Case.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3Cast.cpp -o V3Cast.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3LinkLevel.cpp -o V3LinkLevel.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3LinkParse.cpp -o V3LinkParse.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3Class.cpp -o V3Class.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3Clean.cpp -o V3Clean.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3LinkResolve.cpp -o V3LinkResolve.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3Clock.cpp -o V3Clock.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3Combine.cpp -o V3Combine.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3Common.cpp -o V3Common.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3Coverage.cpp -o V3Coverage.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3CoverageJoin.cpp -o V3CoverageJoin.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3Localize.cpp -o V3Localize.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3MergeCond.cpp -o V3MergeCond.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3Name.cpp -o V3Name.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3Dead.cpp -o V3Dead.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3Delayed.cpp -o V3Delayed.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3Depth.cpp -o V3Depth.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3DepthBlock.cpp -o V3DepthBlock.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3Descope.cpp -o V3Descope.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3Dfg.cpp -o V3Dfg.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3Order.cpp -o V3Order.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3DfgAstToDfg.cpp -o V3DfgAstToDfg.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3OrderGraphBuilder.cpp -o V3OrderGraphBuilder.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3OrderMoveGraph.cpp -o V3OrderMoveGraph.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3DfgCache.cpp -o V3DfgCache.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3OrderParallel.cpp -o V3OrderParallel.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3OrderProcessDomains.cpp -o V3OrderProcessDomains.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3DfgDecomposition.cpp -o V3DfgDecomposition.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3DfgDfgToAst.cpp -o V3DfgDfgToAst.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3DfgOptimizer.cpp -o V3DfgOptimizer.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3OrderSerial.cpp -o V3OrderSerial.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3Param.cpp -o V3Param.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3DfgPasses.cpp -o V3DfgPasses.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3Premit.cpp -o V3Premit.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3DfgPeephole.cpp -o V3DfgPeephole.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3ProtectLib.cpp -o V3ProtectLib.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3Randomize.cpp -o V3Randomize.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3DfgRegularize.cpp -o V3DfgRegularize.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3Reloop.cpp -o V3Reloop.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3DupFinder.cpp -o V3DupFinder.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3EmitCMain.cpp -o V3EmitCMain.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3Sampled.cpp -o V3Sampled.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3EmitCMake.cpp -o V3EmitCMake.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3EmitCModel.cpp -o V3EmitCModel.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3EmitCSyms.cpp -o V3EmitCSyms.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3EmitMk.cpp -o V3EmitMk.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3Sched.cpp -o V3Sched.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3SchedAcyclic.cpp -o V3SchedAcyclic.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3EmitXml.cpp -o V3EmitXml.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3SchedPartition.cpp -o V3SchedPartition.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3ExecGraph.cpp -o V3ExecGraph.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3SchedReplicate.cpp -o V3SchedReplicate.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3Expand.cpp -o V3Expand.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3SchedTiming.cpp -o V3SchedTiming.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3SchedVirtIface.cpp -o V3SchedVirtIface.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3Scope.cpp -o V3Scope.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3Force.cpp -o V3Force.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3Fork.cpp -o V3Fork.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3Scoreboard.cpp -o V3Scoreboard.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3Gate.cpp -o V3Gate.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3HierBlock.cpp -o V3HierBlock.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3Slice.cpp -o V3Slice.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3Split.cpp -o V3Split.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3SplitAs.cpp -o V3SplitAs.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3SplitVar.cpp -o V3SplitVar.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3Inline.cpp -o V3Inline.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3Inst.cpp -o V3Inst.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3StackCount.cpp -o V3StackCount.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3Subst.cpp -o V3Subst.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3InstrCount.cpp -o V3InstrCount.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3TSP.cpp -o V3TSP.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3Interface.cpp -o V3Interface.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3Life.cpp -o V3Life.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3Table.cpp -o V3Table.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3LifePost.cpp -o V3LifePost.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3Task.cpp -o V3Task.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3LinkCells.cpp -o V3LinkCells.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3LinkDot.cpp -o V3LinkDot.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3LinkInc.cpp -o V3LinkInc.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3LinkJump.cpp -o V3LinkJump.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3LinkLValue.cpp -o V3LinkLValue.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3Timing.cpp -o V3Timing.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3LinkLevel.cpp -o V3LinkLevel.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3LinkParse.cpp -o V3LinkParse.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3LinkResolve.cpp -o V3LinkResolve.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3Trace.cpp -o V3Trace.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3TraceDecl.cpp -o V3TraceDecl.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3Localize.cpp -o V3Localize.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3MergeCond.cpp -o V3MergeCond.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3Name.cpp -o V3Name.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3Tristate.cpp -o V3Tristate.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3Order.cpp -o V3Order.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3Undriven.cpp -o V3Undriven.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3OrderGraphBuilder.cpp -o V3OrderGraphBuilder.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3OrderMoveGraph.cpp -o V3OrderMoveGraph.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3Unknown.cpp -o V3Unknown.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3OrderParallel.cpp -o V3OrderParallel.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3OrderProcessDomains.cpp -o V3OrderProcessDomains.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3Unroll.cpp -o V3Unroll.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3OrderSerial.cpp -o V3OrderSerial.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3Width.cpp -o V3Width.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3WidthCommit.cpp -o V3WidthCommit.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3Param.cpp -o V3Param.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3Premit.cpp -o V3Premit.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3ProtectLib.cpp -o V3ProtectLib.o
ccache g++  -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3WidthSel.cpp -o V3WidthSel.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3Randomize.cpp -o V3Randomize.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3Reloop.cpp -o V3Reloop.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3Sampled.cpp -o V3Sampled.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3Sched.cpp -o V3Sched.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3SchedAcyclic.cpp -o V3SchedAcyclic.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3SchedPartition.cpp -o V3SchedPartition.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3SchedReplicate.cpp -o V3SchedReplicate.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3SchedTiming.cpp -o V3SchedTiming.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3SchedVirtIface.cpp -o V3SchedVirtIface.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3Scope.cpp -o V3Scope.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3Scoreboard.cpp -o V3Scoreboard.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3Slice.cpp -o V3Slice.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3Split.cpp -o V3Split.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3SplitAs.cpp -o V3SplitAs.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3SplitVar.cpp -o V3SplitVar.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3StackCount.cpp -o V3StackCount.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3Subst.cpp -o V3Subst.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3TSP.cpp -o V3TSP.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3Table.cpp -o V3Table.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3Task.cpp -o V3Task.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3Timing.cpp -o V3Timing.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3Trace.cpp -o V3Trace.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3TraceDecl.cpp -o V3TraceDecl.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3Tristate.cpp -o V3Tristate.o
      Linking ../../bin/verilator_bin_dbg...
g++ -gz -static-libgcc -static-libstdc++ -Xlinker -gc-sections -o ../../bin/verilator_bin_dbg V3Const__gen.o V3Error.o V3FileLine.o V3Graph.o V3GraphAcyc.o V3GraphAlg.o V3GraphPathChecker.o V3GraphTest.o V3Hash.o V3OptionParser.o V3Os.o V3ParseGrammar.o V3ParseImp.o V3ParseLex.o V3PreProc.o V3PreShell.o V3String.o V3ThreadPool.o V3Waiver.o Verilator.o  V3Ast.o V3AstNodes.o V3Broken.o V3Config.o V3EmitCBase.o V3EmitCConstPool.o V3EmitCFunc.o V3EmitCHeaders.o V3EmitCImp.o V3EmitCInlines.o V3EmitCPch.o V3EmitV.o V3File.o V3FuncOpt.o V3Global.o V3Hasher.o V3Number.o V3Options.o V3Stats.o V3StatsReport.o V3VariableOrder.o  V3Active.o V3ActiveTop.o V3Assert.o V3AssertPre.o V3Begin.o V3Branch.o V3CCtors.o V3CUse.o V3Case.o V3Cast.o V3Class.o V3Clean.o V3Clock.o V3Combine.o V3Common.o V3Coverage.o V3CoverageJoin.o V3Dead.o V3Delayed.o V3Depth.o V3DepthBlock.o V3Descope.o V3Dfg.o V3DfgAstToDfg.o V3DfgCache.o V3DfgDecomposition.o V3DfgDfgToAst.o V3DfgOptimizer.o V3DfgPasses.o V3DfgPeephole.o V3DfgRegularize.o V3DupFinder.o V3EmitCMain.o V3EmitCMake.o V3EmitCModel.o V3EmitCSyms.o V3EmitMk.o V3EmitXml.o V3ExecGraph.o V3Expand.o V3Force.o V3Fork.o V3Gate.o V3HierBlock.o V3Inline.o V3Inst.o V3InstrCount.o V3Interface.o V3Life.o V3LifePost.o V3LinkCells.o V3LinkDot.o V3LinkInc.o V3LinkJump.o V3LinkLValue.o V3LinkLevel.o V3LinkParse.o V3LinkResolve.o V3Localize.o V3MergeCond.o V3Name.o V3Order.o V3OrderGraphBuilder.o V3OrderMoveGraph.o V3OrderParallel.o V3OrderProcessDomains.o V3OrderSerial.o V3Param.o V3Premit.o V3ProtectLib.o V3Randomize.o V3Reloop.o V3Sampled.o V3Sched.o V3SchedAcyclic.o V3SchedPartition.o V3SchedReplicate.o V3SchedTiming.o V3SchedVirtIface.o V3Scope.o V3Scoreboard.o V3Slice.o V3Split.o V3SplitAs.o V3SplitVar.o V3StackCount.o V3Subst.o V3TSP.o V3Table.o V3Task.o V3Timing.o V3Trace.o V3TraceDecl.o V3Tristate.o V3Undriven.o V3Unknown.o V3Unroll.o V3Width.o V3WidthCommit.o V3WidthSel.o   -l:libtcmalloc_minimal.a   -lpthread -latomic -lm
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3Undriven.cpp -o V3Undriven.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3Unknown.cpp -o V3Unknown.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3Unroll.cpp -o V3Unroll.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3Width.cpp -o V3Width.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3WidthCommit.cpp -o V3WidthCommit.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -include V3PchAstNoMT.h -c ../V3WidthSel.cpp -o V3WidthSel.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -Wno-char-subscripts -Wno-unused -c ../V3ParseLex.cpp -o V3ParseLex.o
ccache g++  -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP  -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC=\"\" -DDEFENV_SYSTEMC_ARCH=\"\" -DDEFENV_SYSTEMC_INCLUDE=\"\" -DDEFENV_SYSTEMC_LIBDIR=\"\" -DDEFENV_VERILATOR_ROOT=\"/usr/local/share/verilator\" -Wno-char-subscripts -Wno-unused -c ../V3PreProc.cpp -o V3PreProc.o
      Linking ../../bin/verilator_bin...
g++ -static-libgcc -static-libstdc++ -Xlinker -gc-sections -o ../../bin/verilator_bin V3Const__gen.o V3Error.o V3FileLine.o V3Graph.o V3GraphAcyc.o V3GraphAlg.o V3GraphPathChecker.o V3GraphTest.o V3Hash.o V3OptionParser.o V3Os.o V3ParseGrammar.o V3ParseImp.o V3ParseLex.o V3PreProc.o V3PreShell.o V3String.o V3ThreadPool.o V3Waiver.o Verilator.o  V3Ast.o V3AstNodes.o V3Broken.o V3Config.o V3EmitCBase.o V3EmitCConstPool.o V3EmitCFunc.o V3EmitCHeaders.o V3EmitCImp.o V3EmitCInlines.o V3EmitCPch.o V3EmitV.o V3File.o V3FuncOpt.o V3Global.o V3Hasher.o V3Number.o V3Options.o V3Stats.o V3StatsReport.o V3VariableOrder.o  V3Active.o V3ActiveTop.o V3Assert.o V3AssertPre.o V3Begin.o V3Branch.o V3CCtors.o V3CUse.o V3Case.o V3Cast.o V3Class.o V3Clean.o V3Clock.o V3Combine.o V3Common.o V3Coverage.o V3CoverageJoin.o V3Dead.o V3Delayed.o V3Depth.o V3DepthBlock.o V3Descope.o V3Dfg.o V3DfgAstToDfg.o V3DfgCache.o V3DfgDecomposition.o V3DfgDfgToAst.o V3DfgOptimizer.o V3DfgPasses.o V3DfgPeephole.o V3DfgRegularize.o V3DupFinder.o V3EmitCMain.o V3EmitCMake.o V3EmitCModel.o V3EmitCSyms.o V3EmitMk.o V3EmitXml.o V3ExecGraph.o V3Expand.o V3Force.o V3Fork.o V3Gate.o V3HierBlock.o V3Inline.o V3Inst.o V3InstrCount.o V3Interface.o V3Life.o V3LifePost.o V3LinkCells.o V3LinkDot.o V3LinkInc.o V3LinkJump.o V3LinkLValue.o V3LinkLevel.o V3LinkParse.o V3LinkResolve.o V3Localize.o V3MergeCond.o V3Name.o V3Order.o V3OrderGraphBuilder.o V3OrderMoveGraph.o V3OrderParallel.o V3OrderProcessDomains.o V3OrderSerial.o V3Param.o V3Premit.o V3ProtectLib.o V3Randomize.o V3Reloop.o V3Sampled.o V3Sched.o V3SchedAcyclic.o V3SchedPartition.o V3SchedReplicate.o V3SchedTiming.o V3SchedVirtIface.o V3Scope.o V3Scoreboard.o V3Slice.o V3Split.o V3SplitAs.o V3SplitVar.o V3StackCount.o V3Subst.o V3TSP.o V3Table.o V3Task.o V3Timing.o V3Trace.o V3TraceDecl.o V3Tristate.o V3Undriven.o V3Unknown.o V3Unroll.o V3Width.o V3WidthCommit.o V3WidthSel.o   -l:libtcmalloc_minimal.a   -lpthread -latomic -lm
make[2]: Leaving directory '/home/klee/verilator/src/obj_opt'
make[2]: Leaving directory '/home/klee/verilator/src/obj_dbg'
make[1]: Leaving directory '/home/klee/verilator/src'
Build complete!

Now type 'make test' to test.

   make install
------------------------------------------------------------
making verilator in src
make -C src 
make[1]: Entering directory '/home/klee/verilator/src'
make -C obj_dbg -j 1  TGT=../../bin/verilator_bin_dbg VL_DEBUG=1 -f ../Makefile_obj serial
make[2]: Entering directory '/home/klee/verilator/src/obj_dbg'
make[2]: Nothing to be done for 'serial'.
make[2]: Leaving directory '/home/klee/verilator/src/obj_dbg'
make -C obj_dbg       TGT=../../bin/verilator_bin_dbg VL_DEBUG=1 -f ../Makefile_obj
make[2]: Entering directory '/home/klee/verilator/src/obj_dbg'
      Compile flags:  g++ -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC="" -DDEFENV_SYSTEMC_ARCH="" -DDEFENV_SYSTEMC_INCLUDE="" -DDEFENV_SYSTEMC_LIBDIR="" -DDEFENV_VERILATOR_ROOT="/usr/local/share/verilator"
make[2]: Leaving directory '/home/klee/verilator/src/obj_dbg'
make -C obj_dbg       TGT=../../bin/verilator_coverage_bin_dbg VL_DEBUG=1 VL_VLCOV=1 -f ../Makefile_obj serial_vlcov
make[2]: Entering directory '/home/klee/verilator/src/obj_dbg'
make[2]: Nothing to be done for 'serial_vlcov'.
make[2]: Leaving directory '/home/klee/verilator/src/obj_dbg'
make -C obj_dbg       TGT=../../bin/verilator_coverage_bin_dbg VL_DEBUG=1 VL_VLCOV=1 -f ../Makefile_obj
make[2]: Entering directory '/home/klee/verilator/src/obj_dbg'
      Compile flags:  g++ -Og -ggdb -gz -DVL_DEBUG -D_GLIBCXX_DEBUG -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC="" -DDEFENV_SYSTEMC_ARCH="" -DDEFENV_SYSTEMC_INCLUDE="" -DDEFENV_SYSTEMC_LIBDIR="" -DDEFENV_VERILATOR_ROOT="/usr/local/share/verilator"
make[2]: Leaving directory '/home/klee/verilator/src/obj_dbg'
make -C obj_opt -j 1  TGT=../../bin/verilator_bin -f ../Makefile_obj serial
make[2]: Entering directory '/home/klee/verilator/src/obj_opt'
make[2]: Nothing to be done for 'serial'.
make[2]: Leaving directory '/home/klee/verilator/src/obj_opt'
make -C obj_opt       TGT=../../bin/verilator_bin -f ../Makefile_obj
make[2]: Entering directory '/home/klee/verilator/src/obj_opt'
      Compile flags:  g++ -O3 -DVERILATOR_INTERNAL_ -MMD -I. -I.. -I.. -I../../include -I../../include -MP -faligned-new -Wno-unused-parameter -Wno-shadow -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free -DDEFENV_SYSTEMC="" -DDEFENV_SYSTEMC_ARCH="" -DDEFENV_SYSTEMC_INCLUDE="" -DDEFENV_SYSTEMC_LIBDIR="" -DDEFENV_VERILATOR_ROOT="/usr/local/share/verilator"
make[2]: Leaving directory '/home/klee/verilator/src/obj_opt'
make[1]: Leaving directory '/home/klee/verilator/src'
/bin/sh ./src/mkinstalldirs /usr/local/share/verilator/bin
mkdir /usr/local/share/verilator
mkdir /usr/local/share/verilator/bin
/bin/sh ./src/mkinstalldirs /usr/local/bin
cd ./bin; \
for p in verilator verilator_coverage verilator_gantt verilator_profcfunc  ; do \
  /usr/bin/install -c $p /usr/local/bin/$p; \
done
perl -p -i -e 'use File::Spec;' \
           -e' $path = File::Spec->abs2rel("/usr/local/share/verilator", "/usr/local/bin");' \
           -e 's/my \$verilator_pkgdatadir_relpath = .*/my \$verilator_pkgdatadir_relpath = "$path";/g' \
           -- "//usr/local/bin/verilator"
cd bin; \
for p in verilator_bin verilator_bin_dbg verilator_coverage_bin_dbg  ; do \
  /usr/bin/install -c $p /usr/local/bin/$p; \
done
cd ./bin; \
for p in verilator_ccache_report verilator_includer  ; do \
  /usr/bin/install -c $p /usr/local/share/verilator/bin/$p; \
done
cp ./bin/redirect ./bin/redirect.tmp
perl -p -i -e 'use File::Spec;' \
           -e' $path = File::Spec->abs2rel("/usr/local/bin", "/usr/local/share/verilator/bin");' \
           -e 's/RELPATH.*/"$path";/g' -- "./bin/redirect.tmp"
cd ./bin; \
for p in verilator verilator_coverage verilator_gantt verilator_profcfunc  verilator_bin verilator_bin_dbg verilator_coverage_bin_dbg  ; do \
  /usr/bin/install -c redirect.tmp /usr/local/share/verilator/bin/$p; \
done
rm ./bin/redirect.tmp
/bin/sh ./src/mkinstalldirs /usr/local/share/man/man1
mkdir /usr/local/share/man/man1
for p in verilator.1 verilator_coverage.1 verilator_gantt.1 verilator_profcfunc.1 ; do \
  /usr/bin/install -c -m 644 $p /usr/local/share/man/man1/$p; \
done
/bin/sh ./src/mkinstalldirs /usr/local/share/verilator/include/gtkwave
mkdir /usr/local/share/verilator/include
mkdir /usr/local/share/verilator/include/gtkwave
/bin/sh ./src/mkinstalldirs /usr/local/share/verilator/include/vltstd
mkdir /usr/local/share/verilator/include/vltstd
for p in include/verilated_config.h include/verilated.mk  ; do \
  /usr/bin/install -c -m 644 $p /usr/local/share/verilator/$p; \
done
cd . \
; for p in include/*.[chv]* include/*.vlt include/*.sv include/gtkwave/*.[chv]* include/vltstd/*.[chv]*  ; do \
  /usr/bin/install -c -m 644 $p /usr/local/share/verilator/$p; \
done
/bin/sh ./src/mkinstalldirs /usr/local/share/verilator/examples/make_hello_binary
mkdir /usr/local/share/verilator/examples
mkdir /usr/local/share/verilator/examples/make_hello_binary
/bin/sh ./src/mkinstalldirs /usr/local/share/verilator/examples/make_hello_c
mkdir /usr/local/share/verilator/examples/make_hello_c
/bin/sh ./src/mkinstalldirs /usr/local/share/verilator/examples/make_hello_sc
mkdir /usr/local/share/verilator/examples/make_hello_sc
/bin/sh ./src/mkinstalldirs /usr/local/share/verilator/examples/make_tracing_c
mkdir /usr/local/share/verilator/examples/make_tracing_c
/bin/sh ./src/mkinstalldirs /usr/local/share/verilator/examples/make_tracing_sc
mkdir /usr/local/share/verilator/examples/make_tracing_sc
/bin/sh ./src/mkinstalldirs /usr/local/share/verilator/examples/make_protect_lib
mkdir /usr/local/share/verilator/examples/make_protect_lib
/bin/sh ./src/mkinstalldirs /usr/local/share/verilator/examples/cmake_hello_c
mkdir /usr/local/share/verilator/examples/cmake_hello_c
/bin/sh ./src/mkinstalldirs /usr/local/share/verilator/examples/cmake_hello_sc
mkdir /usr/local/share/verilator/examples/cmake_hello_sc
/bin/sh ./src/mkinstalldirs /usr/local/share/verilator/examples/cmake_tracing_c
mkdir /usr/local/share/verilator/examples/cmake_tracing_c
/bin/sh ./src/mkinstalldirs /usr/local/share/verilator/examples/cmake_tracing_sc
mkdir /usr/local/share/verilator/examples/cmake_tracing_sc
/bin/sh ./src/mkinstalldirs /usr/local/share/verilator/examples/cmake_protect_lib
mkdir /usr/local/share/verilator/examples/cmake_protect_lib
/bin/sh ./src/mkinstalldirs /usr/local/share/verilator/examples/json_py
mkdir /usr/local/share/verilator/examples/json_py
cd . \
; for p in examples/*/*.[chv]* examples/*/CMakeLists.txt examples/*/Makefile* examples/*/vl_*  ; do \
  /usr/bin/install -c -m 644 $p /usr/local/share/verilator/$p; \
done
/bin/sh ./src/mkinstalldirs /usr/local/share/pkgconfig
mkdir /usr/local/share/pkgconfig
/usr/bin/install -c -m 644 verilator.pc /usr/local/share/pkgconfig
/usr/bin/install -c -m 644 verilator-config.cmake /usr/local/share/verilator
/usr/bin/install -c -m 644 verilator-config-version.cmake /usr/local/share/verilator

Installed binaries to /usr/local/bin/verilator
Installed man to /usr/local/share/man/man1
Installed examples to /usr/local/share/verilator/examples

For documentation see 'man verilator' or 'verilator --help'
For forums and to report bugs see https://verilator.org


🔷 Step 6: 验证 Verilator 安装
   verilator --version
Verilator 5.032 2025-01-01 rev v5.032

✅ Verilator v5.032 安装成功！

🔷 Step 5: 验证 Verilator 与 KLEE 版本
   sudo docker exec --user root -it v5k3 verilator --version
Verilator 5.032 2025-01-01 rev v5.032
   sudo docker exec -it v5k3 klee --version
KLEE 3.1 (https://klee.github.io)
  Build mode: RelWithDebInfo (Asserts: TRUE)
  Build revision: fe22b90764887ab69c20b1eccd773d47a8378b95

LLVM (http://llvm.org/):
  LLVM version 13.0.1
  Optimized build with assertions.
  Default target: x86_64-unknown-linux-gnu
  Host CPU: skylake

🔷 Step 6: 自动进入容器 v5k3 交互终端
   sudo docker exec -it v5k3 /bin/bash
klee@20df274bfc64:~$ verilator --version
Verilator 5.032 2025-01-01 rev v5.032
klee@20df274bfc64:~$ klee --version
KLEE 3.1 (https://klee.github.io)
  Build mode: RelWithDebInfo (Asserts: TRUE)
  Build revision: fe22b90764887ab69c20b1eccd773d47a8378b95

LLVM (http://llvm.org/):
  LLVM version 13.0.1
  Optimized build with assertions.
  Default target: x86_64-unknown-linux-gnu
  Host CPU: skylake
klee@20df274bfc64:~$ 
```
