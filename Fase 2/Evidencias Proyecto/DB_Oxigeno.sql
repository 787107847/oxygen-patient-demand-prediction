-- ============================================================
-- PROYECTO APT
-- Sistema predictivo y de planificación logística
-- de oxígeno medicinal domiciliario
--
-- Motor: MySQL 8.x
-- Normalización: Tercera Forma Normal (3FN)
-- ============================================================


-- ============================================================
-- 1. CREACIÓN DE BASE DE DATOS
-- ============================================================

CREATE DATABASE IF NOT EXISTS apt_oxigeno
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_0900_ai_ci;

USE apt_oxigeno;


-- ============================================================
-- 2. TABLAS GEOGRÁFICAS
-- ============================================================

CREATE TABLE region (
    id_region INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    codigo VARCHAR(10) NULL,
    nombre VARCHAR(100) NOT NULL,

    CONSTRAINT uq_region_nombre
        UNIQUE (nombre)
) ENGINE = InnoDB;


CREATE TABLE comuna (
    id_comuna INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    id_region INT UNSIGNED NOT NULL,
    nombre VARCHAR(120) NOT NULL,

    CONSTRAINT fk_comuna_region
        FOREIGN KEY (id_region)
        REFERENCES region(id_region),

    CONSTRAINT uq_comuna_region_nombre
        UNIQUE (id_region, nombre)
) ENGINE = InnoDB;


CREATE TABLE ciudad (
    id_ciudad INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    id_comuna INT UNSIGNED NOT NULL,
    nombre VARCHAR(120) NOT NULL,

    CONSTRAINT fk_ciudad_comuna
        FOREIGN KEY (id_comuna)
        REFERENCES comuna(id_comuna),

    CONSTRAINT uq_ciudad_comuna_nombre
        UNIQUE (id_comuna, nombre)
) ENGINE = InnoDB;


-- ============================================================
-- 3. CATÁLOGO DE SEXO
-- ============================================================

CREATE TABLE sexo (
    id_sexo TINYINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    nombre VARCHAR(30) NOT NULL,

    CONSTRAINT uq_sexo_nombre
        UNIQUE (nombre)
) ENGINE = InnoDB;


INSERT INTO sexo (nombre)
VALUES
    ('FEMENINO'),
    ('MASCULINO'),
    ('NO INFORMADO');


-- ============================================================
-- 4. PACIENTES SEUDONIMIZADOS
-- ============================================================

CREATE TABLE paciente (
    id_paciente BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,

    -- Identificador seudonimizado aleatorio.
    -- Puede utilizarse, por ejemplo, un UUID.
    token_paciente CHAR(36) NOT NULL,

    edad SMALLINT UNSIGNED NULL,
    fecha_referencia_edad DATE NULL,

    id_sexo TINYINT UNSIGNED NULL,
    id_comuna INT UNSIGNED NULL,

    fecha_alta DATE NULL,
    activo BOOLEAN NOT NULL DEFAULT TRUE,

    fecha_creacion DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    fecha_actualizacion DATETIME NOT NULL
        DEFAULT CURRENT_TIMESTAMP
        ON UPDATE CURRENT_TIMESTAMP,

    CONSTRAINT uq_paciente_token
        UNIQUE (token_paciente),

    CONSTRAINT chk_paciente_edad
        CHECK (edad IS NULL OR edad BETWEEN 0 AND 120),

    CONSTRAINT fk_paciente_sexo
        FOREIGN KEY (id_sexo)
        REFERENCES sexo(id_sexo),

    CONSTRAINT fk_paciente_comuna
        FOREIGN KEY (id_comuna)
        REFERENCES comuna(id_comuna)
) ENGINE = InnoDB;


CREATE INDEX idx_paciente_comuna
    ON paciente(id_comuna);

CREATE INDEX idx_paciente_activo
    ON paciente(activo);


-- ============================================================
-- 5. BÓVEDA DE IDENTIDAD
-- ============================================================
--
-- Esta tabla NO debe estar disponible para:
-- - Modelo Machine Learning
-- - Usuarios comunes de aplicación
-- - Servicios analíticos
--
-- Los valores deben ser cifrados ANTES de almacenarse.
-- La clave criptográfica NO debe almacenarse en esta tabla.
-- ============================================================

