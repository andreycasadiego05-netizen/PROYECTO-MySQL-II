USE coworking;

-- =====================================================
-- EVENTOS SQL (20)
-- =====================================================
-- Ejecutar después de 01_estructura.sql y 01_datos_iniciales.sql.
-- Se puede ejecutar varias veces: los prerrequisitos solo agregan lo que
-- falta y cada evento se elimina y se vuelve a crear.
-- Requiere MySQL 8 y un cliente que soporte DELIMITER (consola mysql o
-- MySQL Workbench).
--
-- Los eventos de MySQL no pueden enviar correos. Cada "envío", "alerta" o
-- "reporte" se guarda como una fila en la tabla notificacion (estado
-- Pendiente); una app o un job externo puede consumirla.
-- =====================================================


-- =====================================================
-- PRERREQUISITOS
-- =====================================================

CREATE TABLE IF NOT EXISTS notificacion (
    notificacionID INT AUTO_INCREMENT PRIMARY KEY,
    destinatario ENUM('Usuario', 'Administrador', 'Recepcion', 'Contador') NOT NULL,
    usuarioID INT NULL COMMENT 'Solo cuando el destinatario es un usuario',
    tipo VARCHAR(50) NOT NULL,
    asunto VARCHAR(150) NOT NULL,
    mensaje TEXT NOT NULL,
    referencia_id INT NULL COMMENT 'ID de la membresía/reserva/factura que origina el aviso (evita duplicados)',
    fecha_creacion DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    estado ENUM('Pendiente', 'Enviada') NOT NULL DEFAULT 'Pendiente',
    FOREIGN KEY (usuarioID) REFERENCES usuario(usuarioID),
    INDEX idx_notificacion_tipo_ref (tipo, referencia_id)
);

DELIMITER $$

-- Procedimiento auxiliar: agrega una columna solo si no existe.
-- Se elimina al final de esta sección.
DROP PROCEDURE IF EXISTS sp_agregar_columna$$
CREATE PROCEDURE sp_agregar_columna(
    IN p_tabla VARCHAR(64),
    IN p_columna VARCHAR(64),
    IN p_definicion VARCHAR(255)
)
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE()
          AND TABLE_NAME   = p_tabla
          AND COLUMN_NAME  = p_columna
    ) THEN
        SET @sql_alter = CONCAT('ALTER TABLE `', p_tabla, '` ADD COLUMN `', p_columna, '` ', p_definicion);
        PREPARE stmt FROM @sql_alter;
        EXECUTE stmt;
        DEALLOCATE PREPARE stmt;
    END IF;
END$$

DELIMITER ;

-- Para cancelar reservas pendientes después de 2 horas.
-- Las reservas que ya existen quedan con fecha_creacion NULL (el evento las
-- ignora); las nuevas reciben la fecha y hora actual automáticamente.
CALL sp_agregar_columna('reserva', 'fecha_creacion', 'DATETIME NULL');
ALTER TABLE reserva MODIFY fecha_creacion DATETIME NULL DEFAULT CURRENT_TIMESTAMP;

-- Para facturas vencidas, recargos y bloqueo de servicios
CALL sp_agregar_columna('factura', 'fecha_vencimiento', 'DATE NULL');
CALL sp_agregar_columna('factura', 'recargo', 'DECIMAL(10,2) NOT NULL DEFAULT 0');
CALL sp_agregar_columna('factura', 'recargo_aplicado', 'TINYINT(1) NOT NULL DEFAULT 0');

-- Facturas existentes: vencen 30 días después de emitirse.
-- (Se desactiva el modo seguro de Workbench solo para este UPDATE.)
SET @safe_anterior = @@SQL_SAFE_UPDATES;
SET SQL_SAFE_UPDATES = 0;
UPDATE factura
SET fecha_vencimiento = DATE_ADD(DATE(fecha_emision), INTERVAL 30 DAY)
WHERE fecha_vencimiento IS NULL;
SET SQL_SAFE_UPDATES = @safe_anterior;

CALL sp_agregar_columna('usuario_servicio', 'bloqueado', 'TINYINT(1) NOT NULL DEFAULT 0');

DROP PROCEDURE IF EXISTS sp_agregar_columna;


-- =====================================================
-- ACTIVAR EL PROGRAMADOR DE EVENTOS
-- =====================================================
-- Requiere privilegio SUPER o SYSTEM_VARIABLES_ADMIN. Si no lo tienes, pídele
-- al administrador del servidor que lo active.
SET GLOBAL event_scheduler = ON;

DELIMITER $$


-- =====================================================
-- MEMBRESÍAS
-- =====================================================

-- 1. Revisar diariamente membresías vencidas y actualizarlas a "Vencida".
DROP EVENT IF EXISTS ev_membresias_vencidas$$
CREATE EVENT ev_membresias_vencidas
ON SCHEDULE EVERY 1 DAY
    STARTS TIMESTAMP(CURDATE() + INTERVAL 1 DAY, '00:05:00')
