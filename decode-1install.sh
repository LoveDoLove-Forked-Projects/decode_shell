#!/bin/bash
export LANG=en_US.UTF-8
sred='\033[5;31m'
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
blue='\033[0;36m'
bblue='\033[0;34m'
plain='\033[0m'
red() { echo -e "\033[31m\033[01m$1\033[0m"; }
green() { echo -e "\033[32m\033[01m$1\033[0m"; }
yellow() { echo -e "\033[33m\033[01m$1\033[0m"; }
blue() { echo -e "\033[36m\033[01m$1\033[0m"; }
white() { echo -e "\033[37m\033[01m$1\033[0m"; }
readp() { read -p "$(yellow "$1")" $2; }
[[ $EUID -ne 0 ]] && yellow "请以root模式运行脚本" && exit
#[[ -e /etc/hosts ]] && grep -qE '^ *172.65.251.78 gitlab.com' /etc/hosts || echo -e '\n172.65.251.78 gitlab.com' >> /etc/hosts
if [[ -f /etc/redhat-release ]]; then
	release="Centos"
elif cat /etc/issue | grep -q -E -i "debian"; then
	release="Debian"
elif cat /etc/issue | grep -q -E -i "ubuntu"; then
	release="Ubuntu"
elif cat /etc/issue | grep -q -E -i "centos|red hat|redhat"; then
	release="Centos"
elif cat /proc/version | grep -q -E -i "debian"; then
	release="Debian"
elif cat /proc/version | grep -q -E -i "ubuntu"; then
	release="Ubuntu"
elif cat /proc/version | grep -q -E -i "centos|red hat|redhat"; then
	release="Centos"
else
	red "不支持当前的系统，请选择使用Ubuntu,Debian,Centos系统。" && exit
fi
vsid=$(grep -i version_id /etc/os-release | cut -d \" -f2 | cut -d . -f1)
op=$(cat /etc/redhat-release 2>/dev/null || cat /etc/os-release 2>/dev/null | grep -i pretty_name | cut -d \" -f2)
if [[ $(echo "$op" | grep -i -E "arch|alpine") ]]; then
	red "脚本不支持当前的 $op 系统，请选择使用Ubuntu,Debian,Centos系统。" && exit
fi
version=$(uname -r | cut -d "-" -f1)
vi=$(systemd-detect-virt)
case $(uname -m) in
aarch64) cpu=arm64 ;;
x86_64) cpu=amd64 ;;
*) red "目前脚本不支持$(uname -m)架构" && exit ;;
esac

if [[ -n $(sysctl net.ipv4.tcp_congestion_control 2>/dev/null | awk -F ' ' '{print $3}') ]]; then
	bbr=$(sysctl net.ipv4.tcp_congestion_control | awk -F ' ' '{print $3}')
elif [[ -n $(ping 10.0.0.2 -c 2 | grep ttl) ]]; then
	bbr="Openvz版bbr-plus"
else
	bbr="Openvz/Lxc"
fi

if [ ! -f xuiyg_update ]; then
	green "首次安装x-ui-yg脚本必要的依赖……"
	if [[ $release = Centos && ${vsid} =~ 8 ]]; then
		cd /etc/yum.repos.d/ && mkdir backup && mv *repo backup/
		curl -o /etc/yum.repos.d/CentOS-Base.repo http://mirrors.aliyun.com/repo/Centos-8.repo
		sed -i -e "s|mirrors.cloud.aliyuncs.com|mirrors.aliyun.com|g " /etc/yum.repos.d/CentOS-*
		sed -i -e "s|releasever|releasever-stream|g" /etc/yum.repos.d/CentOS-*
		yum clean all && yum makecache
		cd
	fi
	if [ -x "$(command -v apt-get)" ]; then
		apt update -y
		apt install jq tzdata -y
	elif [ -x "$(command -v yum)" ]; then
		yum update -y && yum install epel-release -y
		yum install jq tzdata -y
	elif [ -x "$(command -v dnf)" ]; then
		dnf update -y
		dnf install jq tzdata -y
	fi
	if [ -x "$(command -v yum)" ] || [ -x "$(command -v dnf)" ]; then
		if ! command -v "cronie" &>/dev/null; then
			if [ -x "$(command -v yum)" ]; then
				yum install -y cronie
			elif [ -x "$(command -v dnf)" ]; then
				dnf install -y cronie
			fi
		fi
	fi
	touch xuiyg_update
fi

packages=("curl" "openssl" "tar" "wget" "cron")
inspackages=("curl" "openssl" "tar" "wget" "cron")
for i in "${!packages[@]}"; do
	package="${packages[$i]}"
	inspackage="${inspackages[$i]}"
	if ! command -v "$package" &>/dev/null; then
		if [ -x "$(command -v apt-get)" ]; then
			apt-get install -y "$inspackage"
		elif [ -x "$(command -v yum)" ]; then
			yum install -y "$inspackage"
		elif [ -x "$(command -v dnf)" ]; then
			dnf install -y "$inspackage"
		fi
	fi
done

if [[ $vi = openvz ]]; then
	TUN=$(cat /dev/net/tun 2>&1)
	if [[ ! $TUN =~ 'in bad state' ]] && [[ ! $TUN =~ '处于错误状态' ]] && [[ ! $TUN =~ 'Die Dateizugriffsnummer ist in schlechter Verfassung' ]]; then
		red "检测到未开启TUN，现尝试添加TUN支持" && sleep 4
		cd /dev && mkdir net && mknod net/tun c 10 200 && chmod 0666 net/tun
		TUN=$(cat /dev/net/tun 2>&1)
		if [[ ! $TUN =~ 'in bad state' ]] && [[ ! $TUN =~ '处于错误状态' ]] && [[ ! $TUN =~ 'Die Dateizugriffsnummer ist in schlechter Verfassung' ]]; then
			green "添加TUN支持失败，建议与VPS厂商沟通或后台设置开启" && exit
		else
			echo '#!/bin/bash' >/root/tun.sh && echo 'cd /dev && mkdir net && mknod net/tun c 10 200 && chmod 0666 net/tun' >>/root/tun.sh && chmod +x /root/tun.sh
			grep -qE "^ *@reboot root bash /root/tun.sh >/dev/null 2>&1" /etc/crontab || echo "@reboot root bash /root/tun.sh >/dev/null 2>&1" >>/etc/crontab
			green "TUN守护功能已启动"
		fi
	fi
fi

argopid() {
	ym=$(cat /usr/local/x-ui/xuiargoympid.log 2>/dev/null)
	ls=$(cat /usr/local/x-ui/xuiargopid.log 2>/dev/null)
}

v4v6() {
	v4=$(curl -s4m5 icanhazip.com -k)
	v6=$(curl -s6m5 icanhazip.com -k)
}