CREATE TABLE boveda_identidad (
    id_identidad BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,

    id_paciente BIGINT UNSIGNED NOT NULL,

    id_original_cifrado VARBINARY(512) NOT NULL,

    -- Hash/HMAC para permitir búsquedas o detectar duplicados
    -- sin descifrar el identificador original.
    id_original_hash BINARY(32) NOT NULL,

    nombre_cifrado VARBINARY(512) NULL,
    apellido_cifrado VARBINARY(512) NULL,

    telefono_cifrado VARBINARY(512) NULL,
    email_cifrado VARBINARY(512) NULL,

    fecha_creacion DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

    fecha_actualizacion DATETIME NOT NULL
        DEFAULT CURRENT_TIMESTAMP
        ON UPDATE CURRENT_TIMESTAMP,

    CONSTRAINT uq_boveda_paciente
        UNIQUE (id_paciente),

    CONSTRAINT uq_boveda_hash
        UNIQUE (id_original_hash),

    CONSTRAINT fk_boveda_paciente
        FOREIGN KEY (id_paciente)
        REFERENCES paciente(id_paciente)
        ON DELETE RESTRICT
) ENGINE = InnoDB;


-- ============================================================
-- 6. UBICACIÓN DE ENTREGA
-- ============================================================
--
-- Dirección y coordenadas se almacenan cifradas.
-- No se entregan al modelo ML.
-- ============================================================

CREATE TABLE ubicacion_entrega (
    id_ubicacion BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,

    id_paciente BIGINT UNSIGNED NOT NULL,
    id_ciudad INT UNSIGNED NULL,

    direccion_cifrada VARBINARY(1024) NULL,
    latitud_cifrada VARBINARY(255) NULL,
    longitud_cifrada VARBINARY(255) NULL,

    activa BOOLEAN NOT NULL DEFAULT TRUE,

    fecha_creacion DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

    fecha_actualizacion DATETIME NOT NULL
        DEFAULT CURRENT_TIMESTAMP
        ON UPDATE CURRENT_TIMESTAMP,

    CONSTRAINT fk_ubicacion_paciente
        FOREIGN KEY (id_paciente)
        REFERENCES paciente(id_paciente),

    CONSTRAINT fk_ubicacion_ciudad
        FOREIGN KEY (id_ciudad)
        REFERENCES ciudad(id_ciudad)
) ENGINE = InnoDB;


CREATE INDEX idx_ubicacion_paciente
    ON ubicacion_entrega(id_paciente);


-- ============================================================
-- 7. ESTADOS DE RUTA
-- ============================================================

CREATE TABLE estado_ruta (
    id_estado_ruta TINYINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    nombre VARCHAR(50) NOT NULL,
    descripcion VARCHAR(255) NULL,

    CONSTRAINT uq_estado_ruta_nombre
        UNIQUE (nombre)
) ENGINE = InnoDB;


INSERT INTO estado_ruta (nombre, descripcion)
VALUES
    ('PLANIFICADA', 'Ruta generada y pendiente de ejecución'),
    ('EN_PREPARACION', 'Ruta en proceso de preparación'),
    ('EN_CURSO', 'Ruta actualmente en ejecución'),
    ('COMPLETADA', 'Ruta finalizada'),
    ('CANCELADA', 'Ruta cancelada');


-- ============================================================
-- 8. RUTAS
-- ============================================================

CREATE TABLE ruta (
    id_ruta BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,

    fecha_programada DATE NOT NULL,

    id_estado_ruta TINYINT UNSIGNED NOT NULL,

    observacion VARCHAR(500) NULL,

    fecha_creacion DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

    fecha_actualizacion DATETIME NOT NULL
        DEFAULT CURRENT_TIMESTAMP
        ON UPDATE CURRENT_TIMESTAMP,

    CONSTRAINT fk_ruta_estado
        FOREIGN KEY (id_estado_ruta)
        REFERENCES estado_ruta(id_estado_ruta)
) ENGINE = InnoDB;


CREATE INDEX idx_ruta_fecha
    ON ruta(fecha_programada);

CREATE INDEX idx_ruta_estado
    ON ruta(id_estado_ruta);


-- ============================================================
-- 9. HISTORIAL DE ESTADOS DE RUTA
-- ============================================================