ON COMPLETION PRESERVE ENABLE
COMMENT 'Membresias 1: marca como Vencida las membresias Activas cuya fecha_fin ya paso'
DO
BEGIN
    UPDATE membresia
    SET estado = 'Vencida'
    WHERE estado = 'Activa'
      AND fecha_fin < CURDATE();
END$$


-- 2. Enviar recordatorio de renovación 5 días antes de vencer la membresía.
DROP EVENT IF EXISTS ev_recordatorio_renovacion$$
CREATE EVENT ev_recordatorio_renovacion
ON SCHEDULE EVERY 1 DAY
    STARTS TIMESTAMP(CURDATE() + INTERVAL 1 DAY, '08:00:00')
ON COMPLETION PRESERVE ENABLE
COMMENT 'Membresias 2: avisa al usuario 5 dias antes del vencimiento'
DO
BEGIN
    INSERT INTO notificacion (destinatario, usuarioID, tipo, asunto, mensaje, referencia_id)
    SELECT
        'Usuario',
        m.usuarioID,
        'Recordatorio renovacion',
        'Tu membresia vence en 5 dias',
        CONCAT('Hola ', u.nombre, ', tu membresia ', m.tipo, ' vence el ',
               DATE_FORMAT(m.fecha_fin, '%d/%m/%Y'),
               '. Renuevala para no perder el acceso al coworking.'),
        m.membresiaID
    FROM membresia m
    JOIN usuario u ON u.usuarioID = m.usuarioID
    WHERE m.estado = 'Activa'
      AND m.fecha_fin = DATE_ADD(CURDATE(), INTERVAL 5 DAY)
      AND NOT EXISTS (
            SELECT 1
            FROM notificacion n
            WHERE n.tipo = 'Recordatorio renovacion'
              AND n.referencia_id = m.membresiaID
      );
END$$


-- 3. Suspender membresías inactivas después de 30 días sin pago.
--    Se suspende la membresía Activa cuyo usuario tiene una factura de
--    membresía pendiente de pago emitida hace más de 30 días.
DROP EVENT IF EXISTS ev_suspender_membresias_sin_pago$$
CREATE EVENT ev_suspender_membresias_sin_pago
ON SCHEDULE EVERY 1 DAY
    STARTS TIMESTAMP(CURDATE() + INTERVAL 1 DAY, '00:10:00')
ON COMPLETION PRESERVE ENABLE
COMMENT 'Membresias 3: suspende membresias con factura de membresia sin pagar hace mas de 30 dias'
DO
BEGIN
    UPDATE membresia m
    SET m.estado = 'Suspendida'
    WHERE m.estado = 'Activa'
      AND EXISTS (
            SELECT 1
            FROM factura f
            JOIN detalle_factura df ON df.facturaID = f.facturaID
            WHERE f.usuarioID = m.usuarioID
              AND f.estado = 'Pendiente'
              AND df.concepto LIKE 'Membres%'
              AND f.fecha_emision < DATE_SUB(NOW(), INTERVAL 30 DAY)
      );
END$$


-- 4. Generar reporte semanal de nuevas membresías al administrador.
--    Se ejecuta los lunes e incluye los 7 días anteriores.
DROP EVENT IF EXISTS ev_reporte_semanal_membresias$$
CREATE EVENT ev_reporte_semanal_membresias
ON SCHEDULE EVERY 1 WEEK
    STARTS TIMESTAMP(DATE_ADD(CURDATE(), INTERVAL (7 - WEEKDAY(CURDATE())) DAY), '07:00:00')
ON COMPLETION PRESERVE ENABLE
COMMENT 'Membresias 4: reporte semanal de nuevas membresias para el administrador'
DO
BEGIN
    DECLARE v_total INT DEFAULT 0;
    DECLARE v_detalle TEXT;

    SET SESSION group_concat_max_len = 65535;

    SELECT COUNT(*) INTO v_total
    FROM membresia
    WHERE fecha_inicio >= DATE_SUB(CURDATE(), INTERVAL 7 DAY)
      AND fecha_inicio <  CURDATE();

    SELECT GROUP_CONCAT(CONCAT(t.tipo, ': ', t.cantidad) ORDER BY t.tipo SEPARATOR ', ')
    INTO v_detalle
    FROM (
        SELECT tipo, COUNT(*) AS cantidad
        FROM membresia
        WHERE fecha_inicio >= DATE_SUB(CURDATE(), INTERVAL 7 DAY)
          AND fecha_inicio <  CURDATE()
        GROUP BY tipo
    ) t;

    INSERT INTO notificacion (destinatario, tipo, asunto, mensaje)
    VALUES (
        'Administrador',
        'Reporte semanal membresias',
        'Reporte semanal de nuevas membresias',
        CONCAT('Del ', DATE_FORMAT(DATE_SUB(CURDATE(), INTERVAL 7 DAY), '%d/%m/%Y'),
               ' al ', DATE_FORMAT(DATE_SUB(CURDATE(), INTERVAL 1 DAY), '%d/%m/%Y'),
               ' se registraron ', v_total, ' nuevas membresias. ',
               COALESCE(CONCAT('Detalle por tipo: ', v_detalle, '.'), 'Sin nuevas membresias.'))
    );
