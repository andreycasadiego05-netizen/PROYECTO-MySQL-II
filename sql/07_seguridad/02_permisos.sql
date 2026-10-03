USE coworking;

CREATE USER 'administrador'@'localhost'
IDENTIFIED BY 'Administrador1!';

CREATE USER 'recepcionista'@'localhost'
IDENTIFIED BY 'Recepcionista1!';

CREATE USER 'contabilidad'@'localhost'
IDENTIFIED BY 'Contabilidad!';

CREATE USER 'cliente'@'localhost'
IDENTIFIED BY 'Cliente1!';

CREATE USER 'gestor_espacios'@'localhost'
IDENTIFIED BY 'Gestor1!';


GRANT ALL PRIVILEGES ON coworking_db.* TO 'administrador'@'localhost';


GRANT ALL PRIVILEGES ON coworking_db.usuario TO 'recepcionista'@'localhost';
GRANT ALL PRIVILEGES ON coworking_db.membresia TO 'recepcionista'@'localhost';
GRANT ALL PRIVILEGES ON coworking_db.reserva TO 'recepcionista'@'localhost';
GRANT ALL PRIVILEGES ON coworking_db.servicio_adicional TO 'recepcionista'@'localhost';
GRANT ALL PRIVILEGES ON coworking_db.usuario_servicio TO 'recepcionista'@'localhost';
GRANT ALL PRIVILEGES ON coworking_db.acceso TO 'recepcionista'@'localhost';
GRANT ALL PRIVILEGES ON coworking_db.asistencia TO 'recepcionista'@'localhost';

GRANT SELECT ON coworking_db.espacio TO 'recepcionista'@'localhost';
GRANT SELECT ON coworking_db.horario_disponibilidad TO 'recepcionista'@'localhost';
GRANT SELECT ON coworking_db.pago TO 'recepcionista'@'localhost';
GRANT SELECT ON coworking_db.factura TO 'recepcionista'@'localhost';
GRANT SELECT ON coworking_db.detalle_factura TO 'recepcionista'@'localhost';


GRANT ALL PRIVILEGES ON coworking_db.pago TO 'contabilidad'@'localhost';
GRANT ALL PRIVILEGES ON coworking_db.factura TO 'contabilidad'@'localhost';
GRANT ALL PRIVILEGES ON coworking_db.detalle_factura TO 'contabilidad'@'localhost';

GRANT SELECT ON coworking_db.usuario TO 'contabilidad'@'localhost';
GRANT SELECT ON coworking_db.membresia TO 'contabilidad'@'localhost';
GRANT SELECT ON coworking_db.reserva TO 'contabilidad'@'localhost';
GRANT SELECT ON coworking_db.servicio_adicional TO 'contabilidad'@'localhost';
GRANT SELECT ON coworking_db.usuario_servicio TO 'contabilidad'@'localhost';
GRANT SELECT ON coworking_db.asistencia TO 'contabilidad'@'localhost';


GRANT ALL PRIVILEGES ON coworking_db.reserva TO 'cliente'@'localhost';
GRANT ALL PRIVILEGES ON coworking_db.usuario_servicio TO 'cliente'@'localhost';

GRANT SELECT ON coworking_db.usuario TO 'cliente'@'localhost';
GRANT SELECT ON coworking_db.membresia TO 'cliente'@'localhost';
GRANT SELECT ON coworking_db.espacio TO 'cliente'@'localhost';
GRANT SELECT ON coworking_db.horario_disponibilidad TO 'cliente'@'localhost';
GRANT SELECT ON coworking_db.servicio_adicional TO 'cliente'@'localhost';
GRANT SELECT ON coworking_db.pago TO 'cliente'@'localhost';
GRANT SELECT ON coworking_db.factura TO 'cliente'@'localhost';
GRANT SELECT ON coworking_db.detalle_factura TO 'cliente'@'localhost';
GRANT SELECT ON coworking_db.acceso TO 'cliente'@'localhost';
GRANT SELECT ON coworking_db.asistencia TO 'cliente'@'localhost';


GRANT ALL PRIVILEGES ON coworking_db.espacio TO 'gestor_espacios'@'localhost';
GRANT ALL PRIVILEGES ON coworking_db.horario_disponibilidad TO 'gestor_espacios'@'localhost';
GRANT ALL PRIVILEGES ON coworking_db.reserva TO 'gestor_espacios'@'localhost';

GRANT SELECT ON coworking_db.usuario TO 'gestor_espacios'@'localhost';
GRANT SELECT ON coworking_db.membresia TO 'gestor_espacios'@'localhost';
GRANT SELECT ON coworking_db.servicio_adicional TO 'gestor_espacios'@'localhost';
GRANT SELECT ON coworking_db.usuario_servicio TO 'gestor_espacios'@'localhost';
GRANT SELECT ON coworking_db.acceso TO 'gestor_espacios'@'localhost';
GRANT SELECT ON coworking_db.asistencia TO 'gestor_espacios'@'localhost';


FLUSH PRIVILEGES;