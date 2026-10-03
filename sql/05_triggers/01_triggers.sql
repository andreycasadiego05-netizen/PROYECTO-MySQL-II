USE coworking;

-- =====================================================================
-- TRIGGERS - BD coworking (20 triggers)
-- Ejecutar DESPUÉS de 00_dll/01_estructura.sql y 01_dml/01_datos_iniciales.sql
-- Este script se puede ejecutar completo una sola vez (los ALTER TABLE de la
-- sección 0 no son idempotentes; los triggers sí: usan DROP TRIGGER IF EXISTS).
-- =====================================================================


-- =====================================================================
-- 0. AJUSTES NECESARIOS AL ESQUEMA
-- El DDL actual no tiene dónde guardar algunos datos que piden los triggers.
-- =====================================================================

-- Última fecha de acceso del usuario (trigger 18)
ALTER TABLE usuario
    ADD COLUMN ultima_fecha_acceso DATETIME NULL;

-- Saldo pendiente de la factura (trigger 14)
ALTER TABLE factura
    ADD COLUMN saldo_pendiente DECIMAL(10,2) NOT NULL DEFAULT 0;

-- Un pago puede ser:
--   * pago normal              -> facturaID NULL (el trigger 11 crea su factura)
--   * abono a factura existente -> facturaID con la factura que abona (trigger 14)
--   * pago de una reserva       -> reservaID con la reserva pagada (trigger 8)
ALTER TABLE pago
    ADD COLUMN facturaID INT NULL,
    ADD COLUMN reservaID INT NULL,
    ADD CONSTRAINT fk_pago_factura FOREIGN KEY (facturaID) REFERENCES factura(facturaID),
    ADD CONSTRAINT fk_pago_reserva FOREIGN KEY (reservaID) REFERENCES reserva(reservaID);

-- Saldo inicial de las facturas ya cargadas en el DML
UPDATE factura SET saldo_pendiente = CASE estado WHEN 'Pendiente' THEN total ELSE 0 END;


-- =====================================================================
-- TABLAS DE LOG
-- =====================================================================

CREATE TABLE IF NOT EXISTS log_cambio_tipo_membresia (
    logID INT AUTO_INCREMENT PRIMARY KEY,
    membresiaID INT NOT NULL,
    usuarioID INT NOT NULL,
    tipoID_anterior INT,
    tipoID_nuevo INT,
    tipo_anterior VARCHAR(20),
    tipo_nuevo VARCHAR(20),
    fecha_cambio DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    usuario_bd VARCHAR(100)
);

CREATE TABLE IF NOT EXISTS log_reserva_cancelada (
    logID INT AUTO_INCREMENT PRIMARY KEY,
    reservaID INT NOT NULL,
    usuarioID INT NOT NULL,
    espacioID INT NOT NULL,
    fecha_reserva DATE NOT NULL,
    hora_inicio TIME NOT NULL,
    estado_anterior VARCHAR(20),
    fecha_cancelacion DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    usuario_bd VARCHAR(100)
);

CREATE TABLE IF NOT EXISTS log_pago_anulado (
    logID INT AUTO_INCREMENT PRIMARY KEY,
    pagoID INT NOT NULL,
    usuarioID INT NOT NULL,
    monto DECIMAL(10,2) NOT NULL,
    metodo_pago VARCHAR(20),
    referencia VARCHAR(100),
    estado_anterior VARCHAR(20),
    fecha_anulacion DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    usuario_bd VARCHAR(100)
);

CREATE TABLE IF NOT EXISTS log_acceso_rechazado (
    logID INT AUTO_INCREMENT PRIMARY KEY,
    asistenciaID INT NOT NULL,
    usuarioID INT NOT NULL,
    fecha_intento DATETIME NOT NULL,
    motivo VARCHAR(100),
    registrado_en DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);


DELIMITER $$

-- =====================================================================
-- MÓDULO MEMBRESÍAS
-- =====================================================================

