#CMP DB configs
rdb.driver={{ .CE_MYSQL_DRIVER | default "com.mysql.cj.jdbc.Driver" }}
rdb.url=jdbc:mysql://{{ .CE_MYSQL_HOST | default "mysql" }}:{{ .CE_MYSQL_PORT | default 3306 }}/{{ .CE_MYSQL_DB | default "fit2cloud" }}?{{ .CE_MYSQL_PARAMS | default "autoReconnect=false&useUnicode=true&characterEncoding=UTF-8&characterSetResults=UTF-8&zeroDateTimeBehavior=CONVERT_TO_NULL&useSSL=false&nullCatalogMeansCurrent=true" }}
rdb.user={{ .CE_MYSQL_USER | default "root"}}
rdb.password={{ .CE_MYSQL_PASSWORD | default "U2FsdGVkX18JHB5ZNHZLFcHJT0XU7AxiNxC1FcV4tu+D8Bp2EswsCAqEMV4p58Lc" }}

#KeyCloak Optional DB configs
optional.rdb.driver={{ .CE_MYSQL_DRIVER | default "com.mysql.cj.jdbc.Driver" }}
optional.rdb.url=jdbc:mysql://{{ .CE_MYSQL_HOST | default "mysql" }}:{{ .CE_MYSQL_PORT | default 3306 }}/{{ .CE_KEYCLOAK_DB | default "keycloak" }}?{{ .CE_KEYCLOAK_PARAMS | default "autoReconnect=false&useUnicode=true&characterEncoding=UTF-8&characterSetResults=UTF-8&zeroDateTimeBehavior=CONVERT_TO_NULL&useSSL=false" }}
optional.rdb.user={{ .CE_MYSQL_USER | default "root"}}
optional.rdb.password={{ .CE_MYSQL_PASSWORD | default "U2FsdGVkX1+sRw3sIGDDMZdi+ZGbbEwipLiqmPhJOMAXD1oWLYwB2J+bZJTUBWVZ" }}

#Activiti
spring.datasource.url=jdbc:mysql://{{ .CE_MYSQL_HOST | default "mysql" }}:{{ .CE_MYSQL_PORT | default 3306 }}/{{ .CE_ACTIVITI_DB | default "activiti" }}?{{ .CE_ACTIVITI_PARAMS | default "autoReconnect=false&useUnicode=true&characterEncoding=UTF-8&characterSetResults=UTF-8&zeroDateTimeBehavior=CONVERT_TO_NULL&useSSL=false" }}
spring.datasource.username={{ .CE_MYSQL_USER | default "root"}}
spring.datasource.password={{ .CE_MYSQL_PASSWORD | default "U2FsdGVkX190n01l5Ko1gDFvGSglhNu0k8bwDRlyWVT/fLJ7xN9Jqo8TZkFOPPc0" }}
spring.datasource.driver-class-name={{ .CE_MYSQL_DRIVER | default "com.mysql.cj.jdbc.Driver" }}
spring.activiti.check-process-definitions=false
spring.activiti.history-level=full

#Redis
{{- $redis_mode := default "single" .CE_REDIS_MODE }}
{{- if eq $redis_mode "single" }}
redis.hostname={{ .CE_REDIS_HOST | default "redis" }}
redis.password={{ .CE_REDIS_PASSWORD | default "U2FsdGVkX18FExvjGK16G7Bu9tnwwjtgsx/BlVMPww/YjouBKeBkhSFzuADH3Vyd" }}
redis.port={{ .CE_REDIS_PORT | default 6379 }}
redis.database={{ .CE_REDIS_DATABASE | default 0 }}
{{- end }}
{{- if eq $redis_mode "cluster" }}
redis.cluster.enabled=true
redis.cluster.nodes={{ .CE_REDIS_HOST | required }}
redis.password={{ .CE_REDIS_PASSWORD | required }}
{{- end }}
{{- if eq $redis_mode "sentinel" }}
redis.sentinel.nodes={{ .CE_REDIS_HOST | required }}
redis.password={{ .CE_REDIS_PASSWORD | required }}
redis.database={{ .CE_REDIS_DATABASE | required }}
{{- end }}

#InfluxDB
spring.influx.url={{ .CE_INFLUXDB_URL | default "http://influxdb:8086" }}
spring.influx.password={{ .CE_INFLUXDB_PASSWORD | default "U2FsdGVkX18Au7ObDKEQdG05o3VEvYDPFrCsI1ZEsCB/dN4T8J8Bc3qdr61z8bhO" }}
spring.influx.user={{ .CE_INFLUXDB_USER | default "fit2cloud" }}
spring.influx.database={{ .CE_INFLUXDB_DATABASE | default "fit2cloud" }}
spring.influx.log.database={{ .CE_INFLUXDB_LOG_DATABASE | default "log_fit2cloud" }}

#KeyCloak
keycloak-server-address={{ .CE_KEYCLOAK_URL | default "http://keycloak:8080/auth" }}
keycloak.auth-server-url=/auth/
keycloak.realm=cmp
keycloak.public-client=true
keycloak.resource=cmp-client

