USE coworking;

-- =====================================================
-- PROCEDIMIENTOS ALMACENADOS (20)
-- =====================================================
-- Ejecutar después de 01_estructura.sql, 01_datos_iniciales.sql y
-- 06_eventos.sql (ese archivo crea la tabla notificacion y las columnas
-- factura.fecha_vencimiento, factura.recargo, factura.recargo_aplicado,
-- reserva.fecha_creacion y usuario_servicio.bloqueado que usan estos
-- procedimientos).
-- Se puede ejecutar varias veces. Requiere MySQL 8 y un cliente que soporte
-- DELIMITER (consola mysql o MySQL Workbench).
--
-- Convenciones:
--  * fecha_fin de una membresía = fecha_inicio + duración - 1 días
--    (igual que los datos de ejemplo: mensual 01/09 a 30/09).
--  * IVA 19 % en las facturas que crean estos procedimientos.
--  * Los errores de validación se lanzan con SIGNAL SQLSTATE '45000' y un
--    mensaje; los procedimientos con varias escrituras usan transacción.
--  * Parámetros OUT: se leen después del CALL, por ejemplo
--      CALL sp_registrar_membresia(1, 2, NULL, @id);  SELECT @id;
--  * Además de los 20 procedimientos pedidos hay uno auxiliar,
--    sp_aux_numero_factura, que genera el siguiente número de factura.
-- =====================================================


-- =====================================================
-- PRERREQUISITOS
-- =====================================================

-- Registro de reembolsos (lo usa sp_cancelar_reserva_con_reembolso).
CREATE TABLE IF NOT EXISTS reembolso (
    reembolsoID INT AUTO_INCREMENT PRIMARY KEY,
    reservaID INT NOT NULL,
    pagoID INT NULL,
    porcentaje DECIMAL(5,2) NOT NULL,
    monto DECIMAL(10,2) NOT NULL,
    motivo VARCHAR(150),
    fecha_solicitud DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    estado ENUM('Pendiente', 'Procesado') NOT NULL DEFAULT 'Pendiente',
    FOREIGN KEY (reservaID) REFERENCES reserva(reservaID),
    FOREIGN KEY (pagoID) REFERENCES pago(pagoID)
);

-- Estado "No Show" para reservas confirmadas a las que nadie asistió.
ALTER TABLE reserva
    MODIFY estado ENUM('Pendiente', 'Confirmada', 'Cancelada', 'Finalizada', 'No Show') NOT NULL;


DELIMITER $$


-- =====================================================
-- AUXILIAR: número de factura
-- =====================================================
-- Devuelve el siguiente número con el formato FAC-AAAA-NNNN. La columna
-- numero_factura es UNIQUE, así que una colisión por concurrencia fallaría
-- en lugar de duplicar.
DROP PROCEDURE IF EXISTS sp_aux_numero_factura$$
CREATE PROCEDURE sp_aux_numero_factura(OUT p_numero VARCHAR(30))
BEGIN
    DECLARE v_prefijo VARCHAR(10);

    SET v_prefijo = CONCAT('FAC-', YEAR(CURDATE()), '-');

    SELECT CONCAT(v_prefijo,
                  LPAD(COALESCE(MAX(CAST(SUBSTRING(numero_factura, CHAR_LENGTH(v_prefijo) + 1) AS UNSIGNED)), 0) + 1,
                       4, '0'))
    INTO p_numero
    FROM factura
    WHERE numero_factura LIKE CONCAT(v_prefijo, '%');
END$$


-- =====================================================
-- MEMBRESÍAS (4)
-- =====================================================

-- 1. Registrar nueva membresía y asignarla a un usuario.
--    Inserta la membresía con fecha de inicio, fecha de fin (según la
--    duración del tipo) y estado inicial 'Activa', y la deja como membresía
--    actual del usuario. Si p_fecha_inicio es NULL se usa la fecha de hoy.
--    Falla si el usuario ya tiene una membresía activa (en ese caso se usa
--    sp_renovar_membresia).
DROP PROCEDURE IF EXISTS sp_registrar_membresia$$
CREATE PROCEDURE sp_registrar_membresia(
    IN  p_usuarioID    INT,
    IN  p_tipoID       INT,
    IN  p_fecha_inicio DATE,
    OUT p_membresiaID  INT
)
BEGIN
    DECLARE v_nombre_tipo VARCHAR(20);
    DECLARE v_duracion INT;
    DECLARE v_inicio DATE;

    IF NOT EXISTS (SELECT 1 FROM usuario WHERE usuarioID = p_usuarioID) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El usuario no existe';
    END IF;

    SELECT nombre, duracion
    INTO v_nombre_tipo, v_duracion
    FROM tipo_membresia
    WHERE tipoID = p_tipoID;

    IF v_nombre_tipo IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El tipo de membresia no existe';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM membresia
        WHERE usuarioID = p_usuarioID
          AND estado = 'Activa'
          AND fecha_fin >= CURDATE()
    ) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'El usuario ya tiene una membresia activa; use sp_renovar_membresia';
    END IF;

    SET v_inicio = COALESCE(p_fecha_inicio, CURDATE());

    INSERT INTO membresia (tipo, estado, fecha_inicio, fecha_fin, usuarioID, tipoID)
    VALUES (v_nombre_tipo, 'Activa', v_inicio,
            DATE_ADD(v_inicio, INTERVAL v_duracion - 1 DAY),
            p_usuarioID, p_tipoID);

    SET p_membresiaID = LAST_INSERT_ID();

    UPDATE usuario
    SET membresiaID = p_membresiaID
    WHERE usuarioID = p_usuarioID;
END$$


-- 2. Renovar una membresía existente.
--    Extiende la vigencia según la duración del tipo contratado: si aún está
--    vigente suma la duración a la fecha_fin actual; si ya venció, cuenta
--    desde hoy. No renueva membresías suspendidas.
DROP PROCEDURE IF EXISTS sp_renovar_membresia$$
CREATE PROCEDURE sp_renovar_membresia(
    IN  p_membresiaID     INT,
    OUT p_nueva_fecha_fin DATE
)
BEGIN
    DECLARE v_estado VARCHAR(20);
    DECLARE v_fin DATE;
    DECLARE v_duracion INT;

    SELECT m.estado, m.fecha_fin, t.duracion
    INTO v_estado, v_fin, v_duracion
    FROM membresia m
    JOIN tipo_membresia t ON t.tipoID = m.tipoID
    WHERE m.membresiaID = p_membresiaID;

    IF v_estado IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La membresia no existe';
    END IF;

    IF v_estado = 'Suspendida' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Membresia suspendida: regularice los pagos antes de renovar';
    END IF;

    IF v_fin >= CURDATE() THEN
        SET p_nueva_fecha_fin = DATE_ADD(v_fin, INTERVAL v_duracion DAY);
    ELSE
        SET p_nueva_fecha_fin = DATE_ADD(CURDATE(), INTERVAL v_duracion - 1 DAY);
    END IF;

    UPDATE membresia
    SET fecha_fin = p_nueva_fecha_fin,
        estado = 'Activa'
    WHERE membresiaID = p_membresiaID;
