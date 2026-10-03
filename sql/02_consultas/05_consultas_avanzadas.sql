USE coworking;

-- =====================================================
-- CONSULTAS AVANZADAS (81-100): subconsultas, joins, CTE y funciones de ventana
-- =====================================================
-- Requiere MySQL 8.0 o superior (CTE y funciones de ventana).
-- Convenciones:
--  * Pago realizado = pago.estado = 'Pagado'.
--  * Reserva activa = Pendiente o Confirmada.
--  * Reserva efectiva (cuenta como uso) = Confirmada o Finalizada.
--  * Membresía actual = la que apunta usuario.membresiaID.
--  * El tipo de ingreso de una factura se deduce del concepto en
--    detalle_factura ('Membresía%', 'Reserva%', 'Servicio%').
-- =====================================================


-- 81. Mostrar los usuarios con el mayor gasto acumulado (subconsulta con SUM).
SELECT t.usuarioID, t.nombre, t.apellido, t.gasto_acumulado
FROM (
    SELECT
        u.usuarioID,
        u.nombre,
        u.apellido,
        (SELECT SUM(p.monto)
         FROM pago p
         WHERE p.usuarioID = u.usuarioID
           AND p.estado = 'Pagado') AS gasto_acumulado
    FROM usuario u
) t
WHERE t.gasto_acumulado IS NOT NULL
ORDER BY t.gasto_acumulado DESC
LIMIT 5;


-- 82. Mostrar los espacios más ocupados considerando reservas confirmadas
--     y asistencias reales.
--     Reserva confirmada = Confirmada o Finalizada. Asistencia real = entrada
--     autorizada ligada a una reserva de ese espacio.
SELECT
    e.espacioID,
    e.nombre AS espacio,
    e.tipo,
    COUNT(DISTINCT r.reservaID) AS reservas_confirmadas,
    COUNT(a.asistenciaID)       AS asistencias_reales,
    COUNT(DISTINCT r.reservaID) + COUNT(a.asistenciaID) AS indice_ocupacion
FROM espacio e
LEFT JOIN reserva r    ON r.espacioID = e.espacioID
                      AND r.estado IN ('Confirmada', 'Finalizada')
LEFT JOIN asistencia a ON a.reservaID = r.reservaID
                      AND a.resultado_validacion = 'Autorizado'
GROUP BY e.espacioID, e.nombre, e.tipo
ORDER BY indice_ocupacion DESC, e.nombre;


-- 83. Calcular el promedio de ingresos por usuario usando subconsultas.
SELECT
    (SELECT COALESCE(SUM(monto), 0) FROM pago WHERE estado = 'Pagado') AS ingresos_totales,
    (SELECT COUNT(*) FROM usuario)                                     AS total_usuarios,
    ROUND(
        (SELECT COALESCE(SUM(monto), 0) FROM pago WHERE estado = 'Pagado')
        / (SELECT COUNT(*) FROM usuario), 2)                           AS promedio_por_usuario_registrado,
    ROUND(
        (SELECT COALESCE(SUM(monto), 0) FROM pago WHERE estado = 'Pagado')
        / (SELECT COUNT(DISTINCT usuarioID) FROM pago WHERE estado = 'Pagado'), 2)
                                                                       AS promedio_por_usuario_que_pago;


-- 84. Listar usuarios que tienen reservas activas y facturas pendientes.
SELECT u.usuarioID, u.nombre, u.apellido
FROM usuario u
WHERE EXISTS (
        SELECT 1 FROM reserva r
        WHERE r.usuarioID = u.usuarioID
          AND r.estado IN ('Pendiente', 'Confirmada')
    )
  AND EXISTS (
        SELECT 1 FROM factura f
        WHERE f.usuarioID = u.usuarioID
          AND f.estado = 'Pendiente'
    )
ORDER BY u.usuarioID;


-- 85. Mostrar empresas cuyos empleados generan más del 20% de los ingresos totales.
--     Ingresos = pagos realizados. El total incluye a los usuarios sin empresa.
SELECT
    e.empresaID,
    e.nombre AS empresa,
    SUM(p.monto) AS ingresos_empresa,
    ROUND(SUM(p.monto) * 100
          / (SELECT SUM(monto) FROM pago WHERE estado = 'Pagado'), 2) AS porcentaje_ingresos
FROM empresa e
JOIN usuario u ON u.empresaID = e.empresaID
JOIN pago    p ON p.usuarioID = u.usuarioID
WHERE p.estado = 'Pagado'
GROUP BY e.empresaID, e.nombre
HAVING SUM(p.monto) > 0.20 * (SELECT SUM(monto) FROM pago WHERE estado = 'Pagado')
ORDER BY porcentaje_ingresos DESC;


