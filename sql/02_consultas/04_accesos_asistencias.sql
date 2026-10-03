USE coworking;

-- =====================================================
-- CONSULTAS: ACCESOS Y ASISTENCIAS (61-80)
-- =====================================================
-- Convenciones:
--  * La tabla acceso guarda las credenciales (RFID/QR) de cada usuario.
--    Cada ingreso al coworking queda en asistencia, así que "accesos" y
--    "asistencias" se calculan sobre asistencia.
--  * Una asistencia válida es la que tiene resultado_validacion = 'Autorizado'.
--  * Membresía actual = la que apunta usuario.membresiaID.
--  * Franjas horarias: mañana = entrada antes de las 12:00,
--    noche = entrada desde las 18:00.
-- =====================================================


-- 61. Listar todos los accesos registrados hoy.
SELECT
    a.asistenciaID,
    a.fecha,
    a.hora_entrada,
    a.hora_salida,
    a.resultado_validacion,
    u.usuarioID,
    u.nombre,
    u.apellido
FROM asistencia a
JOIN usuario u ON u.usuarioID = a.usuarioID
WHERE a.fecha = CURDATE()
ORDER BY a.hora_entrada;


-- 62. Mostrar usuarios con más de 20 asistencias en el mes.
SELECT
    u.usuarioID,
    u.nombre,
    u.apellido,
    COUNT(a.asistenciaID) AS asistencias_mes
FROM usuario u
JOIN asistencia a ON a.usuarioID = u.usuarioID
WHERE a.resultado_validacion = 'Autorizado'
  AND YEAR(a.fecha)  = YEAR(CURDATE())
  AND MONTH(a.fecha) = MONTH(CURDATE())
GROUP BY u.usuarioID, u.nombre, u.apellido
HAVING COUNT(a.asistenciaID) > 20
ORDER BY asistencias_mes DESC;


-- 63. Mostrar usuarios que no asistieron en la última semana.
SELECT u.usuarioID, u.nombre, u.apellido
FROM usuario u
WHERE NOT EXISTS (
    SELECT 1
    FROM asistencia a
    WHERE a.usuarioID = u.usuarioID
      AND a.resultado_validacion = 'Autorizado'
      AND a.fecha >= DATE_SUB(CURDATE(), INTERVAL 7 DAY)
)
ORDER BY u.usuarioID;


-- 64. Calcular la asistencia promedio por día de la semana.
--     Primero se cuentan las asistencias de cada fecha y luego se promedia
--     por día de la semana.
SELECT
    ELT(WEEKDAY(fecha) + 1, 'Lunes', 'Martes', 'Miercoles', 'Jueves',
        'Viernes', 'Sabado', 'Domingo') AS dia_semana,
    COUNT(*)                            AS dias_con_registro,
    ROUND(AVG(asistencias_dia), 2)      AS promedio_asistencias
FROM (
    SELECT fecha, COUNT(*) AS asistencias_dia
    FROM asistencia
    WHERE resultado_validacion = 'Autorizado'
    GROUP BY fecha
) d
GROUP BY WEEKDAY(fecha), dia_semana
ORDER BY WEEKDAY(fecha);


-- 65. Mostrar los 10 usuarios más constantes (más asistencias).
SELECT
    u.usuarioID,
    u.nombre,
    u.apellido,
    COUNT(a.asistenciaID)    AS total_asistencias,
    COUNT(DISTINCT a.fecha)  AS dias_distintos
FROM usuario u
JOIN asistencia a ON a.usuarioID = u.usuarioID
WHERE a.resultado_validacion = 'Autorizado'
GROUP BY u.usuarioID, u.nombre, u.apellido
ORDER BY total_asistencias DESC, dias_distintos DESC
LIMIT 10;


-- 66. Mostrar accesos fuera del horario permitido.
--     El horario está definido por espacio (horario_disponibilidad), así que
--     solo se evalúan las asistencias ligadas a una reserva. Se marca como
--     fuera de horario si el espacio no tiene un horario que cubra el día y
--     la hora de entrada.
SELECT
    a.asistenciaID,
    a.fecha,
    a.hora_entrada,
    u.usuarioID,
    u.nombre,
    u.apellido,
    e.nombre AS espacio
