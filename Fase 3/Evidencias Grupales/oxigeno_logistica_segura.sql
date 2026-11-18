-- =====================================================================
-- PROYECTO APT
-- SISTEMA PREDICTIVO Y DE PLANIFICACION LOGISTICA PARA OXIGENO MEDICINAL
-- ESQUEMA SEGURO V2 - XAMPP / MariaDB
-- =====================================================================
--
-- IMPORTANTE
-- ----------
-- Este script RECREA la base de datos desde cero.
-- NO contiene passwords, API keys, claves AES ni peppers embebidos.
--
-- Seguridad esperada en el backend:
--   * Passwords: Argon2id/bcrypt -> solo se persiste password_hash.
--   * Identificador fuente: HMAC-SHA256 con pepper en .env -> solo se
--     persiste identificador_hash.
--   * Nombre/contacto/direccion/coordenadas: cifrado autenticado
--     (p.ej. AES-256-GCM) en el backend -> la BD guarda ciphertext.
--   * Token anonimo: UUID aleatorio generado por el backend.
--   * Google Maps API key y claves de cifrado: exclusivamente en .env.
--
-- ZONAS LOGICAS
-- -------------
-- ZONA 1: boveda_identidad
--   Contiene el vinculo entre identidad cifrada/hash y token anonimo.
--
-- ZONA 2: paciente_analitico + despachos + predicciones + rutas
--   Nunca almacena identificador real, nombre, contacto ni direccion.
--
-- NO EXISTE FK FISICA entre paciente_analitico y boveda_identidad.
-- Es deliberado: al eliminar la boveda del paciente se rompe de forma
-- efectiva el vinculo reidentificable, conservando los datos analiticos.
-- =====================================================================


DROP DATABASE IF EXISTS oxigeno_logistica;

CREATE DATABASE oxigeno_logistica
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;

USE oxigeno_logistica;


-- =====================================================================
-- 1. USUARIOS DE LA APLICACION WEB
-- =====================================================================

CREATE TABLE usuario_app (
    id_usuario BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,

    username VARCHAR(80) NOT NULL,
    email_hash CHAR(64) NULL,

    -- El hash se calcula en Python (Argon2id/bcrypt).
    -- Nunca almacenar passwords en texto plano.
    password_hash VARCHAR(255) NOT NULL,

    rol VARCHAR(20) NOT NULL DEFAULT 'OPERADOR',
    activo BOOLEAN NOT NULL DEFAULT TRUE,

    intentos_fallidos SMALLINT UNSIGNED NOT NULL DEFAULT 0,
    bloqueado_hasta DATETIME NULL,

    ultimo_login DATETIME NULL,
    password_changed_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
        ON UPDATE CURRENT_TIMESTAMP,

    CONSTRAINT uk_usuario_username UNIQUE (username),
    CONSTRAINT uk_usuario_email_hash UNIQUE (email_hash),

    INDEX idx_usuario_activo (activo)
) ENGINE=InnoDB;


-- =====================================================================
-- 2. ZONA 1 - BOVEDA DE IDENTIDAD
-- =====================================================================
--
-- token_anonimo es la unica llave logica que permite relacionar
-- temporalmente identidad y zona analitica.
--
-- identificador_hash:
--   HMAC-SHA256 del identificador fuente calculado por backend.
--
-- *_enc:
--   Ciphertext generado por backend.
--   La BD NO contiene las claves de cifrado.
--
-- ubicacion_enc:
--   Puede contener JSON cifrado con:
--     direccion
--     latitud
--     longitud
--     precision_geocodificacion
--
-- =====================================================================

CREATE TABLE boveda_identidad (
    id_boveda BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,

    token_anonimo CHAR(36) NOT NULL,
    identificador_hash CHAR(64) NOT NULL,

    nombre_enc LONGBLOB NULL,
    apellido_enc LONGBLOB NULL,
    contacto_enc LONGBLOB NULL,
    direccion_enc LONGBLOB NULL,
    ubicacion_enc LONGBLOB NULL,

    key_version SMALLINT UNSIGNED NOT NULL DEFAULT 1,

    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
        ON UPDATE CURRENT_TIMESTAMP,

    CONSTRAINT uk_boveda_token UNIQUE (token_anonimo),
    CONSTRAINT uk_boveda_identificador_hash UNIQUE (identificador_hash),

    INDEX idx_boveda_token (token_anonimo)
) ENGINE=InnoDB;


-- =====================================================================
-- 3. ZONA 2 - PACIENTE ANALITICO / SEUDONIMIZADO
-- =====================================================================

CREATE TABLE paciente_analitico (
    token_anonimo CHAR(36) PRIMARY KEY,

    edad TINYINT UNSIGNED NULL,
    sexo VARCHAR(20) NULL,
    comuna VARCHAR(100) NULL,

    -- Datos de soporte para seleccionar estrategia predictiva.
    meses_historial SMALLINT UNSIGNED NOT NULL DEFAULT 0,
    n_despachos INT UNSIGNED NOT NULL DEFAULT 0,

    -- Indica si aun existe entrada en boveda.
    -- NO reidentifica por si solo.
    identidad_disponible BOOLEAN NOT NULL DEFAULT TRUE,

    activo BOOLEAN NOT NULL DEFAULT TRUE,

    fuente_inicial VARCHAR(20) NOT NULL DEFAULT 'COLD_START',

    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
        ON UPDATE CURRENT_TIMESTAMP,

    INDEX idx_paciente_comuna (comuna),
    INDEX idx_paciente_activo (activo),
    INDEX idx_paciente_fuente (fuente_inicial)
) ENGINE=InnoDB;