CREATE TABLE historial_estado_ruta (
    id_historial_ruta BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,

    id_ruta BIGINT UNSIGNED NOT NULL,

    id_estado_anterior TINYINT UNSIGNED NULL,
    id_estado_nuevo TINYINT UNSIGNED NOT NULL,

    fecha_cambio DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

    usuario_bd VARCHAR(150) NULL,
    observacion VARCHAR(500) NULL,

    CONSTRAINT fk_hist_ruta_ruta
        FOREIGN KEY (id_ruta)
        REFERENCES ruta(id_ruta),

    CONSTRAINT fk_hist_ruta_estado_anterior
        FOREIGN KEY (id_estado_anterior)
        REFERENCES estado_ruta(id_estado_ruta),

    CONSTRAINT fk_hist_ruta_estado_nuevo
        FOREIGN KEY (id_estado_nuevo)
        REFERENCES estado_ruta(id_estado_ruta)
) ENGINE = InnoDB;


CREATE INDEX idx_historial_ruta
    ON historial_estado_ruta(id_ruta, fecha_cambio);


-- ============================================================
-- 10. ESTADOS DE DESPACHO
-- ============================================================

CREATE TABLE estado_despacho (
    id_estado_despacho TINYINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,

    nombre VARCHAR(50) NOT NULL,
    descripcion VARCHAR(255) NULL,

    CONSTRAINT uq_estado_despacho_nombre
        UNIQUE (nombre)
) ENGINE = InnoDB;


INSERT INTO estado_despacho (nombre, descripcion)
VALUES
    ('PLANIFICADO', 'Despacho creado y pendiente de asignación'),
    ('ASIGNADO', 'Despacho asignado a una ruta'),
    ('EN_RUTA', 'Despacho actualmente en ruta'),
    ('ENTREGADO', 'Entrega realizada correctamente'),
    ('CANCELADO', 'Despacho cancelado');


-- ============================================================
-- 11. DESPACHOS
-- ============================================================
--
-- Un paciente puede tener múltiples despachos.
-- Cada despacho pertenece a un único paciente.
--
-- Una ruta puede contener múltiples despachos.
-- Un despacho puede pertenecer como máximo a una ruta.
-- ============================================================

CREATE TABLE despacho (
    id_despacho BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,

    id_paciente BIGINT UNSIGNED NOT NULL,

    -- Puede ser NULL antes de ser asignado.
    id_ruta BIGINT UNSIGNED NULL,

    id_estado_despacho TINYINT UNSIGNED NOT NULL,

    fecha_programada DATETIME NULL,
    fecha_despacho DATETIME NULL,

    cantidad_cilindros SMALLINT UNSIGNED NOT NULL DEFAULT 1,

    -- Primer día del mes administrativo correspondiente.
    -- Ejemplo: 2025-01-01.
    periodo_reporte DATE NULL,

    orden_en_ruta SMALLINT UNSIGNED NULL,

    observacion VARCHAR(500) NULL,

    fecha_creacion DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

    fecha_actualizacion DATETIME NOT NULL
        DEFAULT CURRENT_TIMESTAMP
        ON UPDATE CURRENT_TIMESTAMP,

    CONSTRAINT chk_despacho_cantidad
        CHECK (cantidad_cilindros > 0),

    CONSTRAINT fk_despacho_paciente
        FOREIGN KEY (id_paciente)
        REFERENCES paciente(id_paciente),

    CONSTRAINT fk_despacho_ruta
        FOREIGN KEY (id_ruta)
        REFERENCES ruta(id_ruta),

    CONSTRAINT fk_despacho_estado
        FOREIGN KEY (id_estado_despacho)
        REFERENCES estado_despacho(id_estado_despacho),

    CONSTRAINT uq_ruta_orden
        UNIQUE (id_ruta, orden_en_ruta)
) ENGINE = InnoDB;


CREATE INDEX idx_despacho_paciente_fecha
    ON despacho(id_paciente, fecha_despacho);

CREATE INDEX idx_despacho_ruta
    ON despacho(id_ruta);

CREATE INDEX idx_despacho_estado
    ON despacho(id_estado_despacho);

CREATE INDEX idx_despacho_periodo
    ON despacho(periodo_reporte);


-- ============================================================
-- 12. HISTORIAL DE ESTADO DE DESPACHO
-- ============================================================

