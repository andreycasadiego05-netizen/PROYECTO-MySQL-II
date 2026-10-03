-- =====================================================
-- 07_SEGURIDAD / 02_PERMISOS
-- Permisos de cada rol sobre la base de datos coworking
-- =====================================================
-- Ejecutar después de 01_roles.sql y después de cargar estructura, datos,
-- eventos (06_eventos.sql: crea notificacion) y procedimientos
-- (07_procedimientos.sql: crea reembolso y los sp_*), porque aquí se dan
-- permisos sobre esos objetos.
-- Ejecutar con un usuario administrador (por ejemplo root). Se puede
-- ejecutar varias veces.
--
-- Principios aplicados:
--  * Mínimo privilegio: cada rol recibe solo lo que necesita (sin DELETE
--    salvo el administrador).
--  * Los permisos se dan a los roles, no a las cuentas (ver 03).
--  * MySQL no tiene seguridad por fila. Para que un Usuario solo vea su
--    información y un Gerente Corporativo solo la de su empresa se usan
--    vistas que filtran por la cuenta conectada (USER()) a través de la
--    tabla cuenta_usuario. Esos roles no tienen acceso a las tablas base.
--  * Las operaciones sensibles (crear reservas, facturar, registrar
--    entradas) se hacen con procedimientos almacenados: se ejecutan con
--    los permisos de quien los creó, así que el rol solo necesita EXECUTE.
--    Los procedimientos reciben IDs como parámetro; la aplicación debe
--    pasar el ID del usuario autenticado.
-- =====================================================

USE coworking;


-- =====================================================
-- 1. TABLA DE APOYO: cuenta MySQL <-> usuario del coworking
-- =====================================================
-- Relaciona una cuenta de MySQL (sin @host) con un usuario registrado.
-- Se llena en 03_usuarios_ejemplo.sql.
CREATE TABLE IF NOT EXISTS cuenta_usuario (
    cuenta VARCHAR(80) NOT NULL PRIMARY KEY COMMENT 'Nombre de la cuenta MySQL, sin @host',
    usuarioID INT NOT NULL,
    FOREIGN KEY (usuarioID) REFERENCES usuario(usuarioID)
);


-- =====================================================
-- 2. VISTAS DE SEGURIDAD
-- =====================================================
-- SQL SECURITY DEFINER: la vista lee las tablas con los permisos de quien la
-- creó, por eso el rol solo necesita SELECT sobre la vista.

-- Auxiliares (no se otorgan a ningún rol).
CREATE OR REPLACE SQL SECURITY DEFINER VIEW v_cuenta_actual AS
SELECT c.usuarioID
FROM cuenta_usuario c
WHERE c.cuenta = SUBSTRING_INDEX(USER(), '@', 1);

CREATE OR REPLACE SQL SECURITY DEFINER VIEW v_cuenta_actual_empresa AS
SELECT u.empresaID
FROM cuenta_usuario c
JOIN usuario u ON u.usuarioID = c.usuarioID
WHERE c.cuenta = SUBSTRING_INDEX(USER(), '@', 1)
  AND u.empresaID IS NOT NULL;


-- ---- Rol Usuario: solo su propia información ----

CREATE OR REPLACE SQL SECURITY DEFINER VIEW v_mis_membresias AS
SELECT m.membresiaID, m.tipo, m.estado, m.fecha_inicio, m.fecha_fin
FROM membresia m
WHERE m.usuarioID = (SELECT usuarioID FROM v_cuenta_actual);

CREATE OR REPLACE SQL SECURITY DEFINER VIEW v_mis_reservas AS
SELECT r.reservaID, r.fecha_reserva, r.hora_inicio, r.hora_fin, r.duracion, r.estado,
       e.nombre AS espacio, e.tipo AS tipo_espacio
FROM reserva r
JOIN espacio e ON e.espacioID = r.espacioID
WHERE r.usuarioID = (SELECT usuarioID FROM v_cuenta_actual);

CREATE OR REPLACE SQL SECURITY DEFINER VIEW v_mis_asistencias AS
SELECT a.asistenciaID, a.fecha, a.hora_entrada, a.hora_salida, a.resultado_validacion, a.reservaID
FROM asistencia a
WHERE a.usuarioID = (SELECT usuarioID FROM v_cuenta_actual);