FROM asistencia a
JOIN usuario  u ON u.usuarioID  = a.usuarioID
JOIN reserva  r ON r.reservaID  = a.reservaID
JOIN espacio  e ON e.espacioID  = r.espacioID
WHERE NOT EXISTS (
    SELECT 1
    FROM horario_disponibilidad h
    WHERE h.espacioID = r.espacioID
      AND h.dia_semana = ELT(WEEKDAY(a.fecha) + 1, 'Lunes', 'Martes', 'Miercoles',
                             'Jueves', 'Viernes', 'Sabado', 'Domingo')
      AND a.hora_entrada BETWEEN h.hora_inicio AND h.hora_fin
)
ORDER BY a.fecha DESC, a.hora_entrada;


-- 67. Mostrar usuarios que accedieron sin membresía activa (rechazados).
SELECT
    a.asistenciaID,
    a.fecha,
    a.hora_entrada,
    u.usuarioID,
    u.nombre,
    u.apellido,
    COALESCE(m.estado, 'Sin membresía') AS estado_membresia
FROM asistencia a
JOIN usuario u ON u.usuarioID = a.usuarioID
LEFT JOIN membresia m ON m.membresiaID = u.membresiaID
WHERE a.resultado_validacion = 'Rechazado'
  AND (m.membresiaID IS NULL OR m.estado <> 'Activa')
ORDER BY a.fecha DESC, a.hora_entrada;


-- 68. Listar usuarios que solo acceden los fines de semana.
--     WEEKDAY: 5 = sábado, 6 = domingo.
SELECT
    u.usuarioID,
    u.nombre,
    u.apellido,
    COUNT(a.asistenciaID) AS asistencias
FROM usuario u
JOIN asistencia a ON a.usuarioID = u.usuarioID
WHERE a.resultado_validacion = 'Autorizado'
GROUP BY u.usuarioID, u.nombre, u.apellido
HAVING SUM(WEEKDAY(a.fecha) < 5) = 0
ORDER BY u.usuarioID;


-- 69. Mostrar usuarios que accedieron más de 2 veces en el mismo día.
SELECT
    u.usuarioID,
    u.nombre,
    u.apellido,
    a.fecha,
    COUNT(a.asistenciaID) AS accesos_en_el_dia
FROM usuario u
JOIN asistencia a ON a.usuarioID = u.usuarioID
GROUP BY u.usuarioID, u.nombre, u.apellido, a.fecha
HAVING COUNT(a.asistenciaID) > 2
ORDER BY accesos_en_el_dia DESC, a.fecha DESC;


-- 70. Mostrar el total de accesos diarios en el último mes.
SELECT
    fecha,
    COUNT(*) AS total_accesos,
    SUM(resultado_validacion = 'Autorizado') AS autorizados,
    SUM(resultado_validacion = 'Rechazado')  AS rechazados
FROM asistencia
WHERE fecha >= DATE_SUB(CURDATE(), INTERVAL 1 MONTH)
GROUP BY fecha
ORDER BY fecha;


-- 71. Mostrar usuarios que han accedido pero no tienen reservas.
SELECT u.usuarioID, u.nombre, u.apellido
FROM usuario u
WHERE EXISTS (
        SELECT 1 FROM asistencia a
        WHERE a.usuarioID = u.usuarioID
          AND a.resultado_validacion = 'Autorizado'
    )
  AND NOT EXISTS (
        SELECT 1 FROM reserva r
        WHERE r.usuarioID = u.usuarioID
    )
ORDER BY u.usuarioID;


-- 72. Mostrar los días con más concurrencia en el coworking.
SELECT
    fecha,
    COUNT(DISTINCT usuarioID) AS usuarios_distintos,
    COUNT(*)                  AS total_accesos
FROM asistencia
WHERE resultado_validacion = 'Autorizado'
GROUP BY fecha
ORDER BY usuarios_distintos DESC, total_accesos DESC
LIMIT 10;


-- 73. Mostrar usuarios que entraron pero no registraron salida.
SELECT
    a.asistenciaID,
    a.fecha,
    a.hora_entrada,
    u.usuarioID,
    u.nombre,
    u.apellido
FROM asistencia a
JOIN usuario u ON u.usuarioID = a.usuarioID
WHERE a.resultado_validacion = 'Autorizado'
  AND a.hora_salida IS NULL
ORDER BY a.fecha DESC, a.hora_entrada;


-- 74. Mostrar accesos de usuarios con membresía vencida.
SELECT
    a.asistenciaID,
    a.fecha,
    a.hora_entrada,
    a.resultado_validacion,
    u.usuarioID,
    u.nombre,
    u.apellido,
    m.fecha_fin AS vencimiento_membresia
FROM asistencia a
JOIN usuario  u ON u.usuarioID   = a.usuarioID
JOIN membresia m ON m.membresiaID = u.membresiaID
WHERE m.estado = 'Vencida'
ORDER BY a.fecha DESC, a.hora_entrada;