END$$


-- 5. Notificar membresías suspendidas cada día a recepción.
DROP EVENT IF EXISTS ev_notificar_membresias_suspendidas$$
CREATE EVENT ev_notificar_membresias_suspendidas
ON SCHEDULE EVERY 1 DAY
    STARTS TIMESTAMP(CURDATE() + INTERVAL 1 DAY, '08:00:00')
ON COMPLETION PRESERVE ENABLE
COMMENT 'Membresias 5: listado diario de membresias suspendidas para recepcion'
DO
BEGIN
    DECLARE v_total INT DEFAULT 0;
    DECLARE v_lista TEXT;

    SET SESSION group_concat_max_len = 65535;

    SELECT
        COUNT(*),
        GROUP_CONCAT(CONCAT(u.nombre, ' ', u.apellido, ' (', m.tipo, ')')
                     ORDER BY u.apellido SEPARATOR '; ')
    INTO v_total, v_lista
    FROM membresia m
    JOIN usuario u ON u.membresiaID = m.membresiaID
    WHERE m.estado = 'Suspendida';

    IF v_total > 0 THEN
        INSERT INTO notificacion (destinatario, tipo, asunto, mensaje)
        VALUES (
            'Recepcion',
            'Membresias suspendidas',
            CONCAT('Membresias suspendidas: ', v_total),
            CONCAT('Usuarios con membresia suspendida: ', v_lista, '.')
        );
    END IF;
END$$


-- =====================================================
-- RESERVAS
-- =====================================================

-- 1. Cancelar automáticamente reservas no confirmadas después de 2 horas.
--    Solo aplica a reservas con fecha_creacion (las anteriores a la migración
--    tienen NULL y no se tocan).
DROP EVENT IF EXISTS ev_cancelar_reservas_no_confirmadas$$
CREATE EVENT ev_cancelar_reservas_no_confirmadas
ON SCHEDULE EVERY 10 MINUTE
ON COMPLETION PRESERVE ENABLE
COMMENT 'Reservas 1: cancela reservas Pendientes con mas de 2 horas sin confirmar'
DO
BEGIN
    UPDATE reserva
    SET estado = 'Cancelada'
    WHERE estado = 'Pendiente'
      AND fecha_creacion IS NOT NULL
      AND fecha_creacion < DATE_SUB(NOW(), INTERVAL 2 HOUR);
END$$


-- 2. Enviar recordatorio 1 hora antes de la reserva a cada usuario.
DROP EVENT IF EXISTS ev_recordatorio_reserva$$
CREATE EVENT ev_recordatorio_reserva
ON SCHEDULE EVERY 5 MINUTE
ON COMPLETION PRESERVE ENABLE
COMMENT 'Reservas 2: recordatorio al usuario cuando su reserva confirmada empieza en menos de 1 hora'
DO
BEGIN
    INSERT INTO notificacion (destinatario, usuarioID, tipo, asunto, mensaje, referencia_id)
    SELECT
        'Usuario',
        r.usuarioID,
        'Recordatorio reserva',
        'Tu reserva comienza pronto',
        CONCAT('Tu reserva en ', e.nombre, ' comienza a las ',
               TIME_FORMAT(r.hora_inicio, '%H:%i'), ' del ',
               DATE_FORMAT(r.fecha_reserva, '%d/%m/%Y'), '.'),
        r.reservaID
    FROM reserva r
    JOIN espacio e ON e.espacioID = r.espacioID
    WHERE r.estado = 'Confirmada'
      AND TIMESTAMP(r.fecha_reserva, r.hora_inicio) BETWEEN NOW() AND DATE_ADD(NOW(), INTERVAL 1 HOUR)
      AND NOT EXISTS (
            SELECT 1
            FROM notificacion n
            WHERE n.tipo = 'Recordatorio reserva'
              AND n.referencia_id = r.reservaID
      );
END$$


-- 3. Eliminar reservas pasadas no asistidas después de 7 días.
--    Solo se borran reservas Pendiente o Confirmada que no tienen ninguna
--    asistencia ligada (las canceladas se conservan como historial).
DROP EVENT IF EXISTS ev_eliminar_reservas_no_asistidas$$
CREATE EVENT ev_eliminar_reservas_no_asistidas
ON SCHEDULE EVERY 1 DAY
    STARTS TIMESTAMP(CURDATE() + INTERVAL 1 DAY, '02:00:00')