-- 1. Calcular la fecha de vencimiento al crear una membresía.
--    fecha_fin = fecha_inicio + duración del tipo - 1 día
--    (Diaria: mismo día; Mensual: 30 días contando el de inicio).
--    Solo actúa si fecha_fin viene vacía o inválida (omitida / NULL / anterior al inicio).
DROP TRIGGER IF EXISTS trg_membresia_bi_fecha_vencimiento$$
CREATE TRIGGER trg_membresia_bi_fecha_vencimiento
BEFORE INSERT ON membresia
FOR EACH ROW
BEGIN
    DECLARE v_dias INT;

    IF NEW.fecha_fin IS NULL OR NEW.fecha_fin < NEW.fecha_inicio THEN
        SELECT duracion INTO v_dias
        FROM tipo_membresia
        WHERE tipoID = NEW.tipoID;

        IF v_dias IS NOT NULL THEN
            SET NEW.fecha_fin = DATE_ADD(NEW.fecha_inicio, INTERVAL (v_dias - 1) DAY);
        END IF;
    END IF;
END$$


-- 2. Pago exitoso -> la membresía suspendida del usuario pasa a "Activa".
--    Se dispara al registrar (INSERT) un pago con estado 'Pagado'.
DROP TRIGGER IF EXISTS trg_pago_ai_activar_membresia$$
CREATE TRIGGER trg_pago_ai_activar_membresia
AFTER INSERT ON pago
FOR EACH ROW
BEGIN
    IF NEW.estado = 'Pagado' THEN
        UPDATE membresia m
        JOIN usuario u ON u.membresiaID = m.membresiaID
        SET m.estado = 'Activa'
        WHERE u.usuarioID = NEW.usuarioID
          AND m.estado = 'Suspendida';
    END IF;
END$$


-- 3. Membresía vencida sin pago -> "Suspendida".
--    MySQL no ejecuta triggers por tiempo; este trigger se evalúa cada vez que
--    se actualiza una membresía. Para revisarlas todas, un evento diario
--    (carpeta 06_eventos) puede hacer:
--        UPDATE membresia SET estado = estado WHERE estado = 'Activa';
--    (BEFORE UPDATE se dispara aunque el valor no cambie.)
--    Regla: si la fecha límite (fecha_fin) ya pasó y el usuario no tiene ningún
--    pago 'Pagado' desde el inicio de la membresía, queda Suspendida.
DROP TRIGGER IF EXISTS trg_membresia_bu_suspender_por_impago$$
CREATE TRIGGER trg_membresia_bu_suspender_por_impago
BEFORE UPDATE ON membresia
FOR EACH ROW
BEGIN
    IF NEW.estado = 'Activa' AND NEW.fecha_fin < CURDATE() THEN
        IF NOT EXISTS (
            SELECT 1
            FROM pago p
            WHERE p.usuarioID = NEW.usuarioID
              AND p.estado = 'Pagado'
              AND DATE(p.fecha_pago) >= NEW.fecha_inicio
        ) THEN
            SET NEW.estado = 'Suspendida';
        END IF;
    END IF;
END$$


-- 4. Log de cambios de tipo de membresía.
DROP TRIGGER IF EXISTS trg_membresia_au_log_cambio_tipo$$
CREATE TRIGGER trg_membresia_au_log_cambio_tipo
AFTER UPDATE ON membresia
FOR EACH ROW
BEGIN
    IF NOT (OLD.tipoID <=> NEW.tipoID) OR NOT (OLD.tipo <=> NEW.tipo) THEN
        INSERT INTO log_cambio_tipo_membresia
            (membresiaID, usuarioID, tipoID_anterior, tipoID_nuevo,
             tipo_anterior, tipo_nuevo, usuario_bd)
        VALUES
            (NEW.membresiaID, NEW.usuarioID, OLD.tipoID, NEW.tipoID,
             OLD.tipo, NEW.tipo, CURRENT_USER());
    END IF;
END$$


-- 5. Bloquear la eliminación de una membresía si el usuario tiene reservas activas.
--    "Activa" = Confirmada y vigente (fecha de hoy o futura).
--    Las reservas Pendientes no bloquean: el trigger 9 las cancela.
DROP TRIGGER IF EXISTS trg_membresia_bd_bloquear_eliminacion$$
CREATE TRIGGER trg_membresia_bd_bloquear_eliminacion
BEFORE DELETE ON membresia
FOR EACH ROW
BEGIN
    IF EXISTS (
        SELECT 1
        FROM reserva r
        WHERE r.usuarioID = OLD.usuarioID
          AND r.estado = 'Confirmada'
          AND r.fecha_reserva >= CURDATE()
    ) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'No se puede eliminar la membresía: el usuario tiene reservas activas';
    END IF;
