USE coworking;

-- =====================================================
-- CONSULTAS: USUARIOS Y MEMBRESÍAS (20)
-- =====================================================
-- Convención: la membresía "actual" de un usuario es la que apunta
-- usuario.membresiaID. El historial completo está en la tabla membresia.
-- =====================================================


-- 1. Listar todos los usuarios con su información básica.
SELECT
    u.usuarioID,
    u.nombre,
    u.apellido,
    u.edad,
    u.contacto,
    e.nombre AS empresa,
    m.tipo   AS tipo_membresia,
    m.estado AS estado_membresia
FROM usuario u
LEFT JOIN empresa   e ON e.empresaID   = u.empresaID
LEFT JOIN membresia m ON m.membresiaID = u.membresiaID
ORDER BY u.usuarioID;


-- 2. Listar los usuarios con membresía activa.
SELECT u.usuarioID, u.nombre, u.apellido, m.tipo, m.fecha_inicio, m.fecha_fin
FROM usuario u
JOIN membresia m ON m.membresiaID = u.membresiaID
WHERE m.estado = 'Activa'
ORDER BY u.usuarioID;


-- 3. Listar los usuarios cuya membresía está vencida.
SELECT u.usuarioID, u.nombre, u.apellido, m.tipo, m.fecha_fin
FROM usuario u
JOIN membresia m ON m.membresiaID = u.membresiaID
WHERE m.estado = 'Vencida'
ORDER BY m.fecha_fin DESC;


-- 4. Listar los usuarios con membresía suspendida.
SELECT u.usuarioID, u.nombre, u.apellido, m.tipo, m.fecha_inicio, m.fecha_fin
FROM usuario u
JOIN membresia m ON m.membresiaID = u.membresiaID
WHERE m.estado = 'Suspendida'
ORDER BY u.usuarioID;


-- 5. Contar cuántos usuarios tienen cada tipo de membresía.
--    (LEFT JOIN para que aparezcan también los tipos con 0 usuarios)
SELECT
    t.nombre AS tipo_membresia,
    COUNT(u.usuarioID) AS total_usuarios
FROM tipo_membresia t
LEFT JOIN membresia m ON m.tipoID      = t.tipoID
LEFT JOIN usuario   u ON u.membresiaID = m.membresiaID
GROUP BY t.tipoID, t.nombre
ORDER BY total_usuarios DESC;


-- 6. Mostrar el top 10 de usuarios con más antigüedad en el coworking.
--    La tabla usuario no tiene fecha de registro; la antigüedad se mide
--    desde la fecha de inicio de su primera membresía.
SELECT
    u.usuarioID,
    u.nombre,
    u.apellido,
    MIN(m.fecha_inicio) AS fecha_primera_membresia,
    DATEDIFF(CURDATE(), MIN(m.fecha_inicio)) AS dias_antiguedad
FROM usuario u
JOIN membresia m ON m.usuarioID = u.usuarioID
GROUP BY u.usuarioID, u.nombre, u.apellido
ORDER BY fecha_primera_membresia ASC
LIMIT 10;


-- 7. Listar usuarios que pertenecen a una empresa específica.
--    Cambia el nombre de la empresa según lo necesites.
SELECT u.usuarioID, u.nombre, u.apellido, u.contacto, e.nombre AS empresa
FROM usuario u
JOIN empresa e ON e.empresaID = u.empresaID
WHERE e.nombre = 'TechSoft SAS'
ORDER BY u.apellido, u.nombre;


-- 8. Contar cuántos usuarios están asociados a cada empresa.
SELECT
    e.empresaID,
    e.nombre AS empresa,
    COUNT(u.usuarioID) AS total_usuarios
FROM empresa e
LEFT JOIN usuario u ON u.empresaID = e.empresaID
GROUP BY e.empresaID, e.nombre
ORDER BY total_usuarios DESC, e.nombre;


-- 9. Mostrar usuarios que nunca han hecho una reserva.
SELECT u.usuarioID, u.nombre, u.apellido
FROM usuario u
WHERE NOT EXISTS (
    SELECT 1 FROM reserva r WHERE r.usuarioID = u.usuarioID
)
ORDER BY u.usuarioID;


-- 10. Mostrar usuarios con más de 5 reservas activas en el mes.
--     "Activa" = estado Pendiente o Confirmada, con fecha dentro del mes actual.
SELECT
    u.usuarioID,
    u.nombre,
    u.apellido,
    COUNT(r.reservaID) AS reservas_activas_mes
FROM usuario u
JOIN reserva r ON r.usuarioID = u.usuarioID
WHERE r.estado IN ('Pendiente', 'Confirmada')
  AND YEAR(r.fecha_reserva)  = YEAR(CURDATE())
  AND MONTH(r.fecha_reserva) = MONTH(CURDATE())
GROUP BY u.usuarioID, u.nombre, u.apellido
HAVING COUNT(r.reservaID) > 5
ORDER BY reservas_activas_mes DESC;


-- 11. Calcular el promedio de edad de los usuarios.
SELECT ROUND(AVG(edad), 2) AS promedio_edad
FROM usuario;


-- 12. Listar usuarios que han cambiado de membresía más de 2 veces.
--     Cada fila de membresia es una membresía; cambios = membresías - 1.
SELECT
    u.usuarioID,
    u.nombre,
    u.apellido,
    COUNT(m.membresiaID)     AS total_membresias,
    COUNT(m.membresiaID) - 1 AS cambios