ON COMPLETION PRESERVE ENABLE
COMMENT 'Reservas 3: borra reservas pasadas hace mas de 7 dias a las que nadie asistio'
DO
BEGIN
    DELETE FROM reserva
    WHERE fecha_reserva < DATE_SUB(CURDATE(), INTERVAL 7 DAY)
      AND estado IN ('Pendiente', 'Confirmada')
      AND NOT EXISTS (
            SELECT 1
            FROM asistencia a
            WHERE a.reservaID = reserva.reservaID
      );
END$$


-- 4. Generar reporte semanal de ocupación de espacios.
--    Se ejecuta los lunes e incluye los 7 días anteriores. Ocupación = horas
--    reservadas (Confirmada/Finalizada) sobre las horas disponibles por semana.
DROP EVENT IF EXISTS ev_reporte_semanal_ocupacion$$
CREATE EVENT ev_reporte_semanal_ocupacion
ON SCHEDULE EVERY 1 WEEK
    STARTS TIMESTAMP(DATE_ADD(CURDATE(), INTERVAL (7 - WEEKDAY(CURDATE())) DAY), '07:30:00')
ON COMPLETION PRESERVE ENABLE
COMMENT 'Reservas 4: reporte semanal de ocupacion por espacio para el administrador'
DO
BEGIN
    DECLARE v_detalle TEXT;

    SET SESSION group_concat_max_len = 65535;

    SELECT GROUP_CONCAT(
               CONCAT(t.nombre, ': ', ROUND(t.horas_reservadas, 1), ' h',
                      IF(t.horas_disponibles > 0,
                         CONCAT(' (', ROUND(t.horas_reservadas / t.horas_disponibles * 100, 1), '%)'),
                         ''))
               ORDER BY t.horas_reservadas DESC SEPARATOR ' | ')
    INTO v_detalle
    FROM (
        SELECT
            e.nombre,
            COALESCE(SUM(r.duracion), 0) / 60 AS horas_reservadas,
            (SELECT SUM(TIME_TO_SEC(TIMEDIFF(h.hora_fin, h.hora_inicio))) / 3600
             FROM horario_disponibilidad h
             WHERE h.espacioID = e.espacioID) AS horas_disponibles
        FROM espacio e
        LEFT JOIN reserva r ON r.espacioID = e.espacioID
                           AND r.estado IN ('Confirmada', 'Finalizada')
                           AND r.fecha_reserva >= DATE_SUB(CURDATE(), INTERVAL 7 DAY)
                           AND r.fecha_reserva <  CURDATE()
        GROUP BY e.espacioID, e.nombre
    ) t;

    INSERT INTO notificacion (destinatario, tipo, asunto, mensaje)
    VALUES (
        'Administrador',
        'Reporte semanal ocupacion',
        'Reporte semanal de ocupacion de espacios',
        CONCAT('Ocupacion del ', DATE_FORMAT(DATE_SUB(CURDATE(), INTERVAL 7 DAY), '%d/%m/%Y'),
               ' al ', DATE_FORMAT(DATE_SUB(CURDATE(), INTERVAL 1 DAY), '%d/%m/%Y'),
               ' (horas reservadas y % sobre horas disponibles): ',
               COALESCE(v_detalle, 'sin espacios registrados'), '.')
    );
END$$


-- 5. Liberar reservas bloqueadas si no se inicia en los primeros 15 minutos.
--    Reserva confirmada cuyo horario ya empezó hace más de 15 minutos, aún no
--    termina y no tiene ninguna entrada autorizada: se cancela y se avisa.
DROP EVENT IF EXISTS ev_liberar_reservas_no_iniciadas$$
CREATE EVENT ev_liberar_reservas_no_iniciadas
ON SCHEDULE EVERY 5 MINUTE
ON COMPLETION PRESERVE ENABLE
COMMENT 'Reservas 5: cancela reservas confirmadas que no se iniciaron en los primeros 15 minutos'
DO
BEGIN
    INSERT INTO notificacion (destinatario, usuarioID, tipo, asunto, mensaje, referencia_id)
    SELECT
        'Usuario',
        r.usuarioID,
        'Reserva liberada',
        'Tu reserva fue liberada',
        CONCAT('Tu reserva en ', e.nombre, ' de las ', TIME_FORMAT(r.hora_inicio, '%H:%i'),
               ' fue liberada porque no se inicio en los primeros 15 minutos.'),
        r.reservaID
    FROM reserva r
    JOIN espacio e ON e.espacioID = r.espacioID
    WHERE r.estado = 'Confirmada'
      AND DATE_ADD(TIMESTAMP(r.fecha_reserva, r.hora_inicio), INTERVAL 15 MINUTE) < NOW()
      AND TIMESTAMP(r.fecha_reserva, r.hora_fin) > NOW()
      AND NOT EXISTS (
            SELECT 1
            FROM asistencia a
            WHERE a.reservaID = r.reservaID
              AND a.resultado_validacion = 'Autorizado'
      );

    UPDATE reserva r
    SET r.estado = 'Cancelada'
    WHERE r.estado = 'Confirmada'
      AND DATE_ADD(TIMESTAMP(r.fecha_reserva, r.hora_inicio), INTERVAL 15 MINUTE) < NOW()
      AND TIMESTAMP(r.fecha_reserva, r.hora_fin) > NOW()
      AND NOT EXISTS (
            SELECT 1
            FROM asistencia a
            WHERE a.reservaID = r.reservaID
              AND a.resultado_validacion = 'Autorizado'
      );