-- =====================================================================
-- 4. DESPACHOS HISTORICOS
-- =====================================================================

CREATE TABLE despacho (
    id_despacho BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,

    token_anonimo CHAR(36) NOT NULL,

    fecha DATE NOT NULL,
    cantidad_cilindros SMALLINT UNSIGNED NOT NULL,

    mes_reporte VARCHAR(10) NULL,

    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_despacho_paciente
        FOREIGN KEY (token_anonimo)
        REFERENCES paciente_analitico(token_anonimo)
        ON DELETE RESTRICT
        ON UPDATE CASCADE,

    INDEX idx_despacho_token_fecha (token_anonimo, fecha)
) ENGINE=InnoDB;


-- =====================================================================
-- 5. REGISTRO DE MODELOS ML
-- =====================================================================

CREATE TABLE modelo_ml (
    id_modelo BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,

    nombre VARCHAR(100) NOT NULL,
    tipo VARCHAR(30) NOT NULL,
    version VARCHAR(50) NOT NULL,

    artifact_hash_sha256 CHAR(64) NULL,

    activo BOOLEAN NOT NULL DEFAULT TRUE,

    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT uk_modelo_version UNIQUE (nombre, version),

    INDEX idx_modelo_tipo_activo (tipo, activo)
) ENGINE=InnoDB;


CREATE TABLE metrica_modelo (
    id_metrica BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,

    id_modelo BIGINT UNSIGNED NOT NULL,

    nombre_metrica VARCHAR(50) NOT NULL,
    valor DECIMAL(14,6) NOT NULL,
    particion VARCHAR(30) NULL,

    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_metrica_modelo
        FOREIGN KEY (id_modelo)
        REFERENCES modelo_ml(id_modelo)
        ON DELETE CASCADE,

    INDEX idx_metrica_modelo (id_modelo)
) ENGINE=InnoDB;


-- =====================================================================
-- 6. PREDICCIONES
-- =====================================================================

CREATE TABLE prediccion (
    id_prediccion BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,

    token_anonimo CHAR(36) NOT NULL,

    estrategia_cantidad VARCHAR(20) NOT NULL,
    estrategia_fecha VARCHAR(20) NOT NULL,

    cantidad_mensual_estimada SMALLINT UNSIGNED NULL,

    dias_estimados SMALLINT UNSIGNED NULL,
    fecha_estimada DATE NULL,

    rango_estimado VARCHAR(30) NULL,
    confianza_rango DECIMAL(6,5) NULL,

    modelo_cantidad VARCHAR(80) NULL,
    modelo_fecha VARCHAR(80) NULL,

    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_prediccion_paciente
        FOREIGN KEY (token_anonimo)
        REFERENCES paciente_analitico(token_anonimo)
        ON DELETE RESTRICT
        ON UPDATE CASCADE,

    INDEX idx_prediccion_token_fecha (token_anonimo, created_at),
    INDEX idx_prediccion_fecha_estimada (fecha_estimada)
) ENGINE=InnoDB;


-- =====================================================================
-- 7. IMPORTACIONES CSV
-- =====================================================================
--
-- El archivo CSV NO se guarda en la BD.
-- Se registra SHA-256 del archivo para trazabilidad.
--
-- tipo_dataset:
--   HISTORICO   -> dataset_completo_cruzado
--   COLD_START  -> pacientes nuevos/sinteticos
--
-- Cada registro representa UN solo archivo.
-- La interfaz solo permite una importacion activa por operacion.
-- =====================================================================

CREATE TABLE importacion_csv (
    id_importacion BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,

    id_usuario BIGINT UNSIGNED NOT NULL,

    archivo_hash_sha256 CHAR(64) NOT NULL,
    tipo_dataset VARCHAR(20) NOT NULL,

    filas_procesadas INT UNSIGNED NOT NULL DEFAULT 0,
    filas_correctas INT UNSIGNED NOT NULL DEFAULT 0,
    filas_error INT UNSIGNED NOT NULL DEFAULT 0,

    estado VARCHAR(30) NOT NULL DEFAULT 'PROCESANDO',

    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    finished_at DATETIME NULL,

    CONSTRAINT fk_importacion_usuario
        FOREIGN KEY (id_usuario)
        REFERENCES usuario_app(id_usuario)
        ON DELETE RESTRICT,

    INDEX idx_importacion_usuario_fecha (id_usuario, created_at),
    INDEX idx_importacion_tipo (tipo_dataset)
) ENGINE=InnoDB;


-- =====================================================================
-- 8. RUTAS
-- =====================================================================
--
-- Una ruta pertenece a UNA comuna.
-- Maximo 25 pacientes por ruta.
-- Si una comuna tiene >25 pacientes, el backend crea ruta 2, 3, etc.
-- =====================================================================

CREATE TABLE ruta (
    id_ruta BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,

    nombre VARCHAR(120) NOT NULL,
    comuna VARCHAR(100) NOT NULL,

    numero_ruta_comuna SMALLINT UNSIGNED NOT NULL DEFAULT 1,

    fecha_planificada DATE NOT NULL,

    estado VARCHAR(30) NOT NULL DEFAULT 'PLANIFICADA',

    total_cilindros INT UNSIGNED NOT NULL DEFAULT 0,
    total_pacientes TINYINT UNSIGNED NOT NULL DEFAULT 0,

    distancia_km DECIMAL(10,2) NULL,
    duracion_minutos INT UNSIGNED NULL,

    created_by BIGINT UNSIGNED NULL,

    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
        ON UPDATE CURRENT_TIMESTAMP,

    CONSTRAINT fk_ruta_usuario
        FOREIGN KEY (created_by)
        REFERENCES usuario_app(id_usuario)
        ON DELETE SET NULL,

    CONSTRAINT uk_ruta_comuna_numero_fecha
        UNIQUE (comuna, numero_ruta_comuna, fecha_planificada),

    INDEX idx_ruta_comuna_fecha (comuna, fecha_planificada),
    INDEX idx_ruta_estado (estado)
) ENGINE=InnoDB;


