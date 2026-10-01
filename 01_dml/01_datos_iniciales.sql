USE coworking;

-- =====================================================
-- DATOS
-- =====================================================

-- 1. EMPRESA
INSERT INTO empresa (nit, nombre, contacto, correo, direccion, estado) VALUES
('900111222-1', 'TechSoft SAS',       '6076001111', 'contacto@techsoft.co',   'Cra 27 #45-10, Bucaramanga',   'Activa'),
('900333444-2', 'Innova Group SAS',   '6076002222', 'info@innovagroup.co',    'Cll 36 #28-50, Bucaramanga',   'Activa'),
('900555666-3', 'Ortiz & Asociados',  '6076003333', 'admin@ortizasoc.co',     'Cra 33 #52-15, Bucaramanga',   'Activa'),
('900777888-4', 'DataCol SAS',        '6076004444', 'hola@datacol.co',        'Cll 41 #31-20, Bucaramanga',   'Activa'),
('900999000-5', 'Creativa Studio',    '6076005555', 'studio@creativa.co',     'Cra 29 #38-12, Bucaramanga',   'Activa'),
('900222333-6', 'Rojas Diseño',       '6076006666', 'info@rojasdiseno.co',    'Cll 48 #27-33, Bucaramanga',   'Inactiva');

-- 2. TIPO_MEMBRESIA (duración en días)
INSERT INTO tipo_membresia (nombre, precio, duracion) VALUES
('Diaria',      30000.00,  1),
('Mensual',     100000.00, 30),
('Corporativa', 500000.00, 365),
('Premium',     250000.00, 30);

-- 3. USUARIO (membresiaID se actualiza después de insertar las membresías)
INSERT INTO usuario (nombre, apellido, edad, contacto, membresiaID, empresaID) VALUES
('Carlos',    'Ramírez Gómez',     36, 'carlos.ramirez@mail.com | 3001234567',    NULL, 1),
('Laura',     'Martínez Pérez',    31, 'laura.martinez@mail.com | 3012345678',    NULL, NULL),
('Andrés',    'Torres Villamizar', 40, 'andres.torres@innova.co | 3023456789',    NULL, 2),
('Daniela',   'Rojas Castillo',    34, 'daniela.rojas@mail.com | 3034567890',     NULL, 6),
('Felipe',    'Herrera Núñez',     28, 'felipe.herrera@mail.com | 3045678901',    NULL, NULL),
('Camila',    'Ortiz Barrera',     33, 'camila.ortiz@mail.com | 3056789012',      NULL, 3),
('Julián',    'Mendoza Díaz',      37, 'julian.mendoza@mail.com | 3067890123',    NULL, NULL),
('Valentina', 'Suárez Acevedo',    30, 'valentina.suarez@mail.com | 3078901234',  NULL, 4),
('Sebastián', 'Gómez Ruiz',        35, 'sebastian.gomez@mail.com | 3089012345',   NULL, NULL),
('Mariana',   'Pineda Soto',       31, 'mariana.pineda@mail.com | 3090123456',    NULL, 5);

-- 4. MEMBRESIA
INSERT INTO membresia (tipo, estado, fecha_inicio, fecha_fin, usuarioID, tipoID) VALUES
('Mensual',     'Activa',     '2026-09-01', '2026-09-30', 1,  2),
('Diaria',      'Vencida',    '2026-09-29', '2026-09-29', 2,  1),
('Corporativa', 'Activa',     '2026-01-01', '2026-12-31', 3,  3),
('Premium',     'Activa',     '2026-09-01', '2026-09-30', 4,  4),
('Diaria',      'Activa',     '2026-09-30', '2026-09-30', 5,  1),
('Mensual',     'Vencida',    '2026-08-01', '2026-08-31', 6,  2),
('Diaria',      'Vencida',    '2026-09-20', '2026-09-20', 7,  1),
('Mensual',     'Activa',     '2026-09-15', '2026-10-14', 8,  2),
('Mensual',     'Suspendida', '2026-09-01', '2026-09-30', 9,  2),
('Mensual',     'Activa',     '2026-10-01', '2026-10-31', 10, 2);

-- Relación usuario -> membresía (cada usuario con su membresía)
UPDATE usuario u
JOIN membresia m ON m.usuarioID = u.usuarioID
SET u.membresiaID = m.membresiaID;

-- 5. ESPACIO
INSERT INTO espacio (nombre, tipo, capacidad_maxima, ubicacion, estado) VALUES
('Escritorio Flex A1',    'Escritorio flexible', 1,  'Piso 1', 'Disponible'),
('Escritorio Flex A2',    'Escritorio flexible', 1,  'Piso 1', 'Ocupado'),
('Oficina Privada 101',   'Oficina privada',     4,  'Piso 2', 'Ocupado'),
('Oficina Privada 102',   'Oficina privada',     6,  'Piso 2', 'Disponible'),
('Sala Reuniones Andes',  'Sala de reuniones',   10, 'Piso 1', 'Disponible'),
('Sala Reuniones Caribe', 'Sala de reuniones',   8,  'Piso 3', 'Mantenimiento'),
('Salón Eventos Gran',    'Sala de eventos',     50, 'Piso 3', 'Disponible'),
('Escritorio Flex A3',    'Escritorio flexible', 1,  'Piso 1', 'Disponible');