END$$


-- 3. Actualizar estado de membresías vencidas.
--    Marca como 'Vencida' las membresías Activas cuya fecha_fin ya pasó.
DROP PROCEDURE IF EXISTS sp_actualizar_membresias_vencidas$$
CREATE PROCEDURE sp_actualizar_membresias_vencidas(OUT p_actualizadas INT)
BEGIN
    UPDATE membresia
    SET estado = 'Vencida'
    WHERE estado = 'Activa'
      AND fecha_fin < CURDATE();

    SET p_actualizadas = ROW_COUNT();
END$$


-- 4. Suspender membresías con facturas impagas por más de X días.
--    Suspende las membresías Activas de usuarios con alguna factura
--    Pendiente emitida hace más de p_dias días y les deja un aviso.
DROP PROCEDURE IF EXISTS sp_suspender_membresias_impagas$$
CREATE PROCEDURE sp_suspender_membresias_impagas(
    IN  p_dias         INT,
    OUT p_suspendidas  INT
)
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    IF p_dias IS NULL OR p_dias < 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'p_dias debe ser un numero mayor o igual a 0';
    END IF;

    START TRANSACTION;

    INSERT INTO notificacion (destinatario, usuarioID, tipo, asunto, mensaje, referencia_id)
    SELECT
        'Usuario',
        m.usuarioID,
        'Membresia suspendida',
        'Tu membresia fue suspendida',
        CONCAT('Tu membresia ', m.tipo, ' fue suspendida por tener facturas impagas de mas de ',
               p_dias, ' dias.'),
        m.membresiaID
    FROM membresia m
    WHERE m.estado = 'Activa'
      AND EXISTS (
            SELECT 1
            FROM factura f
            WHERE f.usuarioID = m.usuarioID
              AND f.estado = 'Pendiente'
              AND f.fecha_emision < DATE_SUB(NOW(), INTERVAL p_dias DAY)
      );

    UPDATE membresia m
    SET m.estado = 'Suspendida'
    WHERE m.estado = 'Activa'
      AND EXISTS (
            SELECT 1
            FROM factura f
            WHERE f.usuarioID = m.usuarioID
              AND f.estado = 'Pendiente'
              AND f.fecha_emision < DATE_SUB(NOW(), INTERVAL p_dias DAY)
      );

    SET p_suspendidas = ROW_COUNT();

    COMMIT;
END$$


-- =====================================================
-- RESERVAS Y ESPACIOS (5)
-- =====================================================

-- 1. Verificar disponibilidad de un espacio antes de crear reserva.
--    p_disponible = 1 si no hay solapamiento con reservas Pendientes o
--    Confirmadas del mismo espacio y el espacio no está en mantenimiento.
--    p_mensaje explica el resultado.
DROP PROCEDURE IF EXISTS sp_verificar_disponibilidad_espacio$$
CREATE PROCEDURE sp_verificar_disponibilidad_espacio(
    IN  p_espacioID   INT,
    IN  p_fecha       DATE,
    IN  p_hora_inicio TIME,
    IN  p_hora_fin    TIME,
    OUT p_disponible  TINYINT,
    OUT p_mensaje     VARCHAR(100)
)
BEGIN
    DECLARE v_estado VARCHAR(20);

    SET p_disponible = 0;

    IF p_hora_inicio IS NULL OR p_hora_fin IS NULL OR p_hora_inicio >= p_hora_fin THEN
        SET p_mensaje = 'La hora de inicio debe ser anterior a la hora de fin';
    ELSE
        SELECT estado INTO v_estado FROM espacio WHERE espacioID = p_espacioID;

        IF v_estado IS NULL THEN
            SET p_mensaje = 'El espacio no existe';
        ELSEIF v_estado = 'Mantenimiento' THEN
            SET p_mensaje = 'El espacio esta en mantenimiento';
        ELSEIF EXISTS (
            SELECT 1
            FROM reserva r
            WHERE r.espacioID = p_espacioID
              AND r.fecha_reserva = p_fecha
              AND r.estado IN ('Pendiente', 'Confirmada')
              AND p_hora_inicio < r.hora_fin
              AND p_hora_fin    > r.hora_inicio
        ) THEN
            SET p_mensaje = 'El espacio ya tiene una reserva en ese horario';
        ELSE
            SET p_disponible = 1;
            SET p_mensaje = 'Disponible';
        END IF;
    END IF;
END$$


-- 2. Crear una nueva reserva de espacio.
--    Inserta la reserva en estado 'Pendiente' ligada al usuario y al espacio.
--    Bloquea la fila del espacio durante la transacción para que dos
--    reservas simultáneas no se solapen.
DROP PROCEDURE IF EXISTS sp_crear_reserva$$
CREATE PROCEDURE sp_crear_reserva(
    IN  p_usuarioID   INT,
    IN  p_espacioID   INT,
    IN  p_fecha       DATE,
    IN  p_hora_inicio TIME,
    IN  p_hora_fin    TIME,
    OUT p_reservaID   INT
)
BEGIN
    DECLARE v_disponible TINYINT DEFAULT 0;
    DECLARE v_mensaje VARCHAR(100);
    DECLARE v_bloqueo INT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    IF NOT EXISTS (SELECT 1 FROM usuario WHERE usuarioID = p_usuarioID) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El usuario no existe';
    END IF;

    IF p_fecha IS NULL OR p_fecha < CURDATE() THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La fecha de la reserva no puede ser pasada';
    END IF;

    START TRANSACTION;

    SELECT espacioID INTO v_bloqueo
    FROM espacio
    WHERE espacioID = p_espacioID
    FOR UPDATE;

    CALL sp_verificar_disponibilidad_espacio(p_espacioID, p_fecha, p_hora_inicio, p_hora_fin,
                                             v_disponible, v_mensaje);

    IF v_disponible = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_mensaje;
    END IF;

    INSERT INTO reserva (fecha_reserva, hora_inicio, hora_fin, duracion, estado, espacioID, usuarioID)
    VALUES (p_fecha, p_hora_inicio, p_hora_fin,
            TIME_TO_SEC(TIMEDIFF(p_hora_fin, p_hora_inicio)) DIV 60,
            'Pendiente', p_espacioID, p_usuarioID);

    SET p_reservaID = LAST_INSERT_ID();

    COMMIT;
END$$


