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