END$$


-- =====================================================================
-- MÓDULO RESERVAS
-- =====================================================================

-- 6. Evitar reservas duplicadas (mismo espacio, fecha y franja horaria).
--    Se rechaza cualquier traslape con una reserva no cancelada.
DROP TRIGGER IF EXISTS trg_reserva_bi_validar_duplicada$$
CREATE TRIGGER trg_reserva_bi_validar_duplicada
BEFORE INSERT ON reserva
FOR EACH ROW
BEGIN
    IF EXISTS (
        SELECT 1
        FROM reserva r
        WHERE r.espacioID = NEW.espacioID
          AND r.fecha_reserva = NEW.fecha_reserva
          AND r.estado <> 'Cancelada'
          AND r.hora_inicio < NEW.hora_fin
          AND r.hora_fin > NEW.hora_inicio
    ) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Ya existe una reserva para ese espacio en la misma fecha y horario';
    END IF;
END$$


-- 7. Toda reserva nueva nace como "Pendiente".
--    (El ENUM del DDL no tiene 'Pendiente de Confirmación'; se usa 'Pendiente'.)
DROP TRIGGER IF EXISTS trg_reserva_bi_estado_pendiente$$
CREATE TRIGGER trg_reserva_bi_estado_pendiente
BEFORE INSERT ON reserva
FOR EACH ROW
BEGIN
    SET NEW.estado = 'Pendiente';
END$$


-- 8. Pago de una reserva -> la reserva pasa a "Confirmada".
--    Se dispara al registrar un pago 'Pagado' con reservaID.
DROP TRIGGER IF EXISTS trg_pago_ai_confirmar_reserva$$
CREATE TRIGGER trg_pago_ai_confirmar_reserva
AFTER INSERT ON pago
FOR EACH ROW
BEGIN
    IF NEW.reservaID IS NOT NULL AND NEW.estado = 'Pagado' THEN
        UPDATE reserva
        SET estado = 'Confirmada'
        WHERE reservaID = NEW.reservaID
          AND estado = 'Pendiente';
    END IF;
END$$


-- 9. Al eliminar la membresía, se cancelan las reservas vigentes del usuario.
DROP TRIGGER IF EXISTS trg_membresia_ad_cancelar_reservas$$
CREATE TRIGGER trg_membresia_ad_cancelar_reservas
AFTER DELETE ON membresia
FOR EACH ROW
BEGIN
    UPDATE reserva
    SET estado = 'Cancelada'
    WHERE usuarioID = OLD.usuarioID
      AND estado IN ('Pendiente', 'Confirmada')
      AND fecha_reserva >= CURDATE();
END$$


-- 10. Log de reservas canceladas (incluye las canceladas por el trigger 9).
DROP TRIGGER IF EXISTS trg_reserva_au_log_cancelacion$$
CREATE TRIGGER trg_reserva_au_log_cancelacion
AFTER UPDATE ON reserva
FOR EACH ROW
BEGIN
    IF NEW.estado = 'Cancelada' AND OLD.estado <> 'Cancelada' THEN
        INSERT INTO log_reserva_cancelada
            (reservaID, usuarioID, espacioID, fecha_reserva, hora_inicio,
             estado_anterior, usuario_bd)
        VALUES
            (NEW.reservaID, NEW.usuarioID, NEW.espacioID, NEW.fecha_reserva,
             NEW.hora_inicio, OLD.estado, CURRENT_USER());
    END IF;
END$$


-- =====================================================================
-- MÓDULO PAGOS Y FACTURACIÓN
-- =====================================================================