-- 3. Confirmar reserva con pago.
--    Registra el pago (p_monto es el valor antes de IVA), genera la factura
--    pagada con su detalle y cambia la reserva de 'Pendiente' a 'Confirmada'.
--    El monto no sale del modelo (espacio no tiene precio), por eso se recibe.
DROP PROCEDURE IF EXISTS sp_confirmar_reserva_con_pago$$
CREATE PROCEDURE sp_confirmar_reserva_con_pago(
    IN  p_reservaID   INT,
    IN  p_monto       DECIMAL(10,2),
    IN  p_metodo_pago VARCHAR(20),
    IN  p_referencia  VARCHAR(100),
    OUT p_pagoID      INT,
    OUT p_facturaID   INT
)
BEGIN
    DECLARE v_estado VARCHAR(20);
    DECLARE v_usuario INT;
    DECLARE v_espacio VARCHAR(100);
    DECLARE v_duracion INT;
    DECLARE v_impuestos DECIMAL(10,2);
    DECLARE v_total DECIMAL(10,2);
    DECLARE v_numero VARCHAR(30);
    DECLARE v_duracion_txt VARCHAR(20);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    IF p_monto IS NULL OR p_monto <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El monto debe ser mayor a 0';
    END IF;

    IF p_metodo_pago IS NULL OR p_metodo_pago NOT IN ('Efectivo', 'Tarjeta', 'Transferencia', 'PayPal') THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Metodo de pago invalido (Efectivo, Tarjeta, Transferencia o PayPal)';
    END IF;

    START TRANSACTION;

    SELECT r.estado, r.usuarioID, e.nombre, r.duracion
    INTO v_estado, v_usuario, v_espacio, v_duracion
    FROM reserva r
    JOIN espacio e ON e.espacioID = r.espacioID
    WHERE r.reservaID = p_reservaID
    FOR UPDATE;

    IF v_estado IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La reserva no existe';
    END IF;

    IF v_estado <> 'Pendiente' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Solo se pueden confirmar reservas en estado Pendiente';
    END IF;

    SET v_impuestos = ROUND(p_monto * 0.19, 2);
    SET v_total = p_monto + v_impuestos;

    INSERT INTO pago (fecha_pago, monto, metodo_pago, estado, referencia, usuarioID)
    VALUES (NOW(), v_total, p_metodo_pago, 'Pagado', p_referencia, v_usuario);
    SET p_pagoID = LAST_INSERT_ID();

    CALL sp_aux_numero_factura(v_numero);

    INSERT INTO factura (numero_factura, fecha_emision, subtotal, impuestos, total, estado,
                         usuarioID, pagoID, fecha_vencimiento)
    VALUES (v_numero, NOW(), p_monto, v_impuestos, v_total, 'Pagada',
            v_usuario, p_pagoID, CURDATE());
    SET p_facturaID = LAST_INSERT_ID();

    IF v_duracion MOD 60 = 0 THEN
        SET v_duracion_txt = CONCAT(v_duracion DIV 60, 'h');
    ELSE
        SET v_duracion_txt = CONCAT(v_duracion, ' min');
    END IF;

    INSERT INTO detalle_factura (facturaID, concepto, cantidad, precio_unitario, subtotal)
    VALUES (p_facturaID, CONCAT('Reserva ', v_espacio, ' (', v_duracion_txt, ')'), 1, p_monto, p_monto);

    UPDATE reserva
    SET estado = 'Confirmada'
    WHERE reservaID = p_reservaID;

    COMMIT;
END$$


-- 4. Cancelar reserva con opción de reembolso parcial.
--    Marca la reserva como 'Cancelada'. Si hay una factura de reserva pagada
--    del usuario para ese espacio (la más reciente sin reembolso), genera un
--    registro en reembolso por el porcentaje indicado.
--    Con p_porcentaje = NULL se aplica la política: 100 % si faltan 24 horas
--    o más, 50 % si faltan 2 horas o más, 0 % si falta menos.
DROP PROCEDURE IF EXISTS sp_cancelar_reserva_con_reembolso$$
CREATE PROCEDURE sp_cancelar_reserva_con_reembolso(
    IN  p_reservaID        INT,
    IN  p_porcentaje       DECIMAL(5,2),
    OUT p_monto_reembolso  DECIMAL(10,2)
)
BEGIN
    DECLARE v_estado VARCHAR(20);
    DECLARE v_usuario INT;
    DECLARE v_fecha DATE;
    DECLARE v_inicio TIME;
    DECLARE v_espacio VARCHAR(100);
    DECLARE v_horas_antes INT;
    DECLARE v_pct DECIMAL(5,2);
    DECLARE v_pagoID INT;
    DECLARE v_pago_monto DECIMAL(10,2);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    IF p_porcentaje IS NOT NULL AND (p_porcentaje < 0 OR p_porcentaje > 100) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El porcentaje debe estar entre 0 y 100';
    END IF;

    START TRANSACTION;

    SELECT r.estado, r.usuarioID, r.fecha_reserva, r.hora_inicio, e.nombre
    INTO v_estado, v_usuario, v_fecha, v_inicio, v_espacio
    FROM reserva r
    JOIN espacio e ON e.espacioID = r.espacioID
    WHERE r.reservaID = p_reservaID
    FOR UPDATE;

    IF v_estado IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La reserva no existe';
    END IF;

    IF v_estado NOT IN ('Pendiente', 'Confirmada') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Solo se pueden cancelar reservas Pendientes o Confirmadas';
    END IF;

    UPDATE reserva
    SET estado = 'Cancelada'
    WHERE reservaID = p_reservaID;

    IF p_porcentaje IS NOT NULL THEN
        SET v_pct = p_porcentaje;
    ELSE
        SET v_horas_antes = TIMESTAMPDIFF(HOUR, NOW(), TIMESTAMP(v_fecha, v_inicio));
        IF v_horas_antes >= 24 THEN
            SET v_pct = 100;
        ELSEIF v_horas_antes >= 2 THEN
            SET v_pct = 50;
        ELSE
            SET v_pct = 0;
        END IF;
    END IF;

    SET p_monto_reembolso = 0;

    SELECT p.pagoID, p.monto
    INTO v_pagoID, v_pago_monto
    FROM factura f
    JOIN pago p             ON p.pagoID     = f.pagoID
    JOIN detalle_factura df ON df.facturaID = f.facturaID
    WHERE f.usuarioID = v_usuario
      AND f.estado = 'Pagada'
      AND p.estado = 'Pagado'
      AND df.concepto LIKE CONCAT('Reserva ', v_espacio, '%')
      AND NOT EXISTS (SELECT 1 FROM reembolso rb WHERE rb.pagoID = p.pagoID)
    ORDER BY f.fecha_emision DESC
    LIMIT 1;

    IF v_pagoID IS NOT NULL AND v_pct > 0 THEN
        SET p_monto_reembolso = ROUND(v_pago_monto * v_pct / 100, 2);

        INSERT INTO reembolso (reservaID, pagoID, porcentaje, monto, motivo, estado)
        VALUES (p_reservaID, v_pagoID, v_pct, p_monto_reembolso, 'Cancelacion de reserva', 'Pendiente');
    END IF;

    COMMIT;
