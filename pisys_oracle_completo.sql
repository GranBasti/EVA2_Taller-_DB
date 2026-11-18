-- =====================================================================================
--  PISYS · Sistema de Reclutamiento y Evaluación de Candidatos
--  Base de datos COMPLETA para Oracle (12c o superior: usa columnas IDENTITY)
--  Empresa: comercialización de salmón
--
--  Contenido
--    1. Limpieza (permite volver a ejecutar el script)
--    2. Tablas, restricciones e índices
--    3. Reglas de negocio con triggers
--    4. Vistas de consulta
--    5. Procedimientos almacenados
--    6. Datos de ejemplo (los mismos que usa el frontend)
--    7. Consultas de comprobación
--
--  Cambios respecto a los scripts originales (01 a 03):
--    * Solicitud_Evaluacion pasa a llamarse Solicitud_Cargo: es una solicitud de CARGOS que se
--      puede publicar (titulo, descripcion, ubicacion, fecha_cierre, publicada, fecha_publicacion).
--    * Detalle_Solicitud_Cargo agrega descripcion y nueva tabla Requisito_Cargo (requisitos).
--    * Candidato agrega origen (Ingreso interno / Postulación web) y fecha_registro.
--    * Nueva tabla Documento (BLOB): currículum del candidato y documentos de evaluación.
--    * Se agregan restricciones únicas, CHECK, índices, triggers, vistas y procedimientos.
--
--  Ejecutar como script completo (SQL Developer: F5 / SQL*Plus: @pisys_oracle_completo.sql)
-- =====================================================================================

SET DEFINE OFF;

-- =====================================================================================
-- 1. LIMPIEZA
-- =====================================================================================
BEGIN
  FOR t IN (SELECT column_value AS nombre FROM TABLE(sys.odcivarchar2list(
              'DOCUMENTO','EVALUACION','ENTREVISTA','HISTORIAL_ESTADO_POSTULACION','POSTULACION',
              'REQUISITO_CARGO','DETALLE_SOLICITUD_CARGO','SOLICITUD_CARGO','SOLICITUD_EVALUACION',
              'EMPLEADO','CANDIDATO','CARGO','ESTADO','ROL'))) LOOP
    BEGIN
      EXECUTE IMMEDIATE 'DROP TABLE ' || t.nombre || ' CASCADE CONSTRAINTS PURGE';
    EXCEPTION WHEN OTHERS THEN
      IF SQLCODE != -942 THEN RAISE; END IF;   -- -942: la tabla no existe
    END;
  END LOOP;
END;
/

-- =====================================================================================
-- 2. TABLAS
-- =====================================================================================

-- ---- Catálogos --------------------------------------------------------------------
CREATE TABLE Rol (
    id_rol      NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre_rol  VARCHAR2(50) NOT NULL
);

-- Ej: Postulado, En Revisión, Rechazado, Aprobado
CREATE TABLE Estado (
    id_estado      NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre_estado  VARCHAR2(50) NOT NULL
);

CREATE TABLE Cargo (
    id_cargo      NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre_cargo  VARCHAR2(100) NOT NULL
);

-- Los nombres de catálogo no se repiten (sin distinguir mayúsculas)  [RF-01, RF-02, RF-03]
CREATE UNIQUE INDEX ux_rol_nombre    ON Rol    (LOWER(nombre_rol));
CREATE UNIQUE INDEX ux_estado_nombre ON Estado (LOWER(nombre_estado));
CREATE UNIQUE INDEX ux_cargo_nombre  ON Cargo  (LOWER(nombre_cargo));

-- ---- Personas ---------------------------------------------------------------------
-- Base de talentos. Un candidato puede ser ingresado por un analista o postular por la web.
CREATE TABLE Candidato (
    id_candidato    NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre          VARCHAR2(100) NOT NULL,
    apellido        VARCHAR2(100) NOT NULL,
    telefono        VARCHAR2(20),
    email           VARCHAR2(100) NOT NULL,
    direccion       VARCHAR2(200),
    origen          VARCHAR2(30)  DEFAULT 'Ingreso interno' NOT NULL,
    fecha_registro  TIMESTAMP     DEFAULT SYSTIMESTAMP NOT NULL,
    CONSTRAINT ck_candidato_origen CHECK (origen IN ('Ingreso interno', 'Postulación web'))
);
CREATE UNIQUE INDEX ux_candidato_email ON Candidato (LOWER(email));     -- [RF-10]

CREATE TABLE Empleado (
    id_empleado  NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre       VARCHAR2(100) NOT NULL,
    apellido     VARCHAR2(100) NOT NULL,
    telefono     VARCHAR2(20),
    email        VARCHAR2(100) NOT NULL,
    direccion    VARCHAR2(200),
    id_rol       NUMBER NOT NULL,
    CONSTRAINT fk_empleado_rol FOREIGN KEY (id_rol) REFERENCES Rol (id_rol)
);
CREATE UNIQUE INDEX ux_empleado_email ON Empleado (LOWER(email));
CREATE INDEX ix_empleado_rol ON Empleado (id_rol);

