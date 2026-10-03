USE coworking;

-- =====================================================
-- CONSULTAS 21 - 40: ESPACIOS Y RESERVAS
-- (compatible con MySQL 8.0+, usa CTE en la 26)
-- =====================================================

-- 21. Listar todos los espacios disponibles con su capacidad.
SELECT espacioID, nombre, tipo, capacidad_maxima, ubicacion
FROM espacio
WHERE estado = 'Disponible'
ORDER BY capacidad_maxima DESC;

-- 22. Listar reservas activas en el día actual.
-- (activa = Pendiente o Confirmada)
SELECT r.reservaID, r.fecha_reserva, r.hora_inicio, r.hora_fin, r.estado,
       e.nombre AS espacio,
       CONCAT(u.nombre, ' ', u.apellido) AS usuario
FROM reserva r
JOIN espacio e ON e.espacioID = r.espacioID
JOIN usuario u ON u.usuarioID = r.usuarioID
WHERE r.fecha_reserva = CURDATE()
  AND r.estado IN ('Pendiente', 'Confirmada')
ORDER BY r.hora_inicio;

-- 23. Mostrar reservas canceladas en el último mes.
SELECT r.reservaID, r.fecha_reserva, r.hora_inicio, r.hora_fin,
       e.nombre AS espacio,
       CONCAT(u.nombre, ' ', u.apellido) AS usuario
FROM reserva r
JOIN espacio e ON e.espacioID = r.espacioID
JOIN usuario u ON u.usuarioID = r.usuarioID
WHERE r.estado = 'Cancelada'
  AND r.fecha_reserva BETWEEN DATE_SUB(CURDATE(), INTERVAL 1 MONTH) AND CURDATE()
ORDER BY r.fecha_reserva DESC;

-- 24. Listar reservas de salas de reuniones en horario pico (9 am - 11 am).
-- Se incluye toda reserva que se cruce con el rango 09:00-11:00.
SELECT r.reservaID, r.fecha_reserva, r.hora_inicio, r.hora_fin, r.estado,
       e.nombre AS sala,
       CONCAT(u.nombre, ' ', u.apellido) AS usuario
FROM reserva r
JOIN espacio e ON e.espacioID = r.espacioID
JOIN usuario u ON u.usuarioID = r.usuarioID
WHERE e.tipo = 'Sala de reuniones'
  AND r.hora_inicio < '11:00:00'
  AND r.hora_fin    > '09:00:00'
ORDER BY r.fecha_reserva, r.hora_inicio;

-- 25. Contar cuántas reservas se hacen por cada tipo de espacio.
SELECT e.tipo, COUNT(r.reservaID) AS total_reservas
FROM espacio e
LEFT JOIN reserva r ON r.espacioID = e.espacioID
GROUP BY e.tipo
ORDER BY total_reservas DESC;

-- 26. Mostrar el espacio más reservado del último mes.
-- Usa CTE para devolver también los empates; excluye canceladas.
WITH conteo AS (
    SELECT e.espacioID, e.nombre, e.tipo, COUNT(*) AS total_reservas
    FROM reserva r
    JOIN espacio e ON e.espacioID = r.espacioID
    WHERE r.estado <> 'Cancelada'
      AND r.fecha_reserva BETWEEN DATE_SUB(CURDATE(), INTERVAL 1 MONTH) AND CURDATE()
    GROUP BY e.espacioID, e.nombre, e.tipo
)
SELECT *
FROM conteo
WHERE total_reservas = (SELECT MAX(total_reservas) FROM conteo);

-- 27. Listar usuarios que más han reservado salas privadas.
-- (sala privada = tipo 'Oficina privada')
SELECT u.usuarioID, CONCAT(u.nombre, ' ', u.apellido) AS usuario,
       COUNT(*) AS reservas_oficina_privada
FROM reserva r
JOIN espacio e ON e.espacioID = r.espacioID
JOIN usuario u ON u.usuarioID = r.usuarioID
WHERE e.tipo = 'Oficina privada'
GROUP BY u.usuarioID, u.nombre, u.apellido
ORDER BY reservas_oficina_privada DESC;