CREATE TABLE historial_estado_despacho (
    id_historial BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,

    id_despacho BIGINT UNSIGNED NOT NULL,

    id_estado_anterior TINYINT UNSIGNED NULL,
    id_estado_nuevo TINYINT UNSIGNED NOT NULL,

    fecha_cambio DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

    usuario_bd VARCHAR(150) NULL,
    observacion VARCHAR(500) NULL,

    CONSTRAINT fk_hist_despacho
        FOREIGN KEY (id_despacho)
        REFERENCES despacho(id_despacho),

    CONSTRAINT fk_hist_despacho_estado_anterior
        FOREIGN KEY (id_estado_anterior)
        REFERENCES estado_despacho(id_estado_despacho),

    CONSTRAINT fk_hist_despacho_estado_nuevo
        FOREIGN KEY (id_estado_nuevo)
        REFERENCES estado_despacho(id_estado_despacho)
) ENGINE = InnoDB;


CREATE INDEX idx_historial_despacho
    ON historial_estado_despacho(id_despacho, fecha_cambio);


-- ============================================================
-- 13. MODELOS DE MACHINE LEARNING
-- ============================================================

CREATE TABLE modelo_ml (
    id_modelo INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,

    nombre VARCHAR(150) NOT NULL,
    version VARCHAR(50) NOT NULL,

    descripcion VARCHAR(500) NULL,

    fecha_entrenamiento DATETIME NULL,
    fecha_activacion DATETIME NULL,

    activo BOOLEAN NOT NULL DEFAULT FALSE,

    fecha_creacion DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT uq_modelo_version
        UNIQUE (nombre, version)
) ENGINE = InnoDB;


-- ============================================================
-- 14. MÉTRICAS DE LOS MODELOS
-- ============================================================

CREATE TABLE metrica_modelo (
    id_metrica BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,

    id_modelo INT UNSIGNED NOT NULL,

    nombre_metrica VARCHAR(100) NOT NULL,
    valor DECIMAL(15,6) NOT NULL,

    conjunto_evaluacion VARCHAR(50) NOT NULL,

    fecha_registro DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_metrica_modelo
        FOREIGN KEY (id_modelo)
        REFERENCES modelo_ml(id_modelo),

    CONSTRAINT uq_modelo_metrica_conjunto
        UNIQUE (
            id_modelo,
            nombre_metrica,
            conjunto_evaluacion
        )
) ENGINE = InnoDB;


-- ============================================================
-- 15. PREDICCIONES
-- ============================================================
--
-- Las predicciones no se sobrescriben.
-- Cada nueva ejecución genera un nuevo registro.
-- ============================================================

CREATE TABLE prediccion (
    id_prediccion BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,

    id_paciente BIGINT UNSIGNED NOT NULL,
    id_modelo INT UNSIGNED NOT NULL,

    fecha_generacion DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

    fecha_proxima_solicitud_estimada DATE NULL,
    dias_estimados SMALLINT UNSIGNED NULL,

    cantidad_cilindros_estimada SMALLINT UNSIGNED NULL,

    CONSTRAINT fk_prediccion_paciente
        FOREIGN KEY (id_paciente)
        REFERENCES paciente(id_paciente),

    CONSTRAINT fk_prediccion_modelo
        FOREIGN KEY (id_modelo)
        REFERENCES modelo_ml(id_modelo)
) ENGINE = InnoDB;


CREATE INDEX idx_prediccion_paciente_fecha
    ON prediccion(id_paciente, fecha_generacion);

CREATE INDEX idx_prediccion_modelo
    ON prediccion(id_modelo);


-- ============================================================
-- 16. AUDITORÍA GENERAL
-- ============================================================
--
-- No almacena datos sensibles.
-- Registra acciones realizadas sobre el sistema.
-- ============================================================

CREATE TABLE auditoria_evento (
    id_auditoria BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,

    fecha_evento DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

    usuario_bd VARCHAR(150) NOT NULL,

    accion VARCHAR(50) NOT NULL,

    entidad VARCHAR(100) NOT NULL,

    id_registro VARCHAR(100) NULL,

    ip_origen VARCHAR(45) NULL,

    descripcion VARCHAR(500) NULL
) ENGINE = InnoDB;


CREATE INDEX idx_auditoria_fecha
    ON auditoria_evento(fecha_evento);