-- ---- Solicitudes de cargos y ofertas ----------------------------------------------
-- Una solicitud agrupa uno o más cargos. Si publicada = 1 aparece en el sitio público.
CREATE TABLE Solicitud_Cargo (
    id_solicitud       NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    titulo             VARCHAR2(150) NOT NULL,
    descripcion        VARCHAR2(4000),
    ubicacion          VARCHAR2(100),
    fecha_cierre       DATE,                         -- NULL = postulación abierta sin plazo
    observacion        VARCHAR2(4000),               -- nota interna, no se publica
    id_evaluador       NUMBER NOT NULL,              -- líder evaluador
    publicada          NUMBER(1) DEFAULT 0 NOT NULL,
    fecha_publicacion  TIMESTAMP,
    CONSTRAINT fk_solicitud_empleado FOREIGN KEY (id_evaluador) REFERENCES Empleado (id_empleado),
    CONSTRAINT ck_solicitud_publicada CHECK (publicada IN (0, 1)),
    CONSTRAINT ck_solicitud_fechapub  CHECK ((publicada = 1 AND fecha_publicacion IS NOT NULL) OR publicada = 0)
);
CREATE INDEX ix_solicitud_evaluador ON Solicitud_Cargo (id_evaluador);
CREATE INDEX ix_solicitud_publicada ON Solicitud_Cargo (publicada, fecha_cierre);

-- Cada cargo ofertado dentro de una solicitud (un cargo no se repite en la misma solicitud)
CREATE TABLE Detalle_Solicitud_Cargo (
    id_detalle    NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_solicitud  NUMBER NOT NULL,
    id_cargo      NUMBER NOT NULL,
    descripcion   VARCHAR2(2000),
    CONSTRAINT fk_detalle_solicitud FOREIGN KEY (id_solicitud) REFERENCES Solicitud_Cargo (id_solicitud) ON DELETE CASCADE,
    CONSTRAINT fk_detalle_cargo     FOREIGN KEY (id_cargo)     REFERENCES Cargo (id_cargo),
    CONSTRAINT uq_detalle_solicitud_cargo UNIQUE (id_solicitud, id_cargo)
);
CREATE INDEX ix_detalle_cargo ON Detalle_Solicitud_Cargo (id_cargo);

-- Requisitos de cada cargo ofertado (uno por fila)
CREATE TABLE Requisito_Cargo (
    id_requisito  NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_detalle    NUMBER NOT NULL,
    orden         NUMBER(3) DEFAULT 1 NOT NULL,
    texto         VARCHAR2(300) NOT NULL,
    CONSTRAINT fk_requisito_detalle FOREIGN KEY (id_detalle) REFERENCES Detalle_Solicitud_Cargo (id_detalle) ON DELETE CASCADE
);
CREATE INDEX ix_requisito_detalle ON Requisito_Cargo (id_detalle, orden);

-- ---- Postulaciones ----------------------------------------------------------------
CREATE TABLE Postulacion (
    id_postulacion     NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_candidato       NUMBER NOT NULL,
    id_detalle         NUMBER NOT NULL,
    fecha_postulacion  TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
    CONSTRAINT fk_post_candidato FOREIGN KEY (id_candidato) REFERENCES Candidato (id_candidato),
    CONSTRAINT fk_post_detalle   FOREIGN KEY (id_detalle)   REFERENCES Detalle_Solicitud_Cargo (id_detalle),
    CONSTRAINT uq_post_candidato_detalle UNIQUE (id_candidato, id_detalle)      -- [RF-14]
);
CREATE INDEX ix_post_detalle ON Postulacion (id_detalle);

-- Trazabilidad: el estado actual es el último registro [RF-15, RF-16]
CREATE TABLE Historial_Estado_Postulacion (
    id_historial    NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_postulacion  NUMBER NOT NULL,
    id_estado       NUMBER NOT NULL,
    fecha_cambio    TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
    CONSTRAINT fk_historial_postulacion FOREIGN KEY (id_postulacion) REFERENCES Postulacion (id_postulacion),
    CONSTRAINT fk_historial_estado      FOREIGN KEY (id_estado)      REFERENCES Estado (id_estado)
);
CREATE INDEX ix_historial_post   ON Historial_Estado_Postulacion (id_postulacion, fecha_cambio);
CREATE INDEX ix_historial_estado ON Historial_Estado_Postulacion (id_estado);

-- ---- Entrevistas y evaluaciones ---------------------------------------------------
CREATE TABLE Entrevista (
    id_entrevista     NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_empleado       NUMBER NOT NULL,             -- quien entrevista
    id_postulacion    NUMBER NOT NULL,
    fecha_entrevista  DATE NOT NULL,
    CONSTRAINT fk_entrevista_empleado FOREIGN KEY (id_empleado)    REFERENCES Empleado (id_empleado),
    CONSTRAINT fk_entrevista_post     FOREIGN KEY (id_postulacion) REFERENCES Postulacion (id_postulacion),
    CONSTRAINT uq_entrevista_agenda   UNIQUE (id_empleado, fecha_entrevista)    -- sin choques de agenda [RF-18]
);
CREATE INDEX ix_entrevista_post ON Entrevista (id_postulacion);

