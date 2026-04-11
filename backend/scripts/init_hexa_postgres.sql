-- One-time setup: creates role + database matching docker-compose.yml and backend/.env
--
-- Run as superuser, e.g. (PowerShell, PostgreSQL 18):
--   $env:PGPASSWORD = "<postgres-superuser-password>"
--   & "C:\Program Files\PostgreSQL\18\bin\psql.exe" -h localhost -U postgres -d postgres -f "C:\Users\anand\OneDrive\Desktop\Purchase Assistant\backend\scripts\init_hexa_postgres.sql"
--
-- If "role hexa already exists", you can instead run only:
--   ALTER ROLE hexa WITH LOGIN PASSWORD 'hexa';

CREATE ROLE hexa WITH LOGIN PASSWORD 'hexa';
CREATE DATABASE hexa OWNER hexa;