FROM usuario u
JOIN membresia m ON m.usuarioID = u.usuarioID
GROUP BY u.usuarioID, u.nombre, u.apellido
HAVING COUNT(m.membresiaID) - 1 > 2
ORDER BY cambios DESC;


-- 13. Listar usuarios que han gastado más de $500 en reservas.
--     El gasto en reservas se toma de detalle_factura (concepto 'Reserva...')
--     de facturas pagadas. Ajusta el umbral (500) si lo necesitas.
SELECT
    u.usuarioID,
    u.nombre,
    u.apellido,
    SUM(df.subtotal) AS total_gastado_reservas
FROM usuario u
JOIN factura         f  ON f.usuarioID  = u.usuarioID
JOIN detalle_factura df ON df.facturaID = f.facturaID
WHERE f.estado = 'Pagada'
  AND df.concepto LIKE 'Reserva%'
GROUP BY u.usuarioID, u.nombre, u.apellido
HAVING SUM(df.subtotal) > 500
ORDER BY total_gastado_reservas DESC;


-- 14. Mostrar usuarios que tienen tanto membresía como servicios adicionales.
SELECT
    u.usuarioID,
    u.nombre,
    u.apellido,
    m.tipo AS tipo_membresia,
    GROUP_CONCAT(DISTINCT s.nombre ORDER BY s.nombre SEPARATOR ', ') AS servicios
FROM usuario u
JOIN membresia        m  ON m.membresiaID = u.membresiaID
JOIN usuario_servicio us ON us.usuarioID  = u.usuarioID
JOIN servicio_adicional s ON s.servicioID = us.servicioID
GROUP BY u.usuarioID, u.nombre, u.apellido, m.tipo
ORDER BY u.usuarioID;


-- 15. Listar usuarios con membresía Premium y reservas activas.
--     Reservas activas = Pendiente o Confirmada.
SELECT DISTINCT
    u.usuarioID,
    u.nombre,
    u.apellido,
    m.estado AS estado_membresia,
    r.reservaID,
    r.fecha_reserva,
    r.estado AS estado_reserva
FROM usuario u
JOIN membresia m ON m.membresiaID = u.membresiaID
JOIN reserva   r ON r.usuarioID   = u.usuarioID
WHERE m.tipo = 'Premium'
  AND r.estado IN ('Pendiente', 'Confirmada')
ORDER BY u.usuarioID, r.fecha_reserva;


-- 16. Mostrar usuarios con membresía Corporativa y su empresa.
SELECT
    u.usuarioID,
    u.nombre,
    u.apellido,
    m.estado AS estado_membresia,
    e.nombre AS empresa,
    e.nit
FROM usuario u
JOIN membresia m ON m.membresiaID = u.membresiaID
LEFT JOIN empresa e ON e.empresaID = u.empresaID
WHERE m.tipo = 'Corporativa'
ORDER BY e.nombre, u.apellido;


-- 17. Identificar usuarios con membresía diaria que la han renovado más de 10 veces.
--     Renovaciones = membresías Diarias del usuario - 1.
SELECT
    u.usuarioID,
    u.nombre,
    u.apellido,
    COUNT(m.membresiaID)     AS total_membresias_diarias,
    COUNT(m.membresiaID) - 1 AS renovaciones
FROM usuario u
JOIN membresia m ON m.usuarioID = u.usuarioID
WHERE m.tipo = 'Diaria'
GROUP BY u.usuarioID, u.nombre, u.apellido
HAVING COUNT(m.membresiaID) - 1 > 10
ORDER BY renovaciones DESC;


-- 18. Mostrar usuarios cuya membresía vence en los próximos 7 días.
SELECT
    u.usuarioID,
    u.nombre,
    u.apellido,
    m.tipo,
    m.fecha_fin,
    DATEDIFF(m.fecha_fin, CURDATE()) AS dias_restantes
FROM usuario u
JOIN membresia m ON m.membresiaID = u.membresiaID
WHERE m.estado = 'Activa'
  AND m.fecha_fin BETWEEN CURDATE() AND DATE_ADD(CURDATE(), INTERVAL 7 DAY)
ORDER BY m.fecha_fin;


-- 19. Listar usuarios que se registraron en el último mes.
--     Sin fecha de registro en usuario, se usa la fecha de inicio de su
--     primera membresía como fecha de ingreso.
SELECT
    u.usuarioID,
    u.nombre,
    u.apellido,
    MIN(m.fecha_inicio) AS fecha_ingreso
FROM usuario u
JOIN membresia m ON m.usuarioID = u.usuarioID
GROUP BY u.usuarioID, u.nombre, u.apellido
HAVING MIN(m.fecha_inicio) >= DATE_SUB(CURDATE(), INTERVAL 1 MONTH)
ORDER BY fecha_ingreso DESC;


-- 20. Mostrar usuarios que nunca han asistido al coworking (0 accesos).
--     Se considera asistencia solo una entrada con resultado 'Autorizado'.
SELECT u.usuarioID, u.nombre, u.apellido
FROM usuario u
WHERE NOT EXISTS (
    SELECT 1
    FROM asistencia a
    WHERE a.usuarioID = u.usuarioID
      AND a.resultado_validacion = 'Autorizado'
)
ORDER BY u.usuarioID;
