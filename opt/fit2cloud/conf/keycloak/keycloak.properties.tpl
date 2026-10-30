DB_VENDOR=mysql
DB_ADDR={{ .CE_MYSQL_HOST | default "mysql" }}
DB_PORT={{ .CE_MYSQL_PORT | default "3306" }}
DB_DATABASE={{ .CE_KEYCLOAK_DB | default "keycloak" }}
DB_USER={{ .CE_MYSQL_USER | default "root" }}
DB_PASSWORD={{ .CE_MYSQL_PASSWORD | default "Password123@mysql" }}

KEYCLOAK_USER={{ .CE_ADMIN_USERNAME | default "admin" }}
KEYCLOAK_PASSWORD={{ .CE_KEYCLOAK_PASSWORD | default "Password123@keycloak" }}

PROXY_ADDRESS_FORWARDING=true

JAVA_OPTS_APPEND=-Xms512m -Xmx2048m -XX:MetaspaceSize=512M -XX:MaxMetaspaceSize=512m -Djboss.as.management.blocking.timeout=1800 -Dquarkus.transaction-manager.default-transaction-timeout=1800

CONFIG_FILE=/opt/fit2cloud/conf/fit2cloud.properties