END$$


-- =====================================================
-- PAGOS Y FACTURACIÓN
-- =====================================================

-- 1. Enviar recordatorio de pago pendiente cada 3 días.
DROP EVENT IF EXISTS ev_recordatorio_pago_pendiente$$
CREATE EVENT ev_recordatorio_pago_pendiente
ON SCHEDULE EVERY 3 DAY
    STARTS TIMESTAMP(CURDATE() + INTERVAL 1 DAY, '09:00:00')
ON COMPLETION PRESERVE ENABLE
COMMENT 'Pagos 1: recordatorio cada 3 dias por cada factura pendiente'
DO
BEGIN
    INSERT INTO notificacion (destinatario, usuarioID, tipo, asunto, mensaje, referencia_id)
    SELECT
        'Usuario',
        f.usuarioID,
        'Recordatorio pago',
        CONCAT('Factura ', f.numero_factura, ' pendiente de pago'),
        CONCAT('Hola ', u.nombre, ', tienes pendiente la factura ', f.numero_factura,
               ' por $', FORMAT(f.total, 2),
               IF(f.fecha_vencimiento IS NOT NULL,
                  CONCAT(' con vencimiento el ', DATE_FORMAT(f.fecha_vencimiento, '%d/%m/%Y')),
                  ''),
               '.'),
        f.facturaID
    FROM factura f
    JOIN usuario u ON u.usuarioID = f.usuarioID
    WHERE f.estado = 'Pendiente';
END$$


-- 2. Bloquear servicios adicionales si existen facturas vencidas mayores a 10 días.
--    Se avisa al usuario y se bloquean sus servicios adicionales.
DROP EVENT IF EXISTS ev_bloquear_servicios_facturas_vencidas$$
CREATE EVENT ev_bloquear_servicios_facturas_vencidas
ON SCHEDULE EVERY 1 DAY
    STARTS TIMESTAMP(CURDATE() + INTERVAL 1 DAY, '00:20:00')
ON COMPLETION PRESERVE ENABLE
COMMENT 'Pagos 2: bloquea servicios adicionales de usuarios con facturas vencidas hace mas de 10 dias'
DO
BEGIN
    INSERT INTO notificacion (destinatario, usuarioID, tipo, asunto, mensaje)
    SELECT DISTINCT
        'Usuario',
        us.usuarioID,
        'Servicios bloqueados',
        'Tus servicios adicionales fueron bloqueados',
        'Tienes facturas vencidas hace mas de 10 dias. Paga tus facturas pendientes para reactivar tus servicios adicionales.'
    FROM usuario_servicio us
    WHERE us.bloqueado = 0
      AND EXISTS (
            SELECT 1
            FROM factura f
            WHERE f.usuarioID = us.usuarioID
              AND f.estado = 'Pendiente'
              AND f.fecha_vencimiento < DATE_SUB(CURDATE(), INTERVAL 10 DAY)
      );

    UPDATE usuario_servicio us
    SET us.bloqueado = 1
    WHERE us.bloqueado = 0
      AND EXISTS (
            SELECT 1
            FROM factura f
            WHERE f.usuarioID = us.usuarioID
              AND f.estado = 'Pendiente'
              AND f.fecha_vencimiento < DATE_SUB(CURDATE(), INTERVAL 10 DAY)
      );
END$$


-- 3. Generar resumen de facturación mensual automáticamente.
--    Se ejecuta el día 1 de cada mes y resume el mes anterior.
DROP EVENT IF EXISTS ev_resumen_facturacion_mensual$$
CREATE EVENT ev_resumen_facturacion_mensual
ON SCHEDULE EVERY 1 MONTH
    STARTS TIMESTAMP(DATE_ADD(LAST_DAY(CURDATE()), INTERVAL 1 DAY), '00:30:00')
