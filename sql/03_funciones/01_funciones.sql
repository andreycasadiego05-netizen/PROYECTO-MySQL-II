USE coworking;

-- =====================================================
-- FUNCIONES SQL (20)
-- =====================================================
-- Ejecutar después de 01_estructura.sql y 01_datos_iniciales.sql.
-- Se puede ejecutar varias veces (DROP FUNCTION IF EXISTS).
-- Requiere MySQL 8 y un cliente que soporte DELIMITER.
--
-- Convenciones (las mismas de las consultas y procedimientos del proyecto):
--  * Membresía actual = la que apunta usuario.membresiaID.
--  * Reserva activa = estado Pendiente o Confirmada, de hoy en adelante.
--  * Asistencia válida = asistencia con resultado_validacion = 'Autorizado'.
--    "Accesos" y "asistencias" se calculan sobre la tabla asistencia.
--  * Ingresos (funciones 12 a 15) = facturas en estado 'Pagada', sobre el
--    subtotal (sin IVA). "Total pagado" (función 11) = pagos en estado
--    'Pagado' (monto con IVA).
--  * Renovaciones = membresías del usuario - 1 (igual que la consulta 17).
-- =====================================================

DELIMITER $$


-- =====================================================
-- MEMBRESÍAS
-- =====================================================

-- 1. Devuelve TRUE si el usuario tiene membresía activa.
DROP FUNCTION IF EXISTS fn_membresia_activa$$
CREATE FUNCTION fn_membresia_activa(p_usuario_id INT)
RETURNS BOOLEAN
READS SQL DATA
BEGIN
    RETURN EXISTS (
        SELECT 1
        FROM usuario u
        JOIN membresia m ON m.membresiaID = u.membresiaID
        WHERE u.usuarioID = p_usuario_id
          AND m.estado = 'Activa'
    );
END$$


-- 2. Días restantes de vigencia de la membresía actual.
--    Devuelve 0 si ya venció o si el usuario no tiene membresía.
DROP FUNCTION IF EXISTS fn_dias_restantes_membresia$$
CREATE FUNCTION fn_dias_restantes_membresia(p_usuario_id INT)
RETURNS INT
READS SQL DATA
BEGIN
    DECLARE v_fin DATE;

    SET v_fin = (
        SELECT m.fecha_fin
        FROM usuario u
        JOIN membresia m ON m.membresiaID = u.membresiaID
        WHERE u.usuarioID = p_usuario_id
    );

    IF v_fin IS NULL THEN
        RETURN 0;
    END IF;

    RETURN GREATEST(DATEDIFF(v_fin, CURDATE()), 0);
END$$


-- 3. Retorna el tipo actual de membresía.
DROP FUNCTION IF EXISTS fn_tipo_membresia$$
CREATE FUNCTION fn_tipo_membresia(p_usuario_id INT)
RETURNS VARCHAR(20)
READS SQL DATA
BEGIN
    DECLARE v_tipo VARCHAR(20);

    SET v_tipo = (
        SELECT m.tipo
        FROM usuario u
        JOIN membresia m ON m.membresiaID = u.membresiaID
        WHERE u.usuarioID = p_usuario_id
    );

    RETURN IFNULL(v_tipo, 'Sin membresía');
END$$


-- 4. Número de veces que renovó (membresías registradas - 1).
DROP FUNCTION IF EXISTS fn_renovaciones_membresia$$
CREATE FUNCTION fn_renovaciones_membresia(p_usuario_id INT)
RETURNS INT
READS SQL DATA
BEGIN
    DECLARE v_total INT;

    SET v_total = (
        SELECT COUNT(*)
        FROM membresia
        WHERE usuarioID = p_usuario_id
    );

    RETURN GREATEST(v_total - 1, 0);
END$$


