USE coworking;

-- =====================================================
-- CONSULTAS: PAGOS Y FACTURACIÓN (41-60)
-- =====================================================
-- Convenciones:
--  * El tipo de ingreso de una factura se deduce del concepto en
--    detalle_factura: 'Membresía%', 'Reserva%' o 'Servicio%'.
--  * Los ingresos se calculan sobre facturas con estado 'Pagada' y
--    sobre el subtotal (sin IVA), salvo que se indique otra cosa.
--  * Los pagos "realizados" son los de estado 'Pagado'.
-- =====================================================


-- 41. Listar todos los pagos realizados con método tarjeta.
SELECT p.pagoID, p.fecha_pago, p.monto, p.referencia,
       u.usuarioID, u.nombre, u.apellido
FROM pago p
JOIN usuario u ON u.usuarioID = p.usuarioID
WHERE p.metodo_pago = 'Tarjeta'
  AND p.estado = 'Pagado'
ORDER BY p.fecha_pago DESC;


-- 42. Listar pagos pendientes de usuarios.
SELECT p.pagoID, p.fecha_pago, p.monto, p.metodo_pago, p.referencia,
       u.usuarioID, u.nombre, u.apellido
FROM pago p
JOIN usuario u ON u.usuarioID = p.usuarioID
WHERE p.estado = 'Pendiente'
ORDER BY p.fecha_pago;


-- 43. Mostrar pagos cancelados en los últimos 3 meses.
SELECT p.pagoID, p.fecha_pago, p.monto, p.metodo_pago, p.referencia,
       u.usuarioID, u.nombre, u.apellido
FROM pago p
JOIN usuario u ON u.usuarioID = p.usuarioID
WHERE p.estado = 'Cancelado'
  AND p.fecha_pago >= DATE_SUB(CURDATE(), INTERVAL 3 MONTH)
ORDER BY p.fecha_pago DESC;


-- 44. Listar facturas generadas por membresías.
SELECT DISTINCT
    f.facturaID, f.numero_factura, f.fecha_emision, f.total, f.estado,
    u.usuarioID, u.nombre, u.apellido
FROM factura f
JOIN detalle_factura df ON df.facturaID = f.facturaID
JOIN usuario u          ON u.usuarioID  = f.usuarioID
WHERE df.concepto LIKE 'Membresía%'
ORDER BY f.fecha_emision DESC;


-- 45. Listar facturas generadas por reservas.
SELECT DISTINCT
    f.facturaID, f.numero_factura, f.fecha_emision, f.total, f.estado,
    u.usuarioID, u.nombre, u.apellido
FROM factura f
JOIN detalle_factura df ON df.facturaID = f.facturaID
JOIN usuario u          ON u.usuarioID  = f.usuarioID
WHERE df.concepto LIKE 'Reserva%'
ORDER BY f.fecha_emision DESC;


-- 46. Mostrar el total de ingresos por membresías en el último mes.
SELECT COALESCE(SUM(df.subtotal), 0) AS ingresos_membresias_ultimo_mes
FROM factura f
JOIN detalle_factura df ON df.facturaID = f.facturaID
WHERE f.estado = 'Pagada'
  AND df.concepto LIKE 'Membresía%'
  AND f.fecha_emision >= DATE_SUB(CURDATE(), INTERVAL 1 MONTH);


-- 47. Mostrar el total de ingresos por reservas en el último mes.
SELECT COALESCE(SUM(df.subtotal), 0) AS ingresos_reservas_ultimo_mes
FROM factura f
JOIN detalle_factura df ON df.facturaID = f.facturaID
WHERE f.estado = 'Pagada'
  AND df.concepto LIKE 'Reserva%'
  AND f.fecha_emision >= DATE_SUB(CURDATE(), INTERVAL 1 MONTH);


-- 48. Mostrar el total de ingresos por servicios adicionales.
--     Total histórico, desglosado por servicio.
SELECT
    df.concepto AS servicio,
    SUM(df.cantidad) AS unidades,
    SUM(df.subtotal) AS ingresos
FROM factura f
JOIN detalle_factura df ON df.facturaID = f.facturaID
WHERE f.estado = 'Pagada'
  AND df.concepto LIKE 'Servicio%'
GROUP BY df.concepto
WITH ROLLUP;


-- 49. Identificar usuarios que nunca han pagado con PayPal.
SELECT u.usuarioID, u.nombre, u.apellido
FROM usuario u
WHERE NOT EXISTS (
    SELECT 1
    FROM pago p
    WHERE p.usuarioID = u.usuarioID
      AND p.metodo_pago = 'PayPal'
      AND p.estado = 'Pagado'
)
ORDER BY u.usuarioID;


-- 50. Calcular el promedio de gasto por usuario.
--     Promedio entre los usuarios que tienen al menos un pago realizado.
SELECT ROUND(AVG(gasto_usuario), 2) AS promedio_gasto_por_usuario
FROM (
    SELECT usuarioID, SUM(monto) AS gasto_usuario
    FROM pago
    WHERE estado = 'Pagado'
    GROUP BY usuarioID
) t;


-- 51. Mostrar el top 5 de usuarios que más han pagado en total.
SELECT
    u.usuarioID,
    u.nombre,
    u.apellido,
    SUM(p.monto) AS total_pagado
FROM usuario u
JOIN pago p ON p.usuarioID = u.usuarioID
WHERE p.estado = 'Pagado'
GROUP BY u.usuarioID, u.nombre, u.apellido
ORDER BY total_pagado DESC
LIMIT 5;