# RabbitMQ
{{- $mq_mode := default "single" .CE_RABBITMQ_MODE }}
{{- if eq $mq_mode "single" }}
spring.rabbitmq.host={{ .CE_RABBITMQ_HOST | default "rabbitmq" }}
spring.rabbitmq.port={{ .CE_RABBITMQ_PORT | default 5672 }}
{{- end }}
{{- if eq $mq_mode "cluster" }}
spring.rabbitmq.addresses={{ .CE_RABBITMQ_HOST | required }}
{{- end }}
spring.rabbitmq.username={{ .CE_RABBITMQ_USER | default "fit2cloud" }}
spring.rabbitmq.password={{ .CE_RABBITMQ_PASSWORD | default "U2FsdGVkX19BmEFPkpUJa4knZvJtTdIbcw/JbPnhOts41JQBYxeP7JghLL9CI2nu" }}
spring.amqp.deserialization-trust-all=true
spring.rabbitmq.listener.simple.retry.enabled=true
spring.rabbitmq.listener.simple.retry.max-attempts=5
spring.rabbitmq.listener.simple.retry.initial-interval=5000ms
spring.rabbitmq.listener.simple.retry.max-interval=120000ms
spring.rabbitmq.listener.simple.retry.multiplier=2

#Ansible
ansible.host={{ .CE_ANSIBLE_HOST | default "http://ansible:8000" }}
ansible.version=v1
ansible.username={{ .CE_ANSIBLE_USER | default "root" }}
ansible.password={{ .CE_ANSIBLE_PASSWORD | default "U2FsdGVkX18lR+gfF3z0nHeV7F7yKwWDBep3f1CvlA0=" }}

#Management node download path
ansible.temp.path=/tmp/apps/
#Target node download path
ansible.temp.target.path=/tmp/apps/
ansible.database.type={{ .CE_ANSIBLE_DATABASE_TYPE | default "mysql" }}
ansible.database.host={{ .CE_ANSIBLE_DATABASE_HOST | default "mysql" }}
ansible.database.port={{ .CE_ANSIBLE_DATABASE_PORT | default "3306" }}
ansible.database.user={{ .CE_ANSIBLE_DATABASE_USER | default "root" }}
ansible.database.password={{ .CE_ANSIBLE_DATABASE_PASSWORD | default "U2FsdGVkX18JHB5ZNHZLFcHJT0XU7AxiNxC1FcV4tu+D8Bp2EswsCAqEMV4p58Lc" }}

ansible.redis.host={{ .CE_ANSIBLE_REDIS_HOST | default "redis" }}
ansible.redis.password={{ .CE_ANSIBLE_REDIS_PASSWORD | default "U2FsdGVkX18FExvjGK16G7Bu9tnwwjtgsx/BlVMPww/YjouBKeBkhSFzuADH3Vyd" }}
ansible.redis.port={{ .CE_ANSIBLE_REDIS_PORT | default 6379 }}

#Log
#DEBUG, INFO, WARN, ERROR
logger.level={{ .CE_LOGGER_LEVEL | default "INFO" }}
#Retention days
fit2cloud.log.max.history={{ .CE_LOGGER_RETENTION_DAYS | default 30 }}
#Maximum log file capacity limit, in GB
fit2cloud.log.total.size.cap={{ .CE_LOGGER_MAX_CAPACITY_LIMIT | default 2 }}
#The maximum size allowed for each log file, in MB
fit2cloud.log.max.file.size={{ .CE_LOGGER_LOG_LIMIT | default 50 }}

#eureka
{{- if eq .CE_MODE "standalone" }}
eureka.client.service-url.defaultZone=http://management-center:{{ .MANAGEMENT_PORT | default 6602 }}/eureka/
{{- end }}
{{- if eq .CE_MODE "ha" }}
{{- $servers := required .EUREKA_SERVERS }}
eureka.client.service-url.defaultZone={{ range $i, $ip := split $servers "," }}{{ if $i }},{{ end }}http://{{ $ip }}:{{ $.MANAGEMENT_PORT | default 6602 }}/eureka/{{ end }}
{{- end }}

#Encryption
security.password={{ .CE_SECURITY_PASSWORD | default true }}

#DevOps
devops.worker.address={{ .CE_DEVOPS_WORKER_ADDRESS | default "http://devops-worker:5919/" }}
orchestrateWorkExecute={{ .CE_ORCHESTRATE_WORK_EXECUTE | default "http://orchestrator-service:6001/orchestrator/" }}

#chronograf
chronograf.url={{ .CE_CHRONOGRAF_URL | default "http://chronograf:8211" }}

#Upload
file.upload.path={{ .CE_FILE_UPLOAD_PATH | default "/opt/fit2cloud/sftp/sftpuser/upload" }}
upload.file.postfix=tar.gz,tar.bz2

maven.setting.path=/usr/lib/mvn/conf/settings.xml


# actuator disable all endpoints, enable only health and info
management.endpoints.enabled-by-default=false
management.endpoint.health.enabled=true
management.endpoint.info.enabled=true


# Synchronize cloud accounts every two hours
sync.cloud.account=0 0 0/2 * * ?