-- 5. Devuelve el estado de la membresía actual (Activa, Suspendida, Vencida).
DROP FUNCTION IF EXISTS fn_estado_membresia$$
CREATE FUNCTION fn_estado_membresia(p_usuario_id INT)
RETURNS VARCHAR(20)
READS SQL DATA
BEGIN
    DECLARE v_estado VARCHAR(20);

    SET v_estado = (
        SELECT m.estado
        FROM usuario u
        JOIN membresia m ON m.membresiaID = u.membresiaID
        WHERE u.usuarioID = p_usuario_id
    );

    RETURN IFNULL(v_estado, 'Sin membresía');
END$$


-- =====================================================
-- RESERVAS
-- =====================================================

-- 6. Cantidad total de reservas del usuario (todos los estados).
DROP FUNCTION IF EXISTS fn_total_reservas$$
CREATE FUNCTION fn_total_reservas(p_usuario_id INT)
RETURNS INT
READS SQL DATA
BEGIN
    RETURN (
        SELECT COUNT(*)
        FROM reserva
        WHERE usuarioID = p_usuario_id
    );
END$$


-- 7. Total de horas reservadas por el usuario en un mes y año (sin canceladas).
DROP FUNCTION IF EXISTS fn_horas_reservadas$$
CREATE FUNCTION fn_horas_reservadas(p_usuario_id INT, p_mes INT, p_anio INT)
RETURNS DECIMAL(10,2)
READS SQL DATA
BEGIN
    DECLARE v_minutos INT;

    SET v_minutos = (
        SELECT SUM(duracion)
        FROM reserva
        WHERE usuarioID = p_usuario_id
          AND estado <> 'Cancelada'
          AND MONTH(fecha_reserva) = p_mes
          AND YEAR(fecha_reserva)  = p_anio
    );

    RETURN ROUND(IFNULL(v_minutos, 0) / 60, 2);
END$$


-- 8. Retorna el ID del espacio más usado (sin contar canceladas).
--    En caso de empate devuelve el de menor ID.
DROP FUNCTION IF EXISTS fn_espacio_mas_reservado$$
CREATE FUNCTION fn_espacio_mas_reservado()
RETURNS INT
READS SQL DATA
BEGIN
    RETURN (
        SELECT espacioID
        FROM reserva
        WHERE estado <> 'Cancelada'
        GROUP BY espacioID
        ORDER BY COUNT(*) DESC, espacioID
        LIMIT 1
    );
END$$


-- 9. Cantidad de reservas activas (Pendiente o Confirmada, de hoy en adelante).
DROP FUNCTION IF EXISTS fn_reservas_activas$$
CREATE FUNCTION fn_reservas_activas(p_usuario_id INT)
RETURNS INT
READS SQL DATA
BEGIN
    RETURN (
        SELECT COUNT(*)
        FROM reserva
        WHERE usuarioID = p_usuario_id
          AND estado IN ('Pendiente', 'Confirmada')
          AND fecha_reserva >= CURDATE()
    );
END$$


-- 10. Promedio de duración (en minutos) de las reservas de un espacio.
DROP FUNCTION IF EXISTS fn_duracion_promedio_reservas$$
CREATE FUNCTION fn_duracion_promedio_reservas(p_espacio_id INT)
RETURNS DECIMAL(10,2)
READS SQL DATA
BEGIN
    DECLARE v_prom DECIMAL(10,2);

    SET v_prom = (
        SELECT AVG(duracion)
        FROM reserva
        WHERE espacioID = p_espacio_id
          AND estado <> 'Cancelada'
    );

    RETURN IFNULL(v_prom, 0);
END$$


-- =====================================================
-- PAGOS Y FACTURACIÓN
-- =====================================================

-- 11. Total pagado por un usuario (pagos en estado 'Pagado', con IVA).
DROP FUNCTION IF EXISTS fn_total_pagado$$
CREATE FUNCTION fn_total_pagado(p_usuario_id INT)
RETURNS DECIMAL(12,2)
READS SQL DATA
BEGIN
    DECLARE v_total DECIMAL(12,2);

    SET v_total = (
        SELECT SUM(monto)
        FROM pago
        WHERE usuarioID = p_usuario_id
          AND estado = 'Pagado'
    );

    RETURN IFNULL(v_total, 0);