warpcheck() {
	wgcfv6=$(curl -s6m5 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
	wgcfv4=$(curl -s4m5 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
}

v6() {
	warpcheck
	if [[ ! $wgcfv4 =~ on|plus && ! $wgcfv6 =~ on|plus ]]; then
		v4=$(curl -s4m5 icanhazip.com -k)
		if [ -z $v4 ]; then
			yellow "检测到 纯IPV6 VPS，添加DNS64"
			echo -e "nameserver 2a00:1098:2b::1\nnameserver 2a00:1098:2c::1\nnameserver 2a01:4f8:c2c:123f::1" >/etc/resolv.conf
		fi
	fi
}

serinstall() {
	green "下载并安装x-ui相关组件……"
	cd /usr/local/
	curl -sSL -o /usr/local/x-ui-linux-${cpu}.tar.gz --insecure https://gitlab.com/rwkgyg/x-ui-yg/raw/main/x-ui-linux-${cpu}.tar.gz
	tar zxvf x-ui-linux-${cpu}.tar.gz >/dev/null 2>&1
	rm x-ui-linux-${cpu}.tar.gz -f
	cd x-ui
	chmod +x x-ui bin/xray-linux-${cpu}
	cp -f x-ui.service /etc/systemd/system/
	systemctl daemon-reload
	systemctl enable x-ui >/dev/null 2>&1
	systemctl start x-ui
	cd
	curl -sSL -o /usr/bin/x-ui --insecure https://gitlab.com/rwkgyg/x-ui-yg/raw/main/1install.sh >/dev/null 2>&1
	chmod +x /usr/bin/x-ui
	if [[ -f /usr/bin/x-ui && -f /usr/local/x-ui/bin/xray-linux-${cpu} ]]; then
		green "下载成功"
	else
		red "下载失败，请检测VPS网络是否正常，脚本退出"
		systemctl stop x-ui
		systemctl disable x-ui
		rm /etc/systemd/system/x-ui.service -f
		systemctl daemon-reload
		systemctl reset-failed
		rm /etc/x-ui-yg/ -rf
		rm /usr/local/x-ui/ -rf
		rm /usr/bin/x-ui -f
		rm -rf xuiyg_update
		exit
	fi
}

userinstall() {
	readp "设置 x-ui 登录用户名（回车跳过为随机6位字符）：" username
	sleep 1
	if [[ -z ${username} ]]; then
		username=$(date +%s%N | md5sum | cut -c 1-6)
	fi
	while true; do
		if [[ ${username} == *admin* ]]; then
			red "不支持包含有 admin 字样的用户名，请重新设置" && readp "设置 x-ui 登录用户名（回车跳过为随机6位字符）：" username
		else
			break
		fi
	done
	sleep 1
	green "x-ui登录用户名：${username}"
	echo
	readp "设置 x-ui 登录密码（回车跳过为随机6位字符）：" password
	sleep 1
	if [[ -z ${password} ]]; then
		password=$(date +%s%N | md5sum | cut -c 1-6)
	fi
	while true; do
		if [[ ${password} == *admin* ]]; then
			red "不支持包含有 admin 字样的密码，请重新设置" && readp "设置 x-ui 登录密码（回车跳过为随机6位字符）：" password
		else
			break
		fi
	done
	sleep 1
	green "x-ui登录密码：${password}"
	/usr/local/x-ui/x-ui setting -username ${username} -password ${password} >/dev/null 2>&1
}

portinstall() {
	echo
	readp "设置x-ui登录端口[1-65535]（回车跳过为2000-65535之间的随机端口）：" port
	sleep 1
	if [[ -z $port ]]; then
		port=$(shuf -i 2000-65535 -n 1)
		until [[ -z $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") && -z $(ss -tunlp | grep -w tcp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]]; do
			[[ -n $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") || -n $(ss -tunlp | grep -w tcp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]] && yellow "\n端口被占用，请重新输入端口" && readp "自定义端口:" port
		done
	else
		until [[ -z $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") && -z $(ss -tunlp | grep -w tcp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]]; do
			[[ -n $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") || -n $(ss -tunlp | grep -w tcp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]] && yellow "\n端口被占用，请重新输入端口" && readp "自定义端口:" port
		done
	fi
	sleep 1
	/usr/local/x-ui/x-ui setting -port $port >/dev/null 2>&1
	green "x-ui登录端口：${port}"
}

resinstall() {
	echo "----------------------------------------------------------------------"
	restart
	curl -s https://gitlab.com/rwkgyg/x-ui-yg/-/raw/main/version/version | awk -F "更新内容" '{print $1}' | head -n 1 >/usr/local/x-ui/v
	xuilogin() {
		v4v6
		if [[ -z $v4 ]]; then
			echo "[$v6]" >/usr/local/x-ui/xip
		elif [[ -n $v4 && -n $v6 ]]; then
			echo "$v4" >/usr/local/x-ui/xip
			echo "[$v6]" >>/usr/local/x-ui/xip
		else
			echo "$v4" >/usr/local/x-ui/xip
		fi
	}
	warpcheck
	if [[ ! $wgcfv4 =~ on|plus && ! $wgcfv6 =~ on|plus ]]; then
		xuilogin
	else
		systemctl stop wg-quick@wgcf >/dev/null 2>&1
		kill -15 $(pgrep warp-go) >/dev/null 2>&1 && sleep 2
		xuilogin
		systemctl start wg-quick@wgcf >/dev/null 2>&1
		systemctl restart warp-go >/dev/null 2>&1
		systemctl enable warp-go >/dev/null 2>&1
		systemctl start warp-go >/dev/null 2>&1
	fi
	sleep 2
	xuigo
	cronxui
	echo "----------------------------------------------------------------------"
	blue "x-ui-yg $(cat /usr/local/x-ui/v 2>/dev/null) 安装成功，自动进入 x-ui 显示管理菜单" && sleep 4
	echo
	show_menu
}

xuiinstall() {
	v6
	echo "----------------------------------------------------------------------"
	openyn
	echo "----------------------------------------------------------------------"
	serinstall
	echo "----------------------------------------------------------------------"
	userinstall
	portinstall
	resinstall
	[[ -e /etc/gai.conf ]] && grep -qE '^ *precedence ::ffff:0:0/96  100' /etc/gai.conf || echo 'precedence ::ffff:0:0/96  100' >>/etc/gai.conf 2>/dev/null
}

update() {
	yellow "升级也有可能出意外哦，建议如下："
	yellow "一、点击x-ui面版中的备份与恢复，下载备份文件x-ui-yg.db"
	yellow "二、在 /etc/x-ui-yg 路径导出备份文件x-ui-yg.db"
	readp "确定升级，请按回车(退出请按ctrl+c):" ins
	if [[ -z $ins ]]; then
		systemctl stop x-ui
		rm /usr/local/x-ui/ -rf
		serinstall && sleep 2
		restart
		curl -s https://gitlab.com/rwkgyg/x-ui-yg/-/raw/main/version/version | awk -F "更新内容" '{print $1}' | head -n 1 >/usr/local/x-ui/v
		green "x-ui更新完成" && sleep 2 && x-ui
	else
		red "输入有误" && update
	fi
}

uninstall() {
	yellow "本次卸载将清除所有数据，建议如下："
	yellow "一、点击x-ui面版中的备份与恢复，下载备份文件x-ui-yg.db"
	yellow "二、在 /etc/x-ui-yg 路径导出备份文件x-ui-yg.db"
	readp "确定卸载，请按回车(退出请按ctrl+c):" ins
	if [[ -z $ins ]]; then
		systemctl stop x-ui
		systemctl disable x-ui
		rm /etc/systemd/system/x-ui.service -f
		systemctl daemon-reload
		systemctl reset-failed
		rm /etc/x-ui-yg/ -rf
		rm /usr/local/x-ui/ -rf
		rm /usr/bin/x-ui -f
		uncronxui
		rm -rf xuiyg_update
		sed -i '/^precedence ::ffff:0:0\/96  100/d' /etc/gai.conf 2>/dev/null
		green "x-ui已卸载完成"
		blue "欢迎继续使用x-ui-yg脚本：bash <(curl -Ls https://gitlab.com/rwkgyg/x-ui-yg/raw/main/install.sh)"
		echo
	else
		red "输入有误" && uninstall
	fi
}

reset_config() {
	/usr/local/x-ui/x-ui setting -reset
	sleep 1
	portinstall
}

stop() {
	systemctl stop x-ui
	check_status
	if [[ $? == 1 ]]; then
		crontab -l >/tmp/crontab.tmp
		sed -i '/goxui.sh/d' /tmp/crontab.tmp
		crontab /tmp/crontab.tmp
		rm /tmp/crontab.tmp
		green "x-ui停止成功"
	else
		red "x-ui停止失败，请运行 x-ui log 查看日志并反馈" && exit
	fi
}

restart() {
	systemctl restart x-ui
	sleep 2
	check_status
	if [[ $? == 0 ]]; then
		crontab -l >/tmp/crontab.tmp
		sed -i '/goxui.sh/d' /tmp/crontab.tmp
		crontab /tmp/crontab.tmp
		rm /tmp/crontab.tmp
		crontab -l >/tmp/crontab.tmp
		echo "* * * * * /usr/local/x-ui/goxui.sh" >>/tmp/crontab.tmp
		crontab /tmp/crontab.tmp
		rm /tmp/crontab.tmp
		green "x-ui重启成功"
	else
		red "x-ui重启失败，请运行 x-ui log 查看日志并反馈" && exit
	fi
}

show_log() {
	journalctl -u x-ui.service -e --no-pager -f
}

get_char() {
	SAVEDSTTY=$(stty -g)
	stty -echo
	stty cbreak
	dd if=/dev/tty bs=1 count=1 2>/dev/null
	stty -raw
	stty echo
	stty $SAVEDSTTY
}

back() {
	white "------------------------------------------------------------------------------------"
	white " 回x-ui主菜单，请按任意键"
	white " 退出脚本，请按Ctrl+C"
	get_char && show_menu
}

acme() {
	bash <(curl -Ls https://gitlab.com/rwkgyg/acme-script/raw/main/acme.sh)
	back
}

bbr() {
	bash <(curl -Ls https://raw.githubusercontent.com/teddysun/across/master/bbr.sh)
	back
}

cfwarp() {
	bash <(curl -Ls https://gitlab.com/rwkgyg/CFwarp/raw/main/CFwarp.sh)
	back
}

xuirestop() {
	echo
	readp "1. 停止 x-ui \n2. 重启 x-ui \n0. 返回主菜单\n请选择：" action
	if [[ $action == "1" ]]; then
		stop
	elif [[ $action == "2" ]]; then
		restart
	else
		show_menu
	fi
}

xuichange() {
	echo
	readp "1. 更改 x-ui 用户名与密码 \n2. 更改 x-ui 面板登录端口 \n3. 重置 x-ui 面板设置（面板设置选项中所有设置都装恢复出厂设置，登录端口将重新自定义，账号密码不变）\n0. 返回主菜单\n请选择：" action
	if [[ $action == "1" ]]; then
		userinstall && restart
	elif [[ $action == "2" ]]; then
		portinstall && restart
	elif [[ $action == "3" ]]; then
		reset_config && restart
	else
		show_menu
	fi
}

check_status() {
	if [[ ! -f /etc/systemd/system/x-ui.service ]]; then
		return 2
	fi
	temp=$(systemctl status x-ui | grep Active | awk '{print $3}' | cut -d "(" -f2 | cut -d ")" -f1)
	if [[ x"${temp}" == x"running" ]]; then
		return 0
	else
		return 1
	fi
}

check_enabled() {
	temp=$(systemctl is-enabled x-ui)
	if [[ x"${temp}" == x"enabled" ]]; then
		return 0
	else
		return 1
	fi
}

check_uninstall() {
	check_status
	if [[ $? != 2 ]]; then
		yellow "x-ui已安装，可先选择2卸载，再安装" && sleep 3
		if [[ $# == 0 ]]; then
			show_menu
		fi
		return 1
	else
		return 0
	fi
}

check_install() {
	check_status
	if [[ $? == 2 ]]; then
		yellow "未安装x-ui，请先安装x-ui" && sleep 3
		if [[ $# == 0 ]]; then
			show_menu
		fi
		return 1
	else
		return 0
	fi
}

show_status() {
	check_status
	case $? in
	0)
		echo -e "x-ui状态: $blue已运行$plain"
		show_enable_status
		;;
	1)
		echo -e "x-ui状态: $yellow未运行$plain"
		show_enable_status
		;;
	2)
		echo -e "x-ui状态: $red未安装$plain"
		;;
	esac
	show_xray_status
}

show_enable_status() {
	check_enabled
	if [[ $? == 0 ]]; then
		echo -e "x-ui自启: $blue是$plain"
	else
		echo -e "x-ui自启: $red否$plain"
	fi
}

check_xray_status() {
	count=$(ps -ef | grep "xray-linux" | grep -v "grep" | wc -l)
	if [[ count -ne 0 ]]; then
		return 0
	else
		return 1
	fi
}

show_xray_status() {
	check_xray_status
	if [[ $? == 0 ]]; then
		echo -e "xray状态: $blue已启动$plain"
	else
		echo -e "xray状态: $red未启动$plain"
	fi
}

xuigo() {
	cat >/usr/local/x-ui/goxui.sh <<-\EOF
		#!/bin/bash
		xui=`ps -aux |grep "x-ui" |grep -v "grep" |wc -l`
		xray=`ps -aux |grep "xray" |grep -v "grep" |wc -l`
		if [ $xui = 0 ];then
		x-ui restart
		fi
		if [ $xray = 0 ];then
		x-ui restart
		fi
	EOF
	chmod +x /usr/local/x-ui/goxui.sh
}

cronxui() {
	uncronxui
	crontab -l >/tmp/crontab.tmp
	echo "* * * * * /usr/local/x-ui/goxui.sh" >>/tmp/crontab.tmp
	echo "0 2 * * * x-ui restart" >>/tmp/crontab.tmp
	crontab /tmp/crontab.tmp
	rm /tmp/crontab.tmp
}

uncronxui() {
	crontab -l >/tmp/crontab.tmp
	sed -i '/goxui.sh/d' /tmp/crontab.tmp
	sed -i '/x-ui restart/d' /tmp/crontab.tmp
	sed -i '/xuiargoport.log/d' /tmp/crontab.tmp
	sed -i '/xuiargopid.log/d' /tmp/crontab.tmp
	sed -i '/xuiargoympid/d' /tmp/crontab.tmp
	crontab /tmp/crontab.tmp
	rm /tmp/crontab.tmp
}

close() {
	systemctl stop firewalld.service >/dev/null 2>&1
	systemctl disable firewalld.service >/dev/null 2>&1
	setenforce 0 >/dev/null 2>&1
	ufw disable >/dev/null 2>&1
	iptables -P INPUT ACCEPT >/dev/null 2>&1
	iptables -P FORWARD ACCEPT >/dev/null 2>&1
	iptables -P OUTPUT ACCEPT >/dev/null 2>&1
	iptables -t mangle -F >/dev/null 2>&1
	iptables -F >/dev/null 2>&1
	iptables -X >/dev/null 2>&1
	netfilter-persistent save >/dev/null 2>&1
	if [[ -n $(apachectl -v 2>/dev/null) ]]; then
		systemctl stop httpd.service >/dev/null 2>&1
		systemctl disable httpd.service >/dev/null 2>&1
		service apache2 stop >/dev/null 2>&1
		systemctl disable apache2 >/dev/null 2>&1
	fi
	sleep 1
	green "执行开放端口，关闭防火墙完毕"
}

openyn() {
	echo
	readp "是否开放端口，关闭防火墙？\n1、是，执行(回车默认)\n2、否，跳过！自行处理\n请选择：" action
	if [[ -z $action ]] || [[ $action == "1" ]]; then
		close
	elif [[ $action == "2" ]]; then
		echo
	else
		red "输入错误,请重新选择" && openyn
	fi
}

cloudflaredargo() {
	if [ ! -e /usr/local/x-ui/cloudflared ]; then
		case $(uname -m) in
		aarch64) cpu=arm64 ;;
		x86_64) cpu=amd64 ;;
		esac
		curl -L -o /usr/local/x-ui/cloudflared -# --retry 2 https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-$cpu
		#curl -L -o /usr/local/x-ui/cloudflared -# --retry 2 https://gitlab.com/rwkgyg/sing-box-yg/-/raw/main/$cpu
		chmod +x /usr/local/x-ui/cloudflared
	fi
}

xuiargo() {
	echo
	yellow "开启Argo隧道节点的两个前提要求："
	green "一、节点的传输协议是WS"
	green "二、节点的TLS必须关闭"
	green "节点类别可选：vmess-ws、vless-ws、trojan-ws、shadowsocks-ws，推荐vmess-ws"
	echo
	yellow "1：设置Argo临时隧道"
	yellow "2：设置Argo固定隧道"
	yellow "0：返回上层"
	readp "请选择【0-2】：" menu
	if [ "$menu" = "1" ]; then
		cfargo
	elif [ "$menu" = "2" ]; then
		cfargoym
	else
		show_menu
	fi
}

cfargo() {
	echo
	yellow "1：重置Argo临时隧道域名"
	yellow "2：停止Argo临时隧道"
	yellow "0：返回上层"
	readp "请选择【0-2】：" menu
	if [ "$menu" = "1" ]; then
		readp "请输入Argo监听的WS节点端口：" port
		echo "$port" >/usr/local/x-ui/xuiargoport.log
		cloudflaredargo
		i=0
		while [ $i -le 4 ]; do
			let i++
			yellow "第$i次刷新验证Cloudflared Argo隧道域名有效性，请稍等……"
			if [[ -n $(ps -e | grep cloudflared) ]]; then
				kill -15 $(cat /usr/local/x-ui/xuiargopid.log 2>/dev/null) >/dev/null 2>&1
			fi
			/usr/local/x-ui/cloudflared tunnel --url http://localhost:$port --edge-ip-version auto --no-autoupdate >/usr/local/x-ui/argo.log 2>&1 &
			echo "$!" >/usr/local/x-ui/xuiargopid.log
			sleep 20
			if [[ -n $(curl -sL https://$(cat /usr/local/x-ui/argo.log 2>/dev/null | grep -a trycloudflare.com | awk 'NR==2{print}' | awk -F// '{print $2}' | awk '{print $1}')/ -I | awk 'NR==1 && /404|400|503/') ]]; then
				argo=$(cat /usr/local/x-ui/argo.log 2>/dev/null | grep -a trycloudflare.com | awk 'NR==2{print}' | awk -F// '{print $2}' | awk '{print $1}')
				blue "Argo隧道申请成功，域名验证有效：$argo" && sleep 2
				break
			fi
			if [ $i -eq 5 ]; then
				red "请注意"
				yellow "1：请确保你输入的端口是x-ui已创建WS协议端口"
				yellow "2：Argo域名验证暂不可用，稍后可能会自动恢复，或者再次重置" && sleep 2
			fi
		done
		crontab -l >/tmp/crontab.tmp
		sed -i '/xuiargoport.log/d' /tmp/crontab.tmp
		crontab /tmp/crontab.tmp
		rm /tmp/crontab.tmp
		crontab -l >/tmp/crontab.tmp
		echo '@reboot /bin/bash -c "/usr/local/x-ui/cloudflared tunnel --url http://localhost:$(cat /usr/local/x-ui/xuiargoport.log) --edge-ip-version auto --no-autoupdate > /usr/local/x-ui/argo.log 2>&1 & pid=\$! && echo \$pid > /usr/local/x-ui/xuiargopid.log"' >>/tmp/crontab.tmp
		crontab /tmp/crontab.tmp
		rm /tmp/crontab.tmp
	elif [ "$menu" = "2" ]; then
		kill -15 $(cat /usr/local/x-ui/xuiargopid.log 2>/dev/null) >/dev/null 2>&1
		rm -rf /usr/local/x-ui/argo.log /usr/local/x-ui/xuiargopid.log /usr/local/x-ui/xuiargoport.log
		crontab -l >/tmp/crontab.tmp
		sed -i '/xuiargopid.log/d' /tmp/crontab.tmp
		crontab /tmp/crontab.tmp
		rm /tmp/crontab.tmp
		green "已卸载Argo临时隧道"
	else
		xuiargo
	fi
}

cfargoym() {
	echo
	if [[ -f /usr/local/x-ui/xuiargotoken.log && -f /usr/local/x-ui/xuiargoym.log ]]; then
		green "当前Argo固定隧道域名：$(cat /usr/local/x-ui/xuiargoym.log 2>/dev/null)"
		green "当前Argo固定隧道Token：$(cat /usr/local/x-ui/xuiargotoken.log 2>/dev/null)"
	fi
	echo
	green "请确保Cloudflare官网 --- Zero Trust --- Networks --- Tunnels已设置完成"
	yellow "1：重置/设置Argo固定隧道域名"
	yellow "2：停止Argo固定隧道"
	yellow "0：返回上层"
	readp "请选择【0-2】：" menu
	if [ "$menu" = "1" ]; then
		readp "请输入Argo监听的WS节点端口：" port
		echo "$port" >/usr/local/x-ui/xuiargoymport.log
		cloudflaredargo
		readp "输入Argo固定隧道Token: " argotoken
		readp "输入Argo固定隧道域名: " argoym
		if [[ -n $(ps -e | grep cloudflared) ]]; then
			kill -15 $(cat /usr/local/x-ui/xuiargoympid.log 2>/dev/null) >/dev/null 2>&1
		fi
		echo
		if [[ -n "${argotoken}" && -n "${argoym}" ]]; then
			nohup /usr/local/x-ui/cloudflared tunnel --edge-ip-version auto run --token ${argotoken} >/dev/null 2>&1 &
			echo "$!" >/usr/local/x-ui/xuiargoympid.log
			sleep 20
		fi
		echo ${argoym} >/usr/local/x-ui/xuiargoym.log
		echo ${argotoken} >/usr/local/x-ui/xuiargotoken.log
		crontab -l >/tmp/crontab.tmp
		sed -i '/xuiargoympid/d' /tmp/crontab.tmp
		echo '@reboot /bin/bash -c "nohup /usr/local/x-ui/cloudflared tunnel --edge-ip-version auto run --token $(cat /usr/local/x-ui/xuiargotoken.log 2>/dev/null) >/dev/null 2>&1 & pid=\$! && echo \$pid > /usr/local/x-ui/xuiargoympid.log"' >>/tmp/crontab.tmp
		crontab /tmp/crontab.tmp
		rm /tmp/crontab.tmp
		argo=$(cat /usr/local/x-ui/xuiargoym.log 2>/dev/null)
		blue "Argo固定隧道设置完成，固定域名：$argo"
	elif [ "$menu" = "2" ]; then
		kill -15 $(cat /usr/local/x-ui/xuiargoympid.log 2>/dev/null) >/dev/null 2>&1
		rm -rf /usr/local/x-ui/xuiargoym.log /usr/local/x-ui/xuiargoymport.log /usr/local/x-ui/xuiargoympid.log /usr/local/x-ui/xuiargotoken.log
		crontab -l >/tmp/crontab.tmp
		sed -i '/xuiargoympid/d' /tmp/crontab.tmp
		crontab /tmp/crontab.tmp
		rm /tmp/crontab.tmp
		green "已卸载Argo固定隧道"
	else
		xuiargo
	fi
}

sharesub_sbcl() {
	xip1=$(cat /usr/local/x-ui/xip 2>/dev/null | sed -n 1p)
	if [[ "$xip1" =~ : ]]; then
		dnsip='tls://[2001:4860:4860::8888]/dns-query'
	else
		dnsip='tls://8.8.8.8/dns-query'
	fi
	cat >/usr/local/x-ui/bin/xui_singbox.json <<EOF
{
  "log": {
    "disabled": false,
    "level": "info",
    "timestamp": true
  },
  "experimental": {
    "clash_api": {
      "external_controller": "127.0.0.1:9090",
      "external_ui": "ui",
      "external_ui_download_url": "",
      "external_ui_download_detour": "",
      "secret": "",
      "default_mode": "Rule"
       },
      "cache_file": {
            "enabled": true,
            "path": "cache.db",
            "store_fakeip": true
        }
    },
    "dns": {
        "servers": [
            {
                "tag": "proxydns",
                "address": "$dnsip",
                "detour": "select"
            },
            {
                "tag": "localdns",
                "address": "h3://223.5.5.5/dns-query",
                "detour": "direct"
            },
            {
                "address": "rcode://refused",
                "tag": "block"
            },
            {
                "tag": "dns_fakeip",
                "address": "fakeip"
            }
        ],
        "rules": [
            {
                "outbound": "any",
                "server": "localdns",
                "disable_cache": true
            },
            {
                "clash_mode": "Global",
                "server": "proxydns"
            },
            {
                "clash_mode": "Direct",
                "server": "localdns"
            },
            {
                "rule_set": "geosite-cn",
                "server": "localdns"
            },
            {
                 "rule_set": "geosite-geolocation-!cn",
                 "server": "proxydns"
            },
             {
                "rule_set": "geosite-geolocation-!cn",
                "query_type": [
                    "A",
                    "AAAA"
                ],
                "server": "dns_fakeip"
            }
          ],
           "fakeip": {
           "enabled": true,
           "inet4_range": "198.18.0.0/15",
           "inet6_range": "fc00::/18"
         },
          "independent_cache": true,
          "final": "proxydns"
        },
      "inbounds": [
    {
      "type": "tun",
      "inet4_address": "172.19.0.1/30",
      "inet6_address": "fd00::1/126",
      "auto_route": true,
      "strict_route": true,
      "sniff": true,
      "sniff_override_destination": true,
      "domain_strategy": "prefer_ipv4"
    }
  ],
  "outbounds": [

//_0

    {
      "tag": "direct",
      "type": "direct"
    },
    {
      "tag": "block",
      "type": "block"
    },
    {
      "tag": "dns-out",
      "type": "dns"
    },
    {
      "tag": "select",
      "type": "selector",
      "default": "auto",
      "outbounds": [
        "auto",

//_1

      ]
    },
    {
      "tag": "auto",
      "type": "urltest",
      "outbounds": [

 //_2

      ],
      "url": "https://www.gstatic.com/generate_204",
      "interval": "1m",
      "tolerance": 50,
      "interrupt_exist_connections": false
    }
  ],
  "route": {
      "rule_set": [
            {
                "tag": "geosite-geolocation-!cn",
                "type": "remote",
                "format": "binary",
                "url": "https://cdn.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@sing/geo/geosite/geolocation-!cn.srs",
                "download_detour": "select",
                "update_interval": "1d"
            },
            {
                "tag": "geosite-cn",
                "type": "remote",
                "format": "binary",
                "url": "https://cdn.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@sing/geo/geosite/geolocation-cn.srs",
                "download_detour": "select",
                "update_interval": "1d"
            },
            {
                "tag": "geoip-cn",
                "type": "remote",
                "format": "binary",
                "url": "https://cdn.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@sing/geo/geoip/cn.srs",
                "download_detour": "select",
                "update_interval": "1d"
            }
        ],
    "auto_detect_interface": true,
    "final": "select",
    "rules": [
      {
        "outbound": "dns-out",
        "protocol": "dns"
      },
      {
        "clash_mode": "Direct",
        "outbound": "direct"
      },
      {
        "clash_mode": "Global",
        "outbound": "select"
      },
      {
        "rule_set": "geoip-cn",
        "outbound": "direct"
      },
      {
        "rule_set": "geosite-cn",
        "outbound": "direct"
      },
      {
      "ip_is_private": true,
      "outbound": "direct"
      },
      {
        "rule_set": "geosite-geolocation-!cn",
        "outbound": "select"
      }
    ]
  },
    "ntp": {
    "enabled": true,
    "server": "time.apple.com",
    "server_port": 123,
    "interval": "30m",
    "detour": "direct"
  }
}
EOF

	cat >/usr/local/x-ui/bin/xui_clashmeta.yaml <<EOF
port: 7890
allow-lan: true
mode: rule
log-level: info
unified-delay: true
global-client-fingerprint: chrome
dns:
  enable: true
  listen: :53
  ipv6: true
  enhanced-mode: fake-ip
  fake-ip-range: 198.18.0.1/16
  default-nameserver:
    - 223.5.5.5
    - 8.8.8.8
  nameserver:
    - https://dns.alidns.com/dns-query
    - https://doh.pub/dns-query
  fallback:
    - https://1.0.0.1/dns-query
    - tls://dns.google
  fallback-filter:
    geoip: true
    geoip-code: CN
    ipcidr:
      - 240.0.0.0/4

proxies:

#_0

proxy-groups:
- name: 负载均衡
  type: load-balance
  url: https://www.gstatic.com/generate_204
  interval: 300
  strategy: round-robin
  proxies:

#_1


- name: 自动选择
  type: url-test
  url: https://www.gstatic.com/generate_204
  interval: 300
  tolerance: 50
  proxies:

#_2

- name: 🌍选择代理节点
  type: select
  proxies:
    - 负载均衡
    - 自动选择
    - DIRECT

#_3

rules:
  - GEOIP,LAN,DIRECT
  - GEOIP,CN,DIRECT
  - MATCH,🌍选择代理节点
EOF

	xui_sb_cl() {
		sed -i "/#_0/r /usr/local/x-ui/bin/cl${i}.log" /usr/local/x-ui/bin/xui_clashmeta.yaml
		sed -i "/#_1/ a\\    - $tag" /usr/local/x-ui/bin/xui_clashmeta.yaml
		sed -i "/#_2/ a\\    - $tag" /usr/local/x-ui/bin/xui_clashmeta.yaml
		sed -i "/#_3/ a\\    - $tag" /usr/local/x-ui/bin/xui_clashmeta.yaml
		sed -i "/\/\/_0/r /usr/local/x-ui/bin/sb${i}.log" /usr/local/x-ui/bin/xui_singbox.json
		sed -i "/\/\/_1/ i\\ \"$tag\"," /usr/local/x-ui/bin/xui_singbox.json
		sed -i "/\/\/_2/ i\\ \"$tag\"," /usr/local/x-ui/bin/xui_singbox.json
	}

	tag_count=$(jq '.inbounds | map(select(.protocol == "vless" or .protocol == "vmess" or .protocol == "trojan" or .protocol == "shadowsocks")) | length' /usr/local/x-ui/bin/config.json)
	for ((i = 0; i < tag_count; i++)); do
		jq -c ".inbounds | map(select(.protocol == \"vless\" or .protocol == \"vmess\" or .protocol == \"trojan\" or .protocol == \"shadowsocks\"))[$i]" /usr/local/x-ui/bin/config.json >"/usr/local/x-ui/bin/$((i + 1)).txt"
	done

	xip1=$(cat /usr/local/x-ui/xip 2>/dev/null | sed -n 1p)
	ymip=$(cat /root/ygkkkca/ca.log 2>/dev/null)
	directory="/usr/local/x-ui/bin/"
	for i in $(seq 1 $tag_count); do
		file="${directory}${i}.txt"
		if [ -f "$file" ]; then
			if grep -q "vless" "$file" && grep -q "shortIds" "$file"; then
				finger=$(jq -r '.streamSettings.realitySettings.fingerprint' /usr/local/x-ui/bin/${i}.txt)
				vl_name=$(jq -r '.streamSettings.realitySettings.serverNames[0]' /usr/local/x-ui/bin/${i}.txt)
				public_key=$(jq -r '.streamSettings.realitySettings.publicKey' /usr/local/x-ui/bin/${i}.txt)
				short_id=$(jq -r '.streamSettings.realitySettings.shortIds[0]' /usr/local/x-ui/bin/${i}.txt)
				uuid=$(jq -r '.settings.clients[0].id' /usr/local/x-ui/bin/${i}.txt)
				vl_port=$(jq -r '.port' /usr/local/x-ui/bin/${i}.txt)
				tag=$(jq -r '.tag' /usr/local/x-ui/bin/${i}.txt)
				cat >/usr/local/x-ui/bin/sb${i}.log <<EOF

 {
      "type": "vless",
      "tag": "$tag",
      "server": "$xip1",
      "server_port": $vl_port,
      "uuid": "$uuid",
      "packet_encoding": "xudp",
      "flow": "xtls-rprx-vision",
      "tls": {
        "enabled": true,
        "server_name": "$vl_name",
        "utls": {
          "enabled": true,
          "fingerprint": "chrome"
        },
      "reality": {
          "enabled": true,
          "public_key": "$public_key",
          "short_id": "$short_id"
        }
      }
    },
EOF

				cat >/usr/local/x-ui/bin/cl${i}.log <<EOF

- name: $tag
  type: vless
  server: $xip1
  port: $vl_port
  uuid: $uuid
  network: tcp
  udp: true
  tls: true
  flow: xtls-rprx-vision
  servername: $vl_name
  reality-opts:
    public-key: $public_key
    short-id: '$short_id'
  client-fingerprint: chrome

EOF
				xui_sb_cl

			elif grep -q "vless" "$file" && grep -q "ws" "$file"; then
				ws_path=$(jq -r '.streamSettings.wsSettings.path' /usr/local/x-ui/bin/${i}.txt)
				[[ -n $ymip ]] && servip=$ymip || servip=$xip1
				tls=$(jq -r '.streamSettings.security' /usr/local/x-ui/bin/${i}.txt)
				[[ $tls == 'tls' ]] && tls=true || tls=false
				vl_name=$(jq -r '.streamSettings.wsSettings.headers.Host' /usr/local/x-ui/bin/${i}.txt)
				uuid=$(jq -r '.settings.clients[0].id' /usr/local/x-ui/bin/${i}.txt)
				vl_port=$(jq -r '.port' /usr/local/x-ui/bin/${i}.txt)
				tag=$(jq -r '.tag' /usr/local/x-ui/bin/${i}.txt)
				cat >/usr/local/x-ui/bin/sb${i}.log <<EOF

{
            "server": "$servip",
            "server_port": $vl_port,
            "tag": "$tag",
            "tls": {
                "enabled": $tls,
                "server_name": "$vl_name",
                "insecure": false,
                "utls": {
                    "enabled": true,
                    "fingerprint": "chrome"
                }
            },
            "packet_encoding": "packetaddr",
            "transport": {
                "headers": {
                    "Host": [
                        "$vl_name"
                    ]
                },
                "path": "$ws_path",
                "type": "ws"
            },
            "type": "vless",
            "uuid": "$uuid"
        },
EOF

				cat >/usr/local/x-ui/bin/cl${i}.log <<EOF

- name: $tag
  type: vless
  server: $servip
  port: $vl_port
  uuid: $uuid
  udp: true
  tls: $tls
  network: ws
  servername: $vl_name
  ws-opts:
    path: "$ws_path"
    headers:
      Host: $vl_name

EOF
				xui_sb_cl

			elif grep -q "vmess" "$file" && grep -q "ws" "$file"; then
				ws_path=$(jq -r '.streamSettings.wsSettings.path' /usr/local/x-ui/bin/${i}.txt)
				[[ -n $ymip ]] && servip=$ymip || servip=$xip1
				tls=$(jq -r '.streamSettings.security' /usr/local/x-ui/bin/${i}.txt)
				[[ $tls == 'tls' ]] && tls=true || tls=false
				vm_name=$(jq -r '.streamSettings.wsSettings.headers.Host' /usr/local/x-ui/bin/${i}.txt)
				uuid=$(jq -r '.settings.clients[0].id' /usr/local/x-ui/bin/${i}.txt)
				vm_port=$(jq -r '.port' /usr/local/x-ui/bin/${i}.txt)
				tag=$(jq -r '.tag' /usr/local/x-ui/bin/${i}.txt)
				cat >/usr/local/x-ui/bin/sb${i}.log <<EOF

{
            "server": "$servip",
            "server_port": $vm_port,
            "tag": "$tag",
            "tls": {
                "enabled": $tls,
                "server_name": "$vm_name",
                "insecure": false,
                "utls": {
                    "enabled": true,
                    "fingerprint": "chrome"
                }
            },
            "packet_encoding": "packetaddr",
            "transport": {
                "headers": {
                    "Host": [
                        "$vm_name"
                    ]
                },
                "path": "$ws_path",
                "type": "ws"
            },
            "type": "vmess",
            "security": "auto",
            "uuid": "$uuid"
        },
EOF

				cat >/usr/local/x-ui/bin/cl${i}.log <<EOF

- name: $tag
  type: vmess
  server: $servip
  port: $vm_port
  uuid: $uuid
  alterId: 0
  cipher: auto
  udp: true
  tls: $tls
  network: ws
  servername: $vm_name
  ws-opts:
    path: "$ws_path"
    headers:
      Host: $vm_name

EOF
				xui_sb_cl
			fi
		else
			red "当前x-ui未设置有效的节点配置" && exit
		fi
	done

	line=$(grep -B1 "//_1" /usr/local/x-ui/bin/xui_singbox.json | grep -v "//_1")
	new_line=$(echo "$line" | sed 's/,//g')
	sed -i "/^$line$/s/.*/$new_line/g" /usr/local/x-ui/bin/xui_singbox.json
	sed -i '/\/\/_0\|\/\/_1\|\/\/_2/d' /usr/local/x-ui/bin/xui_singbox.json
	sed -i '/#_0\|#_1\|#_2\|#_3/d' /usr/local/x-ui/bin/xui_clashmeta.yaml
	cat /usr/local/x-ui/bin/xui_singbox.json
	cat /usr/local/x-ui/bin/xui_clashmeta.yaml
}

show_menu() {
	clear
	white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
	echo -e "${bblue} ░██     ░██      ░██ ██ ██         ░█${plain}█   ░██     ░██   ░██     ░█${red}█   ░██${plain}  "
	echo -e "${bblue}  ░██   ░██      ░██    ░░██${plain}        ░██  ░██      ░██  ░██${red}      ░██  ░██${plain}   "
	echo -e "${bblue}   ░██ ░██      ░██ ${plain}                ░██ ██        ░██ █${red}█        ░██ ██  ${plain}   "
	echo -e "${bblue}     ░██        ░${plain}██    ░██ ██       ░██ ██        ░█${red}█ ██        ░██ ██  ${plain}  "
	echo -e "${bblue}     ░██ ${plain}        ░██    ░░██        ░██ ░██       ░${red}██ ░██       ░██ ░██ ${plain}  "
	echo -e "${bblue}     ░█${plain}█          ░██ ██ ██         ░██  ░░${red}██     ░██  ░░██     ░██  ░░██ ${plain}  "
	white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
	white "甬哥Github项目  ：github.com/yonggekkk"
	white "甬哥Blogger博客 ：ygkkk.blogspot.com"
	white "甬哥YouTube频道 ：www.youtube.com/@ygkkk"
	white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
	white "x-ui-yg脚本快捷方式：x-ui"
	red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
	green " 1. 安装 x-ui"
	green " 2. 卸载 x-ui"
	echo "----------------------------------------------------------------------------------"
	green " 3. 设置Argo临时/固定隧道节点"
	green " 4. 变更 x-ui 面板设置 (用户名密码、登录端口、还原面板)"
	green " 5. 关闭、重启 x-ui"
	green " 6. 更新 x-ui 脚本"
	echo "----------------------------------------------------------------------------------"
	#green " 7. 查看clash-meta与sing-box配置"
	green " 7. 查看 x-ui 运行日志"
	green " 8. 一键原版BBR+FQ加速"
	green " 9. 管理 Acme 申请域名证书"
	green "10. 管理 Warp 查看Netflix、ChatGPT解锁情况"
	green "11. 刷新当前主菜单参数显示"
	green " 0. 退出脚本"
	red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
	insV=$(cat /usr/local/x-ui/v 2>/dev/null)
	latestV=$(curl -s https://gitlab.com/rwkgyg/x-ui-yg/-/raw/main/version/version | awk -F "更新内容" '{print $1}' | head -n 1)
	if [[ -f /usr/local/x-ui/v ]]; then
		if [ "$insV" = "$latestV" ]; then
			echo -e "当前 x-ui-yg 脚本最新版：${bblue}${insV}${plain} (已安装)"
		else
			echo -e "当前 x-ui-yg 脚本版本号：${bblue}${insV}${plain}"
			echo -e "检测到最新 x-ui-yg 脚本版本号：${yellow}${latestV}${plain} (可选择6进行更新)"
			echo -e "${yellow}$(curl -sL https://gitlab.com/rwkgyg/x-ui-yg/-/raw/main/version/version)${plain}"
		fi
	else
		echo -e "当前 x-ui-yg 脚本版本号：${bblue}${latestV}${plain}"
		echo -e "请先选择 1 ，安装 x-ui-yg 脚本"
	fi
	red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
	echo -e "VPS状态如下："
	echo -e "系统:$blue$op$plain  \c"
	echo -e "内核:$blue$version$plain  \c"
	echo -e "处理器:$blue$cpu$plain  \c"
	echo -e "虚拟化:$blue$vi$plain  \c"
	echo -e "BBR算法:$blue$bbr$plain"
	v4v6
	if [[ "$v6" == "2a09"* ]]; then
		w6="【WARP】"
	fi
	if [[ "$v4" == "104.28"* ]]; then
		w4="【WARP】"
	fi
	if [[ -z $v4 ]]; then
		vps_ipv4='无IPV4'
		vps_ipv6="$v6"
	elif [[ -n $v4 && -n $v6 ]]; then
		vps_ipv4="$v4"
		vps_ipv6="$v6"
	else
		vps_ipv4="$v4"
		vps_ipv6='无IPV6'
	fi
	echo -e "本地IPV4地址：$blue$vps_ipv4$w4$plain   本地IPV6地址：$blue$vps_ipv6$w6$plain"
	echo "------------------------------------------------------------------------------------"
	argopid
	if [[ -n $(ps -e | grep -w $ym 2>/dev/null) || -n $(ps -e | grep -w $ls 2>/dev/null) ]]; then
		if [[ -f /usr/local/x-ui/xuiargoport.log ]]; then
			argoprotocol=$(jq -r --arg port "$(cat /usr/local/x-ui/xuiargoport.log 2>/dev/null)" '.inbounds[] | select(.port == ($port | tonumber)) | .protocol' /usr/local/x-ui/bin/config.json)
			echo -e "Argo临时隧道状态：$blue已启动 【监听$yellow${argoprotocol}-ws$plain$blue节点的端口:$plain$yellow$(cat /usr/local/x-ui/xuiargoport.log 2>/dev/null)$plain$blue】$plain$plain"
			argotro=$(jq -r --arg port "$(cat /usr/local/x-ui/xuiargoport.log 2>/dev/null)" '.inbounds[] | select(.port == ($port | tonumber)) | .settings.clients[0].password' /usr/local/x-ui/bin/config.json)
			argoss=$(jq -r --arg port "$(cat /usr/local/x-ui/xuiargoport.log 2>/dev/null)" '.inbounds[] | select(.port == ($port | tonumber)) | .settings.password' /usr/local/x-ui/bin/config.json)
			argouuid=$(jq -r --arg port "$(cat /usr/local/x-ui/xuiargoport.log 2>/dev/null)" '.inbounds[] | select(.port == ($port | tonumber)) | .settings.clients[0].id' /usr/local/x-ui/bin/config.json)
			argopath=$(jq -r --arg port "$(cat /usr/local/x-ui/xuiargoport.log 2>/dev/null)" '.inbounds[] | select(.port == ($port | tonumber)) | .streamSettings.wsSettings.path' /usr/local/x-ui/bin/config.json)
			if [[ ! $argouuid = "null" ]]; then
				argoma=$argouuid
			elif [[ ! $argoss = "null" ]]; then
				argoma=$argoss
			else
				argoma=$argotro
			fi
			argotls=$(jq -r --arg port "$(cat /usr/local/x-ui/xuiargoport.log 2>/dev/null)" '.inbounds[] | select(.port == ($port | tonumber)) | .streamSettings.security' /usr/local/x-ui/bin/config.json)
			if [[ -n $argouuid ]]; then
				if [[ "$argotls" = "tls" ]]; then
					echo -e "错误反馈：$red面板创建的ws节点开启了tls，不支持Argo，请在面板对应的节点中关闭tls$plain"
				else
					echo -e "Argo密码/UUID：$blue$argoma$plain"
					echo -e "Argo路径path：$blue$argopath$plain"
					argolsym=$(cat /usr/local/x-ui/argo.log 2>/dev/null | grep -a trycloudflare.com | awk 'NR==2{print}' | awk -F// '{print $2}' | awk '{print $1}')
					[[ $(echo "$argolsym" | grep -w "api.trycloudflare.com/tunnel") ]] && argolsyms='生成失败，请重置' || argolsyms=$argolsym
					echo -e "Argo临时域名：$blue$argolsyms$plain"

				fi
			else
				echo -e "错误反馈：$red面板尚未创建一个端口为$yellow$(cat /usr/local/x-ui/xuiargoport.log 2>/dev/null)$plain$red的ws节点，推荐vmess-ws$plain$plain"
			fi
		fi

		if [[ -f /usr/local/x-ui/xuiargoymport.log && -f /usr/local/x-ui/xuiargoport.log ]]; then
			echo "--------------------------"
		fi

		if [[ -f /usr/local/x-ui/xuiargoymport.log ]]; then
			argoprotocol=$(jq -r --arg port "$(cat /usr/local/x-ui/xuiargoymport.log 2>/dev/null)" '.inbounds[] | select(.port == ($port | tonumber)) | .protocol' /usr/local/x-ui/bin/config.json)
			echo -e "Argo固定隧道状态：$blue已启动 【监听$yellow${argoprotocol}-ws$plain$blue节点的端口:$plain$yellow$(cat /usr/local/x-ui/xuiargoymport.log 2>/dev/null)$plain$blue】$plain$plain"
			argotro=$(jq -r --arg port "$(cat /usr/local/x-ui/xuiargoymport.log 2>/dev/null)" '.inbounds[] | select(.port == ($port | tonumber)) | .settings.clients[0].password' /usr/local/x-ui/bin/config.json)
			argoss=$(jq -r --arg port "$(cat /usr/local/x-ui/xuiargoymport.log 2>/dev/null)" '.inbounds[] | select(.port == ($port | tonumber)) | .settings.password' /usr/local/x-ui/bin/config.json)
			argouuid=$(jq -r --arg port "$(cat /usr/local/x-ui/xuiargoymport.log 2>/dev/null)" '.inbounds[] | select(.port == ($port | tonumber)) | .settings.clients[0].id' /usr/local/x-ui/bin/config.json)
			argopath=$(jq -r --arg port "$(cat /usr/local/x-ui/xuiargoymport.log 2>/dev/null)" '.inbounds[] | select(.port == ($port | tonumber)) | .streamSettings.wsSettings.path' /usr/local/x-ui/bin/config.json)
			if [[ ! $argouuid = "null" ]]; then
				argoma=$argouuid
			elif [[ ! $argoss = "null" ]]; then
				argoma=$argoss
			else
				argoma=$argotro
			fi
			argotls=$(jq -r --arg port "$(cat /usr/local/x-ui/xuiargoymport.log 2>/dev/null)" '.inbounds[] | select(.port == ($port | tonumber)) | .streamSettings.security' /usr/local/x-ui/bin/config.json)
			if [[ -n $argouuid ]]; then
				if [[ "$argotls" = "tls" ]]; then
					echo -e "错误反馈：$red面板创建的ws节点开启了tls，不支持Argo，请在面板对应的节点中关闭tls$plain"
				else
					echo -e "Argo密码/UUID：$blue$argoma$plain"
					echo -e "Argo路径path：$blue$argopath$plain"
					echo -e "Argo固定域名：$blue$(cat /usr/local/x-ui/xuiargoym.log 2>/dev/null)$plain"
				fi
			else
				echo -e "错误反馈：$red面板尚未创建一个端口为$yellow$(cat /usr/local/x-ui/xuiargoymport.log 2>/dev/null)$plain$red的ws节点，推荐vmess-ws$plain$plain"
			fi
		fi
	else
		echo -e "Argo状态：$blue未启动$plain"
	fi
	echo "------------------------------------------------------------------------------------"
	show_status
	echo "------------------------------------------------------------------------------------"
	acp=$(/usr/local/x-ui/x-ui setting -show 2>/dev/null)
	if [[ -n $acp ]]; then
		if [[ $acp == *admin* ]]; then
			red "x-ui出错，请重置用户名或者卸载重装x-ui"
		else
			xpath=$(echo $acp | awk '{print $8}')
			xport=$(echo $acp | awk '{print $6}')
			xip1=$(cat /usr/local/x-ui/xip 2>/dev/null | sed -n 1p)
			xip2=$(cat /usr/local/x-ui/xip 2>/dev/null | sed -n 2p)
			if [ "$xpath" == "/" ]; then
				path="$sred【严重安全提示: 请进入面板设置，添加url根路径】$plain"
			fi
			echo -e "x-ui登录信息如下："
			echo -e "$blue$acp$path$plain"
			if [[ -n $xip2 ]]; then
				xuimb="http://${xip1}:${xport}${xpath} 或者 http://${xip2}:${xport}${xpath}"
			else
				xuimb="http://${xip1}:${xport}${xpath}"
			fi
			echo -e "$blue默认IP登录地址(非安全)：$xuimb$plain"
			if [[ -f /root/ygkkkca/ca.log ]]; then
				echo -e "$blue路径域名登录地址(安全)：https://$(cat /root/ygkkkca/ca.log 2>/dev/null):${xport}${xpath}$plain"
			fi
		fi
	else
		echo -e "x-ui登录信息如下："
		echo -e "$red未安装x-ui，无显示$plain"
	fi
	red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
	echo
	readp "请输入数字:" Input
	case "$Input" in
	1) check_uninstall && xuiinstall ;;
	2) check_install && uninstall ;;
	3) check_install && xuiargo ;;
	4) check_install && xuichange ;;
	5) check_install && xuirestop ;;
	6) check_install && update ;;
	#7 ) check_install && sharesub_sbcl;;
	7) check_install && show_log ;;
	8) bbr ;;
	9) acme ;;
	10) cfwarp ;;
	11) show_menu ;;
	*) exit ;;
	esac
}
show_menu