-- 75. Mostrar accesos de usuarios corporativos por empresa.
SELECT
    e.empresaID,
    e.nombre AS empresa,
    COUNT(a.asistenciaID)                       AS total_accesos,
    COUNT(DISTINCT u.usuarioID)                 AS usuarios_corporativos,
    SUM(a.resultado_validacion = 'Autorizado')  AS autorizados
FROM asistencia a
JOIN usuario   u ON u.usuarioID   = a.usuarioID
JOIN membresia m ON m.membresiaID = u.membresiaID
JOIN empresa   e ON e.empresaID   = u.empresaID
WHERE m.tipo = 'Corporativa'
GROUP BY e.empresaID, e.nombre
ORDER BY total_accesos DESC;


-- 76. Mostrar clientes que nunca han usado el coworking a pesar de pagar membresía.
--     Pagar membresía = tener una factura pagada con concepto de membresía.
SELECT DISTINCT u.usuarioID, u.nombre, u.apellido
FROM usuario u
JOIN factura         f  ON f.usuarioID  = u.usuarioID
JOIN detalle_factura df ON df.facturaID = f.facturaID
WHERE f.estado = 'Pagada'
  AND df.concepto LIKE 'Membresía%'
  AND NOT EXISTS (
        SELECT 1
        FROM asistencia a
        WHERE a.usuarioID = u.usuarioID
          AND a.resultado_validacion = 'Autorizado'
  )
ORDER BY u.usuarioID;


-- 77. Mostrar accesos rechazados por intentos con QR inválido.
--     No se guarda el motivo del rechazo. Se toman los rechazos de usuarios
--     cuya credencial es QR. Si quieres el motivo exacto, agrega una columna:
--     ALTER TABLE asistencia ADD COLUMN motivo_rechazo VARCHAR(100);
SELECT
    a.asistenciaID,
    a.fecha,
    a.hora_entrada,
    u.usuarioID,
    u.nombre,
    u.apellido,
    ac.tipo_acceso,
    ac.codigo
FROM asistencia a
JOIN usuario u ON u.usuarioID = a.usuarioID
JOIN acceso ac ON ac.usuarioID = u.usuarioID
WHERE a.resultado_validacion = 'Rechazado'
  AND ac.tipo_acceso = 'QR'
ORDER BY a.fecha DESC, a.hora_entrada;


-- 78. Mostrar accesos promedio por usuario.
--     Promedio de asistencias autorizadas entre todos los usuarios
--     (los que nunca asistieron cuentan como 0).
SELECT
    COUNT(a.asistenciaID)       AS total_asistencias,
    COUNT(DISTINCT u.usuarioID) AS total_usuarios,
    ROUND(COUNT(a.asistenciaID) / COUNT(DISTINCT u.usuarioID), 2) AS promedio_por_usuario
FROM usuario u
LEFT JOIN asistencia a ON a.usuarioID = u.usuarioID
                      AND a.resultado_validacion = 'Autorizado';


-- 79. Identificar usuarios que asisten más en la mañana.
--     Más entradas antes de las 12:00 que desde las 12:00.
SELECT
    u.usuarioID,
    u.nombre,
    u.apellido,
    SUM(a.hora_entrada <  '12:00:00') AS asistencias_manana,
    SUM(a.hora_entrada >= '12:00:00') AS asistencias_resto_del_dia
FROM usuario u
JOIN asistencia a ON a.usuarioID = u.usuarioID
WHERE a.resultado_validacion = 'Autorizado'
GROUP BY u.usuarioID, u.nombre, u.apellido
HAVING SUM(a.hora_entrada < '12:00:00') > SUM(a.hora_entrada >= '12:00:00')
ORDER BY asistencias_manana DESC;


-- 80. Identificar usuarios que asisten más en la noche.
--     Más entradas desde las 18:00 que antes de las 18:00.
SELECT
    u.usuarioID,
    u.nombre,
    u.apellido,
    SUM(a.hora_entrada >= '18:00:00') AS asistencias_noche,
    SUM(a.hora_entrada <  '18:00:00') AS asistencias_resto_del_dia
FROM usuario u
JOIN asistencia a ON a.usuarioID = u.usuarioID
WHERE a.resultado_validacion = 'Autorizado'
GROUP BY u.usuarioID, u.nombre, u.apellido
HAVING SUM(a.hora_entrada >= '18:00:00') > SUM(a.hora_entrada < '18:00:00')
ORDER BY asistencias_noche DESC;