ON COMPLETION PRESERVE ENABLE
COMMENT 'Pagos 3: resumen de facturacion del mes anterior para el administrador'
DO
BEGIN
    DECLARE v_inicio DATE;
    DECLARE v_fin DATE;
    DECLARE v_emitidas INT DEFAULT 0;
    DECLARE v_facturado DECIMAL(14,2) DEFAULT 0;
    DECLARE v_pagado DECIMAL(14,2) DEFAULT 0;
    DECLARE v_pendiente DECIMAL(14,2) DEFAULT 0;
    DECLARE v_canceladas INT DEFAULT 0;

    SET v_fin    = DATE_SUB(CURDATE(), INTERVAL (DAYOFMONTH(CURDATE()) - 1) DAY);
    SET v_inicio = DATE_SUB(v_fin, INTERVAL 1 MONTH);

    SELECT
        COUNT(*),
        COALESCE(SUM(CASE WHEN estado <> 'Cancelada' THEN total END), 0),
        COALESCE(SUM(CASE WHEN estado = 'Pagada'    THEN total END), 0),
        COALESCE(SUM(CASE WHEN estado = 'Pendiente' THEN total END), 0),
        COALESCE(SUM(estado = 'Cancelada'), 0)
    INTO v_emitidas, v_facturado, v_pagado, v_pendiente, v_canceladas
    FROM factura
    WHERE fecha_emision >= v_inicio
      AND fecha_emision <  v_fin;

    INSERT INTO notificacion (destinatario, tipo, asunto, mensaje)
    VALUES (
        'Administrador',
        'Resumen facturacion mensual',
        CONCAT('Resumen de facturacion ', DATE_FORMAT(v_inicio, '%Y-%m')),
        CONCAT('Facturas emitidas: ', v_emitidas,
               '. Facturado (sin canceladas): $', FORMAT(v_facturado, 2),
               '. Pagado: $', FORMAT(v_pagado, 2),
               '. Pendiente: $', FORMAT(v_pendiente, 2),
               '. Facturas canceladas: ', v_canceladas, '.')
    );
END$$


-- 4. Aplicar recargos automáticos a facturas vencidas después de 15 días.
--    El porcentaje de recargo (5 %) se cambia en v_porcentaje. El recargo se
--    suma al total, queda como línea en detalle_factura y se aplica una sola
--    vez por factura (recargo_aplicado).
DROP EVENT IF EXISTS ev_recargo_facturas_vencidas$$
CREATE EVENT ev_recargo_facturas_vencidas
ON SCHEDULE EVERY 1 DAY
    STARTS TIMESTAMP(CURDATE() + INTERVAL 1 DAY, '00:30:00')
ON COMPLETION PRESERVE ENABLE
COMMENT 'Pagos 4: aplica un recargo unico a facturas pendientes vencidas hace mas de 15 dias'
DO
BEGIN
    DECLARE v_porcentaje DECIMAL(5,2) DEFAULT 5.00;

    START TRANSACTION;

    INSERT INTO detalle_factura (facturaID, concepto, cantidad, precio_unitario, subtotal)
    SELECT
        f.facturaID,
        CONCAT('Recargo por mora (', v_porcentaje, '%)'),
        1,
        ROUND(f.total * v_porcentaje / 100, 2),
        ROUND(f.total * v_porcentaje / 100, 2)
    FROM factura f
    WHERE f.estado = 'Pendiente'
      AND f.recargo_aplicado = 0
      AND f.fecha_vencimiento < DATE_SUB(CURDATE(), INTERVAL 15 DAY);

    UPDATE factura
    SET recargo = ROUND(total * v_porcentaje / 100, 2),
        total = total + ROUND(total * v_porcentaje / 100, 2),
        recargo_aplicado = 1
    WHERE estado = 'Pendiente'
      AND recargo_aplicado = 0
      AND fecha_vencimiento < DATE_SUB(CURDATE(), INTERVAL 15 DAY);

    COMMIT;
END$$


-- 5. Enviar al contador un reporte de ingresos acumulados cada fin de mes.
--    El evento corre todos los días a las 23:50 y solo actúa el último día del mes.
DROP EVENT IF EXISTS ev_reporte_ingresos_contador$$
CREATE EVENT ev_reporte_ingresos_contador
ON SCHEDULE EVERY 1 DAY
    STARTS TIMESTAMP(CURDATE() + INTERVAL 1 DAY, '23:50:00')
ON COMPLETION PRESERVE ENABLE
COMMENT 'Pagos 5: ultimo dia de cada mes envia al contador los ingresos del mes y del anio'
DO
BEGIN
    DECLARE v_pagos_mes INT DEFAULT 0;
    DECLARE v_ingresos_mes DECIMAL(14,2) DEFAULT 0;
    DECLARE v_ingresos_anio DECIMAL(14,2) DEFAULT 0;

    IF CURDATE() = LAST_DAY(CURDATE()) THEN
        SELECT COUNT(*), COALESCE(SUM(monto), 0)
        INTO v_pagos_mes, v_ingresos_mes
        FROM pago
        WHERE estado = 'Pagado'
          AND YEAR(fecha_pago)  = YEAR(CURDATE())
          AND MONTH(fecha_pago) = MONTH(CURDATE());

        SELECT COALESCE(SUM(monto), 0)
        INTO v_ingresos_anio
        FROM pago
        WHERE estado = 'Pagado'
          AND YEAR(fecha_pago) = YEAR(CURDATE());

        INSERT INTO notificacion (destinatario, tipo, asunto, mensaje)
        VALUES (
            'Contador',
            'Reporte ingresos fin de mes',
            CONCAT('Ingresos acumulados ', DATE_FORMAT(CURDATE(), '%Y-%m')),
            CONCAT('Pagos realizados en el mes: ', v_pagos_mes,
                   '. Ingresos del mes: $', FORMAT(v_ingresos_mes, 2),
                   '. Ingresos acumulados del anio: $', FORMAT(v_ingresos_anio, 2), '.')
        );
    END IF;
