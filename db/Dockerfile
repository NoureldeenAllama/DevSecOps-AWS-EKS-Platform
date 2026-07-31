FROM mysql:8.0.33

ENV MYSQL_DATABASE=accounts

COPY db_backup.sql /docker-entrypoint-initdb.d/

EXPOSE 3306