-- 11. Crear la factura (y su detalle) al registrar un pago normal.
--     Los abonos a una factura existente (facturaID no nulo) no generan otra.
--     Total = monto del pago; el IVA del 19 % se separa del total (igual que el DML).
DROP TRIGGER IF EXISTS trg_pago_ai_crear_factura$$
CREATE TRIGGER trg_pago_ai_crear_factura
AFTER INSERT ON pago
FOR EACH ROW
BEGIN
    DECLARE v_subtotal DECIMAL(10,2);
    DECLARE v_facturaID INT;

    IF NEW.facturaID IS NULL THEN
        SET v_subtotal = ROUND(NEW.monto / 1.19, 2);

        INSERT INTO factura
            (numero_factura, fecha_emision, subtotal, impuestos, total,
             estado, saldo_pendiente, usuarioID, pagoID)
        VALUES
            (CONCAT('FAC-', YEAR(NEW.fecha_pago), '-', LPAD(NEW.pagoID, 4, '0')),
             NOW(), v_subtotal, NEW.monto - v_subtotal, NEW.monto,
             CASE NEW.estado
                 WHEN 'Pagado'    THEN 'Pagada'
                 WHEN 'Cancelado' THEN 'Cancelada'
                 ELSE 'Pendiente'
             END,
             IF(NEW.estado = 'Pendiente', NEW.monto, 0),
             NEW.usuarioID, NEW.pagoID);

        SET v_facturaID = LAST_INSERT_ID();

        INSERT INTO detalle_factura
            (facturaID, concepto, cantidad, precio_unitario, subtotal)
        VALUES
            (v_facturaID,
             IF(NEW.reservaID IS NULL,
                CONCAT('Pago ref. ', IFNULL(NEW.referencia, 'N/A')),
                CONCAT('Reserva #', NEW.reservaID)),
             1, v_subtotal, v_subtotal);
    END IF;
END$$


-- 12. Al confirmarse un pago (Pendiente -> Pagado), la factura pasa a "Pagada".
--     Si el pago es un abono (facturaID), se recalcula el saldo de esa factura.
DROP TRIGGER IF EXISTS trg_pago_au_factura_pagada$$
CREATE TRIGGER trg_pago_au_factura_pagada
AFTER UPDATE ON pago
FOR EACH ROW
BEGIN
    DECLARE v_total DECIMAL(10,2);
    DECLARE v_pago_original INT;
    DECLARE v_pagado DECIMAL(10,2);
    DECLARE v_saldo DECIMAL(10,2);

    IF OLD.estado <> 'Pagado' AND NEW.estado = 'Pagado' THEN
        IF NEW.facturaID IS NULL THEN
            UPDATE factura
            SET estado = 'Pagada',
                saldo_pendiente = 0
            WHERE pagoID = NEW.pagoID
              AND estado = 'Pendiente';
        ELSE
            SELECT total, pagoID INTO v_total, v_pago_original
            FROM factura
            WHERE facturaID = NEW.facturaID;

            SELECT IFNULL(SUM(monto), 0) INTO v_pagado
            FROM pago
            WHERE estado = 'Pagado'
              AND (facturaID = NEW.facturaID OR pagoID = v_pago_original);

            SET v_saldo = GREATEST(v_total - v_pagado, 0);

            UPDATE factura
            SET saldo_pendiente = v_saldo,
                estado = IF(v_saldo = 0, 'Pagada', estado)
            WHERE facturaID = NEW.facturaID
              AND estado <> 'Cancelada';
        END IF;
    END IF;
END$$


-- 13. Bloquear la eliminación de un pago que ya tiene factura asociada.
DROP TRIGGER IF EXISTS trg_pago_bd_bloquear_eliminacion$$
CREATE TRIGGER trg_pago_bd_bloquear_eliminacion
BEFORE DELETE ON pago
FOR EACH ROW
BEGIN
    IF OLD.facturaID IS NOT NULL
       OR EXISTS (SELECT 1 FROM factura f WHERE f.pagoID = OLD.pagoID) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'No se puede eliminar el pago: ya tiene una factura asociada';
    END IF;
END$$


-- 14. Pagos parciales: al registrar un abono 'Pagado' sobre una factura,
--     se recalcula su saldo pendiente (total - pagos 'Pagado' asociados).
--     Cuando el saldo llega a 0 la factura pasa a "Pagada".
DROP TRIGGER IF EXISTS trg_pago_ai_saldo_pendiente$$
CREATE TRIGGER trg_pago_ai_saldo_pendiente
AFTER INSERT ON pago
FOR EACH ROW
BEGIN
    DECLARE v_total DECIMAL(10,2);
    DECLARE v_pago_original INT;
    DECLARE v_pagado DECIMAL(10,2);
    DECLARE v_saldo DECIMAL(10,2);

    IF NEW.facturaID IS NOT NULL AND NEW.estado = 'Pagado' THEN
        SELECT total, pagoID INTO v_total, v_pago_original
        FROM factura
        WHERE facturaID = NEW.facturaID;

        SELECT IFNULL(SUM(monto), 0) INTO v_pagado
        FROM pago
        WHERE estado = 'Pagado'
          AND (facturaID = NEW.facturaID OR pagoID = v_pago_original);

        SET v_saldo = GREATEST(v_total - v_pagado, 0);

        UPDATE factura
        SET saldo_pendiente = v_saldo,
            estado = IF(v_saldo = 0, 'Pagada', estado)
        WHERE facturaID = NEW.facturaID
          AND estado <> 'Cancelada';
    END IF;