END$$


-- 12. Ingresos totales en un mes y año (facturas 'Pagada', sin IVA).
DROP FUNCTION IF EXISTS fn_ingresos_por_mes$$
CREATE FUNCTION fn_ingresos_por_mes(p_mes INT, p_anio INT)
RETURNS DECIMAL(12,2)
READS SQL DATA
BEGIN
    DECLARE v_total DECIMAL(12,2);

    SET v_total = (
        SELECT SUM(subtotal)
        FROM factura
        WHERE estado = 'Pagada'
          AND MONTH(fecha_emision) = p_mes
          AND YEAR(fecha_emision)  = p_anio
    );

    RETURN IFNULL(v_total, 0);
END$$


-- 13. Total de ingresos por membresías (facturas 'Pagada', sin IVA).
DROP FUNCTION IF EXISTS fn_ingresos_por_membresias$$
CREATE FUNCTION fn_ingresos_por_membresias()
RETURNS DECIMAL(12,2)
READS SQL DATA
BEGIN
    DECLARE v_total DECIMAL(12,2);

    SET v_total = (
        SELECT SUM(df.subtotal)
        FROM factura f
        JOIN detalle_factura df ON df.facturaID = f.facturaID
        WHERE f.estado = 'Pagada'
          AND df.concepto LIKE 'Membres%'
    );

    RETURN IFNULL(v_total, 0);
END$$


-- 14. Total de ingresos por reservas (facturas 'Pagada', sin IVA).
DROP FUNCTION IF EXISTS fn_ingresos_por_reservas$$
CREATE FUNCTION fn_ingresos_por_reservas()
RETURNS DECIMAL(12,2)
READS SQL DATA
BEGIN
    DECLARE v_total DECIMAL(12,2);

    SET v_total = (
        SELECT SUM(df.subtotal)
        FROM factura f
        JOIN detalle_factura df ON df.facturaID = f.facturaID
        WHERE f.estado = 'Pagada'
          AND df.concepto LIKE 'Reserva%'
    );

    RETURN IFNULL(v_total, 0);
END$$


-- 15. Ingresos totales por una empresa (facturas 'Pagada' de sus usuarios, sin IVA).
DROP FUNCTION IF EXISTS fn_ingresos_por_empresa$$
CREATE FUNCTION fn_ingresos_por_empresa(p_empresa_id INT)
RETURNS DECIMAL(12,2)
READS SQL DATA
BEGIN
    DECLARE v_total DECIMAL(12,2);

    SET v_total = (
        SELECT SUM(f.subtotal)
        FROM factura f
        JOIN usuario u ON u.usuarioID = f.usuarioID
        WHERE u.empresaID = p_empresa_id
          AND f.estado = 'Pagada'
    );

    RETURN IFNULL(v_total, 0);
END$$


-- =====================================================
-- ACCESOS Y ASISTENCIAS
-- =====================================================

-- 16. Cantidad total de asistencias del usuario (solo 'Autorizado').
DROP FUNCTION IF EXISTS fn_total_asistencias$$
CREATE FUNCTION fn_total_asistencias(p_usuario_id INT)
RETURNS INT
READS SQL DATA
BEGIN
    RETURN (
        SELECT COUNT(*)
        FROM asistencia
        WHERE usuarioID = p_usuario_id
          AND resultado_validacion = 'Autorizado'
    );
END$$


-- 17. Total de asistencias del usuario en un mes y año.
DROP FUNCTION IF EXISTS fn_asistencias_mes$$
CREATE FUNCTION fn_asistencias_mes(p_usuario_id INT, p_mes INT, p_anio INT)
RETURNS INT
READS SQL DATA
BEGIN
    RETURN (
        SELECT COUNT(*)
        FROM asistencia
        WHERE usuarioID = p_usuario_id
          AND resultado_validacion = 'Autorizado'
          AND MONTH(fecha) = p_mes
          AND YEAR(fecha)  = p_anio
    );
