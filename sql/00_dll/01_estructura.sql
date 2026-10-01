DROP DATABASE IF EXISTS coworking;
CREATE DATABASE coworking;
USE coworking;

-- =====================================================
-- TABLAS
-- =====================================================

CREATE TABLE empresa (
    empresaID INT AUTO_INCREMENT PRIMARY KEY,
    nit VARCHAR(20) NOT NULL UNIQUE,
    nombre VARCHAR(100) NOT NULL,
    contacto VARCHAR(50),
    correo VARCHAR(100),
    direccion VARCHAR(150),
    estado ENUM('Activa', 'Inactiva') NOT NULL
);

CREATE TABLE tipo_membresia (
    tipoID INT AUTO_INCREMENT PRIMARY KEY,
    nombre ENUM('Diaria', 'Mensual', 'Corporativa', 'Premium') NOT NULL,
    precio DECIMAL(10,2) NOT NULL,
    duracion INT NOT NULL COMMENT 'Duración en días'
);

-- membresiaID se agrega como FK con ALTER TABLE más abajo,
-- porque usuario y membresia se referencian entre sí (dependencia circular).
CREATE TABLE usuario (
    usuarioID INT AUTO_INCREMENT PRIMARY KEY,
    nombre VARCHAR(50) NOT NULL,
    apellido VARCHAR(80) NOT NULL,
    edad INT NOT NULL,
    contacto VARCHAR(100),
    membresiaID INT NULL,
    empresaID INT NULL,
    FOREIGN KEY (empresaID) REFERENCES empresa(empresaID)
);

CREATE TABLE membresia (
    membresiaID INT AUTO_INCREMENT PRIMARY KEY,
    tipo ENUM('Diaria', 'Mensual', 'Corporativa', 'Premium') NOT NULL,
    estado ENUM('Activa', 'Suspendida', 'Vencida') NOT NULL,
    fecha_inicio DATE NOT NULL,
    fecha_fin DATE NOT NULL,
    usuarioID INT NOT NULL,
    tipoID INT NOT NULL,
    FOREIGN KEY (usuarioID) REFERENCES usuario(usuarioID),
    FOREIGN KEY (tipoID) REFERENCES tipo_membresia(tipoID)
);

ALTER TABLE usuario
    ADD CONSTRAINT fk_usuario_membresia
    FOREIGN KEY (membresiaID) REFERENCES membresia(membresiaID);

CREATE TABLE espacio (
    espacioID INT AUTO_INCREMENT PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL,
    tipo ENUM('Escritorio flexible', 'Oficina privada', 'Sala de reuniones', 'Sala de eventos') NOT NULL,
    capacidad_maxima INT NOT NULL,
    ubicacion VARCHAR(100),
    estado ENUM('Disponible', 'Ocupado', 'Mantenimiento') NOT NULL
);

CREATE TABLE horario_disponibilidad (
    horarioID INT AUTO_INCREMENT PRIMARY KEY,
    dia_semana ENUM('Lunes', 'Martes', 'Miercoles', 'Jueves', 'Viernes', 'Sabado', 'Domingo') NOT NULL,
    hora_inicio TIME NOT NULL,
    hora_fin TIME NOT NULL,
    espacioID INT NOT NULL,
    FOREIGN KEY (espacioID) REFERENCES espacio(espacioID)
);

CREATE TABLE reserva (
    reservaID INT AUTO_INCREMENT PRIMARY KEY,
    fecha_reserva DATE NOT NULL,
    hora_inicio TIME NOT NULL,
    hora_fin TIME NOT NULL,
    duracion INT NOT NULL COMMENT 'Duración en minutos',
    estado ENUM('Pendiente', 'Confirmada', 'Cancelada', 'Finalizada') NOT NULL,
    espacioID INT NOT NULL,
    usuarioID INT NOT NULL,
    FOREIGN KEY (espacioID) REFERENCES espacio(espacioID),
    FOREIGN KEY (usuarioID) REFERENCES usuario(usuarioID)
);

CREATE TABLE servicio_adicional (
    servicioID INT AUTO_INCREMENT PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL,
    descripcion VARCHAR(255),
    precio DECIMAL(10,2) NOT NULL,
    estado ENUM('Disponible', 'No disponible') NOT NULL
);

CREATE TABLE usuario_servicio (
    usuario_servicioID INT AUTO_INCREMENT PRIMARY KEY,
    usuarioID INT NOT NULL,
    servicioID INT NOT NULL,
    fecha_inicio DATE NOT NULL,
    fecha_fin DATE,
    cantidad INT DEFAULT 1,
    FOREIGN KEY (usuarioID) REFERENCES usuario(usuarioID),
    FOREIGN KEY (servicioID) REFERENCES servicio_adicional(servicioID)
);

CREATE TABLE pago (
    pagoID INT AUTO_INCREMENT PRIMARY KEY,
    fecha_pago DATETIME NOT NULL,
    monto DECIMAL(10,2) NOT NULL,
    metodo_pago ENUM('Efectivo', 'Tarjeta', 'Transferencia', 'PayPal') NOT NULL,
    estado ENUM('Pagado', 'Pendiente', 'Cancelado') NOT NULL,
    referencia VARCHAR(100),
    usuarioID INT NOT NULL,
    FOREIGN KEY (usuarioID) REFERENCES usuario(usuarioID)
);

CREATE TABLE factura (
    facturaID INT AUTO_INCREMENT PRIMARY KEY,
    numero_factura VARCHAR(30) NOT NULL UNIQUE,
    fecha_emision DATETIME NOT NULL,
    subtotal DECIMAL(10,2) NOT NULL,
    impuestos DECIMAL(10,2) DEFAULT 0,
    total DECIMAL(10,2) NOT NULL,
    estado ENUM('Pagada', 'Pendiente', 'Cancelada') NOT NULL,
    usuarioID INT NOT NULL,
    pagoID INT,
    FOREIGN KEY (usuarioID) REFERENCES usuario(usuarioID),
    FOREIGN KEY (pagoID) REFERENCES pago(pagoID)
);

CREATE TABLE detalle_factura (
    detalle_facturaID INT AUTO_INCREMENT PRIMARY KEY,
    facturaID INT NOT NULL,
    concepto VARCHAR(150) NOT NULL,
    cantidad INT NOT NULL,
    precio_unitario DECIMAL(10,2) NOT NULL,
    subtotal DECIMAL(10,2) NOT NULL,
    FOREIGN KEY (facturaID) REFERENCES factura(facturaID)
);

CREATE TABLE acceso (
    accesoID INT AUTO_INCREMENT PRIMARY KEY,
    tipo_acceso ENUM('RFID', 'QR') NOT NULL,
    codigo VARCHAR(100) NOT NULL UNIQUE,
    fecha_registro DATETIME NOT NULL,
    usuarioID INT NOT NULL,
    FOREIGN KEY (usuarioID) REFERENCES usuario(usuarioID)
);

CREATE TABLE asistencia (
    asistenciaID INT AUTO_INCREMENT PRIMARY KEY,
    fecha DATE NOT NULL,
    hora_entrada TIME NOT NULL,
    hora_salida TIME,
    resultado_validacion ENUM('Autorizado', 'Rechazado') NOT NULL,
    usuarioID INT NOT NULL,
    reservaID INT,
    FOREIGN KEY (usuarioID) REFERENCES usuario(usuarioID),
    FOREIGN KEY (reservaID) REFERENCES reserva(reservaID)
);