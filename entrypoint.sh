MY=(
    [ROLE]=db
    [RUN_AS]=self

    [DB_DIR]="${DB_DIR:-/var/lib/postgresql/data}"
    [POSTGRES_INITDB_ARGS]="${POSTGRES_INITDB_ARGS:-}"
    [POSTGRES_INITDB_XLOGDIR]="${POSTGRES_INITDB_XLOGDIR:-}"

    [DB_NAME]="${DB_NAME:-postgres}"
    [DB_USER]="${DB_USER:-postgres}"
    [DB_PASS]="${DB_PASS:-}"
)

passthrough_unless 'postgres' "$@"

export PGDATA="${MY[DB_DIR]}" LANG=en_US.UTF-8
export PATH="${PATH}:/usr/lib/postgresql/11/bin"
export RUNDIR=/run/postgresql

! am_root || {
    chown -R postgres:postgres "${PGDATA}" "${RUNDIR}"
    [[ -z "${MY[POSTGRES_INITDB_XLOGDIR]}" ]] || {
        mkdir -p "${MY[POSTGRES_INITDB_XLOGDIR]}"
        chown -R postgres:postgres "${MY[POSTGRES_INITDB_XLOGDIR]}"
        chmod 700 "${MY[POSTGRES_INITDB_XLOGDIR]}"
    }
}

chmod 700 "${PGDATA}"
chmod g+s "${RUNDIR}"

[[ -s "${PGDATA}/PG_VERSION" ]] || {
    [[ -z "${MY[POSTGRES_INITDB_XLOGDIR]}" ]] || {
        MY[POSTGRES_INITDB_ARGS]+=" --xlogdir ${MY[POSTGRES_INITDB_XLOGDIR]}"
    }

    carefully initdb --username="${MY[DB_USER]}" ${MY[POSTGRES_INITDB_ARGS]}
    carefully echo "host all all 0.0.0.0/0 md5" >> "${PGDATA}/pg_hba.conf"

    random_if_empty DB_PASS

    export PGUSER="${MY[DB_USER]}"
    export PGPASSWORD="${MY[DB_PASS]}"

    carefully pg_ctl -D "${PGDATA}" -o "-c listen_addresses='localhost'" -w start

    psql=( carefully psql -v ON_ERROR_STOP=1 --username "${MY[DB_USER]}" --no-password )
    [[ "${MY[DB_NAME]}" = 'postgres' ]] || {
        "${psql[@]}" --dbname postgres --set db="${MY[DB_NAME]}" <<<'CREATE DATABASE :"db" ;'
    }

    psql+=( --dbname "${MY[DB_NAME]}" )
    op="$([[ "${MY[DB_USER]}" = 'postgres' ]] && echo ALTER || echo CREATE)"

    "${psql[@]}" <<<"${op} USER \"${MY[DB_USER]}\" WITH SUPERUSER PASSWORD '${MY[DB_PASS]}';"
    carefully pg_ctl -D "${PGDATA}" -m fast -w stop
    echo 'PostgreSQL init process complete; ready for start up.'
}

run "$@"