-- 86. Mostrar el top 5 de usuarios que más usan servicios adicionales.
--     Se ordena por cantidad de contrataciones y luego por unidades consumidas.
SELECT
    u.usuarioID,
    u.nombre,
    u.apellido,
    COUNT(us.usuario_servicioID)   AS contrataciones,
    COUNT(DISTINCT us.servicioID)  AS servicios_distintos,
    SUM(us.cantidad)               AS unidades_totales
FROM usuario u
JOIN usuario_servicio us ON us.usuarioID = u.usuarioID
GROUP BY u.usuarioID, u.nombre, u.apellido
ORDER BY contrataciones DESC, unidades_totales DESC
LIMIT 5;


-- 87. Mostrar reservas que generaron facturas mayores al promedio.
--     Una reserva se liga a su factura por usuario y por el concepto
--     'Reserva <nombre del espacio>...'. El promedio es el de las facturas
--     generadas por reservas. Para compararlas contra todas las facturas,
--     reemplaza la subconsulta por (SELECT AVG(total) FROM factura).
SELECT
    r.reservaID,
    r.fecha_reserva,
    r.estado AS estado_reserva,
    e.nombre AS espacio,
    u.usuarioID,
    u.nombre,
    u.apellido,
    f.numero_factura,
    f.total AS total_factura
FROM reserva r
JOIN espacio e ON e.espacioID = r.espacioID
JOIN usuario u ON u.usuarioID = r.usuarioID
JOIN factura f ON f.usuarioID = r.usuarioID
JOIN detalle_factura df ON df.facturaID = f.facturaID
                       AND df.concepto LIKE CONCAT('Reserva ', e.nombre, '%')
WHERE r.estado <> 'Cancelada'
  AND f.total > (
        SELECT AVG(f2.total)
        FROM factura f2
        WHERE EXISTS (
            SELECT 1 FROM detalle_factura d2
            WHERE d2.facturaID = f2.facturaID
              AND d2.concepto LIKE 'Reserva%'
        )
    )
ORDER BY f.total DESC;


-- 88. Calcular el porcentaje de ocupación global del coworking por mes.
--     Ocupación = horas reservadas (reservas Confirmada/Finalizada) /
--     horas disponibles según horario_disponibilidad, contando cuántas veces
--     cae cada día de la semana en el mes. Cubre desde el mes de la primera
--     reserva hasta el de la última.
WITH RECURSIVE
rango AS (
    SELECT
        DATE_SUB(MIN(fecha_reserva), INTERVAL DAYOFMONTH(MIN(fecha_reserva)) - 1 DAY) AS ini,
        LAST_DAY(MAX(fecha_reserva)) AS fin
    FROM reserva
),
calendario AS (
    SELECT ini AS fecha FROM rango
    UNION ALL
    SELECT DATE_ADD(c.fecha, INTERVAL 1 DAY)
    FROM calendario c
    JOIN rango r ON c.fecha < r.fin
),
capacidad AS (
    SELECT
        DATE_FORMAT(c.fecha, '%Y-%m') AS mes,
        SUM(TIME_TO_SEC(TIMEDIFF(h.hora_fin, h.hora_inicio)) / 3600) AS horas_disponibles
    FROM calendario c
    JOIN horario_disponibilidad h
      ON h.dia_semana = ELT(WEEKDAY(c.fecha) + 1, 'Lunes', 'Martes', 'Miercoles',
                            'Jueves', 'Viernes', 'Sabado', 'Domingo')
    GROUP BY DATE_FORMAT(c.fecha, '%Y-%m')
),
uso AS (
    SELECT
        DATE_FORMAT(fecha_reserva, '%Y-%m') AS mes,
        SUM(duracion) / 60 AS horas_reservadas
    FROM reserva
    WHERE estado IN ('Confirmada', 'Finalizada')
    GROUP BY DATE_FORMAT(fecha_reserva, '%Y-%m')
)
SELECT
    cap.mes,
    ROUND(COALESCE(uso.horas_reservadas, 0), 2) AS horas_reservadas,
    ROUND(cap.horas_disponibles, 2)             AS horas_disponibles,
    ROUND(COALESCE(uso.horas_reservadas, 0) / cap.horas_disponibles * 100, 2) AS porcentaje_ocupacion
FROM capacidad cap
LEFT JOIN uso ON uso.mes = cap.mes
ORDER BY cap.mes;


-- 89. Mostrar usuarios que tienen más horas de reserva que el promedio del sistema.
--     Promedio = horas de reserva por usuario entre quienes han reservado
--     (se excluyen las canceladas).
SELECT
    u.usuarioID,
    u.nombre,
    u.apellido,
    ROUND(SUM(r.duracion) / 60, 2) AS horas_reservadas