END$$


-- 5. Liberar reservas no confirmadas después de X horas.
--    Cancela las reservas Pendientes creadas hace más de p_horas horas y avisa
--    al usuario. Las reservas anteriores a la migración (fecha_creacion NULL)
--    se ignoran.
DROP PROCEDURE IF EXISTS sp_liberar_reservas_no_confirmadas$$
CREATE PROCEDURE sp_liberar_reservas_no_confirmadas(
    IN  p_horas      INT,
    OUT p_liberadas  INT
)
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    IF p_horas IS NULL OR p_horas <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'p_horas debe ser mayor a 0';
    END IF;

    START TRANSACTION;

    INSERT INTO notificacion (destinatario, usuarioID, tipo, asunto, mensaje, referencia_id)
    SELECT
        'Usuario',
        r.usuarioID,
        'Reserva cancelada',
        'Tu reserva fue cancelada por falta de confirmacion',
        CONCAT('Tu reserva del ', DATE_FORMAT(r.fecha_reserva, '%d/%m/%Y'), ' a las ',
               TIME_FORMAT(r.hora_inicio, '%H:%i'), ' fue cancelada porque no se confirmo en ',
               p_horas, ' horas.'),
        r.reservaID
    FROM reserva r
    WHERE r.estado = 'Pendiente'
      AND r.fecha_creacion IS NOT NULL
      AND r.fecha_creacion < DATE_SUB(NOW(), INTERVAL p_horas HOUR);

    UPDATE reserva
    SET estado = 'Cancelada'
    WHERE estado = 'Pendiente'
      AND fecha_creacion IS NOT NULL
      AND fecha_creacion < DATE_SUB(NOW(), INTERVAL p_horas HOUR);

    SET p_liberadas = ROW_COUNT();

    COMMIT;
END$$


-- =====================================================
-- PAGOS Y FACTURACIÓN (4)
-- =====================================================

-- 1. Generar factura por membresía.
--    Crea la factura (precio del tipo + IVA 19 %) al activar o renovar una
--    membresía. Con p_metodo_pago NULL la factura queda 'Pendiente'; si se
--    indica un método, también registra el pago y la factura queda 'Pagada'.
DROP PROCEDURE IF EXISTS sp_generar_factura_membresia$$
CREATE PROCEDURE sp_generar_factura_membresia(
    IN  p_membresiaID INT,
    IN  p_metodo_pago VARCHAR(20),
    IN  p_referencia  VARCHAR(100),
    OUT p_facturaID   INT
)
BEGIN
    DECLARE v_usuario INT;
    DECLARE v_tipo VARCHAR(20);
    DECLARE v_precio DECIMAL(10,2);
    DECLARE v_impuestos DECIMAL(10,2);
    DECLARE v_total DECIMAL(10,2);
    DECLARE v_numero VARCHAR(30);
    DECLARE v_pagoID INT DEFAULT NULL;
    DECLARE v_estado_factura VARCHAR(20) DEFAULT 'Pendiente';

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    IF p_metodo_pago IS NOT NULL
       AND p_metodo_pago NOT IN ('Efectivo', 'Tarjeta', 'Transferencia', 'PayPal') THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Metodo de pago invalido (Efectivo, Tarjeta, Transferencia o PayPal)';
    END IF;

    SELECT m.usuarioID, t.nombre, t.precio
    INTO v_usuario, v_tipo, v_precio
    FROM membresia m
    JOIN tipo_membresia t ON t.tipoID = m.tipoID
    WHERE m.membresiaID = p_membresiaID;

    IF v_usuario IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La membresia no existe';
    END IF;

    SET v_impuestos = ROUND(v_precio * 0.19, 2);
    SET v_total = v_precio + v_impuestos;

    START TRANSACTION;

    IF p_metodo_pago IS NOT NULL THEN
        INSERT INTO pago (fecha_pago, monto, metodo_pago, estado, referencia, usuarioID)
        VALUES (NOW(), v_total, p_metodo_pago, 'Pagado', p_referencia, v_usuario);
        SET v_pagoID = LAST_INSERT_ID();
        SET v_estado_factura = 'Pagada';
    END IF;

    CALL sp_aux_numero_factura(v_numero);

    INSERT INTO factura (numero_factura, fecha_emision, subtotal, impuestos, total, estado,
                         usuarioID, pagoID, fecha_vencimiento)
    VALUES (v_numero, NOW(), v_precio, v_impuestos, v_total, v_estado_factura,
            v_usuario, v_pagoID, DATE_ADD(CURDATE(), INTERVAL 30 DAY));
    SET p_facturaID = LAST_INSERT_ID();

    INSERT INTO detalle_factura (facturaID, concepto, cantidad, precio_unitario, subtotal)
    VALUES (p_facturaID, CONCAT('Membresía ', v_tipo), 1, v_precio, v_precio);

    COMMIT;
END$$