END$$


-- 15. Log de pagos anulados (estado -> 'Cancelado').
DROP TRIGGER IF EXISTS trg_pago_au_log_anulado$$
CREATE TRIGGER trg_pago_au_log_anulado
AFTER UPDATE ON pago
FOR EACH ROW
BEGIN
    IF NEW.estado = 'Cancelado' AND OLD.estado <> 'Cancelado' THEN
        INSERT INTO log_pago_anulado
            (pagoID, usuarioID, monto, metodo_pago, referencia,
             estado_anterior, usuario_bd)
        VALUES
            (NEW.pagoID, NEW.usuarioID, NEW.monto, NEW.metodo_pago,
             NEW.referencia, OLD.estado, CURRENT_USER());
    END IF;
END$$


-- =====================================================================
-- MÓDULO ACCESOS
-- Flujo: cada validación con QR o tarjeta RFID es un INSERT en `acceso`
-- (con un código único por evento, por la restricción UNIQUE del DDL).
-- De ahí se encadenan los triggers sobre `asistencia`.
-- =====================================================================

-- 16. Registrar la asistencia al validar un acceso.
--     Entra como 'Autorizado'; el trigger 17 la cambia a 'Rechazado' si no
--     hay membresía activa. Si el usuario tiene una reserva confirmada ese
--     día y a esa hora, se enlaza.
DROP TRIGGER IF EXISTS trg_acceso_ai_registrar_asistencia$$
CREATE TRIGGER trg_acceso_ai_registrar_asistencia
AFTER INSERT ON acceso
FOR EACH ROW
BEGIN
    DECLARE v_reservaID INT;

    SET v_reservaID = (
        SELECT r.reservaID
        FROM reserva r
        WHERE r.usuarioID = NEW.usuarioID
          AND r.fecha_reserva = DATE(NEW.fecha_registro)
          AND r.estado = 'Confirmada'
          AND TIME(NEW.fecha_registro) BETWEEN r.hora_inicio AND r.hora_fin
        LIMIT 1
    );

    INSERT INTO asistencia
        (fecha, hora_entrada, hora_salida, resultado_validacion, usuarioID, reservaID)
    VALUES
        (DATE(NEW.fecha_registro), TIME(NEW.fecha_registro), NULL,
         'Autorizado', NEW.usuarioID, v_reservaID);
END$$


-- 17. Bloquear el acceso si el usuario no tiene membresía activa.
--     La entrada queda marcada como 'Rechazado' (no se lanza error para que
--     el intento quede guardado y pueda registrarse en el log, trigger 20).
DROP TRIGGER IF EXISTS trg_asistencia_bi_bloquear_sin_membresia$$
CREATE TRIGGER trg_asistencia_bi_bloquear_sin_membresia
BEFORE INSERT ON asistencia
FOR EACH ROW
BEGIN
    IF NEW.resultado_validacion = 'Autorizado' AND NOT EXISTS (
        SELECT 1
        FROM membresia m
        WHERE m.usuarioID = NEW.usuarioID
          AND m.estado = 'Activa'
          AND NEW.fecha BETWEEN m.fecha_inicio AND m.fecha_fin
    ) THEN
        SET NEW.resultado_validacion = 'Rechazado';
        SET NEW.hora_salida = NULL;
    END IF;
END$$


-- 18. Actualizar la última fecha de acceso del usuario al ingresar (solo autorizados).
DROP TRIGGER IF EXISTS trg_asistencia_ai_ultimo_acceso$$
CREATE TRIGGER trg_asistencia_ai_ultimo_acceso
AFTER INSERT ON asistencia
FOR EACH ROW
BEGIN
    IF NEW.resultado_validacion = 'Autorizado' THEN
        UPDATE usuario
        SET ultima_fecha_acceso = TIMESTAMP(NEW.fecha, NEW.hora_entrada)
        WHERE usuarioID = NEW.usuarioID;
    END IF;