CREATE TABLE ruta_detalle (
    id_ruta_detalle BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,

    id_ruta BIGINT UNSIGNED NOT NULL,
    token_anonimo CHAR(36) NOT NULL,

    orden_visita TINYINT UNSIGNED NOT NULL,

    cantidad_cilindros SMALLINT UNSIGNED NOT NULL,

    distancia_desde_anterior_km DECIMAL(10,2) NULL,
    duracion_desde_anterior_min INT UNSIGNED NULL,

    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_ruta_detalle_ruta
        FOREIGN KEY (id_ruta)
        REFERENCES ruta(id_ruta)
        ON DELETE CASCADE,

    CONSTRAINT fk_ruta_detalle_paciente
        FOREIGN KEY (token_anonimo)
        REFERENCES paciente_analitico(token_anonimo)
        ON DELETE RESTRICT,

    CONSTRAINT uk_ruta_paciente
        UNIQUE (id_ruta, token_anonimo),

    CONSTRAINT uk_ruta_orden
        UNIQUE (id_ruta, orden_visita),

    INDEX idx_ruta_orden (id_ruta, orden_visita)
) ENGINE=InnoDB;


-- =====================================================================
-- 9. AUDITORIA
-- =====================================================================
--
-- detalle_evento NO debe contener PII ni secretos.
-- =====================================================================

CREATE TABLE auditoria_evento (
    id_evento BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,

    id_usuario BIGINT UNSIGNED NULL,

    tipo_evento VARCHAR(60) NOT NULL,
    entidad VARCHAR(50) NULL,

    token_anonimo CHAR(36) NULL,

    detalle_evento VARCHAR(500) NULL,

    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_auditoria_usuario
        FOREIGN KEY (id_usuario)
        REFERENCES usuario_app(id_usuario)
        ON DELETE SET NULL,

    INDEX idx_auditoria_fecha (created_at),
    INDEX idx_auditoria_usuario (id_usuario),
    INDEX idx_auditoria_token (token_anonimo)
) ENGINE=InnoDB;


-- =====================================================================
-- PROCEDIMIENTOS ALMACENADOS
-- =====================================================================

DELIMITER $$


-- ---------------------------------------------------------------------
-- USUARIOS
-- ---------------------------------------------------------------------

CREATE PROCEDURE sp_usuario_crear(
    IN p_username VARCHAR(80),
    IN p_email_hash CHAR(64),
    IN p_password_hash VARCHAR(255)
)
SQL SECURITY DEFINER
BEGIN
    IF p_username IS NULL OR TRIM(p_username) = '' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Username obligatorio';
    END IF;

    IF p_password_hash IS NULL OR CHAR_LENGTH(p_password_hash) < 20 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Password hash invalido';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM usuario_app
        WHERE username = LOWER(TRIM(p_username))
    ) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'El usuario ya existe';
    END IF;

    INSERT INTO usuario_app (
        username,
        email_hash,
        password_hash,
        rol
    )
    VALUES (
        LOWER(TRIM(p_username)),
        p_email_hash,
        p_password_hash,
        'OPERADOR'
    );

    SELECT
        id_usuario,
        username,
        rol,
        activo,
        created_at
    FROM usuario_app
    WHERE id_usuario = LAST_INSERT_ID();
END$$


CREATE PROCEDURE sp_usuario_obtener_auth(
    IN p_username VARCHAR(80)
)
SQL SECURITY DEFINER
BEGIN
    SELECT
        id_usuario,
        username,
        password_hash,
        rol,
        activo,
        intentos_fallidos,
        bloqueado_hasta
    FROM usuario_app
    WHERE username = LOWER(TRIM(p_username))
    LIMIT 1;
END$$


CREATE PROCEDURE sp_usuario_registrar_login(
    IN p_id_usuario BIGINT,
    IN p_exitoso BOOLEAN
)
SQL SECURITY DEFINER
BEGIN
    IF p_exitoso = TRUE THEN
        UPDATE usuario_app
        SET
            intentos_fallidos = 0,
            bloqueado_hasta = NULL,
            ultimo_login = CURRENT_TIMESTAMP
        WHERE id_usuario = p_id_usuario;
    ELSE
        UPDATE usuario_app
        SET
            intentos_fallidos = intentos_fallidos + 1,
            bloqueado_hasta =
                CASE
                    WHEN intentos_fallidos + 1 >= 5
                    THEN DATE_ADD(CURRENT_TIMESTAMP, INTERVAL 15 MINUTE)
                    ELSE bloqueado_hasta
                END
        WHERE id_usuario = p_id_usuario;
    END IF;
END$$


CREATE PROCEDURE sp_usuario_cambiar_password(
    IN p_id_usuario BIGINT,
    IN p_nuevo_password_hash VARCHAR(255)
)
SQL SECURITY DEFINER
BEGIN
    IF p_nuevo_password_hash IS NULL
       OR CHAR_LENGTH(p_nuevo_password_hash) < 20 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Password hash invalido';
    END IF;

    UPDATE usuario_app
    SET
        password_hash = p_nuevo_password_hash,
        password_changed_at = CURRENT_TIMESTAMP,
        intentos_fallidos = 0,
        bloqueado_hasta = NULL
    WHERE id_usuario = p_id_usuario;

    IF ROW_COUNT() = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Usuario no encontrado';
    END IF;
