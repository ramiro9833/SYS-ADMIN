-- tarea11/db/init/01_schema.sql
-- Esquema inicial para validar persistencia (Prueba 11.4)

CREATE TABLE IF NOT EXISTS microservicios (
    id          SERIAL PRIMARY KEY,
    servicio    VARCHAR(100) NOT NULL,
    capa        VARCHAR(50) NOT NULL,
    creado_en   TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO microservicios (servicio, capa) VALUES
    ('nginx', 'publica'),
    ('web_app', 'logica'),
    ('postgresql', 'datos'),
    ('pgadmin', 'gestion');

CREATE TABLE IF NOT EXISTS persistencia_t11 (
    id          SERIAL PRIMARY KEY,
    mensaje     VARCHAR(255) NOT NULL,
    creado_en   TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO persistencia_t11 (mensaje) VALUES ('Datos iniciales - volumen tarea11_db_data');
