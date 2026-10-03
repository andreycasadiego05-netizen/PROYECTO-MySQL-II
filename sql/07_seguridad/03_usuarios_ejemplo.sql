-- =====================================================
-- 07_SEGURIDAD / 03_USUARIOS_EJEMPLO
-- Cuentas de MySQL de ejemplo, una por rol
-- =====================================================
-- Ejecutar después de 01_roles.sql y 02_permisos.sql, con un usuario
-- administrador (por ejemplo root). Se puede ejecutar varias veces.
--
-- IMPORTANTE: las contraseñas de este archivo son solo para pruebas.
-- Cámbialas antes de usar la base de datos fuera del entorno del curso:
--   ALTER USER 'cliente_laura'@'localhost' IDENTIFIED BY 'NuevaClave#2026';
--
-- Cómo crear una cuenta y asignarle un rol (plantilla):
--   1) CREATE USER IF NOT EXISTS 'nombre'@'localhost' IDENTIFIED BY 'Clave#Segura1';
--   2) GRANT 'rol_xxx' TO 'nombre'@'localhost';
--   3) SET DEFAULT ROLE 'rol_xxx' TO 'nombre'@'localhost';
--      (sin este paso el rol no se activa al iniciar sesión)
--   4) Solo para rol_usuario y rol_gerente_corporativo: ligar la cuenta a un
--      usuario registrado en cuenta_usuario (ver sección 3).
-- =====================================================

USE coworking;


-- =====================================================
-- 1. CUENTAS DE EJEMPLO
-- =====================================================
CREATE USER IF NOT EXISTS 'admin_coworking'@'localhost'  IDENTIFIED BY 'Admin#Cowork2026';
CREATE USER IF NOT EXISTS 'recepcion_ana'@'localhost'    IDENTIFIED BY 'Recep#Cowork2026';
CREATE USER IF NOT EXISTS 'cliente_laura'@'localhost'    IDENTIFIED BY 'Cliente#Cowork2026';
CREATE USER IF NOT EXISTS 'gerente_innova'@'localhost'   IDENTIFIED BY 'Gerente#Cowork2026';
CREATE USER IF NOT EXISTS 'contador_juan'@'localhost'    IDENTIFIED BY 'Conta#Cowork2026';


-- =====================================================
-- 2. ASIGNACIÓN DE ROLES
-- =====================================================
GRANT 'rol_administrador'       TO 'admin_coworking'@'localhost';
GRANT 'rol_recepcionista'       TO 'recepcion_ana'@'localhost';
GRANT 'rol_usuario'             TO 'cliente_laura'@'localhost';
GRANT 'rol_gerente_corporativo' TO 'gerente_innova'@'localhost';
GRANT 'rol_contador'            TO 'contador_juan'@'localhost';

-- Activar el rol automáticamente al iniciar sesión.
SET DEFAULT ROLE 'rol_administrador'       TO 'admin_coworking'@'localhost';
SET DEFAULT ROLE 'rol_recepcionista'       TO 'recepcion_ana'@'localhost';
SET DEFAULT ROLE 'rol_usuario'             TO 'cliente_laura'@'localhost';
SET DEFAULT ROLE 'rol_gerente_corporativo' TO 'gerente_innova'@'localhost';
SET DEFAULT ROLE 'rol_contador'            TO 'contador_juan'@'localhost';


-- =====================================================
-- 3. LIGAR CUENTAS CON USUARIOS REGISTRADOS
-- =====================================================
-- Las vistas de rol_usuario y rol_gerente_corporativo usan esta relación para
-- mostrar solo la información de esa persona o de su empresa.
--   cliente_laura  -> usuario 2 (Laura Martínez Pérez, sin empresa)
--   gerente_innova -> usuario 3 (Andrés Torres Villamizar, Innova Group SAS)
INSERT INTO cuenta_usuario (cuenta, usuarioID) VALUES
    ('cliente_laura', 2),
    ('gerente_innova', 3)
ON DUPLICATE KEY UPDATE usuarioID = VALUES(usuarioID);


-- =====================================================
-- VERIFICACIÓN (opcional)
-- =====================================================
-- Revisar roles y permisos de una cuenta:
-- SHOW GRANTS FOR 'recepcion_ana'@'localhost' USING 'rol_recepcionista';
--
-- Pruebas iniciando sesión con cada cuenta (por ejemplo con
-- mysql -u cliente_laura -p coworking):
--   cliente_laura  -> SELECT * FROM v_mis_reservas;      (solo las reservas de Laura)
--                     SELECT * FROM pago;                (debe dar error de permisos)
--   gerente_innova -> SELECT * FROM v_empresa_empleados; (solo empleados de Innova Group)
--   contador_juan  -> CALL sp_reporte_ingresos_mensuales_acumulados(NULL);
--   recepcion_ana  -> SELECT * FROM v_notificaciones_recepcion;
--                     DELETE FROM usuario WHERE usuarioID = 1;  (debe dar error de permisos)