END$$


-- ---------------------------------------------------------------------
-- PACIENTE / BOVEDA
-- ---------------------------------------------------------------------
--
-- El backend entrega:
--   token UUID aleatorio
--   identificador_hash ya calculado
--   campos cifrados ya calculados
--
-- Si identificador_hash ya existe, se reutiliza su token actual.
-- ---------------------------------------------------------------------

CREATE PROCEDURE sp_paciente_registrar(
    IN p_token_nuevo CHAR(36),
    IN p_identificador_hash CHAR(64),

    IN p_edad INT,
    IN p_sexo VARCHAR(20),
    IN p_comuna VARCHAR(100),

    IN p_nombre_enc LONGBLOB,
    IN p_apellido_enc LONGBLOB,
    IN p_contacto_enc LONGBLOB,
    IN p_direccion_enc LONGBLOB,
    IN p_ubicacion_enc LONGBLOB,

    IN p_key_version SMALLINT,
    IN p_fuente_inicial VARCHAR(20),

    IN p_actor_usuario_id BIGINT
)
SQL SECURITY DEFINER
BEGIN
    DECLARE v_token CHAR(36) DEFAULT NULL;

    IF p_identificador_hash IS NULL
       OR CHAR_LENGTH(p_identificador_hash) <> 64 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Hash de identificador invalido';
    END IF;

    IF p_edad IS NOT NULL AND (p_edad < 0 OR p_edad > 130) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Edad fuera de rango';
    END IF;

    IF UPPER(TRIM(p_fuente_inicial)) NOT IN ('HISTORICO', 'COLD_START') THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Fuente inicial invalida';
    END IF;

    START TRANSACTION;

    SELECT token_anonimo
    INTO v_token
    FROM boveda_identidad
    WHERE identificador_hash = p_identificador_hash
    LIMIT 1;

    IF v_token IS NULL THEN

        IF p_token_nuevo IS NULL OR CHAR_LENGTH(TRIM(p_token_nuevo)) <> 36 THEN
            ROLLBACK;
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Token anonimo UUID obligatorio';
        END IF;

        SET v_token = TRIM(p_token_nuevo);

        INSERT INTO boveda_identidad (
            token_anonimo,
            identificador_hash,
            nombre_enc,
            apellido_enc,
            contacto_enc,
            direccion_enc,
            ubicacion_enc,
            key_version
        )
        VALUES (
            v_token,
            p_identificador_hash,
            p_nombre_enc,
            p_apellido_enc,
            p_contacto_enc,
            p_direccion_enc,
            p_ubicacion_enc,
            COALESCE(p_key_version, 1)
        );

    ELSE

        UPDATE boveda_identidad
        SET
            nombre_enc = COALESCE(p_nombre_enc, nombre_enc),
            apellido_enc = COALESCE(p_apellido_enc, apellido_enc),
            contacto_enc = COALESCE(p_contacto_enc, contacto_enc),
            direccion_enc = COALESCE(p_direccion_enc, direccion_enc),
            ubicacion_enc = COALESCE(p_ubicacion_enc, ubicacion_enc),
            key_version = COALESCE(p_key_version, key_version)
        WHERE token_anonimo = v_token;

    END IF;

    INSERT INTO paciente_analitico (
        token_anonimo,
        edad,
        sexo,
        comuna,
        identidad_disponible,
        fuente_inicial
    )
    VALUES (
        v_token,
        p_edad,
        UPPER(TRIM(p_sexo)),
        UPPER(TRIM(p_comuna)),
        TRUE,
        UPPER(TRIM(p_fuente_inicial))
    )
    ON DUPLICATE KEY UPDATE
        edad = VALUES(edad),
        sexo = VALUES(sexo),
        comuna = VALUES(comuna),
        identidad_disponible = TRUE,
        activo = TRUE;

    INSERT INTO auditoria_evento (
        id_usuario,
        tipo_evento,
        entidad,
        token_anonimo,
        detalle_evento
    )
    VALUES (
        p_actor_usuario_id,
        'PACIENTE_REGISTRADO_O_ACTUALIZADO',
        'PACIENTE',
        v_token,
        'Operacion seudonimizada'
    );

    COMMIT;

    SELECT
        v_token AS token_anonimo;
END$$


CREATE PROCEDURE sp_paciente_actualizar_ubicacion_segura(
    IN p_token_anonimo CHAR(36),
    IN p_direccion_enc LONGBLOB,
    IN p_ubicacion_enc LONGBLOB,
    IN p_key_version SMALLINT,
    IN p_actor_usuario_id BIGINT
)
SQL SECURITY DEFINER
BEGIN
    UPDATE boveda_identidad
    SET
        direccion_enc = p_direccion_enc,
        ubicacion_enc = p_ubicacion_enc,
        key_version = COALESCE(p_key_version, key_version)
    WHERE token_anonimo = p_token_anonimo;

    IF ROW_COUNT() = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Identidad no encontrada en boveda';
    END IF;

    INSERT INTO auditoria_evento (
        id_usuario,
        tipo_evento,
        entidad,
        token_anonimo,
        detalle_evento
    )
    VALUES (
        p_actor_usuario_id,
        'UBICACION_SEGURA_ACTUALIZADA',
        'BOVEDA_IDENTIDAD',
        p_token_anonimo,
        'Ubicacion cifrada actualizada'
    );
