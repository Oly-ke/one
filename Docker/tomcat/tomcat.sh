#!/bin/bash
set -e

if [ "$1" = 'catalina.sh' ]; then

: ${TOM_PASS:=$(pwmake 64)}
: ${TOM_CHARSET:=UTF-8}
: ${WWW_ROOT:=ROOT}
: ${HTTP_PORT:=8080}
: ${HTTPS_PORT:=8443}
: ${REDIS_PORT:=6379}
: ${SESSION_TTL:=30}
: ${MAX_MEM=$(($(free -m |grep Mem |awk '{print $2}')*50/100))}

  if [ -z "$(grep "redhat.xyz" /usr/local/tomcat/conf/server.xml)" ]; then
	echo "Initialize tomcat"
	sed -i '2 i <!-- redhat.xyz -->' /usr/local/tomcat/conf/server.xml

	#HTTPS
	keytool -genkey -alias tomcat -keyalg RSA -keypass redhat -storepass redhat -dname "CN=docker-tomcat, OU=redhat.xyz, O=JIOBXN, L=GZ, S=GD, C=CN" -keystore /usr/local/tomcat/conf/.keystore -validity 3600 
	
	cat >/tomcat-ssl.txt <<-END
	    <Connector
               protocol="org.apache.coyote.http11.Http11NioProtocol"
               port="8443" acceptCount="$((`nproc`*10240))" maxThreads="$((`nproc`*10240))"
	       compression="on" disableUploadTimeout="true" URIEncoding="$TOM_CHARSET"
               scheme="https" secure="true" SSLEnabled="true"
               keystoreFile="conf/.keystore" keystorePass="redhat"
               clientAuth="false" sslProtocol="TLS"/>
	END
	sed -i '/A "Connector" using the shared thread pool/ r /tomcat-ssl.txt' /usr/local/tomcat/conf/server.xml
	
	#gzip
	sed -i '/Connector port="8080"/ a \               acceptCount="'$((`nproc`*10240))'" maxThreads="'$((`nproc`*10240))'" \n\               compression="on" disableUploadTimeout="true" URIEncoding='\"$TOM_CHARSET\"'' /usr/local/tomcat/conf/server.xml

	#server name
	if [ "$SERVER_NAME" ]; then
		sed -i 's/webapps/none/g' /usr/local/tomcat/conf/server.xml
		for i in $(echo $SERVER_NAME |sed 's/,/\n/g') ;do
			sed -i '/<\/Engine>/ i \      <Host name='\"$i\"' appBase="webapps" \n            unpackWARs="true" autoDeploy="true"> \n            <Context path="" docBase='\"$WWW_ROOT\"' /> \n      </Host>' /usr/local/tomcat/conf/server.xml
		done
	else
		sed -i '/unpackWARs/ a \            <Context path="" docBase='\"$WWW_ROOT\"' />' /usr/local/tomcat/conf/server.xml
	fi
	
	#alias
	if [ $WWW_ALIAS ]; then
		for i in $(echo "$WWW_ALIAS" |sed 's/;/\n/g'); do
			if [ -n "$(echo $i |grep ',')" ]; then
				sed -i '/unpackWARs/ a \            <Context path='\"$(echo $i |awk -F, '{print $1}')\"' docBase='\"$(echo $i |awk -F, '{print $2}')\"' />' /usr/local/tomcat/conf/server.xml
			fi
		done
	fi
	
	#administrator
	if [ "$TOM_USER" ]; then
		cat >/usr/local/tomcat/conf/tomcat-users.xml <<-END
		<?xml version='1.0' encoding='utf-8'?>
		<tomcat-users xmlns="http://tomcat.apache.org/xml"
			xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
			xsi:schemaLocation="http://tomcat.apache.org/xml tomcat-users.xsd"
			version="1.0">
			<role rolename="admin-gui"/>
			<role rolename="manager-gui"/>
			<role rolename="manager-script"/>
			<role rolename="manager-jmx"/>
			<role rolename="manager-status"/>
			<user username="$TOM_USER" password="$TOM_PASS" roles="admin-gui,manager-gui,manager-script,manager-jmx,manager-status"/>
		</tomcat-users>
		END
		echo "Tomcat user AND password: $TOM_USER  $TOM_PASS"
	fi
	
	
	#index
	if [ ! -d /usr/local/tomcat/webapps/ROOT ]; then
		\cp -a /mnt/webapps/* /usr/local/tomcat/webapps/
	fi
	
	#http port
	if [ $HTTP_PORT -ne 8080 ];then
		sed -i 's/8080/'$HTTP_PORT'/g' /usr/local/tomcat/conf/server.xml
	fi
	
	#https port
	if [ $HTTP_PORT -ne 8443 ];then
		sed -i 's/8443/'$HTTPS_PORT'/g' /usr/local/tomcat/conf/server.xml
	fi
	
	#JVM Optimization
	SIZE=$(($MAX_MEM/4))
	MSIZE=$(($MAX_MEM/2))
	sed -i '/# OS/ i JAVA_OPTS="-Djava.awt.headless=true -Dfile.encoding=UTF-8 -server -Xms'$MAX_MEM'm -Xmx'$MAX_MEM'm -Xss256k -XX:NewSize='$SIZE'm -XX:MaxNewSize='$MSIZE'm -XX:SurvivorRatio=1 -XX:ParallelGCThreads=8 -XX:-DisableExplicitGC -XX:+UseCompressedOops -XX:+UseConcMarkSweepGC -XX:+CMSParallelRemarkEnabled -XX:-UseGCOverheadLimit -Duser.timezone=Asia/Shanghai"\n' /usr/local/tomcat/bin/catalina.sh   

	#JAVA GW
	if [ $JAVA_GW ]; then
		sed -i '/# OS/ i CATALINA_OPTS="-Dcom.sun.management.jmxremote -Dcom.sun.management.jmxremote.authenticate=false -Dcom.sun.management.jmxremote.ssl=false -Dcom.sun.management.jmxremote.port=12345"\n' /usr/local/tomcat/bin/catalina.sh
		echo -e "iptables -A INPUT -s $JAVA_GW -p tcp -m tcp --dport 12345 -m comment --comment JAVA -j ACCEPT \niptables -A INPUT -p tcp -m tcp --dport 12345 -j DROP" >/iptables.sh
	fi

	#Redis
	if [ $REDIS_SERVER ]; then
		cat >/tomcat-redis.txt <<-END
        	   <Valve className="tomcat.request.session.redis.SessionHandlerValve" />
        	   <Manager className="tomcat.request.session.redis.SessionManager" />
		END

		sed -i '/<Context>/ r /tomcat-redis.txt' /usr/local/tomcat/conf/context.xml
		sed -i 's/=127.0.0.1:6379/='$REDIS_SERVER':'$REDIS_PORT'/' /usr/local/tomcat/conf/redis-data-cache.properties
		if [ $REDIS_DB ]; then sed -i 's/#redis.database=0/redis.database='$REDIS_DB'/' /usr/local/tomcat/conf/redis-data-cache.properties; fi
		if [ $REDIS_PASS ]; then sed -i 's/#redis.password=/redis.password='$REDIS_PASS'/' /usr/local/tomcat/conf/redis-data-cache.properties; fi
	fi

        #Session TTL
        if [ "$SESSION_TTL" -ne 30 ]; then
        	sed -i 's@<session-timeout>30</session-timeout>@<session-timeout>'$SESSION_TTL'</session-timeout>@' /usr/local/tomcat/conf/web.xml
        fi
  fi

	echo "Start ****"
        [ -f /iptables.sh ] && [ -z "`iptables -S |grep JAVA`" ] && . /iptables.sh
	exec "$@"
else

	echo -e "
	Example:
					docker run -d --restart always [--privileged] \\
					-v /docker/webapps:/usr/local/tomcat/webapps \\
					-v /docker/upload:/upload \\
					-p 18080:8080 \\
					-p 18443:8443 \\
					-p 12345:12345 \\
					-e HTTP_PORT=[8080] \\
					-e HTTPS_PORT=[8443] \\
					-e TOM_USER=<admin> \\
					-e TOM_PASS=<redhat> \\
					-e WWW_ROOT=[ROOT] \\
					-e WWW_ALIAS=<"/upload,/upload"> \\
					-e SERVER_NAME=<redhat.xyz,www.redhat.xyz> \\
					-e JAVA_GW=<redhat.xyz> \\
					-e REDIS_SERVER=<redhat.xyz> \\
					-e REDIS_PORT=[6379] \\
					-e REDIS_PASS=<bigpass> \\
					-e REDIS_DB=[0] \\
					-e SESSION_TTL=[30] \\
					-e MAX_MEM=<2048> \\
					--hostname tomcat \\
					--name tomcat tomcat
	"
fi