CREATE INDEX idx_auditoria_entidad
    ON auditoria_evento(entidad);


-- ============================================================
-- 17. VISTAS PARA MACHINE LEARNING
-- ============================================================
--
-- Estas vistas no contienen información de identidad
-- ni ubicación exacta.
-- ============================================================

CREATE OR REPLACE VIEW vw_ml_pacientes AS
SELECT
    p.token_paciente,
    p.edad,
    s.nombre AS sexo,
    c.nombre AS comuna,
    r.nombre AS region,
    p.activo
FROM paciente p
LEFT JOIN sexo s
    ON p.id_sexo = s.id_sexo
LEFT JOIN comuna c
    ON p.id_comuna = c.id_comuna
LEFT JOIN region r
    ON c.id_region = r.id_region;


CREATE OR REPLACE VIEW vw_ml_despachos AS
SELECT
    p.token_paciente,
    d.fecha_despacho,
    d.cantidad_cilindros,
    d.periodo_reporte
FROM despacho d
INNER JOIN paciente p
    ON d.id_paciente = p.id_paciente
WHERE d.fecha_despacho IS NOT NULL;


CREATE OR REPLACE VIEW vw_ml_predicciones AS
SELECT
    p.token_paciente,
    m.nombre AS modelo,
    m.version,
    pr.fecha_generacion,
    pr.fecha_proxima_solicitud_estimada,
    pr.dias_estimados,
    pr.cantidad_cilindros_estimada
FROM prediccion pr
INNER JOIN paciente p
    ON pr.id_paciente = p.id_paciente
INNER JOIN modelo_ml m
    ON pr.id_modelo = m.id_modelo;


-- ============================================================
-- 18. TRIGGERS DE HISTORIAL DE RUTA
-- ============================================================

DELIMITER $$


CREATE TRIGGER trg_ruta_historial_insert
AFTER INSERT ON ruta
FOR EACH ROW
BEGIN

    INSERT INTO historial_estado_ruta (
        id_ruta,
        id_estado_anterior,
        id_estado_nuevo,
        fecha_cambio,
        usuario_bd
    )
    VALUES (
        NEW.id_ruta,
        NULL,
        NEW.id_estado_ruta,
        CURRENT_TIMESTAMP,
        CURRENT_USER()
    );

END$$


CREATE TRIGGER trg_ruta_historial_update
AFTER UPDATE ON ruta
FOR EACH ROW
BEGIN

    IF NOT (OLD.id_estado_ruta <=> NEW.id_estado_ruta) THEN

        INSERT INTO historial_estado_ruta (
            id_ruta,
            id_estado_anterior,
            id_estado_nuevo,
            fecha_cambio,
            usuario_bd
        )
        VALUES (
            NEW.id_ruta,
            OLD.id_estado_ruta,
            NEW.id_estado_ruta,
            CURRENT_TIMESTAMP,
            CURRENT_USER()
        );

    END IF;

END$$


-- ============================================================
-- 19. TRIGGERS DE HISTORIAL DE DESPACHO
-- ============================================================

CREATE TRIGGER trg_despacho_historial_insert
AFTER INSERT ON despacho
FOR EACH ROW
BEGIN

    INSERT INTO historial_estado_despacho (
        id_despacho,
        id_estado_anterior,
        id_estado_nuevo,
        fecha_cambio,
        usuario_bd
    )
    VALUES (
        NEW.id_despacho,
        NULL,
        NEW.id_estado_despacho,
        CURRENT_TIMESTAMP,
        CURRENT_USER()
    );

END$$


CREATE TRIGGER trg_despacho_historial_update
AFTER UPDATE ON despacho
FOR EACH ROW
BEGIN

    IF NOT (
        OLD.id_estado_despacho
        <=>
        NEW.id_estado_despacho
    ) THEN

        INSERT INTO historial_estado_despacho (
            id_despacho,
            id_estado_anterior,
            id_estado_nuevo,
            fecha_cambio,
            usuario_bd
        )
        VALUES (
            NEW.id_despacho,
            OLD.id_estado_despacho,
            NEW.id_estado_despacho,
            CURRENT_TIMESTAMP,
            CURRENT_USER()
        );

    END IF;

END$$


DELIMITER ;


-- ============================================================
-- FIN DE CREACIÓN DE ESTRUCTURA
-- ============================================================