-- 6. HORARIO_DISPONIBILIDAD
INSERT INTO horario_disponibilidad (dia_semana, hora_inicio, hora_fin, espacioID) VALUES
('Lunes',     '07:00:00', '20:00:00', 1),
('Martes',    '07:00:00', '20:00:00', 1),
('Sabado',    '08:00:00', '14:00:00', 1),
('Lunes',     '07:00:00', '20:00:00', 2),
('Miercoles', '07:00:00', '20:00:00', 3),
('Jueves',    '07:00:00', '20:00:00', 4),
('Lunes',     '08:00:00', '18:00:00', 5),
('Jueves',    '08:00:00', '18:00:00', 5),
('Viernes',   '08:00:00', '18:00:00', 5),
('Martes',    '08:00:00', '18:00:00', 6),
('Viernes',   '14:00:00', '23:00:00', 7),
('Sabado',    '10:00:00', '23:00:00', 7),
('Viernes',   '07:00:00', '20:00:00', 8);

-- 7. RESERVA (duración en minutos)
INSERT INTO reserva (fecha_reserva, hora_inicio, hora_fin, duracion, estado, espacioID, usuarioID) VALUES
('2026-09-28', '09:00:00', '11:00:00', 120, 'Finalizada', 5, 3),
('2026-09-29', '08:00:00', '18:00:00', 600, 'Finalizada', 4, 4),
('2026-10-02', '14:00:00', '16:00:00', 120, 'Confirmada', 5, 5),
('2026-09-30', '08:00:00', '17:00:00', 540, 'Confirmada', 1, 1),
('2026-09-25', '10:00:00', '12:00:00', 120, 'Finalizada', 5, 9),
('2026-10-10', '15:00:00', '20:00:00', 300, 'Pendiente',  7, 8),
('2026-09-29', '08:00:00', '17:00:00', 540, 'Finalizada', 2, 2),
('2026-09-05', '10:00:00', '11:00:00', 60,  'Cancelada',  6, 6),
('2026-10-03', '08:00:00', '12:00:00', 240, 'Pendiente',  3, 10),
('2026-11-05', '16:00:00', '22:00:00', 360, 'Confirmada', 7, 3);

-- 8. SERVICIO_ADICIONAL
INSERT INTO servicio_adicional (nombre, descripcion, precio, estado) VALUES
('Internet premium', 'Conexión de fibra dedicada de alta velocidad', 25000.00, 'Disponible'),
('Locker',           'Casillero personal con llave',                 20000.00, 'Disponible'),
('Café ilimitado',   'Acceso libre a café y aromáticas',             30000.00, 'Disponible'),
('Impresiones',      'Impresión y escaneo por página',               500.00,   'Disponible'),
('Uso de proyector', 'Proyector HD por sesión',                      15000.00, 'Disponible'),
('Parqueadero',      'Cupo mensual de parqueadero cubierto',         60000.00, 'No disponible');

-- 9. USUARIO_SERVICIO
INSERT INTO usuario_servicio (usuarioID, servicioID, fecha_inicio, fecha_fin, cantidad) VALUES
(1, 1, '2026-09-01', '2026-09-30', 1),
(3, 1, '2026-01-01', '2026-12-31', 1),
(3, 5, '2026-09-28', '2026-09-28', 1),
(4, 3, '2026-09-01', '2026-09-30', 1),
(4, 2, '2026-09-01', '2026-09-30', 1),
(8, 3, '2026-09-15', '2026-10-14', 1),
(8, 2, '2026-09-15', '2026-10-14', 1),
(2, 4, '2026-09-29', '2026-09-29', 40);

-- 10. PAGO
INSERT INTO pago (fecha_pago, monto, metodo_pago, estado, referencia, usuarioID) VALUES
('2026-09-01 09:15:00', 119000.00, 'Tarjeta',       'Pagado',    'TRX-0001', 1),
('2026-09-29 08:05:00', 35700.00,  'Efectivo',      'Pagado',    'EFE-0002', 2),
('2026-01-02 10:30:00', 595000.00, 'Transferencia', 'Pagado',    'TRF-0003', 3),
('2026-09-01 11:00:00', 297500.00, 'PayPal',        'Pagado',    'PP-0004',  4),
('2026-09-30 07:50:00', 59500.00,  'Tarjeta',       'Pendiente', 'TRX-0005', 5),
('2026-08-01 09:00:00', 119000.00, 'Transferencia', 'Pagado',    'TRF-0006', 6),
('2026-09-20 08:10:00', 35700.00,  'Efectivo',      'Cancelado', 'EFE-0007', 7),
('2026-09-15 10:45:00', 178500.00, 'Tarjeta',       'Pagado',    'TRX-0008', 8),
('2026-09-25 09:30:00', 71400.00,  'Efectivo',      'Pagado',    'EFE-0009', 9),
('2026-09-30 12:00:00', 119000.00, 'Transferencia', 'Pendiente', 'TRF-0010', 10);

