#!/bin/sh
#
# mysql backup script
#
{{ if .Values.debug }}
set -ex
{{ end }}

{{ if .Values.mysql.host }}

BACKUP_DIR="/backup"
TIMESTAMP="$(date +%Y%m%d%H%M%S)"

echo "test mysql connection"
if [ -z "$(mysql -h ${MYSQL_HOST} -P ${MYSQL_PORT} -u ${MYSQL_USERNAME} -B -N -e 'SHOW DATABASES;')" ]; then
  echo "mysql connection failed! exiting..."
  exit 1
fi

echo "started" > ${BACKUP_DIR}/${TIMESTAMP}.state

{{ if or (.Values.persistence.enabled) (.Values.persistentVolumeClaim) }}
{{ if .Values.housekeeping.enabled }}
echo "delete old backups"
find ${BACKUP_DIR} -maxdepth 2 -mtime +${KEEP_DAYS} -regex "^${BACKUP_DIR}/.*[0-9]*_.*\.sql\.gz$" -type f -exec rm {} \;
{{ end -}}
{{ end -}}

{{ if and (.Values.mysql.db) (eq .Values.allDatabases.enabled false) }}
MYSQL_DB="{{ .Values.mysql.db }}"
echo "Backing up single db ${MYSQL_DB}"
{{ if .Values.saveToDirectory }}mkdir -p "${BACKUP_DIR}"/"${MYSQL_DB}"{{ end }}
mysqldump ${MYSQL_OPTS} -h ${MYSQL_HOST} -P ${MYSQL_PORT} -u ${MYSQL_USERNAME} --databases ${MYSQL_DB} | gzip > ${BACKUP_DIR}/{{ if .Values.saveToDirectory }}${MYSQL_DB}/{{ end }}${TIMESTAMP}_${MYSQL_DB}.sql.gz
rc=$?
{{ else if and (.Values.allDatabases.enabled) (eq .Values.allDatabases.singleBackupFile false)}}
for MYSQL_DB in $(mysql -h "${MYSQL_HOST}" -P ${MYSQL_PORT} -u ${MYSQL_USERNAME} -B -N -e "SHOW DATABASES;"|egrep -v '^(information|performance)_schema$'); do
  echo "Backing up db ${MYSQL_DB}"
  {{ if .Values.saveToDirectory }}mkdir -p "${BACKUP_DIR}"/"${MYSQL_DB}"{{ end }}
  mysqldump ${MYSQL_OPTS} -h ${MYSQL_HOST} -P ${MYSQL_PORT} -u ${MYSQL_USERNAME} --databases ${MYSQL_DB} | gzip > ${BACKUP_DIR}/{{ if .Values.saveToDirectory }}${MYSQL_DB}/{{ end }}${TIMESTAMP}_${MYSQL_DB}.sql.gz
  rc=$?
done

{{ else if and (.Values.allDatabases.enabled) (.Values.allDatabases.singleBackupFile) }}
echo "Backing up all databases"
MYSQL_DB="alldatabases"
{{ if .Values.saveToDirectory }}mkdir -p "${BACKUP_DIR}"/"${MYSQL_DB}"{{ end }}
mysqldump ${MYSQL_OPTS} -h ${MYSQL_HOST} -P ${MYSQL_PORT} -u ${MYSQL_USERNAME} --all-databases | gzip > ${BACKUP_DIR}/{{ if .Values.saveToDirectory }}${MYSQL_DB}/{{ end }}${TIMESTAMP}_${MYSQL_DB}.sql.gz
rc=$?
{{- end -}}

{{ if .Values.dumpAllToStdout }}
mysqldump ${MYSQL_OPTS} -h ${MYSQL_HOST} -P ${MYSQL_PORT} -u ${MYSQL_USERNAME} --all-databases
rc=$?
{{ end }}

{{ if .Values.debug }}
  echo Contents of ${BACKUP_DIR}
  ls -lahR ${BACKUP_DIR}
{{ end }}

if [ "$rc" != "0" ]; then
  echo "backup failed"
  exit 1
fi

{{ if .Values.additionalSteps }}
  {{- range .Values.additionalSteps }}
  {{ . }}
  {{- end }}
{{- end }}

echo "complete" > ${BACKUP_DIR}/${TIMESTAMP}.state

echo "Disk usage in ${BACKUP_DIR}"
du -h -d 2 ${BACKUP_DIR}

echo "Backup successful! :-)"
{{ else }}
echo "no mysql.host set in values file... nothing to do... exiting :)"
{{ end }}