-- 2. Generar factura consolidada para empresa.
--    Agrupa en una sola factura las facturas Pendientes de los empleados de la
--    empresa emitidas entre p_desde y p_hasta (NULL = sin límite inferior /
--    hasta hoy). Las facturas originales pasan a 'Cancelada' para no cobrarlas
--    dos veces y la consolidada queda a nombre del titular: el empleado con
--    membresía Corporativa de menor ID (el modelo no tiene empresa en factura).
DROP PROCEDURE IF EXISTS sp_generar_factura_consolidada_empresa$$
CREATE PROCEDURE sp_generar_factura_consolidada_empresa(
    IN  p_empresaID INT,
    IN  p_desde     DATE,
    IN  p_hasta     DATE,
    OUT p_facturaID INT
)
BEGIN
    DECLARE v_estado_emp VARCHAR(20);
    DECLARE v_titular INT;
    DECLARE v_desde DATE;
    DECLARE v_hasta DATE;
    DECLARE v_n INT DEFAULT 0;
    DECLARE v_subtotal DECIMAL(14,2) DEFAULT 0;
    DECLARE v_impuestos DECIMAL(14,2) DEFAULT 0;
    DECLARE v_total DECIMAL(14,2) DEFAULT 0;
    DECLARE v_numero VARCHAR(30);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    SELECT estado INTO v_estado_emp FROM empresa WHERE empresaID = p_empresaID;

    IF v_estado_emp IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La empresa no existe';
    END IF;

    SET v_desde = COALESCE(p_desde, '2000-01-01');
    SET v_hasta = COALESCE(p_hasta, CURDATE());

    SELECT
        COUNT(*),
        COALESCE(SUM(f.subtotal), 0),
        COALESCE(SUM(f.impuestos), 0),
        COALESCE(SUM(f.total), 0)
    INTO v_n, v_subtotal, v_impuestos, v_total
    FROM factura f
    JOIN usuario u ON u.usuarioID = f.usuarioID
    WHERE u.empresaID = p_empresaID
      AND f.estado = 'Pendiente'
      AND DATE(f.fecha_emision) BETWEEN v_desde AND v_hasta
      AND NOT EXISTS (
            SELECT 1 FROM detalle_factura d
            WHERE d.facturaID = f.facturaID AND d.concepto LIKE 'Consolidado%'
      );

    IF v_n = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'No hay facturas pendientes de empleados de la empresa en ese periodo';
    END IF;

    SELECT u.usuarioID
    INTO v_titular
    FROM usuario u
    LEFT JOIN membresia m ON m.membresiaID = u.membresiaID
    WHERE u.empresaID = p_empresaID
    ORDER BY (m.tipo = 'Corporativa') DESC, u.usuarioID
    LIMIT 1;

    START TRANSACTION;

    CALL sp_aux_numero_factura(v_numero);

    INSERT INTO factura (numero_factura, fecha_emision, subtotal, impuestos, total, estado,
                         usuarioID, pagoID, fecha_vencimiento)
    VALUES (v_numero, NOW(), v_subtotal, v_impuestos, v_total, 'Pendiente',
            v_titular, NULL, DATE_ADD(CURDATE(), INTERVAL 30 DAY));
    SET p_facturaID = LAST_INSERT_ID();

    INSERT INTO detalle_factura (facturaID, concepto, cantidad, precio_unitario, subtotal)
    SELECT
        p_facturaID,
        CONCAT('Consolidado ', f.numero_factura, ' - ', u.nombre, ' ', u.apellido),
        1,
        f.subtotal,
        f.subtotal
    FROM factura f
    JOIN usuario u ON u.usuarioID = f.usuarioID
    WHERE u.empresaID = p_empresaID
      AND f.estado = 'Pendiente'
      AND f.facturaID <> p_facturaID
      AND DATE(f.fecha_emision) BETWEEN v_desde AND v_hasta
      AND NOT EXISTS (
            SELECT 1 FROM detalle_factura d
            WHERE d.facturaID = f.facturaID AND d.concepto LIKE 'Consolidado%'
      );

    UPDATE factura f
    JOIN usuario u ON u.usuarioID = f.usuarioID
    SET f.estado = 'Cancelada'
    WHERE u.empresaID = p_empresaID
      AND f.estado = 'Pendiente'
      AND f.facturaID <> p_facturaID
      AND DATE(f.fecha_emision) BETWEEN v_desde AND v_hasta
      AND NOT EXISTS (
            SELECT 1 FROM detalle_factura d
            WHERE d.facturaID = f.facturaID AND d.concepto LIKE 'Consolidado%'
      );

    COMMIT;
END$$


-- 3. Aplicar recargos a facturas vencidas.
--    Incrementa en p_porcentaje % el total de las facturas Pendientes con más
--    de p_dias días de vencidas. El recargo se aplica una sola vez por
--    factura (recargo_aplicado) y queda como línea en detalle_factura.
DROP PROCEDURE IF EXISTS sp_aplicar_recargos_facturas_vencidas$$
CREATE PROCEDURE sp_aplicar_recargos_facturas_vencidas(
    IN  p_dias        INT,
    IN  p_porcentaje  DECIMAL(5,2),
    OUT p_facturas    INT
)
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    IF p_dias IS NULL OR p_dias < 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'p_dias debe ser un numero mayor o igual a 0';
    END IF;

    IF p_porcentaje IS NULL OR p_porcentaje <= 0 OR p_porcentaje > 100 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El porcentaje debe ser mayor a 0 y no superar 100';
    END IF;

    START TRANSACTION;

    INSERT INTO detalle_factura (facturaID, concepto, cantidad, precio_unitario, subtotal)
    SELECT
        f.facturaID,
        CONCAT('Recargo por mora (', p_porcentaje, '%)'),
        1,
        ROUND(f.total * p_porcentaje / 100, 2),
        ROUND(f.total * p_porcentaje / 100, 2)
    FROM factura f
    WHERE f.estado = 'Pendiente'
      AND f.recargo_aplicado = 0
      AND f.fecha_vencimiento < DATE_SUB(CURDATE(), INTERVAL p_dias DAY);

    UPDATE factura
    SET recargo = ROUND(total * p_porcentaje / 100, 2),
        total = total + ROUND(total * p_porcentaje / 100, 2),
        recargo_aplicado = 1
    WHERE estado = 'Pendiente'
      AND recargo_aplicado = 0
      AND fecha_vencimiento < DATE_SUB(CURDATE(), INTERVAL p_dias DAY);

    SET p_facturas = ROW_COUNT();

    COMMIT;
END$$


-- 4. Bloquear servicios adicionales por falta de pago.
--    Bloquea los servicios adicionales de usuarios con facturas Pendientes ya
--    vencidas hace más de p_dias_gracia días (0 = cualquier factura vencida)
--    y avisa a cada usuario afectado.
DROP PROCEDURE IF EXISTS sp_bloquear_servicios_por_impago$$
CREATE PROCEDURE sp_bloquear_servicios_por_impago(
    IN  p_dias_gracia          INT,
    OUT p_servicios_bloqueados INT
)
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    IF p_dias_gracia IS NULL OR p_dias_gracia < 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'p_dias_gracia debe ser un numero mayor o igual a 0';
    END IF;

    START TRANSACTION;

    INSERT INTO notificacion (destinatario, usuarioID, tipo, asunto, mensaje)
    SELECT DISTINCT
        'Usuario',
        us.usuarioID,
        'Servicios bloqueados',
        'Tus servicios adicionales fueron bloqueados',
        'Tienes facturas vencidas sin pagar. Paga tus facturas pendientes para reactivar tus servicios adicionales.'
    FROM usuario_servicio us
    WHERE us.bloqueado = 0
      AND EXISTS (
            SELECT 1
            FROM factura f
            WHERE f.usuarioID = us.usuarioID
              AND f.estado = 'Pendiente'
              AND f.fecha_vencimiento < DATE_SUB(CURDATE(), INTERVAL p_dias_gracia DAY)
      );

    UPDATE usuario_servicio us
    SET us.bloqueado = 1
    WHERE us.bloqueado = 0
      AND EXISTS (
            SELECT 1
            FROM factura f
            WHERE f.usuarioID = us.usuarioID
              AND f.estado = 'Pendiente'
              AND f.fecha_vencimiento < DATE_SUB(CURDATE(), INTERVAL p_dias_gracia DAY)
      );

    SET p_servicios_bloqueados = ROW_COUNT();

    COMMIT;