-- 11. FACTURA (IVA 19%)
INSERT INTO factura (numero_factura, fecha_emision, subtotal, impuestos, total, estado, usuarioID, pagoID) VALUES
('FAC-2026-0001', '2026-09-01 09:20:00', 100000.00, 19000.00, 119000.00, 'Pagada',    1,  1),
('FAC-2026-0002', '2026-09-29 08:10:00', 30000.00,  5700.00,  35700.00,  'Pagada',    2,  2),
('FAC-2026-0003', '2026-01-02 10:35:00', 500000.00, 95000.00, 595000.00, 'Pagada',    3,  3),
('FAC-2026-0004', '2026-09-01 11:05:00', 250000.00, 47500.00, 297500.00, 'Pagada',    4,  4),
('FAC-2026-0005', '2026-09-30 07:55:00', 50000.00,  9500.00,  59500.00,  'Pendiente', 5,  5),
('FAC-2026-0006', '2026-08-01 09:05:00', 100000.00, 19000.00, 119000.00, 'Pagada',    6,  6),
('FAC-2026-0007', '2026-09-20 08:15:00', 30000.00,  5700.00,  35700.00,  'Cancelada', 7,  7),
('FAC-2026-0008', '2026-09-15 10:50:00', 150000.00, 28500.00, 178500.00, 'Pagada',    8,  8),
('FAC-2026-0009', '2026-09-25 09:35:00', 60000.00,  11400.00, 71400.00,  'Pagada',    9,  9),
('FAC-2026-0010', '2026-09-30 12:05:00', 100000.00, 19000.00, 119000.00, 'Pendiente', 10, 10);

-- 12. DETALLE_FACTURA
INSERT INTO detalle_factura (facturaID, concepto, cantidad, precio_unitario, subtotal) VALUES
(1,  'Membresía Mensual',                 1, 100000.00, 100000.00),
(2,  'Membresía Diaria',                  1, 30000.00,  30000.00),
(3,  'Membresía Corporativa',             1, 500000.00, 500000.00),
(4,  'Membresía Premium',                 1, 250000.00, 250000.00),
(5,  'Reserva Sala Reuniones Andes (2h)', 2, 25000.00,  50000.00),
(6,  'Membresía Mensual',                 1, 100000.00, 100000.00),
(7,  'Membresía Diaria',                  1, 30000.00,  30000.00),
(8,  'Membresía Mensual',                 1, 100000.00, 100000.00),
(8,  'Servicio Café ilimitado',           1, 30000.00,  30000.00),
(8,  'Servicio Locker',                   1, 20000.00,  20000.00),
(9,  'Reserva Sala Reuniones Andes (2h)', 2, 30000.00,  60000.00),
(10, 'Membresía Mensual',                 1, 100000.00, 100000.00);

-- 13. ACCESO
INSERT INTO acceso (tipo_acceso, codigo, fecha_registro, usuarioID) VALUES
('RFID', 'RFID-A1B2C3D4', '2026-09-01 09:30:00', 1),
('QR',   'QR-7F3K9L2M',   '2026-09-29 08:15:00', 2),
('RFID', 'RFID-E5F6G7H8', '2026-01-02 10:45:00', 3),
('RFID', 'RFID-I9J0K1L2', '2026-09-01 11:15:00', 4),
('QR',   'QR-2P8R5T1V',   '2026-09-30 08:00:00', 5),
('RFID', 'RFID-M3N4O5P6', '2026-08-01 09:10:00', 6),
('QR',   'QR-9X4C7B6N',   '2026-09-20 08:20:00', 7),
('RFID', 'RFID-Q7R8S9T0', '2026-09-15 11:00:00', 8),
('QR',   'QR-5H1J8K3L',   '2026-09-01 09:00:00', 9),
('RFID', 'RFID-U1V2W3X4', '2026-09-30 12:10:00', 10);

-- 14. ASISTENCIA
INSERT INTO asistencia (fecha, hora_entrada, hora_salida, resultado_validacion, usuarioID, reservaID) VALUES
('2026-09-30', '08:05:00', NULL,       'Autorizado', 1, 4),
('2026-09-29', '08:10:00', '17:00:00', 'Autorizado', 2, 7),
('2026-09-28', '08:55:00', '11:05:00', 'Autorizado', 3, 1),
('2026-09-29', '07:58:00', '18:10:00', 'Autorizado', 4, 2),
('2026-09-29', '09:00:00', '17:30:00', 'Autorizado', 8, NULL),
('2026-09-25', '09:55:00', '12:00:00', 'Autorizado', 9, 5),
('2026-09-10', '10:00:00', NULL,       'Rechazado',  6, NULL),
('2026-09-21', '08:30:00', NULL,       'Rechazado',  7, NULL),
('2026-09-29', '08:00:00', '18:00:00', 'Autorizado', 3, NULL),
('2026-09-29', '09:15:00', NULL,       'Rechazado',  9, NULL);