CREATE TABLE Evaluacion (
    id_evaluacion  NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_entrevista  NUMBER NOT NULL,                -- relación 1:1
    id_empleado    NUMBER NOT NULL,                -- quien registró la evaluación
    calificacion   NUMBER(5,2),
    comentarios    VARCHAR2(4000),
    CONSTRAINT uq_evaluacion_entrevista UNIQUE (id_entrevista),
    CONSTRAINT fk_evaluacion_entrevista FOREIGN KEY (id_entrevista) REFERENCES Entrevista (id_entrevista),
    CONSTRAINT fk_evaluacion_empleado   FOREIGN KEY (id_empleado)   REFERENCES Empleado (id_empleado),
    CONSTRAINT ck_evaluacion_nota CHECK (calificacion IS NULL OR calificacion BETWEEN 0 AND 100)   -- [RF-20]
);
CREATE INDEX ix_evaluacion_empleado ON Evaluacion (id_empleado);

-- ---- Documentos adjuntos (PDF / Word) ----------------------------------------------
-- Pertenecen a un candidato (currículum, certificados) O a una evaluación (pruebas, test psicológicos).
CREATE TABLE Documento (
    id_documento    NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_candidato    NUMBER,
    id_evaluacion   NUMBER,
    categoria       VARCHAR2(40)  NOT NULL,        -- Currículum, Test psicológico, Prueba técnica...
    nombre_archivo  VARCHAR2(255) NOT NULL,
    tipo_mime       VARCHAR2(100) NOT NULL,
    tamano          NUMBER        NOT NULL,        -- bytes
    contenido       BLOB          NOT NULL,
    fecha_carga     TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
    CONSTRAINT fk_doc_candidato  FOREIGN KEY (id_candidato)  REFERENCES Candidato (id_candidato)   ON DELETE CASCADE,
    CONSTRAINT fk_doc_evaluacion FOREIGN KEY (id_evaluacion) REFERENCES Evaluacion (id_evaluacion) ON DELETE CASCADE,
    CONSTRAINT ck_doc_dueno CHECK ((id_candidato IS NOT NULL AND id_evaluacion IS NULL)
                                OR (id_candidato IS NULL AND id_evaluacion IS NOT NULL)),
    CONSTRAINT ck_doc_tamano CHECK (tamano > 0 AND tamano <= 1048576),                              -- máx. 1 MB
    CONSTRAINT ck_doc_tipo CHECK (tipo_mime IN ('application/pdf', 'application/msword',
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document'))                -- solo PDF o Word
);
CREATE INDEX ix_doc_candidato  ON Documento (id_candidato);
CREATE INDEX ix_doc_evaluacion ON Documento (id_evaluacion);

-- ---- Comentarios del diccionario de datos ------------------------------------------
COMMENT ON TABLE Solicitud_Cargo            IS 'Solicitud de cargos. Si publicada=1 se muestra en el sitio público de ofertas.';
COMMENT ON TABLE Detalle_Solicitud_Cargo    IS 'Cargo ofertado dentro de una solicitud.';
COMMENT ON TABLE Requisito_Cargo            IS 'Requisitos que debe cumplir quien postule a un cargo ofertado.';
COMMENT ON TABLE Historial_Estado_Postulacion IS 'Historial inmutable; el estado actual es el último registro.';
COMMENT ON TABLE Documento                  IS 'Archivos PDF/Word del candidato o de una evaluación (BLOB, máx. 1 MB).';
COMMENT ON COLUMN Candidato.origen          IS 'Ingreso interno (analista) o Postulación web (el propio candidato).';

-- =====================================================================================
-- 3. REGLAS DE NEGOCIO (TRIGGERS)
-- =====================================================================================

-- El historial de estados nunca se modifica ni se borra [RF-15]
CREATE OR REPLACE TRIGGER trg_historial_inmutable
BEFORE UPDATE OR DELETE ON Historial_Estado_Postulacion
BEGIN
  RAISE_APPLICATION_ERROR(-20001, 'El historial de estados no se puede modificar ni eliminar.');
END;
/

-- No se puede programar una entrevista en una fecha anterior a hoy [RF-18]
CREATE OR REPLACE TRIGGER trg_entrevista_fecha
BEFORE INSERT ON Entrevista
FOR EACH ROW
BEGIN
  IF TRUNC(:NEW.fecha_entrevista) < TRUNC(SYSDATE) THEN
    RAISE_APPLICATION_ERROR(-20002, 'La fecha de la entrevista no puede ser anterior a hoy.');
  END IF;
END;
/

-- Una solicitud solo se publica si tiene al menos un cargo y todos sus cargos tienen requisitos
CREATE OR REPLACE TRIGGER trg_solicitud_publicar
BEFORE INSERT OR UPDATE OF publicada ON Solicitud_Cargo
FOR EACH ROW
WHEN (NEW.publicada = 1)
DECLARE
  v_cargos       NUMBER;
  v_sin_requisito NUMBER;
BEGIN
  IF INSERTING THEN
    RAISE_APPLICATION_ERROR(-20003, 'Crea la solicitud como borrador, agrega cargos con requisitos y luego publícala.');
  END IF;
  SELECT COUNT(*) INTO v_cargos FROM Detalle_Solicitud_Cargo WHERE id_solicitud = :NEW.id_solicitud;
  IF v_cargos = 0 THEN
    RAISE_APPLICATION_ERROR(-20004, 'Agrega al menos un cargo antes de publicar la solicitud.');
  END IF;
  SELECT COUNT(*) INTO v_sin_requisito
    FROM Detalle_Solicitud_Cargo d
   WHERE d.id_solicitud = :NEW.id_solicitud
     AND NOT EXISTS (SELECT 1 FROM Requisito_Cargo r WHERE r.id_detalle = d.id_detalle);
  IF v_sin_requisito > 0 THEN
    RAISE_APPLICATION_ERROR(-20005, 'Todos los cargos deben tener requisitos antes de publicar.');
  END IF;
  IF :NEW.fecha_publicacion IS NULL THEN
    :NEW.fecha_publicacion := SYSTIMESTAMP;
  END IF;
END;
/

-- Solo se puede postular a ofertas publicadas y vigentes (fecha de cierre no vencida)
CREATE OR REPLACE TRIGGER trg_postulacion_oferta
BEFORE INSERT ON Postulacion
FOR EACH ROW
DECLARE
  v_publicada NUMBER;
  v_cierre    DATE;
BEGIN
  SELECT s.publicada, s.fecha_cierre
    INTO v_publicada, v_cierre
    FROM Detalle_Solicitud_Cargo d
    JOIN Solicitud_Cargo s ON s.id_solicitud = d.id_solicitud
   WHERE d.id_detalle = :NEW.id_detalle;
  IF v_publicada = 0 THEN
    RAISE_APPLICATION_ERROR(-20006, 'La oferta no está publicada.');
  ELSIF v_cierre IS NOT NULL AND TRUNC(v_cierre) < TRUNC(SYSDATE) THEN
    RAISE_APPLICATION_ERROR(-20007, 'La oferta ya cerró su plazo de postulación.');
  END IF;
END;
/

-- =====================================================================================
-- 4. VISTAS
-- =====================================================================================

-- Estado actual de cada postulación (último registro del historial)
CREATE OR REPLACE VIEW vw_estado_actual AS
SELECT id_postulacion, id_estado, nombre_estado, fecha_cambio
  FROM (SELECT h.id_postulacion, h.id_estado, e.nombre_estado, h.fecha_cambio,
               ROW_NUMBER() OVER (PARTITION BY h.id_postulacion
                                  ORDER BY h.fecha_cambio DESC, h.id_historial DESC) AS rn
          FROM Historial_Estado_Postulacion h
          JOIN Estado e ON e.id_estado = h.id_estado)
 WHERE rn = 1;

-- Ofertas visibles en el sitio público
CREATE OR REPLACE VIEW vw_ofertas_publicas AS
SELECT d.id_detalle, s.id_solicitud, s.titulo, s.ubicacion, s.fecha_cierre, s.fecha_publicacion,
       c.nombre_cargo, NVL(d.descripcion, s.descripcion) AS descripcion
  FROM Detalle_Solicitud_Cargo d
  JOIN Solicitud_Cargo s ON s.id_solicitud = d.id_solicitud
  JOIN Cargo c           ON c.id_cargo = d.id_cargo
 WHERE s.publicada = 1
   AND (s.fecha_cierre IS NULL OR TRUNC(s.fecha_cierre) >= TRUNC(SYSDATE));

-- Ficha de postulación: postulante, oferta, estado actual y cantidad de documentos
CREATE OR REPLACE VIEW vw_postulacion_detalle AS
SELECT p.id_postulacion, p.fecha_postulacion,
       ca.id_candidato, ca.nombre || ' ' || ca.apellido AS candidato, ca.email, ca.telefono,
       ca.direccion, ca.origen,
       d.id_detalle, c.nombre_cargo, s.titulo AS solicitud,
       ea.nombre_estado AS estado_actual,
       (SELECT COUNT(*) FROM Documento doc WHERE doc.id_candidato = ca.id_candidato) AS documentos
  FROM Postulacion p
  JOIN Candidato ca                ON ca.id_candidato = p.id_candidato
  JOIN Detalle_Solicitud_Cargo d   ON d.id_detalle    = p.id_detalle
  JOIN Cargo c                     ON c.id_cargo      = d.id_cargo
  JOIN Solicitud_Cargo s           ON s.id_solicitud  = d.id_solicitud
  LEFT JOIN vw_estado_actual ea    ON ea.id_postulacion = p.id_postulacion;

-- Ranking por cargo ofertado: promedio de calificaciones [RF-21]
CREATE OR REPLACE VIEW vw_ranking_cargo AS
SELECT id_detalle, id_postulacion, candidato, calificacion,
       RANK() OVER (PARTITION BY id_detalle ORDER BY calificacion DESC) AS posicion
  FROM (SELECT p.id_detalle, p.id_postulacion, ca.nombre || ' ' || ca.apellido AS candidato,
               ROUND(AVG(ev.calificacion), 2) AS calificacion
          FROM Postulacion p
          JOIN Candidato ca  ON ca.id_candidato = p.id_candidato
          JOIN Entrevista en ON en.id_postulacion = p.id_postulacion
          JOIN Evaluacion ev ON ev.id_entrevista = en.id_entrevista
         WHERE ev.calificacion IS NOT NULL
         GROUP BY p.id_detalle, p.id_postulacion, ca.nombre, ca.apellido);

-- Conteo de postulaciones por estado actual [RF-22]
CREATE OR REPLACE VIEW vw_postulaciones_por_estado AS
SELECT e.id_estado, e.nombre_estado, COUNT(ea.id_postulacion) AS total
  FROM Estado e
  LEFT JOIN vw_estado_actual ea ON ea.id_estado = e.id_estado
 GROUP BY e.id_estado, e.nombre_estado;

-- =====================================================================================
-- 5. PROCEDIMIENTOS ALMACENADOS
-- =====================================================================================

-- Postula a un candidato y deja el estado inicial "Postulado" en el historial
CREATE OR REPLACE PROCEDURE sp_postular (
  p_id_candidato   IN  NUMBER,
  p_id_detalle     IN  NUMBER,
  p_id_postulacion OUT NUMBER
) AS
  v_estado NUMBER;
BEGIN
  SELECT id_estado INTO v_estado FROM Estado WHERE LOWER(nombre_estado) = 'postulado';
  INSERT INTO Postulacion (id_candidato, id_detalle)
  VALUES (p_id_candidato, p_id_detalle)
  RETURNING id_postulacion INTO p_id_postulacion;
  INSERT INTO Historial_Estado_Postulacion (id_postulacion, id_estado)
  VALUES (p_id_postulacion, v_estado);
EXCEPTION
  WHEN DUP_VAL_ON_INDEX THEN
    RAISE_APPLICATION_ERROR(-20008, 'El candidato ya está postulado a este cargo.');
END sp_postular;
/

-- Postulación pública: crea el candidato (o reutiliza el existente por email), guarda su CV y postula
CREATE OR REPLACE PROCEDURE sp_postular_publico (
  p_nombre         IN  VARCHAR2,
  p_apellido       IN  VARCHAR2,
  p_email          IN  VARCHAR2,
  p_telefono       IN  VARCHAR2,
  p_direccion      IN  VARCHAR2,
  p_id_detalle     IN  NUMBER,
  p_nombre_cv      IN  VARCHAR2,
  p_tipo_mime      IN  VARCHAR2,
  p_cv             IN  BLOB,
  p_id_postulacion OUT NUMBER
) AS
  v_candidato NUMBER;
BEGIN
  BEGIN
    SELECT id_candidato INTO v_candidato FROM Candidato WHERE LOWER(email) = LOWER(TRIM(p_email));
  EXCEPTION WHEN NO_DATA_FOUND THEN
    INSERT INTO Candidato (nombre, apellido, telefono, email, direccion, origen)
    VALUES (TRIM(p_nombre), TRIM(p_apellido), p_telefono, TRIM(p_email), p_direccion, 'Postulación web')
    RETURNING id_candidato INTO v_candidato;
  END;
  INSERT INTO Documento (id_candidato, categoria, nombre_archivo, tipo_mime, tamano, contenido)
  VALUES (v_candidato, 'Currículum', p_nombre_cv, p_tipo_mime, DBMS_LOB.GETLENGTH(p_cv), p_cv);
  sp_postular(v_candidato, p_id_detalle, p_id_postulacion);
END sp_postular_publico;
/

-- Cambia el estado de una postulación agregando un registro al historial
CREATE OR REPLACE PROCEDURE sp_cambiar_estado (
  p_id_postulacion IN NUMBER,
  p_id_estado      IN NUMBER
) AS
  v_actual NUMBER;
BEGIN
  SELECT id_estado INTO v_actual FROM vw_estado_actual WHERE id_postulacion = p_id_postulacion;
  IF v_actual = p_id_estado THEN
    RAISE_APPLICATION_ERROR(-20009, 'La postulación ya se encuentra en ese estado.');
  END IF;
  INSERT INTO Historial_Estado_Postulacion (id_postulacion, id_estado)
  VALUES (p_id_postulacion, p_id_estado);
END sp_cambiar_estado;
/

-- Publica o despublica una solicitud (las validaciones las hace trg_solicitud_publicar)
CREATE OR REPLACE PROCEDURE sp_publicar_solicitud (
  p_id_solicitud IN NUMBER,
  p_publicar     IN NUMBER   -- 1 publicar, 0 despublicar
) AS
BEGIN
  UPDATE Solicitud_Cargo
     SET publicada = p_publicar,
         fecha_publicacion = CASE WHEN p_publicar = 1 THEN SYSTIMESTAMP ELSE NULL END
   WHERE id_solicitud = p_id_solicitud;
  IF SQL%ROWCOUNT = 0 THEN
    RAISE_APPLICATION_ERROR(-20010, 'La solicitud no existe.');
  END IF;
END sp_publicar_solicitud;
/

-- =====================================================================================
-- 6. DATOS DE EJEMPLO
-- =====================================================================================

INSERT INTO Rol (nombre_rol) VALUES ('Administrador');
INSERT INTO Rol (nombre_rol) VALUES ('Líder evaluador');
INSERT INTO Rol (nombre_rol) VALUES ('Analista');

INSERT INTO Estado (nombre_estado) VALUES ('Postulado');
INSERT INTO Estado (nombre_estado) VALUES ('En Revisión');
INSERT INTO Estado (nombre_estado) VALUES ('Rechazado');
INSERT INTO Estado (nombre_estado) VALUES ('Aprobado');

INSERT INTO Cargo (nombre_cargo) VALUES ('Ejecutivo/a de Ventas Internacionales');
INSERT INTO Cargo (nombre_cargo) VALUES ('Supervisor/a de Calidad');
INSERT INTO Cargo (nombre_cargo) VALUES ('Analista de Logística y Exportaciones');
INSERT INTO Cargo (nombre_cargo) VALUES ('Jefe/a de Planta de Proceso');

INSERT INTO Empleado (nombre, apellido, telefono, email, direccion, id_rol)
  SELECT 'Andrea', 'Vidal', '+56944444444', 'admin@pisys.test',   'Puerto Montt', id_rol FROM Rol WHERE nombre_rol = 'Administrador';
INSERT INTO Empleado (nombre, apellido, telefono, email, direccion, id_rol)
  SELECT 'Javier', 'Mora',  '+56955555555', 'lider@pisys.test',   'Puerto Montt', id_rol FROM Rol WHERE nombre_rol = 'Líder evaluador';
INSERT INTO Empleado (nombre, apellido, telefono, email, direccion, id_rol)
  SELECT 'Paula',  'Reyes', '+56966666666', 'analista@pisys.test','Puerto Montt', id_rol FROM Rol WHERE nombre_rol = 'Analista';

INSERT INTO Candidato (nombre, apellido, telefono, email, direccion, origen) VALUES ('Valentina', 'Rojas',  '+56911111111', 'valentina.rojas@correo.test', 'Puerto Montt', 'Ingreso interno');
INSERT INTO Candidato (nombre, apellido, telefono, email, direccion, origen) VALUES ('Matías',    'Soto',   '+56922222222', 'matias.soto@correo.test',     'Osorno',       'Ingreso interno');
INSERT INTO Candidato (nombre, apellido, telefono, email, direccion, origen) VALUES ('Camila',    'Núñez',  '+56933333333', 'camila.nunez@correo.test',    'Puerto Varas', 'Ingreso interno');
INSERT INTO Candidato (nombre, apellido, telefono, email, direccion, origen) VALUES ('Felipe',    'Araya',  NULL,           'felipe.araya@correo.test',    NULL,           'Postulación web');

-- Solicitudes: se crean como borrador y se publican al final, cuando ya tienen cargos y requisitos
INSERT INTO Solicitud_Cargo (titulo, descripcion, ubicacion, fecha_cierre, observacion, id_evaluador)
  SELECT 'Equipo Comercial y Exportaciones',
         'Buscamos reforzar el equipo que comercializa salmón fresco y congelado en mercados de Asia, Norteamérica y Europa.',
         'Puerto Montt', TRUNC(SYSDATE) + 30, 'Prioridad alta para el próximo trimestre.', id_empleado
    FROM Empleado WHERE email = 'lider@pisys.test';
INSERT INTO Solicitud_Cargo (titulo, descripcion, ubicacion, fecha_cierre, observacion, id_evaluador)
  SELECT 'Aseguramiento de Calidad',
         'Velamos por la inocuidad y la trazabilidad del salmón que llega a nuestros clientes.',
         'Calbuco', NULL, NULL, id_empleado
    FROM Empleado WHERE email = 'lider@pisys.test';
INSERT INTO Solicitud_Cargo (titulo, descripcion, ubicacion, fecha_cierre, observacion, id_evaluador)
  SELECT 'Jefatura de Planta (borrador)', NULL, 'Puerto Montt', NULL,
         'Pendiente de definir requisitos con gerencia.', id_empleado
    FROM Empleado WHERE email = 'lider@pisys.test';

-- Cargos ofertados
INSERT INTO Detalle_Solicitud_Cargo (id_solicitud, id_cargo, descripcion)
  SELECT s.id_solicitud, c.id_cargo, 'Gestiona la cartera de clientes internacionales y cierra contratos de venta de salmón.'
    FROM Solicitud_Cargo s, Cargo c
   WHERE s.titulo = 'Equipo Comercial y Exportaciones' AND c.nombre_cargo = 'Ejecutivo/a de Ventas Internacionales';
INSERT INTO Detalle_Solicitud_Cargo (id_solicitud, id_cargo, descripcion)
  SELECT s.id_solicitud, c.id_cargo, 'Coordina embarques, documentación de exportación y cadena de frío.'
    FROM Solicitud_Cargo s, Cargo c
   WHERE s.titulo = 'Equipo Comercial y Exportaciones' AND c.nombre_cargo = 'Analista de Logística y Exportaciones';
INSERT INTO Detalle_Solicitud_Cargo (id_solicitud, id_cargo, descripcion)
  SELECT s.id_solicitud, c.id_cargo, 'Verifica los estándares de calidad y la trazabilidad del producto.'
    FROM Solicitud_Cargo s, Cargo c
   WHERE s.titulo = 'Aseguramiento de Calidad' AND c.nombre_cargo = 'Supervisor/a de Calidad';

-- Requisitos (se buscan por nombre de cargo dentro de su solicitud)
INSERT INTO Requisito_Cargo (id_detalle, orden, texto)
  SELECT d.id_detalle, r.orden, r.texto
    FROM Detalle_Solicitud_Cargo d
    JOIN Cargo c ON c.id_cargo = d.id_cargo
    JOIN (SELECT 1 orden, 'Título profesional en Administración, Comercio Internacional o carrera afín' texto FROM dual UNION ALL
          SELECT 2, '2 años de experiencia en ventas o exportaciones' FROM dual UNION ALL
          SELECT 3, 'Inglés intermedio-avanzado' FROM dual UNION ALL
          SELECT 4, 'Disponibilidad para viajar' FROM dual) r ON 1 = 1
   WHERE c.nombre_cargo = 'Ejecutivo/a de Ventas Internacionales';
INSERT INTO Requisito_Cargo (id_detalle, orden, texto)
  SELECT d.id_detalle, r.orden, r.texto
    FROM Detalle_Solicitud_Cargo d
    JOIN Cargo c ON c.id_cargo = d.id_cargo
    JOIN (SELECT 1 orden, 'Experiencia en logística o comercio exterior' texto FROM dual UNION ALL
          SELECT 2, 'Manejo de Excel nivel intermedio' FROM dual UNION ALL
          SELECT 3, 'Conocimiento de documentación aduanera (deseable)' FROM dual) r ON 1 = 1
   WHERE c.nombre_cargo = 'Analista de Logística y Exportaciones';
INSERT INTO Requisito_Cargo (id_detalle, orden, texto)
  SELECT d.id_detalle, r.orden, r.texto
    FROM Detalle_Solicitud_Cargo d
    JOIN Cargo c ON c.id_cargo = d.id_cargo
    JOIN (SELECT 1 orden, 'Técnico o profesional en Alimentos, Acuicultura o carrera afín' texto FROM dual UNION ALL
          SELECT 2, 'Conocimiento de HACCP y Buenas Prácticas de Manufactura' FROM dual UNION ALL
          SELECT 3, 'Disponibilidad para trabajar en turnos' FROM dual) r ON 1 = 1
   WHERE c.nombre_cargo = 'Supervisor/a de Calidad';

-- Publicación (el trigger valida que haya cargos y requisitos)
UPDATE Solicitud_Cargo SET publicada = 1, fecha_publicacion = SYSTIMESTAMP - INTERVAL '7' DAY WHERE titulo = 'Equipo Comercial y Exportaciones';
UPDATE Solicitud_Cargo SET publicada = 1, fecha_publicacion = SYSTIMESTAMP - INTERVAL '3' DAY WHERE titulo = 'Aseguramiento de Calidad';

-- Postulaciones con sus fechas pasadas (se insertan directo para fijar la fecha; el trigger exige oferta publicada)
INSERT INTO Postulacion (id_candidato, id_detalle, fecha_postulacion)
  SELECT ca.id_candidato, d.id_detalle, SYSTIMESTAMP - INTERVAL '10' DAY
    FROM Candidato ca, Detalle_Solicitud_Cargo d JOIN Cargo c ON c.id_cargo = d.id_cargo
   WHERE ca.email = 'valentina.rojas@correo.test' AND c.nombre_cargo = 'Ejecutivo/a de Ventas Internacionales';
INSERT INTO Postulacion (id_candidato, id_detalle, fecha_postulacion)
  SELECT ca.id_candidato, d.id_detalle, SYSTIMESTAMP - INTERVAL '9' DAY
    FROM Candidato ca, Detalle_Solicitud_Cargo d JOIN Cargo c ON c.id_cargo = d.id_cargo
   WHERE ca.email = 'matias.soto@correo.test' AND c.nombre_cargo = 'Ejecutivo/a de Ventas Internacionales';
INSERT INTO Postulacion (id_candidato, id_detalle, fecha_postulacion)
  SELECT ca.id_candidato, d.id_detalle, SYSTIMESTAMP - INTERVAL '5' DAY
    FROM Candidato ca, Detalle_Solicitud_Cargo d JOIN Cargo c ON c.id_cargo = d.id_cargo
   WHERE ca.email = 'camila.nunez@correo.test' AND c.nombre_cargo = 'Supervisor/a de Calidad';

-- Historial de estados
INSERT INTO Historial_Estado_Postulacion (id_postulacion, id_estado, fecha_cambio)
  SELECT p.id_postulacion, e.id_estado, p.fecha_postulacion
    FROM Postulacion p JOIN Candidato ca ON ca.id_candidato = p.id_candidato, Estado e
   WHERE e.nombre_estado = 'Postulado';
INSERT INTO Historial_Estado_Postulacion (id_postulacion, id_estado, fecha_cambio)
  SELECT p.id_postulacion, e.id_estado, SYSTIMESTAMP - INTERVAL '8' DAY
    FROM Postulacion p JOIN Candidato ca ON ca.id_candidato = p.id_candidato, Estado e
   WHERE ca.email = 'valentina.rojas@correo.test' AND e.nombre_estado = 'En Revisión';

-- Entrevistas: una pasada (ya evaluada) y una futura. El trigger de fecha se desactiva solo para cargar la pasada.
ALTER TRIGGER trg_entrevista_fecha DISABLE;
INSERT INTO Entrevista (id_empleado, id_postulacion, fecha_entrevista)
  SELECT emp.id_empleado, p.id_postulacion, TRUNC(SYSDATE) - 3
    FROM Empleado emp, Postulacion p JOIN Candidato ca ON ca.id_candidato = p.id_candidato
   WHERE emp.email = 'analista@pisys.test' AND ca.email = 'valentina.rojas@correo.test';
ALTER TRIGGER trg_entrevista_fecha ENABLE;
INSERT INTO Entrevista (id_empleado, id_postulacion, fecha_entrevista)
  SELECT emp.id_empleado, p.id_postulacion, TRUNC(SYSDATE) + 2
    FROM Empleado emp, Postulacion p JOIN Candidato ca ON ca.id_candidato = p.id_candidato
   WHERE emp.email = 'analista@pisys.test' AND ca.email = 'matias.soto@correo.test';

INSERT INTO Evaluacion (id_entrevista, id_empleado, calificacion, comentarios)
  SELECT en.id_entrevista, en.id_empleado, 86.5, 'Buen dominio comercial y comunicación clara.'
    FROM Entrevista en JOIN Postulacion p ON p.id_postulacion = en.id_postulacion
    JOIN Candidato ca ON ca.id_candidato = p.id_candidato
   WHERE ca.email = 'valentina.rojas@correo.test';

-- Documentos de ejemplo: un PDF mínimo (605 bytes) como CV y como test psicológico
INSERT INTO Documento (id_candidato, categoria, nombre_archivo, tipo_mime, tamano, contenido, fecha_carga)
  SELECT id_candidato, 'Currículum', 'CV_Valentina_Rojas.pdf', 'application/pdf', 605,
         TO_BLOB(HEXTORAW('255044462D312E340A312030206F626A0A3C3C202F54797065202F436174616C6F67202F5061676573203220302052203E3E0A656E646F626A0A322030206F626A0A3C3C202F54797065202F5061676573202F4B696473205B33203020525D202F436F756E742031203E3E0A656E646F626A0A332030206F626A0A3C3C202F54797065202F50616765202F506172656E74203220302052202F4D65646961426F78205B30203020333030203134345D202F436F6E74656E7473203420302052202F5265736F7572636573203C3C202F466F6E74203C3C202F4631203520302052203E3E203E3E203E3E0A656E646F626A0A342030206F626A0A3C3C202F4C656E677468203631203E3E0A73747265616D0A4254202F46312031342054662032302038302054642028446F63756D656E746F2064652064656D6F7374726163696F6E2050495359532920546A2045540A656E6473747265616D0A656E646F626A0A352030206F626A0A3C3C202F54797065202F466F6E74202F53756274797065202F5479706531202F42617365466F6E74202F48656C766574696361203E3E0A656E646F626A0A787265660A3020360A303030303030303030302036353533352066200A30303030303030303039203030303030206E200A30303030303030303538203030303030206E200A30303030303030313135203030303030206E200A30303030303030323431203030303030206E200A30303030303030333532203030303030206E200A747261696C65720A3C3C202F53697A652036202F526F6F74203120302052203E3E0A7374617274787265660A3432320A2525454F460A')), SYSTIMESTAMP - INTERVAL '10' DAY
    FROM Candidato WHERE email = 'valentina.rojas@correo.test';
INSERT INTO Documento (id_evaluacion, categoria, nombre_archivo, tipo_mime, tamano, contenido, fecha_carga)
  SELECT id_evaluacion, 'Test psicológico', 'Test_psicologico_Valentina.pdf', 'application/pdf', 605,
         TO_BLOB(HEXTORAW('255044462D312E340A312030206F626A0A3C3C202F54797065202F436174616C6F67202F5061676573203220302052203E3E0A656E646F626A0A322030206F626A0A3C3C202F54797065202F5061676573202F4B696473205B33203020525D202F436F756E742031203E3E0A656E646F626A0A332030206F626A0A3C3C202F54797065202F50616765202F506172656E74203220302052202F4D65646961426F78205B30203020333030203134345D202F436F6E74656E7473203420302052202F5265736F7572636573203C3C202F466F6E74203C3C202F4631203520302052203E3E203E3E203E3E0A656E646F626A0A342030206F626A0A3C3C202F4C656E677468203631203E3E0A73747265616D0A4254202F46312031342054662032302038302054642028446F63756D656E746F2064652064656D6F7374726163696F6E2050495359532920546A2045540A656E6473747265616D0A656E646F626A0A352030206F626A0A3C3C202F54797065202F466F6E74202F53756274797065202F5479706531202F42617365466F6E74202F48656C766574696361203E3E0A656E646F626A0A787265660A3020360A303030303030303030302036353533352066200A30303030303030303039203030303030206E200A30303030303030303538203030303030206E200A30303030303030313135203030303030206E200A30303030303030323431203030303030206E200A30303030303030333532203030303030206E200A747261696C65720A3C3C202F53697A652036202F526F6F74203120302052203E3E0A7374617274787265660A3432320A2525454F460A')), SYSTIMESTAMP - INTERVAL '3' DAY
    FROM Evaluacion;

COMMIT;

-- =====================================================================================
-- 7. CONSULTAS DE COMPROBACIÓN
-- =====================================================================================
-- SELECT * FROM vw_ofertas_publicas;                 -- 3 ofertas visibles en el sitio público
-- SELECT * FROM vw_postulacion_detalle;              -- postulantes con su estado y documentos
-- SELECT * FROM vw_postulaciones_por_estado;         -- Postulado 2, En Revisión 1, Rechazado 0, Aprobado 0
-- SELECT * FROM vw_ranking_cargo;                    -- Valentina Rojas 86.5 en el cargo de ventas
-- SELECT c.nombre_cargo, r.orden, r.texto
--   FROM Requisito_Cargo r JOIN Detalle_Solicitud_Cargo d ON d.id_detalle = r.id_detalle
--   JOIN Cargo c ON c.id_cargo = d.id_cargo ORDER BY c.nombre_cargo, r.orden;
--
-- Ejemplos de uso de los procedimientos:
-- DECLARE v NUMBER; BEGIN sp_postular(4, 2, v); DBMS_OUTPUT.PUT_LINE('Postulación ' || v); END;
-- BEGIN sp_cambiar_estado(1, 4); END;           -- aprobar la postulación 1
-- BEGIN sp_publicar_solicitud(3, 1); END;       -- falla: la solicitud 3 no tiene cargos