END$$


-- 18. Usuario con más accesos (ID del usuario con más asistencias autorizadas).
--     En caso de empate devuelve el de menor ID.
DROP FUNCTION IF EXISTS fn_top_usuario_asistencias$$
CREATE FUNCTION fn_top_usuario_asistencias()
RETURNS INT
READS SQL DATA
BEGIN
    RETURN (
        SELECT usuarioID
        FROM asistencia
        WHERE resultado_validacion = 'Autorizado'
        GROUP BY usuarioID
        ORDER BY COUNT(*) DESC, usuarioID
        LIMIT 1
    );
END$$


-- 19. Fecha de la última asistencia autorizada del usuario (NULL si no tiene).
DROP FUNCTION IF EXISTS fn_ultima_asistencia$$
CREATE FUNCTION fn_ultima_asistencia(p_usuario_id INT)
RETURNS DATE
READS SQL DATA
BEGIN
    RETURN (
        SELECT MAX(fecha)
        FROM asistencia
        WHERE usuarioID = p_usuario_id
          AND resultado_validacion = 'Autorizado'
    );
END$$


-- 20. Promedio de asistencias por usuario
--     (asistencias autorizadas / total de usuarios registrados).
DROP FUNCTION IF EXISTS fn_promedio_asistencias$$
CREATE FUNCTION fn_promedio_asistencias()
RETURNS DECIMAL(10,2)
READS SQL DATA
BEGIN
    DECLARE v_asistencias INT;
    DECLARE v_usuarios INT;

    SET v_asistencias = (
        SELECT COUNT(*)
        FROM asistencia
        WHERE resultado_validacion = 'Autorizado'
    );
    SET v_usuarios = (SELECT COUNT(*) FROM usuario);

    IF v_usuarios = 0 THEN
        RETURN 0;
    END IF;

    RETURN ROUND(v_asistencias / v_usuarios, 2);
END$$


DELIMITER ;


-- =====================================================
-- PRUEBAS RÁPIDAS
-- Resultado esperado con los datos iniciales (hoy = 2026-10-01)
-- =====================================================
SELECT fn_membresia_activa(3)            AS membresia_activa,      -- 1
       fn_dias_restantes_membresia(3)    AS dias_restantes,        -- 91
       fn_tipo_membresia(3)              AS tipo,                  -- Corporativa
       fn_renovaciones_membresia(3)      AS renovaciones,          -- 0
       fn_estado_membresia(3)            AS estado;                -- Activa

SELECT fn_total_reservas(3)              AS total_reservas,        -- 2
       fn_horas_reservadas(3, 9, 2026)   AS horas_sep_2026,        -- 2.00
       fn_espacio_mas_reservado()        AS espacio_top,           -- 5
       fn_reservas_activas(3)            AS reservas_activas,      -- 1
       fn_duracion_promedio_reservas(5)  AS duracion_prom_esp5;    -- 120.00

SELECT fn_total_pagado(3)                AS total_pagado,          -- 595000.00
       fn_ingresos_por_mes(9, 2026)      AS ingresos_sep_2026,     -- 590000.00
       fn_ingresos_por_membresias()      AS ingresos_membresias,   -- 1080000.00
       fn_ingresos_por_reservas()        AS ingresos_reservas,     -- 60000.00
       fn_ingresos_por_empresa(1)        AS ingresos_empresa_1;    -- 100000.00

SELECT fn_total_asistencias(3)           AS total_asistencias,     -- 2
       fn_asistencias_mes(3, 9, 2026)    AS asistencias_sep,       -- 2
       fn_top_usuario_asistencias()      AS usuario_top,           -- 3
       fn_ultima_asistencia(3)           AS ultima_asistencia,     -- 2026-09-29
       fn_promedio_asistencias()         AS promedio_asistencias;  -- 0.70
