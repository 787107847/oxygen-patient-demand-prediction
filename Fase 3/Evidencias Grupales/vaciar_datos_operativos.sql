USE oxigeno_logistica;

START TRANSACTION;

DELETE FROM ruta_detalle;
DELETE FROM ruta;
DELETE FROM prediccion;
DELETE FROM despacho;
DELETE FROM importacion_csv;
DELETE FROM auditoria_evento;
DELETE FROM paciente_analitico;
DELETE FROM boveda_identidad;

COMMIT;

ALTER TABLE ruta_detalle AUTO_INCREMENT = 1;
ALTER TABLE ruta AUTO_INCREMENT = 1;
ALTER TABLE prediccion AUTO_INCREMENT = 1;
ALTER TABLE despacho AUTO_INCREMENT = 1;
ALTER TABLE importacion_csv AUTO_INCREMENT = 1;
ALTER TABLE auditoria_evento AUTO_INCREMENT = 1;
ALTER TABLE boveda_identidad AUTO_INCREMENT = 1;