-- 28. Mostrar reservas que exceden la capacidad máxima del espacio.
-- La tabla reserva NO guarda número de personas. Se usa como aproximación
-- la cantidad de asistentes registrados en asistencia por cada reserva.
SELECT r.reservaID, e.nombre AS espacio, e.capacidad_maxima,
       COUNT(a.asistenciaID) AS asistentes
FROM reserva r
JOIN espacio e ON e.espacioID = r.espacioID
JOIN asistencia a ON a.reservaID = r.reservaID
GROUP BY r.reservaID, e.nombre, e.capacidad_maxima
HAVING COUNT(a.asistenciaID) > e.capacidad_maxima;
-- Si agregas una columna reserva.num_personas, sería:
-- SELECT r.* FROM reserva r JOIN espacio e USING (espacioID)
-- WHERE r.num_personas > e.capacidad_maxima;

-- 29. Listar espacios que no se han reservado en la última semana.
SELECT e.espacioID, e.nombre, e.tipo, e.estado
FROM espacio e
WHERE NOT EXISTS (
    SELECT 1
    FROM reserva r
    WHERE r.espacioID = e.espacioID
      AND r.estado <> 'Cancelada'
      AND r.fecha_reserva BETWEEN DATE_SUB(CURDATE(), INTERVAL 7 DAY) AND CURDATE()
);

-- 30. Calcular la tasa de ocupación promedio de cada espacio.
-- Por reserva: minutos reservados / minutos del horario de ese día de la semana.
-- Las reservas en días sin horario definido quedan fuera del promedio (NULL).
SELECT e.espacioID, e.nombre,
       ROUND(AVG(r.duracion / TIMESTAMPDIFF(MINUTE, h.hora_inicio, h.hora_fin)) * 100, 2)
           AS tasa_ocupacion_pct
FROM espacio e
LEFT JOIN reserva r
       ON r.espacioID = e.espacioID AND r.estado <> 'Cancelada'
LEFT JOIN horario_disponibilidad h
       ON h.espacioID = e.espacioID
      AND h.dia_semana = ELT(WEEKDAY(r.fecha_reserva) + 1,
                             'Lunes', 'Martes', 'Miercoles', 'Jueves',
                             'Viernes', 'Sabado', 'Domingo')
GROUP BY e.espacioID, e.nombre
ORDER BY tasa_ocupacion_pct DESC;

-- 31. Mostrar reservas de más de 8 horas.
SELECT r.reservaID, r.fecha_reserva, r.hora_inicio, r.hora_fin,
       ROUND(r.duracion / 60, 1) AS horas,
       e.nombre AS espacio,
       CONCAT(u.nombre, ' ', u.apellido) AS usuario
FROM reserva r
JOIN espacio e ON e.espacioID = r.espacioID
JOIN usuario u ON u.usuarioID = r.usuarioID
WHERE r.duracion > 480
ORDER BY r.duracion DESC;

-- 32. Identificar usuarios con más de 20 reservas en total.
SELECT u.usuarioID, CONCAT(u.nombre, ' ', u.apellido) AS usuario,
       COUNT(r.reservaID) AS total_reservas
FROM usuario u
JOIN reserva r ON r.usuarioID = u.usuarioID
GROUP BY u.usuarioID, u.nombre, u.apellido
HAVING COUNT(r.reservaID) > 20;

-- 33. Mostrar reservas realizadas por empresas con más de 10 empleados.
-- Empleados = usuarios asociados a la empresa.
SELECT r.reservaID, r.fecha_reserva, emp.nombre AS empresa,
       CONCAT(u.nombre, ' ', u.apellido) AS usuario,
       e.nombre AS espacio
FROM reserva r
JOIN usuario u  ON u.usuarioID = r.usuarioID
JOIN empresa emp ON emp.empresaID = u.empresaID
JOIN espacio e  ON e.espacioID = r.espacioID
WHERE u.empresaID IN (
    SELECT empresaID
    FROM usuario
    WHERE empresaID IS NOT NULL
    GROUP BY empresaID
    HAVING COUNT(*) > 10
);

-- 34. Listar reservas que se solapan en horario (mismo espacio y mismo día).
SELECT r1.reservaID AS reserva_1, r2.reservaID AS reserva_2,
       e.nombre AS espacio, r1.fecha_reserva,
       r1.hora_inicio AS inicio_1, r1.hora_fin AS fin_1,
       r2.hora_inicio AS inicio_2, r2.hora_fin AS fin_2