END$$


-- =====================================================
-- ACCESOS Y ASISTENCIAS (4)
-- =====================================================

-- 1. Registrar acceso de usuario (entrada).
--    Recibe el código de la credencial (RFID/QR), identifica al usuario y
--    autoriza la entrada si tiene membresía vigente o una reserva confirmada
--    para este momento (se permite entrar hasta 15 minutos antes). Registra
--    la asistencia como Autorizado o Rechazado. Si el código no existe o el
--    usuario ya tiene una entrada abierta hoy, no se registra nada y se
--    devuelve el motivo.
DROP PROCEDURE IF EXISTS sp_registrar_entrada$$
CREATE PROCEDURE sp_registrar_entrada(
    IN  p_codigo     VARCHAR(100),
    OUT p_resultado  VARCHAR(20),
    OUT p_mensaje    VARCHAR(100)
)
BEGIN
    DECLARE v_usuario INT;
    DECLARE v_reserva INT;
    DECLARE v_membresia_vigente INT DEFAULT 0;

    SET p_resultado = 'Rechazado';

    SELECT usuarioID INTO v_usuario FROM acceso WHERE codigo = p_codigo;

    IF v_usuario IS NULL THEN
        SET p_mensaje = 'Credencial no registrada';
    ELSEIF EXISTS (
        SELECT 1
        FROM asistencia
        WHERE usuarioID = v_usuario
          AND fecha = CURDATE()
          AND resultado_validacion = 'Autorizado'
          AND hora_salida IS NULL
    ) THEN
        SET p_mensaje = 'El usuario ya tiene una entrada sin salida registrada';
    ELSE
        SELECT COUNT(*)
        INTO v_membresia_vigente
        FROM usuario u
        JOIN membresia m ON m.membresiaID = u.membresiaID
        WHERE u.usuarioID = v_usuario
          AND m.estado = 'Activa'
          AND CURDATE() BETWEEN m.fecha_inicio AND m.fecha_fin;

        SELECT r.reservaID
        INTO v_reserva
        FROM reserva r
        WHERE r.usuarioID = v_usuario
          AND r.estado = 'Confirmada'
          AND r.fecha_reserva = CURDATE()
          AND CURTIME() BETWEEN SUBTIME(r.hora_inicio, '00:15:00') AND r.hora_fin
        ORDER BY r.hora_inicio
        LIMIT 1;

        IF v_membresia_vigente > 0 OR v_reserva IS NOT NULL THEN
            INSERT INTO asistencia (fecha, hora_entrada, hora_salida, resultado_validacion, usuarioID, reservaID)
            VALUES (CURDATE(), CURTIME(), NULL, 'Autorizado', v_usuario, v_reserva);
            SET p_resultado = 'Autorizado';
            SET p_mensaje = 'Acceso autorizado';
        ELSE
            INSERT INTO asistencia (fecha, hora_entrada, hora_salida, resultado_validacion, usuarioID, reservaID)
            VALUES (CURDATE(), CURTIME(), NULL, 'Rechazado', v_usuario, NULL);
            SET p_mensaje = 'Sin membresia vigente ni reserva activa';
        END IF;
    END IF;
END$$


-- 2. Registrar salida de usuario.
--    Completa la asistencia abierta de hoy (entrada autorizada sin salida)
--    con la hora actual y devuelve su ID.
DROP PROCEDURE IF EXISTS sp_registrar_salida$$
CREATE PROCEDURE sp_registrar_salida(
    IN  p_usuarioID     INT,
    OUT p_asistenciaID  INT
)
BEGIN
    SELECT asistenciaID
    INTO p_asistenciaID
    FROM asistencia
    WHERE usuarioID = p_usuarioID
      AND fecha = CURDATE()
      AND resultado_validacion = 'Autorizado'
      AND hora_salida IS NULL
    ORDER BY hora_entrada DESC
    LIMIT 1;

    IF p_asistenciaID IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'No hay una entrada abierta hoy para este usuario';
    END IF;

    UPDATE asistencia
    SET hora_salida = CURTIME()
    WHERE asistenciaID = p_asistenciaID;
END$$


-- 3. Generar reporte diario de asistencias.
--    Devuelve dos resultados: (1) resumen del día con ingresos, autorizados,
--    rechazados y usuarios únicos; (2) ingresos por franja horaria, marcando
--    la(s) hora(s) pico. p_fecha NULL = hoy.
DROP PROCEDURE IF EXISTS sp_reporte_diario_asistencias$$
CREATE PROCEDURE sp_reporte_diario_asistencias(IN p_fecha DATE)
BEGIN
    DECLARE v_fecha DATE;

    SET v_fecha = COALESCE(p_fecha, CURDATE());

    SELECT
        v_fecha AS fecha,
        COUNT(*) AS ingresos_totales,
        COALESCE(SUM(resultado_validacion = 'Autorizado'), 0) AS autorizados,
        COALESCE(SUM(resultado_validacion = 'Rechazado'), 0)  AS rechazados,
        COUNT(DISTINCT CASE WHEN resultado_validacion = 'Autorizado' THEN usuarioID END) AS usuarios_unicos
    FROM asistencia
    WHERE fecha = v_fecha;

    SELECT
        CONCAT(LPAD(t.hora, 2, '0'), ':00') AS franja_horaria,
        t.ingresos,
        t.usuarios_unicos,
        IF(t.ingresos = MAX(t.ingresos) OVER (), 'PICO', '') AS hora_pico
    FROM (
        SELECT
            HOUR(hora_entrada)        AS hora,
            COUNT(*)                  AS ingresos,
            COUNT(DISTINCT usuarioID) AS usuarios_unicos
        FROM asistencia
        WHERE fecha = v_fecha
          AND resultado_validacion = 'Autorizado'
        GROUP BY HOUR(hora_entrada)
    ) t
    ORDER BY t.ingresos DESC, t.hora;
END$$


