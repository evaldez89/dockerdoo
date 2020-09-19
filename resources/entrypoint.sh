#!/bin/bash

set -x

# set the postgres database host, port, user and password according to the environment
# and pass them as arguments to the odoo process if not present in the config file
: ${PGHOST:=${DB_PORT_5432_TCP_ADDR:='db'}}
: ${PGPORT:=${DB_PORT_5432_TCP_PORT:=5432}}
: ${PGUSER:=${DB_ENV_POSTGRES_USER:=${POSTGRES_USER:='odoo'}}}
: ${PGPASSWORD:=${DB_ENV_POSTGRES_PASSWORD:=${POSTGRES_PASSWORD:='odoo'}}}
export PGHOST PGPORT PGUSER PGPASSWORD

# set all variables
function getAddons() {
    EXTRA_ADDONS_PATHS=$(python3 getaddons.py ${ODOO_EXTRA_ADDONS} 2>&1)
    DOMINICANA_ADDONS_PATH=$(python3 getaddons.py ${ODOO_DOMINICANA_BASEPATH} 2>&1)
}

function installRequirements() {
    IFS=',' read -ra ADDR <<< "$1"
    for i in "${ADDR[@]}"; do
        if [ "$PIP_AUTO_INSTALL" -eq "1" ]; then
            find $i -name 'requirements.txt' -exec pip3 install --user -r {} \;
        fi
    done
}

getAddons

ADDONS_PATH=${ODOO_ADDONS_BASEPATH},${DOMINICANA_ADDONS_PATH}

if [ ! -f ${ODOO_RC} ]; then
echo "
[options]
admin_passwd = ${ADMIN_PASSWORD}
data_dir = ${ODOO_DATA_DIR}
db_host = ${DB_PORT_5432_TCP_ADDR}
db_maxconn = ${DB_MAXCONN}
db_password = ${DB_ENV_POSTGRES_PASSWORD}
db_port = ${DB_PORT_5432_TCP_PORT}
db_sslmode = ${DB_SSLMODE}
db_template = ${DB_TEMPLATE}
db_user = ${DB_ENV_POSTGRES_USER}
dbfilter = ${DBFILTER}
http_interface = ${HTTP_INTERFACE}
http_port = ${HTTP_PORT}
limit_request = ${LIMIT_REQUEST}
limit_memory_hard = ${LIMIT_MEMORY_HARD}
limit_memory_soft = ${LIMIT_MEMORY_SOFT}
limit_time_cpu = ${LIMIT_TIME_CPU}
limit_time_real = ${LIMIT_TIME_REAL}
limit_time_real_cron = ${LIMIT_TIME_REAL_CRON}
list_db = ${LIST_DB}
log_db = ${LOG_DB}
log_db_level = ${LOG_DB_LEVEL}
logfile = ${logfile}
log_handler = ${LOG_HANDLER}
log_level = ${LOG_LEVEL}
max_cron_threads = ${MAX_CRON_THREADS}
proxy_mode = ${PROXY_MODE}
server_wide_modules = ${SERVER_WIDE_MODULES}
smtp_password = ${SMTP_PASSWORD}
smtp_port = ${SMTP_PORT}
smtp_server = ${SMTP_SERVER}
smtp_ssl = ${SMTP_SSL}
smtp_user = ${SMTP_USER}
test_enable = ${TEST_ENABLE}
unaccent = ${UNACCENT}
without_demo = ${WITHOUT_DEMO}
workers = ${WORKERS}" > $ODOO_RC
    if [ -z "$EXTRA_ADDONS_PATHS" ]; then
        echo "The variable \$EXTRA_ADDONS_PATHS is empty, using default addons_path"
    else
        ADDONS_PATH+=",${EXTRA_ADDONS_PATHS}"
        installRequirements $ODOO_EXTRA_ADDONS
    fi
    installRequirements $DOMINICANA_ADDONS_PATH
    echo "addons_path = ${ADDONS_PATH}" >> $ODOO_RC
fi

DB_ARGS=()
function check_config() {
    param="$1"
    value="$2"
    if ! grep -q -E "^\s*\b${param}\b\s*=" "$ODOO_RC" ; then
        DB_ARGS+=("--${param}")
        DB_ARGS+=("${value}")
   fi;
}

check_config "db_host" "$PGHOST"
check_config "db_port" "$PGPORT"
check_config "db_user" "$PGUSER"
check_config "db_password" "$PGPASSWORD"

case "$1" in
    -- | odoo | ${ODOO_CMD})
        shift
        if [[ "$1" == "scaffold" ]] ; then
            exec odoo "$@"
        elif [[ "$RUN_TESTS" -eq "1" ]] ; then
            if [ -z "$EXTRA_MODULES" ]; then
                EXTRA_MODULES=$(python3 -c "from getaddons import get_modules; print(','.join(get_modules('${ODOO_EXTRA_ADDONS}', depth=3)))")
            fi
            exec odoo "$@" "--test-enable" "--stop-after-init" "-i" "${EXTRA_MODULES}" "--test-tags" "${EXTRA_MODULES}" "-d" "${TEST_DB:-test}" "${DB_ARGS[@]}"
        else
            exec odoo "$@" "${DB_ARGS[@]}"
        fi
        ;;
    -*)
        exec odoo "$@" "${DB_ARGS[@]}"
        ;;
    *)
        exec "$@"
esac

exit 1