CREATE OR REPLACE SQL SECURITY DEFINER VIEW v_mis_servicios AS
SELECT us.usuario_servicioID, s.nombre AS servicio, us.fecha_inicio, us.fecha_fin,
       us.cantidad, us.bloqueado
FROM usuario_servicio us
JOIN servicio_adicional s ON s.servicioID = us.servicioID
WHERE us.usuarioID = (SELECT usuarioID FROM v_cuenta_actual);

CREATE OR REPLACE SQL SECURITY DEFINER VIEW v_mis_pagos AS
SELECT p.pagoID, p.fecha_pago, p.monto, p.metodo_pago, p.estado, p.referencia
FROM pago p
WHERE p.usuarioID = (SELECT usuarioID FROM v_cuenta_actual);

-- Facturas del usuario (para consultarlas y descargarlas).
CREATE OR REPLACE SQL SECURITY DEFINER VIEW v_mis_facturas AS
SELECT f.facturaID, f.numero_factura, f.fecha_emision, f.fecha_vencimiento,
       f.subtotal, f.impuestos, f.recargo, f.total, f.estado
FROM factura f
WHERE f.usuarioID = (SELECT usuarioID FROM v_cuenta_actual);

CREATE OR REPLACE SQL SECURITY DEFINER VIEW v_mis_detalle_facturas AS
SELECT d.detalle_facturaID, d.facturaID, f.numero_factura, d.concepto, d.cantidad,
       d.precio_unitario, d.subtotal
FROM detalle_factura d
JOIN factura f ON f.facturaID = d.facturaID
WHERE f.usuarioID = (SELECT usuarioID FROM v_cuenta_actual);


-- ---- Rol Gerente Corporativo: solo la empresa de su cuenta ----

CREATE OR REPLACE SQL SECURITY DEFINER VIEW v_empresa_empleados AS
SELECT u.usuarioID, u.nombre, u.apellido, u.edad, u.contacto,
       m.tipo AS tipo_membresia, m.estado AS estado_membresia, m.fecha_fin AS vence_membresia
FROM usuario u
LEFT JOIN membresia m ON m.membresiaID = u.membresiaID
WHERE u.empresaID = (SELECT empresaID FROM v_cuenta_actual_empresa);

-- Facturas de los empleados de la empresa, incluidas las consolidadas.
CREATE OR REPLACE SQL SECURITY DEFINER VIEW v_empresa_facturas AS
SELECT f.facturaID, f.numero_factura, f.fecha_emision, f.fecha_vencimiento,
       f.subtotal, f.impuestos, f.recargo, f.total, f.estado,
       u.usuarioID, u.nombre, u.apellido
FROM factura f
JOIN usuario u ON u.usuarioID = f.usuarioID
WHERE u.empresaID = (SELECT empresaID FROM v_cuenta_actual_empresa);

CREATE OR REPLACE SQL SECURITY DEFINER VIEW v_empresa_detalle_facturas AS
SELECT d.detalle_facturaID, d.facturaID, f.numero_factura, d.concepto, d.cantidad,
       d.precio_unitario, d.subtotal
FROM detalle_factura d
JOIN factura f ON f.facturaID = d.facturaID
JOIN usuario u ON u.usuarioID = f.usuarioID
WHERE u.empresaID = (SELECT empresaID FROM v_cuenta_actual_empresa);


-- ---- Avisos del sistema (tabla notificacion) por destinatario ----

CREATE OR REPLACE SQL SECURITY DEFINER VIEW v_notificaciones_recepcion AS
SELECT notificacionID, tipo, asunto, mensaje, fecha_creacion, estado
FROM notificacion
WHERE destinatario = 'Recepcion';

CREATE OR REPLACE SQL SECURITY DEFINER VIEW v_notificaciones_contador AS
SELECT notificacionID, tipo, asunto, mensaje, fecha_creacion, estado
FROM notificacion
WHERE destinatario = 'Contador';


-- =====================================================
-- 3. ADMINISTRADOR DEL COWORKING: acceso total
-- =====================================================
-- Incluye tablas, vistas, procedimientos, eventos y triggers de coworking.
GRANT ALL PRIVILEGES ON coworking.* TO 'rol_administrador';