FROM reserva r1
JOIN reserva r2
  ON r1.espacioID = r2.espacioID
 AND r1.fecha_reserva = r2.fecha_reserva
 AND r1.reservaID < r2.reservaID
 AND r1.hora_inicio < r2.hora_fin
 AND r2.hora_inicio < r1.hora_fin
JOIN espacio e ON e.espacioID = r1.espacioID
WHERE r1.estado <> 'Cancelada'
  AND r2.estado <> 'Cancelada';

-- 35. Listar reservas de fin de semana.
-- DAYOFWEEK: 1 = domingo, 7 = sábado.
SELECT r.reservaID, r.fecha_reserva,
       DAYNAME(r.fecha_reserva) AS dia,
       r.hora_inicio, r.hora_fin, r.estado,
       e.nombre AS espacio
FROM reserva r
JOIN espacio e ON e.espacioID = r.espacioID
WHERE DAYOFWEEK(r.fecha_reserva) IN (1, 7)
ORDER BY r.fecha_reserva;

-- 36. Mostrar el porcentaje de ocupación por cada tipo de espacio.
-- Ocupación = espacios en estado 'Ocupado' sobre el total de espacios del tipo.
SELECT tipo,
       COUNT(*) AS total_espacios,
       SUM(estado = 'Ocupado') AS ocupados,
       ROUND(SUM(estado = 'Ocupado') / COUNT(*) * 100, 2) AS porcentaje_ocupacion
FROM espacio
GROUP BY tipo;

-- 37. Mostrar la duración promedio de reservas por tipo de espacio.
SELECT e.tipo,
       ROUND(AVG(r.duracion), 1)      AS promedio_minutos,
       ROUND(AVG(r.duracion) / 60, 2) AS promedio_horas
FROM espacio e
JOIN reserva r ON r.espacioID = e.espacioID
GROUP BY e.tipo
ORDER BY promedio_minutos DESC;

-- 38. Mostrar reservas con servicios adicionales incluidos.
-- Se considera incluido el servicio del usuario vigente en la fecha de la reserva.
SELECT r.reservaID, r.fecha_reserva,
       CONCAT(u.nombre, ' ', u.apellido) AS usuario,
       e.nombre AS espacio,
       s.nombre AS servicio, us.cantidad
FROM reserva r
JOIN usuario u ON u.usuarioID = r.usuarioID
JOIN espacio e ON e.espacioID = r.espacioID
JOIN usuario_servicio us
  ON us.usuarioID = r.usuarioID
 AND r.fecha_reserva BETWEEN us.fecha_inicio AND COALESCE(us.fecha_fin, r.fecha_reserva)
JOIN servicio_adicional s ON s.servicioID = us.servicioID
ORDER BY r.reservaID;

-- 39. Listar usuarios que reservaron sala de eventos en los últimos 6 meses.
-- Sin límite superior de fecha: incluye reservas futuras ya registradas.
-- Para solo pasadas, agrega: AND r.fecha_reserva <= CURDATE()
SELECT DISTINCT u.usuarioID, CONCAT(u.nombre, ' ', u.apellido) AS usuario, u.contacto
FROM reserva r
JOIN espacio e ON e.espacioID = r.espacioID
JOIN usuario u ON u.usuarioID = r.usuarioID
WHERE e.tipo = 'Sala de eventos'
  AND r.estado <> 'Cancelada'
  AND r.fecha_reserva >= DATE_SUB(CURDATE(), INTERVAL 6 MONTH);

-- 40. Identificar reservas realizadas y nunca asistidas.
-- Reservas no canceladas, ya vencidas, sin ninguna asistencia autorizada.
SELECT r.reservaID, r.fecha_reserva, r.hora_inicio, r.hora_fin, r.estado,
       e.nombre AS espacio,
       CONCAT(u.nombre, ' ', u.apellido) AS usuario
FROM reserva r
JOIN espacio e ON e.espacioID = r.espacioID
JOIN usuario u ON u.usuarioID = r.usuarioID
WHERE r.estado IN ('Confirmada', 'Finalizada')
  AND r.fecha_reserva <= CURDATE()
  AND NOT EXISTS (
      SELECT 1
      FROM asistencia a
      WHERE a.reservaID = r.reservaID
        AND a.resultado_validacion = 'Autorizado'
  );