FROM usuario u
JOIN reserva r ON r.usuarioID = u.usuarioID
WHERE r.estado <> 'Cancelada'
GROUP BY u.usuarioID, u.nombre, u.apellido
HAVING SUM(r.duracion) / 60 > (
    SELECT AVG(horas)
    FROM (
        SELECT SUM(duracion) / 60 AS horas
        FROM reserva
        WHERE estado <> 'Cancelada'
        GROUP BY usuarioID
    ) t
)
ORDER BY horas_reservadas DESC;


-- 90. Mostrar el top 3 de salas más usadas en el último trimestre.
--     Salas = espacios de tipo 'Sala de reuniones' y 'Sala de eventos'.
--     Se cuentan reservas Confirmada/Finalizada de los últimos 3 meses, hasta hoy.
SELECT
    e.espacioID,
    e.nombre AS sala,
    e.tipo,
    COUNT(r.reservaID)           AS reservas,
    ROUND(SUM(r.duracion) / 60, 2) AS horas_reservadas
FROM espacio e
JOIN reserva r ON r.espacioID = e.espacioID
WHERE e.tipo IN ('Sala de reuniones', 'Sala de eventos')
  AND r.estado IN ('Confirmada', 'Finalizada')
  AND r.fecha_reserva BETWEEN DATE_SUB(CURDATE(), INTERVAL 3 MONTH) AND CURDATE()
GROUP BY e.espacioID, e.nombre, e.tipo
ORDER BY reservas DESC, horas_reservadas DESC
LIMIT 3;


-- 91. Calcular ingresos promedio por tipo de membresía (agrupado con AVG).
--     Se promedia el total de las facturas pagadas que incluyen cada tipo de
--     membresía. Los tipos sin facturas aparecen con NULL.
SELECT
    t.nombre AS tipo_membresia,
    COUNT(f.facturaID)        AS facturas_pagadas,
    ROUND(AVG(f.total), 2)    AS ingreso_promedio,
    SUM(f.total)              AS ingreso_total
FROM tipo_membresia t
LEFT JOIN detalle_factura df ON df.concepto = CONCAT('Membresía ', t.nombre)
LEFT JOIN factura f          ON f.facturaID = df.facturaID
                            AND f.estado = 'Pagada'
GROUP BY t.tipoID, t.nombre
ORDER BY ingreso_promedio DESC;


-- 92. Mostrar usuarios que pagan solo con un método de pago (subconsulta).
SELECT
    u.usuarioID,
    u.nombre,
    u.apellido,
    p.metodo_pago,
    COUNT(*) AS pagos_realizados
FROM usuario u
JOIN pago p ON p.usuarioID = u.usuarioID
WHERE p.estado = 'Pagado'
  AND u.usuarioID IN (
        SELECT usuarioID
        FROM pago
        WHERE estado = 'Pagado'
        GROUP BY usuarioID
        HAVING COUNT(DISTINCT metodo_pago) = 1
    )
GROUP BY u.usuarioID, u.nombre, u.apellido, p.metodo_pago
ORDER BY pagos_realizados DESC, u.usuarioID;


-- 93. Mostrar reservas canceladas por usuarios que nunca asistieron.
SELECT
    r.reservaID,
    r.fecha_reserva,
    e.nombre AS espacio,
    u.usuarioID,
    u.nombre,
    u.apellido
FROM reserva r
JOIN usuario u ON u.usuarioID = r.usuarioID
JOIN espacio e ON e.espacioID = r.espacioID
WHERE r.estado = 'Cancelada'
  AND NOT EXISTS (
        SELECT 1
        FROM asistencia a
        WHERE a.usuarioID = r.usuarioID
          AND a.resultado_validacion = 'Autorizado'
  )
ORDER BY r.fecha_reserva DESC;


-- 94. Mostrar facturas con pagos parciales y calcular saldo pendiente.
--     Cada factura apunta a un solo pago, así que es parcial cuando el pago
--     realizado es menor que el total de la factura.
SELECT
    f.facturaID,
    f.numero_factura,
    f.total        AS total_factura,
    p.monto        AS monto_pagado,
    f.total - p.monto AS saldo_pendiente,
    u.usuarioID,
    u.nombre,
    u.apellido
FROM factura f
JOIN pago    p ON p.pagoID    = f.pagoID
JOIN usuario u ON u.usuarioID = f.usuarioID
WHERE p.estado = 'Pagado'
  AND f.estado <> 'Cancelada'
  AND p.monto < f.total
ORDER BY saldo_pendiente DESC;