END$$


-- =====================================================
-- ACCESOS Y ASISTENCIAS
-- =====================================================

-- 1. Eliminar accesos antiguos (más de 1 año) automáticamente.
--    Se borran los registros de ingreso (asistencia). La tabla acceso guarda
--    las credenciales RFID/QR vigentes de los usuarios y no se toca.
DROP EVENT IF EXISTS ev_eliminar_accesos_antiguos$$
CREATE EVENT ev_eliminar_accesos_antiguos
ON SCHEDULE EVERY 1 DAY
    STARTS TIMESTAMP(CURDATE() + INTERVAL 1 DAY, '03:00:00')
ON COMPLETION PRESERVE ENABLE
COMMENT 'Accesos 1: borra registros de asistencia de mas de 1 anio'
DO
BEGIN
    DELETE FROM asistencia
    WHERE fecha < DATE_SUB(CURDATE(), INTERVAL 1 YEAR);
END$$


-- 2. Enviar reporte diario de asistencias al administrador.
DROP EVENT IF EXISTS ev_reporte_diario_asistencias$$
CREATE EVENT ev_reporte_diario_asistencias
ON SCHEDULE EVERY 1 DAY
    STARTS TIMESTAMP(CURDATE() + INTERVAL 1 DAY, '23:55:00')
ON COMPLETION PRESERVE ENABLE
COMMENT 'Accesos 2: reporte diario de asistencias para el administrador'
DO
BEGIN
    DECLARE v_total INT DEFAULT 0;
    DECLARE v_autorizados INT DEFAULT 0;
    DECLARE v_rechazados INT DEFAULT 0;
    DECLARE v_usuarios INT DEFAULT 0;
    DECLARE v_sin_salida INT DEFAULT 0;

    SELECT
        COUNT(*),
        COALESCE(SUM(resultado_validacion = 'Autorizado'), 0),
        COALESCE(SUM(resultado_validacion = 'Rechazado'), 0),
        COUNT(DISTINCT usuarioID),
        COALESCE(SUM(resultado_validacion = 'Autorizado' AND hora_salida IS NULL), 0)
    INTO v_total, v_autorizados, v_rechazados, v_usuarios, v_sin_salida
    FROM asistencia
    WHERE fecha = CURDATE();

    INSERT INTO notificacion (destinatario, tipo, asunto, mensaje)
    VALUES (
        'Administrador',
        'Reporte diario asistencias',
        CONCAT('Asistencias del ', DATE_FORMAT(CURDATE(), '%d/%m/%Y')),
        CONCAT('Accesos totales: ', v_total,
               '. Autorizados: ', v_autorizados,
               '. Rechazados: ', v_rechazados,
               '. Usuarios distintos: ', v_usuarios,
               '. Entradas sin salida registrada: ', v_sin_salida, '.')
    );
END$$


-- 3. Generar reporte semanal de usuarios inactivos (sin accesos).
--    Se ejecuta los lunes: usuarios sin ninguna entrada autorizada en los 7
--    días anteriores.
DROP EVENT IF EXISTS ev_reporte_semanal_usuarios_inactivos$$
CREATE EVENT ev_reporte_semanal_usuarios_inactivos
ON SCHEDULE EVERY 1 WEEK
    STARTS TIMESTAMP(DATE_ADD(CURDATE(), INTERVAL (7 - WEEKDAY(CURDATE())) DAY), '08:00:00')
ON COMPLETION PRESERVE ENABLE
COMMENT 'Accesos 3: reporte semanal de usuarios sin accesos en los ultimos 7 dias'
DO
BEGIN
    DECLARE v_total INT DEFAULT 0;
    DECLARE v_lista TEXT;

    SET SESSION group_concat_max_len = 65535;

    SELECT
        COUNT(*),
        GROUP_CONCAT(CONCAT(u.nombre, ' ', u.apellido) ORDER BY u.apellido, u.nombre SEPARATOR ', ')
    INTO v_total, v_lista
    FROM usuario u
    WHERE NOT EXISTS (
            SELECT 1
            FROM asistencia a
            WHERE a.usuarioID = u.usuarioID
              AND a.resultado_validacion = 'Autorizado'
              AND a.fecha >= DATE_SUB(CURDATE(), INTERVAL 7 DAY)
    );

    INSERT INTO notificacion (destinatario, tipo, asunto, mensaje)
    VALUES (
        'Administrador',
        'Reporte semanal inactivos',
        CONCAT('Usuarios sin accesos en la ultima semana: ', v_total),
        CONCAT('Usuarios sin accesos entre el ', DATE_FORMAT(DATE_SUB(CURDATE(), INTERVAL 7 DAY), '%d/%m/%Y'),
               ' y el ', DATE_FORMAT(DATE_SUB(CURDATE(), INTERVAL 1 DAY), '%d/%m/%Y'), ': ',
               COALESCE(v_lista, 'ninguno'), '.')
    );