-- 4. Marcar reservas como "No Show" y generar penalización.
--    Detecta reservas Confirmadas que ya terminaron (más p_minutos_gracia
--    minutos) y en cuya fecha el usuario no tuvo ninguna entrada autorizada.
--    Las pasa a 'No Show' y, si p_monto_penalizacion > 0, genera una factura
--    Pendiente por la penalización (más IVA 19 %).
DROP PROCEDURE IF EXISTS sp_marcar_no_show_y_penalizar$$
CREATE PROCEDURE sp_marcar_no_show_y_penalizar(
    IN  p_minutos_gracia      INT,
    IN  p_monto_penalizacion  DECIMAL(10,2),
    OUT p_reservas_marcadas   INT
)
BEGIN
    DECLARE v_fin TINYINT DEFAULT 0;
    DECLARE v_reserva INT;
    DECLARE v_usuario INT;
    DECLARE v_espacio VARCHAR(100);
    DECLARE v_impuestos DECIMAL(10,2);
    DECLARE v_total DECIMAL(10,2);
    DECLARE v_numero VARCHAR(30);
    DECLARE v_facturaID INT;

    DECLARE cur_no_show CURSOR FOR
        SELECT r.reservaID, r.usuarioID, e.nombre
        FROM reserva r
        JOIN espacio e ON e.espacioID = r.espacioID
        WHERE r.estado = 'Confirmada'
          AND DATE_ADD(TIMESTAMP(r.fecha_reserva, r.hora_fin), INTERVAL p_minutos_gracia MINUTE) < NOW()
          AND NOT EXISTS (
                SELECT 1
                FROM asistencia a
                WHERE a.usuarioID = r.usuarioID
                  AND a.fecha = r.fecha_reserva
                  AND a.resultado_validacion = 'Autorizado'
          );

    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_fin = 1;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    IF p_minutos_gracia IS NULL OR p_minutos_gracia < 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'p_minutos_gracia debe ser mayor o igual a 0';
    END IF;

    IF p_monto_penalizacion IS NULL OR p_monto_penalizacion < 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El monto de penalizacion no puede ser negativo';
    END IF;

    SET p_reservas_marcadas = 0;

    START TRANSACTION;

    OPEN cur_no_show;

    leer: LOOP
        FETCH cur_no_show INTO v_reserva, v_usuario, v_espacio;
        IF v_fin = 1 THEN
            LEAVE leer;
        END IF;

        UPDATE reserva
        SET estado = 'No Show'
        WHERE reservaID = v_reserva;

        IF p_monto_penalizacion > 0 THEN
            SET v_impuestos = ROUND(p_monto_penalizacion * 0.19, 2);
            SET v_total = p_monto_penalizacion + v_impuestos;

            CALL sp_aux_numero_factura(v_numero);

            INSERT INTO factura (numero_factura, fecha_emision, subtotal, impuestos, total, estado,
                                 usuarioID, pagoID, fecha_vencimiento)
            VALUES (v_numero, NOW(), p_monto_penalizacion, v_impuestos, v_total, 'Pendiente',
                    v_usuario, NULL, DATE_ADD(CURDATE(), INTERVAL 30 DAY));
            SET v_facturaID = LAST_INSERT_ID();

            INSERT INTO detalle_factura (facturaID, concepto, cantidad, precio_unitario, subtotal)
            VALUES (v_facturaID,
                    CONCAT('Penalización No Show - Reserva #', v_reserva, ' (', v_espacio, ')'),
                    1, p_monto_penalizacion, p_monto_penalizacion);
        END IF;

        SET p_reservas_marcadas = p_reservas_marcadas + 1;
    END LOOP;

    CLOSE cur_no_show;

    COMMIT;
END$$


-- =====================================================
-- CORPORATIVOS Y ADMINISTRACIÓN (3)
-- =====================================================

-- 1. Registrar lote de empleados de una empresa con membresía corporativa.
--    Recibe un arreglo JSON, inserta cada empleado ligado a la empresa y le
--    asigna una membresía Corporativa (usando sp_registrar_membresia). Todo
--    en una transacción: si un empleado falla, no se registra ninguno.
--    Ejemplo de p_empleados:
--      '[{"nombre":"Ana","apellido":"Lopez Diaz","edad":29,"contacto":"ana@mail.com | 3001112233"},
--        {"nombre":"Luis","apellido":"Prada Rey","edad":34,"contacto":"luis@mail.com | 3004445566"}]'
--    p_fecha_inicio NULL = hoy.
DROP PROCEDURE IF EXISTS sp_registrar_lote_empleados$$
CREATE PROCEDURE sp_registrar_lote_empleados(
    IN  p_empresaID    INT,
    IN  p_empleados    JSON,
    IN  p_fecha_inicio DATE,
    OUT p_registrados  INT
)
BEGIN
    DECLARE v_fin TINYINT DEFAULT 0;
    DECLARE v_estado_emp VARCHAR(20);
    DECLARE v_tipoID INT;
    DECLARE v_invalidos INT DEFAULT 0;
    DECLARE v_nombre VARCHAR(50);
    DECLARE v_apellido VARCHAR(80);
    DECLARE v_edad INT;
    DECLARE v_contacto VARCHAR(100);
    DECLARE v_usuarioID INT;
    DECLARE v_membresiaID INT;

    DECLARE cur_empleados CURSOR FOR
        SELECT jt.nombre, jt.apellido, jt.edad, jt.contacto
        FROM JSON_TABLE(
            p_empleados, '$[*]'
            COLUMNS (
                nombre   VARCHAR(50)  PATH '$.nombre',
                apellido VARCHAR(80)  PATH '$.apellido',
                edad     INT          PATH '$.edad',
                contacto VARCHAR(100) PATH '$.contacto'
            )
        ) AS jt;

    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_fin = 1;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    SELECT estado INTO v_estado_emp FROM empresa WHERE empresaID = p_empresaID;

    IF v_estado_emp IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La empresa no existe';
    END IF;

    IF v_estado_emp <> 'Activa' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La empresa esta inactiva';
    END IF;

    IF p_empleados IS NULL OR JSON_TYPE(p_empleados) <> 'ARRAY' OR JSON_LENGTH(p_empleados) = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'p_empleados debe ser un arreglo JSON con al menos un empleado';
    END IF;

    SELECT COUNT(*)
    INTO v_invalidos
    FROM JSON_TABLE(
        p_empleados, '$[*]'
        COLUMNS (
            nombre   VARCHAR(50) PATH '$.nombre',
            apellido VARCHAR(80) PATH '$.apellido',
            edad     INT         PATH '$.edad'
        )
    ) AS jt
    WHERE jt.nombre IS NULL OR jt.apellido IS NULL OR jt.edad IS NULL;

    IF v_invalidos > 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Cada empleado debe traer nombre, apellido y edad';
    END IF;

    SELECT tipoID INTO v_tipoID FROM tipo_membresia WHERE nombre = 'Corporativa' LIMIT 1;

    IF v_tipoID IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'No existe el tipo de membresia Corporativa';
    END IF;

    SET v_fin = 0;
    SET p_registrados = 0;

    START TRANSACTION;

    OPEN cur_empleados;

    leer: LOOP
        FETCH cur_empleados INTO v_nombre, v_apellido, v_edad, v_contacto;
        IF v_fin = 1 THEN
            LEAVE leer;
        END IF;

        INSERT INTO usuario (nombre, apellido, edad, contacto, membresiaID, empresaID)
        VALUES (v_nombre, v_apellido, v_edad, v_contacto, NULL, p_empresaID);
        SET v_usuarioID = LAST_INSERT_ID();

        CALL sp_registrar_membresia(v_usuarioID, v_tipoID, p_fecha_inicio, v_membresiaID);

        SET p_registrados = p_registrados + 1;
    END LOOP;

    CLOSE cur_empleados;

    COMMIT;
