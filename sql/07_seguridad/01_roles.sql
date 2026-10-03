-- =====================================================
-- 07_SEGURIDAD / 01_ROLES
-- Control de acceso y roles (5 roles)
-- =====================================================
-- Crea los 5 roles del proyecto. Los roles solo agrupan permisos: los
-- privilegios se asignan en 02_permisos.sql y las cuentas de ejemplo se
-- crean en 03_usuarios_ejemplo.sql.
--
-- Orden de ejecución de la carpeta 07_seguridad: 01_roles, 02_permisos,
-- 03_usuarios_ejemplo. Ejecutar con un usuario administrador (por ejemplo
-- root) y después de cargar estructura, datos, eventos y procedimientos.
-- Requiere MySQL 8.0 o superior (los roles no existen en MySQL 5.7).
--
-- Se puede ejecutar varias veces sin error.
-- =====================================================

USE coworking;

-- Administrador del Coworking -> acceso total a la base de datos.
CREATE ROLE IF NOT EXISTS 'rol_administrador';

-- Recepcionista -> registro de usuarios, asignación de membresías y
-- gestión de reservas y accesos.
CREATE ROLE IF NOT EXISTS 'rol_recepcionista';

-- Usuario -> reservar espacios, consultar su historial y descargar sus
-- facturas (solo ve su propia información).
CREATE ROLE IF NOT EXISTS 'rol_usuario';

-- Gerente Corporativo -> administrar los empleados de su empresa y ver la
-- facturación consolidada de su empresa.
CREATE ROLE IF NOT EXISTS 'rol_gerente_corporativo';

-- Contador -> gestión de ingresos y reportes financieros.
CREATE ROLE IF NOT EXISTS 'rol_contador';


-- =====================================================
-- VERIFICACIÓN (opcional)
-- =====================================================
-- Los roles quedan guardados como cuentas bloqueadas en mysql.user:
-- SELECT user AS rol, account_locked FROM mysql.user WHERE user LIKE 'rol\_%';