END$$


-- 19. Si el usuario vuelve a entrar sin haber registrado salida, se cierra
--     la asistencia abierta: hora de salida = hora del nuevo ingreso
--     (si quedó abierta de un día anterior, se cierra a las 23:59:59).
--     Es BEFORE INSERT para ejecutarse antes de que el trigger 16 cree la nueva.
DROP TRIGGER IF EXISTS trg_acceso_bi_salida_automatica$$
CREATE TRIGGER trg_acceso_bi_salida_automatica
BEFORE INSERT ON acceso
FOR EACH ROW
BEGIN
    UPDATE asistencia
    SET hora_salida = IF(fecha = DATE(NEW.fecha_registro),
                         TIME(NEW.fecha_registro),
                         '23:59:59')
    WHERE usuarioID = NEW.usuarioID
      AND hora_salida IS NULL
      AND resultado_validacion = 'Autorizado'
      AND fecha <= DATE(NEW.fecha_registro);
END$$


-- 20. Log de cada intento de acceso rechazado.
DROP TRIGGER IF EXISTS trg_asistencia_ai_log_rechazado$$
CREATE TRIGGER trg_asistencia_ai_log_rechazado
AFTER INSERT ON asistencia
FOR EACH ROW
BEGIN
    IF NEW.resultado_validacion = 'Rechazado' THEN
        INSERT INTO log_acceso_rechazado
            (asistenciaID, usuarioID, fecha_intento, motivo)
        VALUES
            (NEW.asistenciaID, NEW.usuarioID,
             TIMESTAMP(NEW.fecha, NEW.hora_entrada),
             IF(EXISTS (SELECT 1 FROM membresia m
                        WHERE m.usuarioID = NEW.usuarioID
                          AND m.estado = 'Activa'
                          AND NEW.fecha BETWEEN m.fecha_inicio AND m.fecha_fin),
                'Rechazado manualmente',
                'Sin membresía activa'));
    END IF;
END$$

DELIMITER ;


-- =====================================================================
-- PRUEBAS RÁPIDAS (descomentar para probar uno por uno)
-- =====================================================================

-- T1: fecha_fin automática (Mensual desde 2026-10-05 -> 2026-11-03)
-- INSERT INTO membresia (tipo, estado, fecha_inicio, usuarioID, tipoID)
-- VALUES ('Mensual', 'Activa', '2026-10-05', 2, 2);
-- SELECT membresiaID, fecha_inicio, fecha_fin FROM membresia ORDER BY membresiaID DESC LIMIT 1;

-- T6: reserva duplicada (Sala Andes, 2026-10-02, 14-16 ya existe) -> debe dar error
-- INSERT INTO reserva (fecha_reserva, hora_inicio, hora_fin, duracion, estado, espacioID, usuarioID)
-- VALUES ('2026-10-02', '15:00:00', '17:00:00', 120, 'Pendiente', 5, 1);

-- T5: usuario 5 tiene reserva confirmada futura -> debe bloquear
-- UPDATE usuario SET membresiaID = NULL WHERE usuarioID = 5;
-- DELETE FROM membresia WHERE membresiaID = 5;

-- T13: el pago 1 ya tiene factura -> debe bloquear
-- DELETE FROM pago WHERE pagoID = 1;

-- T12: confirmar el pago 5 -> FAC-2026-0005 pasa a Pagada
-- UPDATE pago SET estado = 'Pagado' WHERE pagoID = 5;

-- T19/T16/T17/T18/T20: usuario 1 entra de nuevo (cierra su asistencia abierta);
-- usuario 9 (membresía Suspendida) queda Rechazado y en el log
-- INSERT INTO acceso (tipo_acceso, codigo, fecha_registro, usuarioID) VALUES
--   ('QR', 'QR-TEST-0001', '2026-09-30 15:00:00', 1),
--   ('QR', 'QR-TEST-0002', '2026-09-30 15:05:00', 9);
-- SELECT * FROM asistencia ORDER BY asistenciaID DESC LIMIT 3;
-- SELECT * FROM log_acceso_rechazado;