END$$


-- 4. Alertar accesos fuera de horario laboral cada día.
--    Horario laboral: 07:00 a 20:00 (cámbialo en v_inicio y v_fin).
DROP EVENT IF EXISTS ev_alerta_accesos_fuera_horario$$
CREATE EVENT ev_alerta_accesos_fuera_horario
ON SCHEDULE EVERY 1 DAY
    STARTS TIMESTAMP(CURDATE() + INTERVAL 1 DAY, '23:50:00')
ON COMPLETION PRESERVE ENABLE
COMMENT 'Accesos 4: alerta diaria de entradas fuera del horario laboral'
DO
BEGIN
    DECLARE v_inicio TIME DEFAULT '07:00:00';
    DECLARE v_fin TIME DEFAULT '20:00:00';
    DECLARE v_total INT DEFAULT 0;
    DECLARE v_lista TEXT;

    SET SESSION group_concat_max_len = 65535;

    SELECT
        COUNT(*),
        GROUP_CONCAT(CONCAT(u.nombre, ' ', u.apellido, ' (', TIME_FORMAT(a.hora_entrada, '%H:%i'), ')')
                     ORDER BY a.hora_entrada SEPARATOR '; ')
    INTO v_total, v_lista
    FROM asistencia a
    JOIN usuario u ON u.usuarioID = a.usuarioID
    WHERE a.fecha = CURDATE()
      AND (a.hora_entrada < v_inicio OR a.hora_entrada > v_fin);

    IF v_total > 0 THEN
        INSERT INTO notificacion (destinatario, tipo, asunto, mensaje)
        VALUES (
            'Administrador',
            'Alerta acceso fuera de horario',
            CONCAT('Accesos fuera de horario el ', DATE_FORMAT(CURDATE(), '%d/%m/%Y'), ': ', v_total),
            CONCAT('Entradas fuera del horario laboral (', TIME_FORMAT(v_inicio, '%H:%i'), ' a ',
                   TIME_FORMAT(v_fin, '%H:%i'), '): ', v_lista, '.')
        );
    END IF;
END$$


-- 5. Enviar reporte de top 10 usuarios más frecuentes cada mes.
--    Se ejecuta el día 1 de cada mes y analiza el mes anterior.
DROP EVENT IF EXISTS ev_reporte_mensual_top10_frecuentes$$
CREATE EVENT ev_reporte_mensual_top10_frecuentes
ON SCHEDULE EVERY 1 MONTH
    STARTS TIMESTAMP(DATE_ADD(LAST_DAY(CURDATE()), INTERVAL 1 DAY), '01:00:00')
ON COMPLETION PRESERVE ENABLE
COMMENT 'Accesos 5: top 10 de usuarios con mas asistencias del mes anterior'
DO
BEGIN
    DECLARE v_inicio DATE;
    DECLARE v_fin DATE;
    DECLARE v_lista TEXT;

    SET SESSION group_concat_max_len = 65535;

    SET v_fin    = DATE_SUB(CURDATE(), INTERVAL (DAYOFMONTH(CURDATE()) - 1) DAY);
    SET v_inicio = DATE_SUB(v_fin, INTERVAL 1 MONTH);

    SELECT GROUP_CONCAT(CONCAT(t.nombre, ' ', t.apellido, ' (', t.asistencias, ')')
                        ORDER BY t.asistencias DESC, t.apellido SEPARATOR ' | ')
    INTO v_lista
    FROM (
        SELECT u.nombre, u.apellido, COUNT(*) AS asistencias
        FROM asistencia a
        JOIN usuario u ON u.usuarioID = a.usuarioID
        WHERE a.resultado_validacion = 'Autorizado'
          AND a.fecha >= v_inicio
          AND a.fecha <  v_fin
        GROUP BY u.usuarioID, u.nombre, u.apellido
        ORDER BY asistencias DESC, u.apellido
        LIMIT 10
    ) t;

    INSERT INTO notificacion (destinatario, tipo, asunto, mensaje)
    VALUES (
        'Administrador',
        'Reporte mensual top 10',
        CONCAT('Top 10 usuarios mas frecuentes ', DATE_FORMAT(v_inicio, '%Y-%m')),
        CONCAT('Usuarios con mas asistencias (asistencias entre parentesis): ',
               COALESCE(v_lista, 'sin asistencias en el mes'), '.')
    );
END$$

DELIMITER ;


-- =====================================================
-- VERIFICACIÓN (opcional)
-- =====================================================
-- SELECT event_name, status, interval_value, interval_field, starts, last_executed
-- FROM information_schema.EVENTS
-- WHERE event_schema = 'coworking'
-- ORDER BY event_name;
--
-- SELECT * FROM notificacion ORDER BY fecha_creacion DESC;