END$$


CREATE PROCEDURE sp_paciente_ubicacion_segura_obtener(
    IN p_token_anonimo CHAR(36),
    IN p_actor_usuario_id BIGINT
)
SQL SECURITY DEFINER
BEGIN
    INSERT INTO auditoria_evento (
        id_usuario,
        tipo_evento,
        entidad,
        token_anonimo,
        detalle_evento
    )
    VALUES (
        p_actor_usuario_id,
        'ACCESO_UBICACION_SEGURA',
        'BOVEDA_IDENTIDAD',
        p_token_anonimo,
        'Lectura de ciphertext para descifrado en backend'
    );

    SELECT
        token_anonimo,
        direccion_enc,
        ubicacion_enc,
        key_version
    FROM boveda_identidad
    WHERE token_anonimo = p_token_anonimo
    LIMIT 1;
END$$


CREATE PROCEDURE sp_paciente_desvincular_identidad(
    IN p_token_anonimo CHAR(36),
    IN p_actor_usuario_id BIGINT
)
SQL SECURITY DEFINER
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM paciente_analitico
        WHERE token_anonimo = p_token_anonimo
    ) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Paciente analitico no encontrado';
    END IF;

    START TRANSACTION;

    DELETE FROM boveda_identidad
    WHERE token_anonimo = p_token_anonimo;

    UPDATE paciente_analitico
    SET
        identidad_disponible = FALSE
    WHERE token_anonimo = p_token_anonimo;

    INSERT INTO auditoria_evento (
        id_usuario,
        tipo_evento,
        entidad,
        token_anonimo,
        detalle_evento
    )
    VALUES (
        p_actor_usuario_id,
        'IDENTIDAD_DESVINCULADA',
        'PACIENTE',
        p_token_anonimo,
        'Boveda eliminada; datos analiticos conservados'
    );

    COMMIT;
END$$


-- ---------------------------------------------------------------------
-- DESPACHOS
-- ---------------------------------------------------------------------

CREATE PROCEDURE sp_despacho_insertar(
    IN p_token_anonimo CHAR(36),
    IN p_fecha DATE,
    IN p_cantidad_cilindros INT,
    IN p_mes_reporte VARCHAR(10)
)
SQL SECURITY DEFINER
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM paciente_analitico
        WHERE token_anonimo = p_token_anonimo
    ) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Paciente no encontrado';
    END IF;

    IF p_fecha IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Fecha obligatoria';
    END IF;

    IF p_cantidad_cilindros IS NULL OR p_cantidad_cilindros < 1 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Cantidad de cilindros invalida';
    END IF;

    INSERT INTO despacho (
        token_anonimo,
        fecha,
        cantidad_cilindros,
        mes_reporte
    )
    VALUES (
        p_token_anonimo,
        p_fecha,
        p_cantidad_cilindros,
        p_mes_reporte
    );

    UPDATE paciente_analitico
    SET n_despachos = (
        SELECT COUNT(*)
        FROM despacho
        WHERE token_anonimo = p_token_anonimo
    )
    WHERE token_anonimo = p_token_anonimo;
END$$


CREATE PROCEDURE sp_paciente_actualizar_resumen_historial(
    IN p_token_anonimo CHAR(36),
    IN p_meses_historial INT,
    IN p_n_despachos INT
)
SQL SECURITY DEFINER
BEGIN
    UPDATE paciente_analitico
    SET
        meses_historial = GREATEST(COALESCE(p_meses_historial, 0), 0),
        n_despachos = GREATEST(COALESCE(p_n_despachos, 0), 0)
    WHERE token_anonimo = p_token_anonimo;

    IF ROW_COUNT() = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Paciente no encontrado';
    END IF;
END$$


-- ---------------------------------------------------------------------
-- MODELOS / METRICAS
-- ---------------------------------------------------------------------

CREATE PROCEDURE sp_modelo_registrar(
    IN p_nombre VARCHAR(100),
    IN p_tipo VARCHAR(30),
    IN p_version VARCHAR(50),
    IN p_artifact_hash_sha256 CHAR(64)
)
SQL SECURITY DEFINER
BEGIN
    INSERT INTO modelo_ml (
        nombre,
        tipo,
        version,
        artifact_hash_sha256,
        activo
    )
    VALUES (
        TRIM(p_nombre),
        UPPER(TRIM(p_tipo)),
        TRIM(p_version),
        p_artifact_hash_sha256,
        TRUE
    )
    ON DUPLICATE KEY UPDATE
        artifact_hash_sha256 = VALUES(artifact_hash_sha256),
        activo = TRUE;

    SELECT id_modelo
    FROM modelo_ml
    WHERE nombre = TRIM(p_nombre)
      AND version = TRIM(p_version)
    LIMIT 1;
END$$


CREATE PROCEDURE sp_modelo_metrica_guardar(
    IN p_id_modelo BIGINT,
    IN p_nombre_metrica VARCHAR(50),
    IN p_valor DECIMAL(14,6),
    IN p_particion VARCHAR(30)
)
SQL SECURITY DEFINER
BEGIN
    INSERT INTO metrica_modelo (
        id_modelo,
        nombre_metrica,
        valor,
        particion
    )
    VALUES (
        p_id_modelo,
        TRIM(p_nombre_metrica),
        p_valor,
        p_particion
    );
END$$


-- ---------------------------------------------------------------------
-- PREDICCIONES
-- ---------------------------------------------------------------------