-- 52. Mostrar facturas con monto mayor a $1000.
--     Ajusta el umbral si lo necesitas (los montos están en pesos).
SELECT f.facturaID, f.numero_factura, f.fecha_emision, f.total, f.estado,
       u.usuarioID, u.nombre, u.apellido
FROM factura f
JOIN usuario u ON u.usuarioID = f.usuarioID
WHERE f.total > 1000
ORDER BY f.total DESC;


-- 53. Listar pagos realizados después de la fecha de vencimiento.
--     El modelo no tiene fecha de vencimiento en factura, así que se usa
--     como referencia la fecha_fin de la membresía actual del usuario.
SELECT
    p.pagoID,
    p.fecha_pago,
    p.monto,
    u.usuarioID,
    u.nombre,
    u.apellido,
    m.fecha_fin AS fecha_vencimiento,
    DATEDIFF(DATE(p.fecha_pago), m.fecha_fin) AS dias_despues
FROM pago p
JOIN usuario  u ON u.usuarioID   = p.usuarioID
JOIN membresia m ON m.membresiaID = u.membresiaID
WHERE p.estado = 'Pagado'
  AND DATE(p.fecha_pago) > m.fecha_fin
ORDER BY dias_despues DESC;


-- 54. Calcular el total recaudado en el año actual.
SELECT COALESCE(SUM(monto), 0) AS total_recaudado_anio_actual
FROM pago
WHERE estado = 'Pagado'
  AND YEAR(fecha_pago) = YEAR(CURDATE());


-- 55. Mostrar facturas anuladas y su motivo.
--     La tabla factura no guarda el motivo de anulación. Se muestra el estado
--     del pago asociado como referencia. Si quieres el motivo real, agrega
--     una columna: ALTER TABLE factura ADD COLUMN motivo_anulacion VARCHAR(200);
SELECT
    f.facturaID,
    f.numero_factura,
    f.fecha_emision,
    f.total,
    u.usuarioID,
    u.nombre,
    u.apellido,
    p.estado     AS estado_pago_asociado,
    p.referencia AS referencia_pago
FROM factura f
JOIN usuario u ON u.usuarioID = f.usuarioID
LEFT JOIN pago p ON p.pagoID  = f.pagoID
WHERE f.estado = 'Cancelada'
ORDER BY f.fecha_emision DESC;


-- 56. Mostrar usuarios con facturas pendientes mayores a $200.
--     Se suma lo pendiente por usuario y se filtra el acumulado.
SELECT
    u.usuarioID,
    u.nombre,
    u.apellido,
    COUNT(f.facturaID) AS facturas_pendientes,
    SUM(f.total)       AS total_pendiente
FROM usuario u
JOIN factura f ON f.usuarioID = u.usuarioID
WHERE f.estado = 'Pendiente'
GROUP BY u.usuarioID, u.nombre, u.apellido
HAVING SUM(f.total) > 200
ORDER BY total_pendiente DESC;


-- 57. Mostrar usuarios que han pagado más de una vez el mismo servicio.
SELECT
    u.usuarioID,
    u.nombre,
    u.apellido,
    df.concepto AS servicio,
    COUNT(DISTINCT f.facturaID) AS veces_pagado
FROM usuario u
JOIN factura f          ON f.usuarioID  = u.usuarioID
JOIN detalle_factura df ON df.facturaID = f.facturaID
WHERE f.estado = 'Pagada'
  AND df.concepto LIKE 'Servicio%'
GROUP BY u.usuarioID, u.nombre, u.apellido, df.concepto
HAVING COUNT(DISTINCT f.facturaID) > 1
ORDER BY veces_pagado DESC;


-- 58. Listar ingresos por cada método de pago.
SELECT
    metodo_pago,
    COUNT(*)   AS cantidad_pagos,
    SUM(monto) AS total_ingresos
FROM pago
WHERE estado = 'Pagado'
GROUP BY metodo_pago
ORDER BY total_ingresos DESC;


-- 59. Mostrar facturación acumulada por empresa.
--     Facturado = facturas no canceladas; pagado = solo las 'Pagada'.
SELECT
    e.empresaID,
    e.nombre AS empresa,
    COUNT(f.facturaID)                                     AS facturas,
    COALESCE(SUM(f.total), 0)                              AS total_facturado,
    COALESCE(SUM(CASE WHEN f.estado = 'Pagada' THEN f.total END), 0) AS total_pagado
FROM empresa e
LEFT JOIN usuario u ON u.empresaID = e.empresaID
LEFT JOIN factura f ON f.usuarioID = u.usuarioID
                   AND f.estado <> 'Cancelada'
GROUP BY e.empresaID, e.nombre
ORDER BY total_facturado DESC;


-- 60. Mostrar ingresos netos por mes del último año.
--     Ingreso neto = subtotal (total menos impuestos) de facturas pagadas.
SELECT
    DATE_FORMAT(fecha_emision, '%Y-%m') AS mes,
    SUM(subtotal)  AS ingresos_netos,
    SUM(impuestos) AS impuestos,
    SUM(total)     AS total_facturado
FROM factura
WHERE estado = 'Pagada'
  AND fecha_emision >= DATE_SUB(CURDATE(), INTERVAL 12 MONTH)
GROUP BY DATE_FORMAT(fecha_emision, '%Y-%m')
ORDER BY mes;
