# 🛡️ Roles y permisos

Documentación del control de acceso de la base de datos **`coworking`**: los 5 roles del proyecto, qué puede hacer cada uno, cómo se limita lo que ve cada persona y cómo crear cuentas y asignarles un rol.

Los scripts que lo implementan están en `sql/07_seguridad/`:

| Archivo | Qué hace |
|---|---|
| `01_roles.sql` | Crea los 5 roles. |
| `02_permisos.sql` | Crea la tabla `cuenta_usuario` y las vistas de seguridad, y otorga los permisos a cada rol. |
| `03_usuarios_ejemplo.sql` | Crea una cuenta de prueba por rol, les asigna el rol y liga las cuentas con usuarios del coworking. |

---

## 📑 Contenido

1. [Resumen de roles](#-resumen-de-roles)
2. [Modelo de seguridad](#-modelo-de-seguridad)
3. [Matriz de permisos](#-matriz-de-permisos)
4. [Detalle por rol](#-detalle-por-rol)
5. [Cómo se limita lo que ve cada usuario](#-cómo-se-limita-lo-que-ve-cada-usuario)
6. [Crear usuarios y asignarles un rol](#-crear-usuarios-y-asignarles-un-rol)
7. [Cuentas de ejemplo](#-cuentas-de-ejemplo)
8. [Pruebas por rol](#-pruebas-por-rol)
9. [Notas y limitaciones](#-notas-y-limitaciones)

---

## 👥 Resumen de roles

| Rol de MySQL | Rol del enunciado | Responsabilidad |
|---|---|---|
| `rol_administrador` | Administrador del Coworking | Acceso total. |
| `rol_recepcionista` | Recepcionista | Registro de usuarios, asignación de membresías y gestión de reservas. |
| `rol_usuario` | Usuario | Reservar espacios, consultar su historial y descargar sus facturas. |
| `rol_gerente_corporativo` | Gerente Corporativo | Administrar los empleados de su empresa y ver la facturación consolidada. |
| `rol_contador` | Contador | Gestión de ingresos y reportes financieros. |

---

## 🔐 Modelo de seguridad

El diseño sigue cuatro ideas:

1. **Permisos en los roles, no en las cuentas.** Cada cuenta recibe un rol y hereda sus permisos. Para cambiar lo que puede hacer un tipo de persona se modifica el rol una sola vez.
2. **Mínimo privilegio.** Cada rol tiene solo lo que necesita. Solo el administrador puede eliminar registros (`DELETE`); el resto puede consultar, crear o modificar según su función.
3. **Operaciones sensibles mediante procedimientos.** Cobrar una reserva, facturar o registrar una entrada exige escribir en varias tablas. Esos procedimientos se ejecutan con los permisos de quien los creó (`SQL SECURITY DEFINER`, el valor por defecto), así que el rol solo necesita el permiso `EXECUTE` y no acceso directo a las tablas de pagos y facturas.
4. **Vistas para limitar lo que se ve.** MySQL no tiene seguridad por fila. Los roles *Usuario* y *Gerente Corporativo* no tienen acceso a las tablas: consultan vistas que filtran por la cuenta conectada.

---

## 🧾 Matriz de permisos

**Leyenda:** `S` = SELECT · `I` = INSERT · `U` = UPDATE · `D` = DELETE · `ALL` = todos los privilegios · `E` = EXECUTE · `—` = sin acceso.

### Tablas

| Tabla | Administrador | Recepcionista | Usuario | Gerente Corp. | Contador |
|---|:---:|:---:|:---:|:---:|:---:|
| `empresa` | ALL | S | — | — | S |
| `tipo_membresia` | ALL | S | S | S | S |
| `usuario` | ALL | S I U | — | — | S *(solo id, nombre, apellido, empresa y membresía)* |
| `membresia` | ALL | S I U | — | — | S |
| `espacio` | ALL | S | S | S | S |
| `horario_disponibilidad` | ALL | S | S | S | — |
| `reserva` | ALL | S I U | — | — | S |
| `servicio_adicional` | ALL | S | S | — | S |
| `usuario_servicio` | ALL | S I U | — | — | S |
| `pago` | ALL | S | — | — | S I U |
| `factura` | ALL | S | — | — | S I U |
| `detalle_factura` | ALL | S | — | — | S I U |
| `acceso` | ALL | S I U | — | — | — |
| `asistencia` | ALL | S I U | — | — | — |
| `reembolso` | ALL | S | — | — | S U |
| `notificacion` | ALL | — | — | — | — |
| `cuenta_usuario` | ALL | — | — | — | — |

### Vistas

| Vista | Qué muestra | Administrador | Recepcionista | Usuario | Gerente Corp. | Contador |
|---|---|:---:|:---:|:---:|:---:|:---:|
| `v_mis_membresias` | Membresías de la cuenta conectada. | ALL | — | S | — | — |
| `v_mis_reservas` | Reservas de la cuenta conectada, con el nombre del espacio. | ALL | — | S | — | — |
| `v_mis_asistencias` | Historial de asistencias de la cuenta conectada. | ALL | — | S | — | — |
| `v_mis_servicios` | Servicios adicionales de la cuenta conectada. | ALL | — | S | — | — |
| `v_mis_pagos` | Pagos de la cuenta conectada. | ALL | — | S | — | — |
| `v_mis_facturas` | Facturas de la cuenta conectada (para consultarlas y descargarlas). | ALL | — | S | — | — |
| `v_mis_detalle_facturas` | Líneas de las facturas de la cuenta conectada. | ALL | — | S | — | — |
| `v_empresa_empleados` | Empleados de la empresa de la cuenta, con su membresía. | ALL | — | — | S | — |
| `v_empresa_facturas` | Facturas de los empleados de la empresa, incluidas las consolidadas. | ALL | — | — | S | — |
| `v_empresa_detalle_facturas` | Líneas de esas facturas. | ALL | — | — | S | — |
| `v_notificaciones_recepcion` | Avisos dirigidos a recepción (por ejemplo, membresías suspendidas). | ALL | S | — | — | — |
| `v_notificaciones_contador` | Reportes dirigidos al contador (por ejemplo, ingresos de fin de mes). | ALL | — | — | — | S |

Las vistas auxiliares `v_cuenta_actual` y `v_cuenta_actual_empresa` identifican al usuario y a la empresa de la cuenta conectada; no se otorgan a ningún rol.

### Procedimientos almacenados

| Procedimiento | Administrador | Recepcionista | Usuario | Gerente Corp. | Contador |
|---|:---:|:---:|:---:|:---:|:---:|
| `sp_registrar_membresia` | E | E | — | — | — |
| `sp_renovar_membresia` | E | E | — | — | — |
| `sp_actualizar_membresias_vencidas` | E | — | — | — | — |
| `sp_suspender_membresias_impagas` | E | — | — | — | — |
| `sp_verificar_disponibilidad_espacio` | E | E | E | — | — |
| `sp_crear_reserva` | E | E | E | — | — |
| `sp_confirmar_reserva_con_pago` | E | E | — | — | — |
| `sp_cancelar_reserva_con_reembolso` | E | E | E | — | — |
| `sp_liberar_reservas_no_confirmadas` | E | — | — | — | — |
| `sp_generar_factura_membresia` | E | E | — | — | E |
| `sp_generar_factura_consolidada_empresa` | E | — | — | E | E |
| `sp_aplicar_recargos_facturas_vencidas` | E | — | — | — | E |
| `sp_bloquear_servicios_por_impago` | E | — | — | — | — |
| `sp_registrar_entrada` | E | E | — | — | — |
| `sp_registrar_salida` | E | E | — | — | — |
| `sp_reporte_diario_asistencias` | E | E | — | — | — |
| `sp_marcar_no_show_y_penalizar` | E | — | — | — | — |
| `sp_registrar_lote_empleados` | E | — | — | E | — |
| `sp_cancelar_reservas_futuras_usuario` | E | — | — | — | — |
| `sp_reporte_ingresos_mensuales_acumulados` | E | — | — | — | E |

`sp_aux_numero_factura` es un procedimiento auxiliar que usan internamente los demás; ningún rol lo ejecuta directamente.

---

## 📋 Detalle por rol

### 👑 Administrador del Coworking — `rol_administrador`

- **Permisos:** `ALL PRIVILEGES` sobre `coworking.*` (tablas, vistas, procedimientos, funciones, eventos y triggers).
- **Para qué:** administración completa de la base de datos y tareas de mantenimiento como actualizar membresías vencidas, liberar reservas o marcar *No Show*.

### 🧑‍💼 Recepcionista — `rol_recepcionista`

| Necesidad del enunciado | Cómo se cubre |
|---|---|
| Registro de usuarios | `S I U` sobre `usuario` (y `S` sobre `empresa`). |
| Asignación de membresías | `S I U` sobre `membresia`, `sp_registrar_membresia`, `sp_renovar_membresia` y `sp_generar_factura_membresia`. |
| Gestión de reservas | `S I U` sobre `reserva`, `sp_verificar_disponibilidad_espacio`, `sp_crear_reserva`, `sp_confirmar_reserva_con_pago` y `sp_cancelar_reserva_con_reembolso`. |
| Servicios y accesos (apoyo a la operación) | `S I U` sobre `usuario_servicio`, `acceso` y `asistencia`; `sp_registrar_entrada`, `sp_registrar_salida` y `sp_reporte_diario_asistencias`. |

- **Solo lectura:** catálogos (`tipo_membresia`, `espacio`, `horario_disponibilidad`, `servicio_adicional`), `pago`, `factura`, `detalle_factura`, `reembolso` y los avisos de recepción.
- **No puede:** eliminar registros ni modificar pagos y facturas directamente (los cobros pasan por los procedimientos).

### 🙋 Usuario — `rol_usuario`

| Necesidad del enunciado | Cómo se cubre |
|---|---|
| Reservar espacios | `sp_verificar_disponibilidad_espacio`, `sp_crear_reserva` y `sp_cancelar_reserva_con_reembolso`; consulta de `espacio`, `horario_disponibilidad`, `servicio_adicional` y `tipo_membresia`. |
| Consultar historial | Vistas `v_mis_membresias`, `v_mis_reservas`, `v_mis_asistencias`, `v_mis_servicios` y `v_mis_pagos`. |
| Descargar facturas | Vistas `v_mis_facturas` y `v_mis_detalle_facturas`. |

- **Solo ve su propia información** (ver la sección siguiente).
- **No puede:** acceder a las tablas base ni confirmar reservas con pago (esa operación recibe el monto como parámetro, por eso la hacen recepción o la aplicación).

### 🏢 Gerente Corporativo — `rol_gerente_corporativo`

| Necesidad del enunciado | Cómo se cubre |
|---|---|
| Administrar empleados de su empresa | Vista `v_empresa_empleados` y `sp_registrar_lote_empleados` (alta de empleados con membresía Corporativa). |
| Ver facturación consolidada | Vistas `v_empresa_facturas` y `v_empresa_detalle_facturas`, y `sp_generar_factura_consolidada_empresa`. |

- **Solo ve la empresa a la que pertenece su cuenta.**
- **Consulta adicional:** `tipo_membresia`, `espacio` y `horario_disponibilidad`.

### 📈 Contador — `rol_contador`

| Necesidad del enunciado | Cómo se cubre |
|---|---|
| Gestión de ingresos | `S I U` sobre `pago`, `factura` y `detalle_factura`; `S U` sobre `reembolso`. |
| Reportes financieros | `sp_reporte_ingresos_mensuales_acumulados`, `sp_aplicar_recargos_facturas_vencidas`, `sp_generar_factura_membresia`, `sp_generar_factura_consolidada_empresa` y la vista `v_notificaciones_contador`. |

- **Solo lectura para conciliar:** `empresa`, `membresia`, `tipo_membresia`, `reserva`, `espacio`, `servicio_adicional` y `usuario_servicio`.
- **Datos de usuarios limitados:** de `usuario` solo ve `usuarioID`, `nombre`, `apellido`, `empresaID` y `membresiaID`; no ve el contacto.
- **No puede:** eliminar pagos ni facturas (son registros contables).

---

## 🔎 Cómo se limita lo que ve cada usuario

Los roles *Usuario* y *Gerente Corporativo* necesitan ver **solo una parte** de las tablas. Como MySQL no permite restringir filas por permisos, se resuelve así:

1. La tabla **`cuenta_usuario`** relaciona el nombre de una cuenta de MySQL con un usuario del coworking:

   | cuenta | usuarioID |
   |---|---|
   | `cliente_laura` | 2 |
   | `gerente_innova` | 3 |

2. Las **vistas** filtran por la cuenta que inició sesión (`USER()`), por ejemplo:

   ```sql
   -- Vista auxiliar: ¿qué usuario del coworking es la cuenta conectada?
   CREATE OR REPLACE SQL SECURITY DEFINER VIEW v_cuenta_actual AS
   SELECT c.usuarioID
   FROM cuenta_usuario c
   WHERE c.cuenta = SUBSTRING_INDEX(USER(), '@', 1);

   -- Las reservas de esa persona
   CREATE OR REPLACE SQL SECURITY DEFINER VIEW v_mis_reservas AS
   SELECT r.reservaID, r.fecha_reserva, r.hora_inicio, r.hora_fin, r.duracion, r.estado,
          e.nombre AS espacio, e.tipo AS tipo_espacio
   FROM reserva r
   JOIN espacio e ON e.espacioID = r.espacioID
   WHERE r.usuarioID = (SELECT usuarioID FROM v_cuenta_actual);
   ```

3. Las vistas usan `SQL SECURITY DEFINER`: leen las tablas con los permisos de quien las creó, así que el rol solo necesita `SELECT` sobre la vista y nunca sobre la tabla.

Para el **Gerente Corporativo** el filtro es la empresa del usuario ligado a su cuenta (`v_cuenta_actual_empresa`): ve a los empleados y las facturas de esa empresa y de ninguna otra.

> Una cuenta de *Usuario* o *Gerente Corporativo* **sin fila en `cuenta_usuario`** no ve ningún dato: las vistas devuelven resultados vacíos.

---

## 🧑‍💻 Crear usuarios y asignarles un rol

> Ejecutar con una cuenta administradora (por ejemplo `root`) y **después** de `01_roles.sql` y `02_permisos.sql`. Requiere MySQL 8.0 o superior.

### Paso a paso

```sql
-- 1. Crear la cuenta
CREATE USER 'nombre_cuenta'@'localhost' IDENTIFIED BY 'Clave#Segura1';

-- 2. Asignarle el rol
GRANT 'rol_recepcionista' TO 'nombre_cuenta'@'localhost';

-- 3. Activar el rol automáticamente al iniciar sesión
--    (sin este paso la cuenta inicia sin permisos)
SET DEFAULT ROLE 'rol_recepcionista' TO 'nombre_cuenta'@'localhost';
```

### Cuentas de los roles *Usuario* y *Gerente Corporativo*

Además de los tres pasos anteriores, hay que ligar la cuenta con un usuario registrado:

```sql
INSERT INTO cuenta_usuario (cuenta, usuarioID)
VALUES ('nombre_cuenta', 7)
ON DUPLICATE KEY UPDATE usuarioID = VALUES(usuarioID);
```

- Para `rol_usuario`, `usuarioID` es la persona que usará la cuenta.
- Para `rol_gerente_corporativo`, `usuarioID` es un usuario que pertenezca a la empresa que se va a gestionar (debe tener `empresaID`).

### Mantenimiento de cuentas

```sql
-- Cambiar la contraseña
ALTER USER 'nombre_cuenta'@'localhost' IDENTIFIED BY 'NuevaClave#2026';

-- Quitar un rol
REVOKE 'rol_recepcionista' FROM 'nombre_cuenta'@'localhost';

-- Eliminar la cuenta (y su vínculo con el coworking)
DROP USER 'nombre_cuenta'@'localhost';
DELETE FROM cuenta_usuario WHERE cuenta = 'nombre_cuenta';
```

### Ver permisos

```sql
SHOW GRANTS FOR 'rol_contador';
SHOW GRANTS FOR 'contador_juan'@'localhost' USING 'rol_contador';
```

---

## 🧪 Cuentas de ejemplo

El script `03_usuarios_ejemplo.sql` crea una cuenta de prueba por rol:

| Cuenta | Rol | Vinculada a |
|---|---|---|
| `admin_coworking` | `rol_administrador` | — |
| `recepcion_ana` | `rol_recepcionista` | — |
| `cliente_laura` | `rol_usuario` | Usuario 2 (Laura Martínez Pérez) |
| `gerente_innova` | `rol_gerente_corporativo` | Usuario 3 (Andrés Torres Villamizar, Innova Group SAS) |
| `contador_juan` | `rol_contador` | — |

> 🔑 Las contraseñas del script son solo para pruebas. Cámbialas antes de usar la base de datos fuera del entorno del curso.

---

## ✅ Pruebas por rol

Inicia sesión con cada cuenta (`mysql -u <cuenta> -p coworking`) y comprueba el resultado. Los valores corresponden a los datos iniciales.

| Cuenta | Consulta | Resultado esperado |
|---|---|---|
| `cliente_laura` | `SELECT * FROM v_mis_reservas;` | ✅ Solo la reserva de Laura (usuario 2). |
| `cliente_laura` | `SELECT * FROM v_mis_facturas;` | ✅ Solo su factura `FAC-2026-0002`. |
| `cliente_laura` | `SELECT * FROM pago;` | ❌ Error 1142: acceso denegado a la tabla. |
| `cliente_laura` | `SELECT * FROM membresia;` | ❌ Error 1142. |
| `gerente_innova` | `SELECT * FROM v_empresa_empleados;` | ✅ Solo los empleados de Innova Group SAS. |
| `gerente_innova` | `SELECT * FROM v_empresa_facturas;` | ✅ Solo las facturas de esa empresa (`FAC-2026-0003`). |
| `gerente_innova` | `SELECT * FROM usuario;` | ❌ Error 1142. |
| `recepcion_ana` | `SELECT * FROM v_notificaciones_recepcion;` | ✅ Avisos de recepción. |
| `recepcion_ana` | `SELECT * FROM factura;` | ✅ Lectura permitida. |
| `recepcion_ana` | `UPDATE factura SET estado = 'Pagada' WHERE facturaID = 5;` | ❌ Error 1142: solo lectura. |
| `recepcion_ana` | `DELETE FROM usuario WHERE usuarioID = 1;` | ❌ Error 1142: no puede eliminar. |
| `contador_juan` | `CALL sp_reporte_ingresos_mensuales_acumulados(NULL);` | ✅ Ingresos por mes y acumulado del año. |
| `contador_juan` | `SELECT usuarioID, nombre, apellido FROM usuario;` | ✅ Columnas permitidas. |
| `contador_juan` | `SELECT contacto FROM usuario;` | ❌ Error 1143: acceso denegado a la columna. |
| `contador_juan` | `DELETE FROM pago WHERE pagoID = 1;` | ❌ Error 1142: no puede eliminar. |
| `admin_coworking` | Cualquier operación sobre `coworking` | ✅ Permitido. |

---

## 📝 Notas y limitaciones

- **Procedimientos que reciben IDs.** Procedimientos como `sp_crear_reserva` o `sp_registrar_lote_empleados` reciben el ID del usuario o de la empresa como parámetro. MySQL no puede comprobar que ese ID sea el de quien llama, por lo que la aplicación debe enviar siempre el ID del usuario autenticado.
- **Eventos y triggers no dependen de los roles.** Se ejecutan con los permisos de quien los creó, no con los del usuario que provoca el cambio.
- **Funciones.** No se otorgan permisos `EXECUTE` sobre funciones directamente a los roles. Las funciones que usen los triggers, eventos o procedimientos se ejecutan con los permisos de su definidor. Si algún rol necesita llamar una función desde sus propias consultas, se le otorga con `GRANT EXECUTE ON FUNCTION coworking.nombre_funcion TO 'rol_xxx';`.
- **Nuevos objetos.** Si se agregan tablas, vistas o procedimientos, hay que otorgarlos a los roles que correspondan; no se heredan automáticamente.
- **Orden de ejecución.** `07_seguridad` se ejecuta al final, porque otorga permisos sobre objetos creados por los scripts de estructura, eventos y procedimientos (`notificacion`, `reembolso` y los `sp_*`).
- **Contraseñas.** Las del script de ejemplo son de prueba; no deben usarse en producción.