CREATE PROCEDURE sp_prediccion_guardar(
    IN p_token_anonimo CHAR(36),

    IN p_estrategia_cantidad VARCHAR(20),
    IN p_estrategia_fecha VARCHAR(20),

    IN p_cantidad INT,

    IN p_dias INT,
    IN p_fecha_estimada DATE,

    IN p_rango VARCHAR(30),
    IN p_confianza DECIMAL(6,5),

    IN p_modelo_cantidad VARCHAR(80),
    IN p_modelo_fecha VARCHAR(80)
)
SQL SECURITY DEFINER
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM paciente_analitico
        WHERE token_anonimo = p_token_anonimo
    ) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Paciente no encontrado';
    END IF;

    IF UPPER(TRIM(p_estrategia_cantidad))
       NOT IN ('HISTORICO', 'COLD_START') THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Estrategia de cantidad invalida';
    END IF;

    IF UPPER(TRIM(p_estrategia_fecha))
       NOT IN ('HISTORICO', 'COLD_START') THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Estrategia de fecha invalida';
    END IF;

    IF p_cantidad IS NOT NULL AND p_cantidad < 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Cantidad estimada invalida';
    END IF;

    IF p_dias IS NOT NULL AND p_dias < 1 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Dias estimados invalidos';
    END IF;

    IF p_confianza IS NOT NULL
       AND (p_confianza < 0 OR p_confianza > 1) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Confianza fuera de rango';
    END IF;

    INSERT INTO prediccion (
        token_anonimo,
        estrategia_cantidad,
        estrategia_fecha,
        cantidad_mensual_estimada,
        dias_estimados,
        fecha_estimada,
        rango_estimado,
        confianza_rango,
        modelo_cantidad,
        modelo_fecha
    )
    VALUES (
        p_token_anonimo,
        UPPER(TRIM(p_estrategia_cantidad)),
        UPPER(TRIM(p_estrategia_fecha)),
        p_cantidad,
        p_dias,
        p_fecha_estimada,
        p_rango,
        p_confianza,
        p_modelo_cantidad,
        p_modelo_fecha
    );
END$$


-- ---------------------------------------------------------------------
-- IMPORTACIONES CSV
-- ---------------------------------------------------------------------

CREATE PROCEDURE sp_importacion_crear(
    IN p_id_usuario BIGINT,
    IN p_archivo_hash_sha256 CHAR(64),
    IN p_tipo_dataset VARCHAR(20),
    OUT p_id_importacion BIGINT
)
SQL SECURITY DEFINER
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM usuario_app
        WHERE id_usuario = p_id_usuario
          AND activo = TRUE
    ) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Usuario invalido';
    END IF;

    IF p_archivo_hash_sha256 IS NULL
       OR CHAR_LENGTH(p_archivo_hash_sha256) <> 64 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Hash SHA-256 del archivo invalido';
    END IF;

    IF UPPER(TRIM(p_tipo_dataset))
       NOT IN ('HISTORICO', 'COLD_START') THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Tipo de dataset invalido';
    END IF;

    INSERT INTO importacion_csv (
        id_usuario,
        archivo_hash_sha256,
        tipo_dataset,
        estado
    )
    VALUES (
        p_id_usuario,
        p_archivo_hash_sha256,
        UPPER(TRIM(p_tipo_dataset)),
        'PROCESANDO'
    );

    SET p_id_importacion = LAST_INSERT_ID();
END$$


CREATE PROCEDURE sp_importacion_finalizar(
    IN p_id_importacion BIGINT,
    IN p_filas_procesadas INT,
    IN p_filas_correctas INT,
    IN p_filas_error INT,
    IN p_estado VARCHAR(30)
)
SQL SECURITY DEFINER
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM importacion_csv
        WHERE id_importacion = p_id_importacion
    ) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Importacion no encontrada';
    END IF;

    UPDATE importacion_csv
    SET
        filas_procesadas = GREATEST(COALESCE(p_filas_procesadas, 0), 0),
        filas_correctas = GREATEST(COALESCE(p_filas_correctas, 0), 0),
        filas_error = GREATEST(COALESCE(p_filas_error, 0), 0),
        estado = UPPER(TRIM(p_estado)),
        finished_at = CURRENT_TIMESTAMP
    WHERE id_importacion = p_id_importacion;
END$$


-- ---------------------------------------------------------------------
-- RUTAS
-- ---------------------------------------------------------------------

CREATE PROCEDURE sp_ruta_crear(
    IN p_nombre VARCHAR(120),
    IN p_comuna VARCHAR(100),
    IN p_numero_ruta_comuna INT,
    IN p_fecha DATE,
    IN p_created_by BIGINT,
    OUT p_id_ruta BIGINT
)
SQL SECURITY DEFINER
BEGIN
    IF p_nombre IS NULL OR TRIM(p_nombre) = '' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Nombre de ruta obligatorio';
    END IF;

    IF p_comuna IS NULL OR TRIM(p_comuna) = '' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Comuna obligatoria';
    END IF;

    IF p_numero_ruta_comuna IS NULL OR p_numero_ruta_comuna < 1 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Numero de ruta por comuna invalido';
    END IF;

    IF p_fecha IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Fecha planificada obligatoria';
    END IF;

    INSERT INTO ruta (
        nombre,
        comuna,
        numero_ruta_comuna,
        fecha_planificada,
        created_by
    )
    VALUES (
        TRIM(p_nombre),
        UPPER(TRIM(p_comuna)),
        p_numero_ruta_comuna,
        p_fecha,
        p_created_by
    );

    SET p_id_ruta = LAST_INSERT_ID();