-- =====================================================
-- 4. RECEPCIONISTA
-- =====================================================
-- Registro de usuarios, asignación de membresías, gestión de reservas y
-- accesos. Puede crear y modificar, pero no eliminar.
GRANT SELECT, INSERT, UPDATE ON coworking.usuario          TO 'rol_recepcionista';
GRANT SELECT, INSERT, UPDATE ON coworking.membresia        TO 'rol_recepcionista';
GRANT SELECT, INSERT, UPDATE ON coworking.reserva          TO 'rol_recepcionista';
GRANT SELECT, INSERT, UPDATE ON coworking.usuario_servicio TO 'rol_recepcionista';
GRANT SELECT, INSERT, UPDATE ON coworking.acceso           TO 'rol_recepcionista';
GRANT SELECT, INSERT, UPDATE ON coworking.asistencia       TO 'rol_recepcionista';

-- Consulta de catálogos y de lo financiero (sin modificarlo).
GRANT SELECT ON coworking.empresa                 TO 'rol_recepcionista';
GRANT SELECT ON coworking.tipo_membresia          TO 'rol_recepcionista';
GRANT SELECT ON coworking.espacio                 TO 'rol_recepcionista';
GRANT SELECT ON coworking.horario_disponibilidad  TO 'rol_recepcionista';
GRANT SELECT ON coworking.servicio_adicional      TO 'rol_recepcionista';
GRANT SELECT ON coworking.pago                    TO 'rol_recepcionista';
GRANT SELECT ON coworking.factura                 TO 'rol_recepcionista';
GRANT SELECT ON coworking.detalle_factura         TO 'rol_recepcionista';
GRANT SELECT ON coworking.reembolso               TO 'rol_recepcionista';
GRANT SELECT ON coworking.v_notificaciones_recepcion TO 'rol_recepcionista';

-- Operaciones guiadas (cobrar una reserva o una membresía exige escribir en
-- pago y factura, que el rol no puede tocar directamente).
GRANT EXECUTE ON PROCEDURE coworking.sp_registrar_membresia             TO 'rol_recepcionista';
GRANT EXECUTE ON PROCEDURE coworking.sp_renovar_membresia               TO 'rol_recepcionista';
GRANT EXECUTE ON PROCEDURE coworking.sp_generar_factura_membresia       TO 'rol_recepcionista';
GRANT EXECUTE ON PROCEDURE coworking.sp_verificar_disponibilidad_espacio TO 'rol_recepcionista';
GRANT EXECUTE ON PROCEDURE coworking.sp_crear_reserva                   TO 'rol_recepcionista';
GRANT EXECUTE ON PROCEDURE coworking.sp_confirmar_reserva_con_pago      TO 'rol_recepcionista';
GRANT EXECUTE ON PROCEDURE coworking.sp_cancelar_reserva_con_reembolso  TO 'rol_recepcionista';
GRANT EXECUTE ON PROCEDURE coworking.sp_registrar_entrada               TO 'rol_recepcionista';
GRANT EXECUTE ON PROCEDURE coworking.sp_registrar_salida                TO 'rol_recepcionista';
GRANT EXECUTE ON PROCEDURE coworking.sp_reporte_diario_asistencias      TO 'rol_recepcionista';


-- =====================================================
-- 5. USUARIO
-- =====================================================
-- Reservar espacios, consultar su historial y descargar sus facturas.
-- Solo ve su información, a través de las vistas v_mis_*.
GRANT SELECT ON coworking.v_mis_membresias       TO 'rol_usuario';
GRANT SELECT ON coworking.v_mis_reservas         TO 'rol_usuario';
GRANT SELECT ON coworking.v_mis_asistencias      TO 'rol_usuario';
GRANT SELECT ON coworking.v_mis_servicios        TO 'rol_usuario';
GRANT SELECT ON coworking.v_mis_pagos            TO 'rol_usuario';
GRANT SELECT ON coworking.v_mis_facturas         TO 'rol_usuario';
GRANT SELECT ON coworking.v_mis_detalle_facturas TO 'rol_usuario';

-- Catálogos públicos para elegir espacio y servicios.
GRANT SELECT ON coworking.espacio                TO 'rol_usuario';
GRANT SELECT ON coworking.horario_disponibilidad TO 'rol_usuario';
GRANT SELECT ON coworking.servicio_adicional     TO 'rol_usuario';
GRANT SELECT ON coworking.tipo_membresia         TO 'rol_usuario';

