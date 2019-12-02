DNSCrypt
===
## 简介
* **DNSCrypt** 是一种用于保护客户端和DNS解析器之间的通信的协议，使用高速高安全性的椭圆曲线加密技术。
> * 项目地址：https://github.com/jedisct1/dnscrypt-proxy
> * chinadns：https://github.com/zfl9/chinadns-ng
> * BIND ebook：http://www.zytrax.com/books/dns/


## Example:

    #运行一个bind服务器
    docker run -d --restart unless-stopped -p 53:53/udp --name dns jiobxn/dnscrypt

    #运行一个dnscrypt服务器
    docker run -d --restart unless-stopped -p 53:53/udp -e DNSCRYPT=Y --name dns jiobxn/dnscrypt

    #运行一个chinadns服务器
    docker run -d --restart unless-stopped -p 53:53/udp -e CHINADNS=Y --name dns jiobxn/dnscrypt

    #在Windows上运行一个dnscrypt客户端，连接到公共DNS服务器(将本地DNS改为127.0.0.1)
    ./dnscrypt-proxy.exe

    #测试
    docker exec -it dns dig @27.0.0.1 -p 53 g.cn


## Run Defult Parameter
**协定：** []是默参数，<>是自定义参数

				docker run -d --restart unless-stopped \\
				-v /docker/dnslog:/dnslog \\
				-p 53:53/udp \\
				-e VERSION=["windows 2003 DNS"] \\   DNS版本描使 [bind]
				-e LISTEN_ADDR=[0.0.0.0] \\          监听地址
				-e LISTEN_PORT=[53] \\               监听端口
				-e BIND_DNS=<9.9.9.9;8.8.8.8> \\     转发DNS，";"分隔 [bind]
				-e FORWARD_ONLY=<Y> \\               只使用转发DNS [bind]
				-e CACHE_SIZE=[256] \\               dns缓存大小 M
				-e QUERY_LOG=<Y> \\                  记录解析日记
				-e LOG_SIZE=[100] \\                 日志文件大小 M
				-e DNSCRYPT=<Y> \\                   使用无污染的公共DNS
				-e MAX_CLIENT=[250] \\               最大并发数 [dnscrypt]
				-e CHINADNS=<Y> \\                   智能解析。原理：定义两组DNS(内\外)，解析有chnroute.txt IP的以"内"为准，非chnroute.txt IP的以"外"为准
				-e TRUSE_DNS=[127.0.0.1#55] \\       可信DNS(dnscrypt)
				-e CHINA_DNS=[114.114.114.114,223.5.5.5] \\    大陆DNS
				--name dns dnscrypt

****

## 添加NS解析

	DOMAIN=qq.com
	IPADDR=192.168.80.100
	
	cat >>/etc/named.rfc1912.zones <<-END
	#$DOMAIN
	zone "$DOMAIN" IN {
			type master;
			file "$DOMAIN";
			allow-update { none; };
	};
	END

	cat >/var/named/$DOMAIN <<-END
	@       IN SOA  ns.$DOMAIN. root.$DOMAIN. (
									$(date +%Y%m%d%H)
											1D
											1H
											1W
											3H )
	@     IN      NS      ns.$DOMAIN.
	ns    IN      A       $IPADDR

	@     IN      A       $IPADDR
	m     IN      A       $IPADDR
	*     IN      A       $IPADDR
	END

### dnsmasq

	yum install dnsmasq -y
	echo address=/.google.com/192.168.1.3 >/etc/dnsmasq.d/google.conf
	echo address=/m.youtube.com/192.168.1.3 >/etc/dnsmasq.d/youtube.conf
	systemctl restart dnsmasq.service