END$$


CREATE PROCEDURE sp_ruta_agregar_paciente(
    IN p_id_ruta BIGINT,
    IN p_token_anonimo CHAR(36),
    IN p_orden_visita INT,
    IN p_cantidad_cilindros INT
)
SQL SECURITY DEFINER
BEGIN
    DECLARE v_total INT DEFAULT 0;
    DECLARE v_comuna_ruta VARCHAR(100);
    DECLARE v_comuna_paciente VARCHAR(100);

    SELECT comuna
    INTO v_comuna_ruta
    FROM ruta
    WHERE id_ruta = p_id_ruta
    LIMIT 1;

    IF v_comuna_ruta IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Ruta no encontrada';
    END IF;

    SELECT comuna
    INTO v_comuna_paciente
    FROM paciente_analitico
    WHERE token_anonimo = p_token_anonimo
      AND activo = TRUE
    LIMIT 1;

    IF v_comuna_paciente IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Paciente no encontrado o inactivo';
    END IF;

    IF UPPER(TRIM(v_comuna_ruta))
       <> UPPER(TRIM(v_comuna_paciente)) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Paciente y ruta deben pertenecer a la misma comuna';
    END IF;

    SELECT COUNT(*)
    INTO v_total
    FROM ruta_detalle
    WHERE id_ruta = p_id_ruta;

    IF v_total >= 25 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Ruta completa: maximo 25 pacientes';
    END IF;

    IF p_orden_visita IS NULL
       OR p_orden_visita < 1
       OR p_orden_visita > 25 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Orden de visita debe estar entre 1 y 25';
    END IF;

    IF p_cantidad_cilindros IS NULL OR p_cantidad_cilindros < 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Cantidad de cilindros invalida';
    END IF;

    INSERT INTO ruta_detalle (
        id_ruta,
        token_anonimo,
        orden_visita,
        cantidad_cilindros
    )
    VALUES (
        p_id_ruta,
        p_token_anonimo,
        p_orden_visita,
        p_cantidad_cilindros
    );

    UPDATE ruta
    SET
        total_pacientes = (
            SELECT COUNT(*)
            FROM ruta_detalle
            WHERE id_ruta = p_id_ruta
        ),
        total_cilindros = (
            SELECT COALESCE(SUM(cantidad_cilindros), 0)
            FROM ruta_detalle
            WHERE id_ruta = p_id_ruta
        )
    WHERE id_ruta = p_id_ruta;
END$$


CREATE PROCEDURE sp_ruta_eliminar_paciente(
    IN p_id_ruta BIGINT,
    IN p_token_anonimo CHAR(36)
)
SQL SECURITY DEFINER
BEGIN
    DELETE FROM ruta_detalle
    WHERE id_ruta = p_id_ruta
      AND token_anonimo = p_token_anonimo;

    UPDATE ruta
    SET
        total_pacientes = (
            SELECT COUNT(*)
            FROM ruta_detalle
            WHERE id_ruta = p_id_ruta
        ),
        total_cilindros = (
            SELECT COALESCE(SUM(cantidad_cilindros), 0)
            FROM ruta_detalle
            WHERE id_ruta = p_id_ruta
        )
    WHERE id_ruta = p_id_ruta;
END$$


CREATE PROCEDURE sp_ruta_actualizar_metricas(
    IN p_id_ruta BIGINT,
    IN p_distancia_km DECIMAL(10,2),
    IN p_duracion_minutos INT
)
SQL SECURITY DEFINER
BEGIN
    UPDATE ruta
    SET
        distancia_km = p_distancia_km,
        duracion_minutos = p_duracion_minutos
    WHERE id_ruta = p_id_ruta;

    IF ROW_COUNT() = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Ruta no encontrada';
    END IF;
END$$


CREATE PROCEDURE sp_ruta_obtener(
    IN p_id_ruta BIGINT
)
SQL SECURITY DEFINER
BEGIN
    SELECT
        id_ruta,
        nombre,
        comuna,
        numero_ruta_comuna,
        fecha_planificada,
        estado,
        total_pacientes,
        total_cilindros,
        distancia_km,
        duracion_minutos,
        created_at
    FROM ruta
    WHERE id_ruta = p_id_ruta;

    SELECT
        rd.orden_visita,
        rd.token_anonimo,
        p.edad,
        p.sexo,
        p.comuna,
        p.identidad_disponible,
        rd.cantidad_cilindros,
        rd.distancia_desde_anterior_km,
        rd.duracion_desde_anterior_min
    FROM ruta_detalle rd
    INNER JOIN paciente_analitico p
        ON p.token_anonimo = rd.token_anonimo
    WHERE rd.id_ruta = p_id_ruta
    ORDER BY rd.orden_visita;
END$$


CREATE PROCEDURE sp_rutas_listar()
SQL SECURITY DEFINER
BEGIN
    SELECT
        id_ruta,
        nombre,
        comuna,
        numero_ruta_comuna,
        fecha_planificada,
        estado,
        total_pacientes,
        total_cilindros,
        distancia_km,
        duracion_minutos
    FROM ruta
    ORDER BY fecha_planificada DESC, comuna, numero_ruta_comuna;
END$$


-- ---------------------------------------------------------------------
-- CONSULTA PRINCIPAL DE PACIENTES
-- ---------------------------------------------------------------------
--
-- No devuelve identidad, direccion ni coordenadas.
-- La ubicacion se pide aparte mediante procedimiento seguro.
-- ---------------------------------------------------------------------