-- Reservar y cancelar. La confirmación con pago la hace recepción o la
-- aplicación (recibe el monto como parámetro, por eso no se da al usuario).
GRANT EXECUTE ON PROCEDURE coworking.sp_verificar_disponibilidad_espacio TO 'rol_usuario';
GRANT EXECUTE ON PROCEDURE coworking.sp_crear_reserva                    TO 'rol_usuario';
GRANT EXECUTE ON PROCEDURE coworking.sp_cancelar_reserva_con_reembolso   TO 'rol_usuario';


-- =====================================================
-- 6. GERENTE CORPORATIVO
-- =====================================================
-- Administrar los empleados de su empresa y ver su facturación consolidada.
-- Solo ve la empresa a la que pertenece su cuenta (v_empresa_*).
GRANT SELECT ON coworking.v_empresa_empleados        TO 'rol_gerente_corporativo';
GRANT SELECT ON coworking.v_empresa_facturas         TO 'rol_gerente_corporativo';
GRANT SELECT ON coworking.v_empresa_detalle_facturas TO 'rol_gerente_corporativo';

GRANT SELECT ON coworking.tipo_membresia         TO 'rol_gerente_corporativo';
GRANT SELECT ON coworking.espacio                TO 'rol_gerente_corporativo';
GRANT SELECT ON coworking.horario_disponibilidad TO 'rol_gerente_corporativo';

-- Alta de empleados (con membresía corporativa) y facturación consolidada.
GRANT EXECUTE ON PROCEDURE coworking.sp_registrar_lote_empleados             TO 'rol_gerente_corporativo';
GRANT EXECUTE ON PROCEDURE coworking.sp_generar_factura_consolidada_empresa  TO 'rol_gerente_corporativo';


-- =====================================================
-- 7. CONTADOR
-- =====================================================
-- Gestión de ingresos y reportes financieros. Puede registrar y corregir
-- pagos y facturas, pero no eliminarlos (son registros contables).
GRANT SELECT, INSERT, UPDATE ON coworking.pago            TO 'rol_contador';
GRANT SELECT, INSERT, UPDATE ON coworking.factura         TO 'rol_contador';
GRANT SELECT, INSERT, UPDATE ON coworking.detalle_factura TO 'rol_contador';
GRANT SELECT, UPDATE         ON coworking.reembolso       TO 'rol_contador';

-- Solo lectura de lo necesario para conciliar (de usuario solo identificación,
-- sin datos de contacto).
GRANT SELECT (usuarioID, nombre, apellido, empresaID, membresiaID) ON coworking.usuario TO 'rol_contador';
GRANT SELECT ON coworking.empresa            TO 'rol_contador';
GRANT SELECT ON coworking.membresia          TO 'rol_contador';
GRANT SELECT ON coworking.tipo_membresia     TO 'rol_contador';
GRANT SELECT ON coworking.reserva            TO 'rol_contador';
GRANT SELECT ON coworking.espacio            TO 'rol_contador';
GRANT SELECT ON coworking.servicio_adicional TO 'rol_contador';
GRANT SELECT ON coworking.usuario_servicio   TO 'rol_contador';
GRANT SELECT ON coworking.v_notificaciones_contador TO 'rol_contador';

-- Reportes y procesos financieros.
GRANT EXECUTE ON PROCEDURE coworking.sp_reporte_ingresos_mensuales_acumulados TO 'rol_contador';
GRANT EXECUTE ON PROCEDURE coworking.sp_aplicar_recargos_facturas_vencidas    TO 'rol_contador';
GRANT EXECUTE ON PROCEDURE coworking.sp_generar_factura_membresia             TO 'rol_contador';
GRANT EXECUTE ON PROCEDURE coworking.sp_generar_factura_consolidada_empresa   TO 'rol_contador';


-- =====================================================
-- VERIFICACIÓN (opcional)
-- =====================================================
-- SHOW GRANTS FOR 'rol_recepcionista';
-- SHOW GRANTS FOR 'rol_usuario';
-- SHOW GRANTS FOR 'rol_gerente_corporativo';
-- SHOW GRANTS FOR 'rol_contador';