END$$


-- 2. Cancelar reservas futuras al eliminar membresía de usuario.
--    Cancela las reservas Pendientes o Confirmadas del usuario que aún no han
--    empezado y le avisa por cada una. Se llama después de eliminar o cancelar
--    la membresía del usuario.
DROP PROCEDURE IF EXISTS sp_cancelar_reservas_futuras_usuario$$
CREATE PROCEDURE sp_cancelar_reservas_futuras_usuario(
    IN  p_usuarioID   INT,
    OUT p_canceladas  INT
)
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    IF NOT EXISTS (SELECT 1 FROM usuario WHERE usuarioID = p_usuarioID) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El usuario no existe';
    END IF;

    START TRANSACTION;

    INSERT INTO notificacion (destinatario, usuarioID, tipo, asunto, mensaje, referencia_id)
    SELECT
        'Usuario',
        r.usuarioID,
        'Reserva cancelada',
        'Tu reserva fue cancelada',
        CONCAT('Tu reserva del ', DATE_FORMAT(r.fecha_reserva, '%d/%m/%Y'), ' a las ',
               TIME_FORMAT(r.hora_inicio, '%H:%i'),
               ' fue cancelada porque tu membresia ya no esta disponible.'),
        r.reservaID
    FROM reserva r
    WHERE r.usuarioID = p_usuarioID
      AND r.estado IN ('Pendiente', 'Confirmada')
      AND (r.fecha_reserva > CURDATE()
           OR (r.fecha_reserva = CURDATE() AND r.hora_inicio > CURTIME()));

    UPDATE reserva
    SET estado = 'Cancelada'
    WHERE usuarioID = p_usuarioID
      AND estado IN ('Pendiente', 'Confirmada')
      AND (fecha_reserva > CURDATE()
           OR (fecha_reserva = CURDATE() AND hora_inicio > CURTIME()));

    SET p_canceladas = ROW_COUNT();

    COMMIT;
END$$


-- 3. Generar reporte de ingresos mensuales acumulados.
--    Para el año indicado (NULL = año actual) devuelve, mes a mes, los pagos
--    realizados, el ingreso del mes y el ingreso acumulado del año (función
--    de ventana). En el año actual solo muestra hasta el mes en curso.
DROP PROCEDURE IF EXISTS sp_reporte_ingresos_mensuales_acumulados$$
CREATE PROCEDURE sp_reporte_ingresos_mensuales_acumulados(IN p_anio INT)
BEGIN
    DECLARE v_anio INT;

    SET v_anio = COALESCE(p_anio, YEAR(CURDATE()));

    WITH RECURSIVE meses AS (
        SELECT 1 AS mes
        UNION ALL
        SELECT mes + 1 FROM meses WHERE mes < 12
    ),
    ingresos AS (
        SELECT
            MONTH(fecha_pago) AS mes,
            COUNT(*)          AS pagos,
            SUM(monto)        AS total
        FROM pago
        WHERE estado = 'Pagado'
          AND YEAR(fecha_pago) = v_anio
        GROUP BY MONTH(fecha_pago)
    )
    SELECT
        CONCAT(v_anio, '-', LPAD(m.mes, 2, '0')) AS mes,
        COALESCE(i.pagos, 0)                     AS pagos_realizados,
        COALESCE(i.total, 0)                     AS ingresos_mes,
        SUM(COALESCE(i.total, 0)) OVER (ORDER BY m.mes) AS ingresos_acumulados_anio
    FROM meses m
    LEFT JOIN ingresos i ON i.mes = m.mes
    WHERE v_anio <> YEAR(CURDATE())
       OR m.mes <= MONTH(CURDATE())
    ORDER BY m.mes;
END$$

DELIMITER ;


-- =====================================================
-- EJEMPLOS DE USO (opcional; quita los comentarios para probar)
-- =====================================================
-- CALL sp_registrar_membresia(2, 2, NULL, @membresia);       SELECT @membresia;
-- CALL sp_renovar_membresia(1, @nueva_fin);                  SELECT @nueva_fin;
-- CALL sp_actualizar_membresias_vencidas(@n);                SELECT @n;
-- CALL sp_suspender_membresias_impagas(30, @n);              SELECT @n;
--
-- CALL sp_verificar_disponibilidad_espacio(5, '2026-10-20', '09:00', '11:00', @ok, @msg);  SELECT @ok, @msg;
-- CALL sp_crear_reserva(2, 5, '2026-10-20', '09:00', '11:00', @reserva);                   SELECT @reserva;
-- CALL sp_confirmar_reserva_con_pago(@reserva, 50000, 'Tarjeta', 'TRX-9001', @pago, @factura);
-- CALL sp_cancelar_reserva_con_reembolso(@reserva, NULL, @reembolso);                      SELECT @reembolso;
-- CALL sp_liberar_reservas_no_confirmadas(2, @n);            SELECT @n;
--
-- CALL sp_generar_factura_membresia(1, NULL, NULL, @factura);                              SELECT @factura;
-- CALL sp_generar_factura_consolidada_empresa(1, NULL, NULL, @factura);                    SELECT @factura;
-- CALL sp_aplicar_recargos_facturas_vencidas(15, 5.00, @n);  SELECT @n;
-- CALL sp_bloquear_servicios_por_impago(10, @n);             SELECT @n;
--
-- CALL sp_registrar_entrada('RFID-A1B2C3D4', @res, @msg);    SELECT @res, @msg;
-- CALL sp_registrar_salida(1, @asistencia);                  SELECT @asistencia;
-- CALL sp_reporte_diario_asistencias(NULL);
-- CALL sp_marcar_no_show_y_penalizar(0, 20000, @n);          SELECT @n;
--
-- CALL sp_registrar_lote_empleados(1,
--      '[{"nombre":"Ana","apellido":"Lopez Diaz","edad":29,"contacto":"ana@mail.com | 3001112233"}]',
--      NULL, @n);                                            SELECT @n;
-- CALL sp_cancelar_reservas_futuras_usuario(1, @n);          SELECT @n;
-- CALL sp_reporte_ingresos_mensuales_acumulados(NULL);