CREATE PROCEDURE sp_pacientes_listar()
SQL SECURITY DEFINER
BEGIN
    SELECT
        p.token_anonimo,
        p.edad,
        p.sexo,
        p.comuna,
        p.meses_historial,
        p.n_despachos,
        p.identidad_disponible,
        p.fuente_inicial,

        pr.cantidad_mensual_estimada,
        pr.dias_estimados,
        pr.fecha_estimada,
        pr.rango_estimado,
        pr.confianza_rango,
        pr.estrategia_cantidad,
        pr.estrategia_fecha,
        pr.modelo_cantidad,
        pr.modelo_fecha,
        pr.created_at AS fecha_prediccion,

        r.id_ruta,
        r.nombre AS nombre_ruta,
        r.numero_ruta_comuna,
        r.fecha_planificada,
        rd.orden_visita

    FROM paciente_analitico p

    LEFT JOIN prediccion pr
        ON pr.id_prediccion = (
            SELECT MAX(pr2.id_prediccion)
            FROM prediccion pr2
            WHERE pr2.token_anonimo = p.token_anonimo
        )

    LEFT JOIN ruta_detalle rd
        ON rd.id_ruta_detalle = (
            SELECT MAX(rd2.id_ruta_detalle)
            FROM ruta_detalle rd2
            WHERE rd2.token_anonimo = p.token_anonimo
        )

    LEFT JOIN ruta r
        ON r.id_ruta = rd.id_ruta

    WHERE p.activo = TRUE

    ORDER BY p.comuna, p.token_anonimo;
END$$


-- ---------------------------------------------------------------------
-- AUDITORIA
-- ---------------------------------------------------------------------

CREATE PROCEDURE sp_auditoria_registrar(
    IN p_id_usuario BIGINT,
    IN p_tipo_evento VARCHAR(60),
    IN p_entidad VARCHAR(50),
    IN p_token_anonimo CHAR(36),
    IN p_detalle_evento VARCHAR(500)
)
SQL SECURITY DEFINER
BEGIN
    INSERT INTO auditoria_evento (
        id_usuario,
        tipo_evento,
        entidad,
        token_anonimo,
        detalle_evento
    )
    VALUES (
        p_id_usuario,
        UPPER(TRIM(p_tipo_evento)),
        UPPER(TRIM(p_entidad)),
        p_token_anonimo,
        p_detalle_evento
    );
END$$


-- =====================================================================
-- TRIGGER 1
-- MAXIMO 25 PACIENTES POR RUTA + VALIDACION DE COMUNA
-- =====================================================================

CREATE TRIGGER trg_ruta_detalle_validar_insert
BEFORE INSERT ON ruta_detalle
FOR EACH ROW
BEGIN
    DECLARE v_total INT DEFAULT 0;
    DECLARE v_comuna_ruta VARCHAR(100);
    DECLARE v_comuna_paciente VARCHAR(100);

    SELECT COUNT(*)
    INTO v_total
    FROM ruta_detalle
    WHERE id_ruta = NEW.id_ruta;

    IF v_total >= 25 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'No se permiten mas de 25 pacientes por ruta';
    END IF;

    IF NEW.orden_visita < 1 OR NEW.orden_visita > 25 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Orden de visita fuera de rango';
    END IF;

    SELECT comuna
    INTO v_comuna_ruta
    FROM ruta
    WHERE id_ruta = NEW.id_ruta
    LIMIT 1;

    SELECT comuna
    INTO v_comuna_paciente
    FROM paciente_analitico
    WHERE token_anonimo = NEW.token_anonimo
    LIMIT 1;

    IF v_comuna_ruta IS NULL OR v_comuna_paciente IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Ruta o paciente inexistente';
    END IF;

    IF UPPER(TRIM(v_comuna_ruta))
       <> UPPER(TRIM(v_comuna_paciente)) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'La ruta solo admite pacientes de su comuna';
    END IF;
END$$


-- =====================================================================
-- TRIGGER 2
-- PROTECCION EXTRA: total_pacientes nunca puede superar 25
-- =====================================================================

CREATE TRIGGER trg_ruta_validar_update
BEFORE UPDATE ON ruta
FOR EACH ROW
BEGIN
    IF NEW.total_pacientes > 25 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Total de pacientes no puede superar 25';
    END IF;
END$$


DELIMITER ;


-- =====================================================================
-- FIN DEL ESQUEMA
-- =====================================================================
--
-- CREDENCIALES DE SERVICIO DE MARIADB
-- -----------------------------------
-- NO se crean aqui para evitar secrets embebidos.
--
-- Crearlas manualmente en phpMyAdmin y guardar las passwords solo en .env.
--
-- Ejemplo conceptual (NO ejecutar literalmente con placeholders):
--
-- CREATE USER 'oxigeno_app'@'localhost' IDENTIFIED BY '<PASSWORD_FROM_ENV>';
-- CREATE USER 'oxigeno_vault'@'localhost' IDENTIFIED BY '<PASSWORD_FROM_ENV>';
--
-- oxigeno_app:
--   EXECUTE sobre procedimientos de usuarios, analitica, predicciones,
--   importaciones y rutas.
--
-- oxigeno_vault:
--   EXECUTE solamente sobre:
--     sp_paciente_registrar
--     sp_paciente_actualizar_ubicacion_segura
--     sp_paciente_ubicacion_segura_obtener
--     sp_paciente_desvincular_identidad
--
-- El backend tendra dos conexiones separadas y tomara ambas credenciales
-- desde variables de entorno.
--
-- =====================================================================
