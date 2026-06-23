-- tarea10/db/init/01_schema.sql
-- Esquema inicial: tabla de usuarios (replica logica de practicas anteriores)

CREATE TABLE IF NOT EXISTS usuarios (
    id          SERIAL PRIMARY KEY,
    nombre      VARCHAR(100) NOT NULL,
    departamento VARCHAR(50) NOT NULL DEFAULT 'General',
    email       VARCHAR(150),
    creado_en   TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO usuarios (nombre, departamento, email) VALUES
    ('cuate01', 'Cuates', 'cuate01@sysadmin.local'),
    ('cuate02', 'Cuates', 'cuate02@sysadmin.local'),
    ('nocuate01', 'No Cuates', 'nocuate01@sysadmin.local'),
    ('admin_identidad', 'AdminDelegados', 'admin_identidad@sysadmin.local');

-- Tabla de metadatos para verificar persistencia (Prueba 10.1)
CREATE TABLE IF NOT EXISTS persistencia_test (
    id          SERIAL PRIMARY KEY,
    mensaje     VARCHAR(255) NOT NULL,
    creado_en   TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO persistencia_test (mensaje) VALUES ('Datos iniciales - volumen db_data');