-- 95. Calcular la facturación total de cada empresa y ordenarla de mayor a menor.
--     Se excluyen las facturas canceladas.
SELECT
    e.empresaID,
    e.nombre AS empresa,
    COALESCE(SUM(f.total), 0) AS facturacion_total
FROM empresa e
LEFT JOIN usuario u ON u.empresaID = e.empresaID
LEFT JOIN factura f ON f.usuarioID = u.usuarioID
                   AND f.estado <> 'Cancelada'
GROUP BY e.empresaID, e.nombre
ORDER BY facturacion_total DESC;


-- 96. Identificar usuarios que superan en reservas al promedio de su empresa.
--     Se cuentan las reservas no canceladas. El promedio se calcula entre los
--     usuarios de la misma empresa.
WITH reservas_usuario AS (
    SELECT
        u.usuarioID,
        u.nombre,
        u.apellido,
        u.empresaID,
        COUNT(r.reservaID) AS total_reservas
    FROM usuario u
    LEFT JOIN reserva r ON r.usuarioID = u.usuarioID
                       AND r.estado <> 'Cancelada'
    WHERE u.empresaID IS NOT NULL
    GROUP BY u.usuarioID, u.nombre, u.apellido, u.empresaID
),
promedio_empresa AS (
    SELECT empresaID, AVG(total_reservas) AS promedio_reservas
    FROM reservas_usuario
    GROUP BY empresaID
)
SELECT
    ru.usuarioID,
    ru.nombre,
    ru.apellido,
    e.nombre AS empresa,
    ru.total_reservas,
    ROUND(pe.promedio_reservas, 2) AS promedio_empresa
FROM reservas_usuario ru
JOIN promedio_empresa pe ON pe.empresaID = ru.empresaID
JOIN empresa e           ON e.empresaID  = ru.empresaID
WHERE ru.total_reservas > pe.promedio_reservas
ORDER BY ru.total_reservas DESC;


-- 97. Mostrar las 3 empresas con más empleados activos en el coworking.
--     Empleado activo = usuario de la empresa con membresía actual Activa.
SELECT
    e.empresaID,
    e.nombre AS empresa,
    COUNT(DISTINCT u.usuarioID) AS empleados_activos
FROM empresa e
JOIN usuario   u ON u.empresaID   = e.empresaID
JOIN membresia m ON m.membresiaID = u.membresiaID
WHERE m.estado = 'Activa'
GROUP BY e.empresaID, e.nombre
ORDER BY empleados_activos DESC, e.nombre
LIMIT 3;


-- 98. Calcular el porcentaje de usuarios activos frente al total de registrados.
--     Activo = membresía actual en estado Activa.
SELECT
    COUNT(*) AS total_usuarios,
    SUM(m.estado = 'Activa') AS usuarios_activos,
    ROUND(SUM(m.estado = 'Activa') * 100 / COUNT(*), 2) AS porcentaje_activos
FROM usuario u
LEFT JOIN membresia m ON m.membresiaID = u.membresiaID;


-- 99. Mostrar ingresos mensuales acumulados con función de ventana (OVER).
SELECT
    mes,
    ingresos_mes,
    SUM(ingresos_mes) OVER (ORDER BY mes) AS ingresos_acumulados
FROM (
    SELECT
        DATE_FORMAT(fecha_pago, '%Y-%m') AS mes,
        SUM(monto) AS ingresos_mes
    FROM pago
    WHERE estado = 'Pagado'
    GROUP BY DATE_FORMAT(fecha_pago, '%Y-%m')
) m
ORDER BY mes;


-- 100. Mostrar usuarios con más de 10 reservas, más de $500 en facturación
--      y membresía activa (con múltiples joins).
--      Reservas y facturas se agregan por separado antes de unirlas, para que
--      un join no multiplique las filas del otro. Se excluyen canceladas.
SELECT
    u.usuarioID,
    u.nombre,
    u.apellido,
    e.nombre AS empresa,
    m.tipo   AS tipo_membresia,
    r.total_reservas,
    f.total_facturado
FROM usuario u
JOIN membresia m ON m.membresiaID = u.membresiaID
                AND m.estado = 'Activa'
LEFT JOIN empresa e ON e.empresaID = u.empresaID
JOIN (
    SELECT usuarioID, COUNT(*) AS total_reservas
    FROM reserva
    WHERE estado <> 'Cancelada'
    GROUP BY usuarioID
    HAVING COUNT(*) > 10
) r ON r.usuarioID = u.usuarioID
JOIN (
    SELECT usuarioID, SUM(total) AS total_facturado
    FROM factura
    WHERE estado <> 'Cancelada'
    GROUP BY usuarioID
    HAVING SUM(total) > 500
) f ON f.usuarioID = u.usuarioID
ORDER BY r.total_reservas DESC, f.total_facturado DESC;
