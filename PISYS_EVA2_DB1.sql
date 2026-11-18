-- PISYS EVA2 · TODO EN UNO: objetos PL/SQL (01) + demostración con resultados (05)
-- Ejecutar DESPUÉS de pisys_oracle_completo.sql, con el mismo usuario.

-- =====================================================================================
--  PISYS · Evaluación 2 · Objetos PL/SQL (Oracle 12c o superior)
--  Requiere haber ejecutado antes: pisys_oracle_completo.sql  (tablas, vistas y datos)
--
--  Contenido
--    0. Tabla de auditoría
--    1. Funciones almacenadas        (sin parámetros y con parámetros)
--    2. Procedimientos almacenados   (sin parámetros y con parámetros IN / OUT / IN OUT)
--    3. Packages                     (elementos públicos y privados)
--    4. Triggers                     (a nivel de fila y a nivel de sentencia)
--
--  Orden de creación: funciones -> procedimientos -> packages -> triggers
--  (cada grupo usa objetos del anterior; si falla una compilación: SHOW ERRORS)
-- =====================================================================================
SET DEFINE OFF;
SET SERVEROUTPUT ON SIZE UNLIMITED;

-- =====================================================================================
-- 0. AUDITORÍA
-- =====================================================================================
BEGIN
  EXECUTE IMMEDIATE 'DROP TABLE Auditoria_Proceso PURGE';
EXCEPTION WHEN OTHERS THEN
  IF SQLCODE != -942 THEN RAISE; END IF;
END;
/

CREATE TABLE Auditoria_Proceso (
    id_auditoria  NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tabla         VARCHAR2(30)  NOT NULL,
    operacion     VARCHAR2(10)  NOT NULL,                    -- INSERT / UPDATE / DELETE
    nivel         VARCHAR2(10)  NOT NULL,                    -- FILA o SENTENCIA
    usuario       VARCHAR2(128) DEFAULT USER NOT NULL,
    fecha         TIMESTAMP     DEFAULT SYSTIMESTAMP NOT NULL,
    detalle       VARCHAR2(400),
    CONSTRAINT ck_aud_nivel CHECK (nivel IN ('FILA', 'SENTENCIA'))
);

-- =====================================================================================
-- 1. FUNCIONES ALMACENADAS
-- =====================================================================================

-- ---- 1.1 SIN parámetros: cuántos cargos se pueden postular hoy -----------------------
CREATE OR REPLACE FUNCTION fn_total_ofertas_vigentes RETURN NUMBER AS
  v_total NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_total FROM vw_ofertas_publicas;
  RETURN v_total;
END fn_total_ofertas_vigentes;
/

-- ---- 1.2 SIN parámetros: postulaciones que aún están en estado "Postulado" ----------
CREATE OR REPLACE FUNCTION fn_postulaciones_pendientes RETURN NUMBER AS
  v_total NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_total
    FROM vw_estado_actual
   WHERE LOWER(nombre_estado) = 'postulado';
  RETURN v_total;
END fn_postulaciones_pendientes;
/

-- ---- 1.3 CON parámetros: estado actual de una postulación (NULL si no existe) --------
CREATE OR REPLACE FUNCTION fn_estado_actual (p_id_postulacion IN NUMBER) RETURN VARCHAR2 AS
  v_estado VARCHAR2(50);
BEGIN
  SELECT nombre_estado INTO v_estado
    FROM vw_estado_actual
   WHERE id_postulacion = p_id_postulacion;
  RETURN v_estado;
EXCEPTION
  WHEN NO_DATA_FOUND THEN
    RETURN NULL;              -- una consulta SQL que llama a la función no debe "reventar" por una fila
END fn_estado_actual;
/

-- ---- 1.4 CON parámetros: promedio de las evaluaciones de una postulación ---------------
CREATE OR REPLACE FUNCTION fn_promedio_evaluacion (p_id_postulacion IN NUMBER) RETURN NUMBER AS
  v_promedio NUMBER;
BEGIN
  -- AVG sin GROUP BY siempre devuelve una fila (NULL si no hay evaluaciones): no hay NO_DATA_FOUND
  SELECT ROUND(AVG(ev.calificacion), 2) INTO v_promedio
    FROM Entrevista en
    JOIN Evaluacion ev ON ev.id_entrevista = en.id_entrevista
   WHERE en.id_postulacion = p_id_postulacion;
  RETURN v_promedio;
END fn_promedio_evaluacion;
/

-- ---- 1.5 CON parámetros: días que faltan para el cierre (negativo = ya venció) ---------
CREATE OR REPLACE FUNCTION fn_dias_para_cierre (p_id_solicitud IN NUMBER) RETURN NUMBER AS
  v_dias NUMBER;
BEGIN
  SELECT TRUNC(fecha_cierre) - TRUNC(SYSDATE) INTO v_dias
    FROM Solicitud_Cargo
   WHERE id_solicitud = p_id_solicitud;
  RETURN v_dias;              -- NULL si la solicitud no tiene fecha de cierre
EXCEPTION
  WHEN NO_DATA_FOUND THEN
    RETURN NULL;
END fn_dias_para_cierre;
/

-- ---- 1.6 CON parámetros y valor por defecto: ¿la oferta está vigente? (1 / 0) -----------
-- SQL no tiene tipo BOOLEAN, por eso devuelve NUMBER para poder usarse en un WHERE.
CREATE OR REPLACE FUNCTION fn_es_oferta_vigente (
  p_id_detalle IN NUMBER,
  p_fecha      IN DATE DEFAULT SYSDATE
) RETURN NUMBER AS
  v_total NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_total
    FROM Detalle_Solicitud_Cargo d
    JOIN Solicitud_Cargo s ON s.id_solicitud = d.id_solicitud
   WHERE d.id_detalle = p_id_detalle
     AND s.publicada = 1
     AND (s.fecha_cierre IS NULL OR TRUNC(s.fecha_cierre) >= TRUNC(p_fecha));
  RETURN v_total;
END fn_es_oferta_vigente;
/

-- =====================================================================================
-- 2. PROCEDIMIENTOS ALMACENADOS
-- =====================================================================================

-- ---- 2.1 SIN parámetros: resumen del proceso (se llama con EXEC sp_resumen_proceso) ------
CREATE OR REPLACE PROCEDURE sp_resumen_proceso AS
BEGIN
  DBMS_OUTPUT.PUT_LINE('=== Resumen del proceso de reclutamiento ===');
  FOR r IN (SELECT nombre_estado, total FROM vw_postulaciones_por_estado ORDER BY id_estado) LOOP
    DBMS_OUTPUT.PUT_LINE(RPAD(r.nombre_estado, 15) || r.total);
  END LOOP;
  DBMS_OUTPUT.PUT_LINE('Ofertas vigentes (cargos): ' || fn_total_ofertas_vigentes);
  DBMS_OUTPUT.PUT_LINE('Postulaciones pendientes: ' || fn_postulaciones_pendientes);
END sp_resumen_proceso;
/

-- ---- 2.2 SIN parámetros: despublica las solicitudes cuyo plazo ya venció ---------------
-- Pensado para ejecutarse una vez al día (DBMS_SCHEDULER). No hace COMMIT: lo decide quien lo llama.
CREATE OR REPLACE PROCEDURE sp_cerrar_ofertas_vencidas AS
  v_cerradas PLS_INTEGER;
BEGIN
  UPDATE Solicitud_Cargo
     SET publicada = 0,
         fecha_publicacion = NULL
   WHERE publicada = 1
     AND fecha_cierre IS NOT NULL
     AND TRUNC(fecha_cierre) < TRUNC(SYSDATE);
  v_cerradas := SQL%ROWCOUNT;
  DBMS_OUTPUT.PUT_LINE('Solicitudes despublicadas por plazo vencido: ' || v_cerradas);
END sp_cerrar_ofertas_vencidas;
/

-- ---- 2.3 CON parámetros (IN con valor por defecto): programa una entrevista -------------
CREATE OR REPLACE PROCEDURE sp_programar_entrevista (
  p_id_postulacion IN NUMBER,
  p_id_empleado    IN NUMBER,
  p_fecha          IN DATE DEFAULT TRUNC(SYSDATE) + 1
) AS
  v_estado      VARCHAR2(50);
  v_id_revision NUMBER;
BEGIN
  v_estado := fn_estado_actual(p_id_postulacion);
  IF v_estado IS NULL THEN
    RAISE_APPLICATION_ERROR(-20020, 'La postulación no existe.');
  ELSIF v_estado IN ('Aprobado', 'Rechazado') THEN
    RAISE_APPLICATION_ERROR(-20021, 'No se puede entrevistar una postulación en estado ' || v_estado || '.');
  END IF;

  INSERT INTO Entrevista (id_empleado, id_postulacion, fecha_entrevista)
  VALUES (p_id_empleado, p_id_postulacion, TRUNC(p_fecha));

  -- Al agendar la primera entrevista la postulación pasa a "En Revisión"
  IF v_estado = 'Postulado' THEN
    SELECT id_estado INTO v_id_revision FROM Estado WHERE LOWER(nombre_estado) = 'en revisión';
    INSERT INTO Historial_Estado_Postulacion (id_postulacion, id_estado)
    VALUES (p_id_postulacion, v_id_revision);
  END IF;
EXCEPTION
  WHEN DUP_VAL_ON_INDEX THEN   -- uq_entrevista_agenda (mismo entrevistador, mismo día)
    RAISE_APPLICATION_ERROR(-20022, 'El entrevistador ya tiene una entrevista ese día.');
END sp_programar_entrevista;
/

-- ---- 2.4 CON parámetros IN y OUT: registra la evaluación y devuelve su id ----------------
CREATE OR REPLACE PROCEDURE sp_registrar_evaluacion (
  p_id_entrevista IN  NUMBER,
  p_id_empleado   IN  NUMBER,
  p_calificacion  IN  NUMBER,
  p_id_evaluacion OUT NUMBER,
  p_comentarios   IN  VARCHAR2 DEFAULT NULL
) AS
  e_padre_inexistente EXCEPTION;
  PRAGMA EXCEPTION_INIT(e_padre_inexistente, -2291);   -- ORA-02291: clave foránea sin padre
BEGIN
  INSERT INTO Evaluacion (id_entrevista, id_empleado, calificacion, comentarios)
  VALUES (p_id_entrevista, p_id_empleado, p_calificacion, p_comentarios)
  RETURNING id_evaluacion INTO p_id_evaluacion;
EXCEPTION
  WHEN DUP_VAL_ON_INDEX THEN   -- uq_evaluacion_entrevista (relación 1:1)
    RAISE_APPLICATION_ERROR(-20023, 'Esta entrevista ya tiene una evaluación registrada.');
  WHEN e_padre_inexistente THEN
    RAISE_APPLICATION_ERROR(-20026, 'La entrevista o el empleado indicado no existe.');
END sp_registrar_evaluacion;
/

-- ---- 2.5 CON parámetro IN OUT: entra con el texto original y sale normalizado ------------
CREATE OR REPLACE PROCEDURE sp_normalizar_email (p_email IN OUT VARCHAR2) AS
BEGIN
  p_email := LOWER(TRIM(p_email));
  IF p_email IS NULL OR NOT REGEXP_LIKE(p_email, '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$') THEN
    RAISE_APPLICATION_ERROR(-20024, 'El formato del email no es válido.');
  END IF;
END sp_normalizar_email;
/

-- =====================================================================================
-- 3. PACKAGES
-- =====================================================================================

-- ---- 3.1 pkg_reclutamiento: el flujo de postulación y decisión --------------------------
-- La ESPECIFICACIÓN es la parte PÚBLICA: lo único que otros programas pueden usar.
CREATE OR REPLACE PACKAGE pkg_reclutamiento AS
  -- Constantes públicas
  c_estado_inicial         CONSTANT VARCHAR2(50) := 'Postulado';
  c_estado_revision        CONSTANT VARCHAR2(50) := 'En Revisión';
  c_estado_aprobado        CONSTANT VARCHAR2(50) := 'Aprobado';
  c_estado_rechazado       CONSTANT VARCHAR2(50) := 'Rechazado';
  c_nota_minima_aprobacion CONSTANT NUMBER       := 70;

  -- Excepciones públicas (quien llama puede capturarlas por nombre)
  e_oferta_cerrada EXCEPTION;
  PRAGMA EXCEPTION_INIT(e_oferta_cerrada, -20007);
  e_ya_postulado   EXCEPTION;
  PRAGMA EXCEPTION_INIT(e_ya_postulado, -20008);

  -- Procedimientos públicos
  PROCEDURE postular (
    p_id_candidato   IN  NUMBER,
    p_id_detalle     IN  NUMBER,
    p_id_postulacion OUT NUMBER
  );

  PROCEDURE postular_publico (
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
  );

  PROCEDURE cambiar_estado (p_id_postulacion IN NUMBER, p_nombre_estado IN VARCHAR2);
  PROCEDURE decidir        (p_id_postulacion IN NUMBER);   -- aprueba o rechaza según el promedio

  -- Funciones públicas (la segunda y la tercera están SOBRECARGADAS: mismo nombre, distintos parámetros)
  FUNCTION postulaciones_en_sesion RETURN PLS_INTEGER;
  FUNCTION promedio (p_id_postulacion IN NUMBER) RETURN NUMBER;
  FUNCTION promedio (p_id_detalle IN NUMBER, p_id_candidato IN NUMBER) RETURN NUMBER;
END pkg_reclutamiento;
/

-- El CUERPO contiene la implementación y los elementos PRIVADOS (no aparecen en la especificación).
CREATE OR REPLACE PACKAGE BODY pkg_reclutamiento AS

  -- ===== ELEMENTOS PRIVADOS (solo visibles dentro del package) =====
  g_postulaciones_sesion PLS_INTEGER := 0;     -- variable privada: vive mientras dura la sesión

  FUNCTION obtener_id_estado (p_nombre IN VARCHAR2) RETURN NUMBER IS
    v_id NUMBER;
  BEGIN
    SELECT id_estado INTO v_id FROM Estado WHERE LOWER(nombre_estado) = LOWER(p_nombre);
    RETURN v_id;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      RAISE_APPLICATION_ERROR(-20030, 'El estado "' || p_nombre || '" no existe en el catálogo.');
  END obtener_id_estado;

  PROCEDURE agregar_historial (p_id_postulacion IN NUMBER, p_nombre_estado IN VARCHAR2) IS
    -- una función PRIVADA no se puede llamar dentro de una sentencia SQL (PLS-00231):
    -- se evalúa antes en PL/SQL y el INSERT usa la variable
    v_id_estado NUMBER := obtener_id_estado(p_nombre_estado);
  BEGIN
    INSERT INTO Historial_Estado_Postulacion (id_postulacion, id_estado)
    VALUES (p_id_postulacion, v_id_estado);
  END agregar_historial;

  FUNCTION oferta_vigente (p_id_detalle IN NUMBER) RETURN BOOLEAN IS
  BEGIN
    RETURN fn_es_oferta_vigente(p_id_detalle) = 1;   -- BOOLEAN solo existe en PL/SQL, por eso es privada
  END oferta_vigente;

  -- ===== IMPLEMENTACIÓN DE LOS ELEMENTOS PÚBLICOS =====
  PROCEDURE postular (
    p_id_candidato   IN  NUMBER,
    p_id_detalle     IN  NUMBER,
    p_id_postulacion OUT NUMBER
  ) IS
  BEGIN
    IF NOT oferta_vigente(p_id_detalle) THEN
      RAISE_APPLICATION_ERROR(-20007, 'La oferta no está disponible o ya cerró su plazo.');
    END IF;

    INSERT INTO Postulacion (id_candidato, id_detalle)
    VALUES (p_id_candidato, p_id_detalle)
    RETURNING id_postulacion INTO p_id_postulacion;

    agregar_historial(p_id_postulacion, c_estado_inicial);
    g_postulaciones_sesion := g_postulaciones_sesion + 1;
  EXCEPTION
    WHEN DUP_VAL_ON_INDEX THEN
      RAISE_APPLICATION_ERROR(-20008, 'El candidato ya está postulado a este cargo.');
  END postular;

  PROCEDURE postular_publico (
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
  ) IS
    v_email     VARCHAR2(100) := p_email;
    v_candidato NUMBER;
  BEGIN
    SAVEPOINT antes_de_postular;                  -- todo o nada: candidato + CV + postulación
    sp_normalizar_email(v_email);

    BEGIN
      SELECT id_candidato INTO v_candidato FROM Candidato WHERE LOWER(email) = v_email;
    EXCEPTION
      WHEN NO_DATA_FOUND THEN
        INSERT INTO Candidato (nombre, apellido, telefono, email, direccion, origen)
        VALUES (TRIM(p_nombre), TRIM(p_apellido), p_telefono, v_email, p_direccion, 'Postulación web')
        RETURNING id_candidato INTO v_candidato;
    END;

    INSERT INTO Documento (id_candidato, categoria, nombre_archivo, tipo_mime, tamano, contenido)
    VALUES (v_candidato, 'Currículum', p_nombre_cv, p_tipo_mime, DBMS_LOB.GETLENGTH(p_cv), p_cv);

    postular(v_candidato, p_id_detalle, p_id_postulacion);
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK TO SAVEPOINT antes_de_postular;    -- deshace lo hecho por este procedimiento
      RAISE;                                      -- y vuelve a lanzar el error original
  END postular_publico;

  PROCEDURE cambiar_estado (p_id_postulacion IN NUMBER, p_nombre_estado IN VARCHAR2) IS
    v_actual VARCHAR2(50) := fn_estado_actual(p_id_postulacion);
  BEGIN
    IF v_actual IS NULL THEN
      RAISE_APPLICATION_ERROR(-20020, 'La postulación no existe.');
    ELSIF LOWER(v_actual) = LOWER(p_nombre_estado) THEN
      RAISE_APPLICATION_ERROR(-20009, 'La postulación ya se encuentra en ese estado.');
    END IF;
    agregar_historial(p_id_postulacion, p_nombre_estado);
  END cambiar_estado;

  PROCEDURE decidir (p_id_postulacion IN NUMBER) IS
    v_promedio NUMBER := fn_promedio_evaluacion(p_id_postulacion);
  BEGIN
    IF v_promedio IS NULL THEN
      RAISE_APPLICATION_ERROR(-20025, 'La postulación aún no tiene evaluaciones.');
    END IF;
    cambiar_estado(
      p_id_postulacion,
      CASE WHEN v_promedio >= c_nota_minima_aprobacion THEN c_estado_aprobado ELSE c_estado_rechazado END
    );
  END decidir;

  FUNCTION postulaciones_en_sesion RETURN PLS_INTEGER IS
  BEGIN
    RETURN g_postulaciones_sesion;                -- acceso controlado a una variable privada
  END postulaciones_en_sesion;

  FUNCTION promedio (p_id_postulacion IN NUMBER) RETURN NUMBER IS
  BEGIN
    RETURN fn_promedio_evaluacion(p_id_postulacion);
  END promedio;

  FUNCTION promedio (p_id_detalle IN NUMBER, p_id_candidato IN NUMBER) RETURN NUMBER IS
    v_promedio NUMBER;
  BEGIN
    SELECT ROUND(AVG(ev.calificacion), 2) INTO v_promedio
      FROM Postulacion p
      JOIN Entrevista en ON en.id_postulacion = p.id_postulacion
      JOIN Evaluacion ev ON ev.id_entrevista  = en.id_entrevista
     WHERE p.id_detalle = p_id_detalle
       AND p.id_candidato = p_id_candidato;
    RETURN v_promedio;
  END promedio;

END pkg_reclutamiento;
/

-- ---- 3.2 pkg_reportes: consultas y listados para pantalla o API ---------------------------
CREATE OR REPLACE PACKAGE pkg_reportes AS
  PROCEDURE reporte_por_estado;
  PROCEDURE reporte_ranking (p_id_detalle IN NUMBER);
  PROCEDURE reporte_postulante (p_id_postulacion IN NUMBER);
  FUNCTION  ranking (p_id_detalle IN NUMBER) RETURN SYS_REFCURSOR;   -- para que la aplicación lea el resultado
END pkg_reportes;
/

CREATE OR REPLACE PACKAGE BODY pkg_reportes AS

  -- ===== PRIVADOS =====
  c_sangria CONSTANT VARCHAR2(4) := '  ';

  PROCEDURE linea (p_texto IN VARCHAR2) IS
  BEGIN
    DBMS_OUTPUT.PUT_LINE(c_sangria || p_texto);
  END linea;

  -- ===== PÚBLICOS =====
  PROCEDURE reporte_por_estado IS
  BEGIN
    linea('ESTADO          TOTAL');
    FOR r IN (SELECT nombre_estado, total FROM vw_postulaciones_por_estado ORDER BY id_estado) LOOP
      linea(RPAD(r.nombre_estado, 16) || r.total);
    END LOOP;
  END reporte_por_estado;

  PROCEDURE reporte_ranking (p_id_detalle IN NUMBER) IS
    v_filas PLS_INTEGER := 0;
  BEGIN
    linea('RANKING DEL CARGO OFERTADO #' || p_id_detalle);
    FOR r IN (SELECT posicion, candidato, calificacion
                FROM vw_ranking_cargo
               WHERE id_detalle = p_id_detalle
               ORDER BY posicion) LOOP
      linea(r.posicion || '. ' || RPAD(r.candidato, 22) || TO_CHAR(r.calificacion, 'FM990.00'));
      v_filas := v_filas + 1;
    END LOOP;
    IF v_filas = 0 THEN
      linea('(sin evaluaciones todavía)');
    END IF;
  END reporte_ranking;

  PROCEDURE reporte_postulante (p_id_postulacion IN NUMBER) IS
    v vw_postulacion_detalle%ROWTYPE;
  BEGIN
    SELECT * INTO v FROM vw_postulacion_detalle WHERE id_postulacion = p_id_postulacion;
    linea('Candidato  : ' || v.candidato);
    linea('Email      : ' || v.email);
    linea('Cargo      : ' || v.nombre_cargo);
    linea('Estado     : ' || v.estado_actual);
    linea('Promedio   : ' || NVL(TO_CHAR(fn_promedio_evaluacion(p_id_postulacion), 'FM990.00'), 'sin evaluar'));
    linea('Documentos : ' || v.documentos);
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      RAISE_APPLICATION_ERROR(-20020, 'La postulación no existe.');
  END reporte_postulante;

  FUNCTION ranking (p_id_detalle IN NUMBER) RETURN SYS_REFCURSOR IS
    c SYS_REFCURSOR;
  BEGIN
    OPEN c FOR
      SELECT posicion, candidato, calificacion
        FROM vw_ranking_cargo
       WHERE id_detalle = p_id_detalle
       ORDER BY posicion;
    RETURN c;
  END ranking;

END pkg_reportes;
/

-- =====================================================================================
-- 4. TRIGGERS  (el trigger de sentencia de historial y los de fila de entrevista, solicitud y
--               postulación ya están en pisys_oracle_completo.sql)
-- =====================================================================================

-- ---------- NIVEL DE SENTENCIA: se ejecuta UNA vez por instrucción, afecte a 0, 1 o 1000 filas ----------

-- 4.1 Auditoría de Candidato (una línea por cada INSERT / UPDATE / DELETE ejecutado)
CREATE OR REPLACE TRIGGER trg_candidato_aud_stmt
AFTER INSERT OR UPDATE OR DELETE ON Candidato
DECLARE
  v_op VARCHAR2(10);
BEGIN
  v_op := CASE WHEN INSERTING THEN 'INSERT' WHEN UPDATING THEN 'UPDATE' ELSE 'DELETE' END;
  INSERT INTO Auditoria_Proceso (tabla, operacion, nivel, detalle)
  VALUES ('CANDIDATO', v_op, 'SENTENCIA', 'Se ejecutó una sentencia ' || v_op || ' sobre Candidato');
END trg_candidato_aud_stmt;
/

-- 4.2 Auditoría de Evaluacion (misma idea: quién y cuándo tocó las evaluaciones)
CREATE OR REPLACE TRIGGER trg_evaluacion_aud_stmt
AFTER INSERT OR UPDATE OR DELETE ON Evaluacion
DECLARE
  v_op VARCHAR2(10);
BEGIN
  v_op := CASE WHEN INSERTING THEN 'INSERT' WHEN UPDATING THEN 'UPDATE' ELSE 'DELETE' END;
  INSERT INTO Auditoria_Proceso (tabla, operacion, nivel, detalle)
  VALUES ('EVALUACION', v_op, 'SENTENCIA', 'Sentencia ' || v_op || ' sobre Evaluacion');
END trg_evaluacion_aud_stmt;
/

-- ---------- NIVEL DE FILA (FOR EACH ROW): se ejecuta UNA vez por cada fila afectada; usa :OLD y :NEW ----------

-- 4.3 Auditoría fila a fila de Candidato: guarda qué candidato cambió y qué email tenía antes
CREATE OR REPLACE TRIGGER trg_candidato_aud_fila
AFTER INSERT OR UPDATE OR DELETE ON Candidato
FOR EACH ROW
DECLARE
  v_op      VARCHAR2(10);
  v_detalle VARCHAR2(400);
BEGIN
  v_op := CASE WHEN INSERTING THEN 'INSERT' WHEN UPDATING THEN 'UPDATE' ELSE 'DELETE' END;
  v_detalle := 'id_candidato=' || NVL(:NEW.id_candidato, :OLD.id_candidato);
  -- INSERTING / UPDATING / DELETING solo se pueden usar en PL/SQL (no dentro de una sentencia SQL)
  IF UPDATING AND :OLD.email <> :NEW.email THEN
    v_detalle := v_detalle || ' | email: ' || :OLD.email || ' -> ' || :NEW.email;
  END IF;
  INSERT INTO Auditoria_Proceso (tabla, operacion, nivel, detalle)
  VALUES ('CANDIDATO', v_op, 'FILA', v_detalle);
END trg_candidato_aud_fila;
/

-- 4.4 Regla de negocio por fila: una nota baja debe justificarse; además limpia los comentarios
CREATE OR REPLACE TRIGGER trg_evaluacion_nota_fila
BEFORE INSERT OR UPDATE OF calificacion, comentarios ON Evaluacion
FOR EACH ROW
BEGIN
  :NEW.comentarios := TRIM(:NEW.comentarios);
  IF :NEW.calificacion IS NOT NULL AND :NEW.calificacion < 40
     AND (:NEW.comentarios IS NULL OR LENGTH(:NEW.comentarios) < 10) THEN
    RAISE_APPLICATION_ERROR(-20040, 'Una nota inferior a 40 debe justificarse con comentarios (mínimo 10 caracteres).');
  END IF;
END trg_evaluacion_nota_fila;
/

-- 4.5 Consecuencia por fila: si se evalúa a alguien que seguía "Postulado", pasa a "En Revisión"
CREATE OR REPLACE TRIGGER trg_evaluacion_estado_fila
AFTER INSERT ON Evaluacion
FOR EACH ROW
DECLARE
  v_id_post NUMBER;
BEGIN
  SELECT id_postulacion INTO v_id_post FROM Entrevista WHERE id_entrevista = :NEW.id_entrevista;
  IF fn_estado_actual(v_id_post) = 'Postulado' THEN
    INSERT INTO Historial_Estado_Postulacion (id_postulacion, id_estado)
    SELECT v_id_post, id_estado FROM Estado WHERE LOWER(nombre_estado) = 'en revisión';
  END IF;
END trg_evaluacion_estado_fila;
/

-- 4.6 Regla entre tablas por fila: no se adjuntan documentos a evaluaciones de postulaciones ya cerradas
CREATE OR REPLACE TRIGGER trg_documento_validar
BEFORE INSERT ON Documento
FOR EACH ROW
DECLARE
  v_estado VARCHAR2(50);
BEGIN
  IF :NEW.id_evaluacion IS NOT NULL THEN
    SELECT fn_estado_actual(en.id_postulacion) INTO v_estado
      FROM Evaluacion ev
      JOIN Entrevista en ON en.id_entrevista = ev.id_entrevista
     WHERE ev.id_evaluacion = :NEW.id_evaluacion;
    IF v_estado IN ('Aprobado', 'Rechazado') THEN
      RAISE_APPLICATION_ERROR(-20041, 'No se pueden adjuntar documentos: la postulación ya está en estado ' || v_estado || '.');
    END IF;
  END IF;
EXCEPTION
  WHEN NO_DATA_FOUND THEN
    NULL;   -- evaluación inexistente: que lo informe la clave foránea (ORA-02291), no este trigger
END trg_documento_validar;
/

-- =====================================================================================
-- Verificación: todos los objetos deben quedar VALID
-- =====================================================================================
-- SELECT object_type, object_name, status
--   FROM user_objects
--  WHERE object_type IN ('FUNCTION','PROCEDURE','PACKAGE','PACKAGE BODY','TRIGGER')
--  ORDER BY object_type, object_name;
-- SHOW ERRORS


-- =====================================================================================
--  PISYS · EVA2 · Demostración con resultados (DBMS_OUTPUT)
--  Requiere: pisys_oracle_completo.sql  y  01_objetos_plsql.sql  (o el archivo todo-en-uno)
--  Cada bloque imprime su resultado y termina en ROLLBACK, así los datos quedan intactos.
--  En SQL Developer: ejecutar con F5 y abrir Ver > Salida de DBMS (o usar SET SERVEROUTPUT ON).
-- =====================================================================================
SET SERVEROUTPUT ON SIZE UNLIMITED;
SET DEFINE OFF;

-- =====================================================================================
-- 1. PROCEDIMIENTOS ALMACENADOS
-- =====================================================================================

-- 1.A SIN parámetros ------------------------------------------------------------------
BEGIN
  DBMS_OUTPUT.PUT_LINE('##### 1.A PROCEDIMIENTOS SIN PARÁMETROS #####');
  sp_resumen_proceso;                    -- imprime el resumen por estado
  sp_cerrar_ofertas_vencidas;            -- sin ofertas vencidas en los datos originales
  ROLLBACK;
END;
/

-- 1.B CON parámetros: IN, OUT, IN OUT y DEFAULT -----------------------------------------
DECLARE
  v_post_camila NUMBER;
  v_lider       NUMBER;
  v_ent         NUMBER;
  v_eval        NUMBER;
  v_email       VARCHAR2(100) := '   ANA.Perez@Mail.COM  ';
BEGIN
  DBMS_OUTPUT.PUT_LINE('##### 1.B PROCEDIMIENTOS CON PARÁMETROS #####');
  SELECT p.id_postulacion INTO v_post_camila
    FROM Postulacion p JOIN Candidato c ON c.id_candidato = p.id_candidato
   WHERE c.email = 'camila.nunez@correo.test';
  SELECT id_empleado INTO v_lider FROM Empleado WHERE email = 'lider@pisys.test';

  DBMS_OUTPUT.PUT_LINE('Estado antes     : ' || fn_estado_actual(v_post_camila));

  -- parámetros IN con notación por nombre; p_fecha usa su DEFAULT (mañana)
  sp_programar_entrevista(p_id_postulacion => v_post_camila, p_id_empleado => v_lider);
  DBMS_OUTPUT.PUT_LINE('Entrevista agendada. Estado ahora: ' || fn_estado_actual(v_post_camila));

  -- parámetro OUT: el procedimiento devuelve el id de la evaluación creada
  SELECT id_entrevista INTO v_ent FROM Entrevista WHERE id_postulacion = v_post_camila;
  sp_registrar_evaluacion(v_ent, v_lider, 74, v_eval, 'Buen perfil técnico, falta experiencia.');
  DBMS_OUTPUT.PUT_LINE('Evaluación creada con id ' || v_eval || ' (parámetro OUT)');
  DBMS_OUTPUT.PUT_LINE('Promedio de Camila: ' || fn_promedio_evaluacion(v_post_camila));

  -- error controlado: segunda evaluación para la misma entrevista
  BEGIN
    sp_registrar_evaluacion(v_ent, v_lider, 90, v_eval);
  EXCEPTION WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('Error esperado   : ' || SQLERRM);
  END;

  -- parámetro IN OUT: entra con espacios y mayúsculas, sale normalizado
  DBMS_OUTPUT.PUT_LINE('Email antes      : [' || v_email || ']');
  sp_normalizar_email(v_email);
  DBMS_OUTPUT.PUT_LINE('Email después    : [' || v_email || ']  (IN OUT)');
  ROLLBACK;
END;
/

-- =====================================================================================
-- 2. FUNCIONES ALMACENADAS
-- =====================================================================================

-- 2.A SIN parámetros ------------------------------------------------------------------
BEGIN
  DBMS_OUTPUT.PUT_LINE('##### 2.A FUNCIONES SIN PARÁMETROS #####');
  DBMS_OUTPUT.PUT_LINE('Ofertas vigentes       : ' || fn_total_ofertas_vigentes);
  DBMS_OUTPUT.PUT_LINE('Postulaciones pendientes: ' || fn_postulaciones_pendientes);
END;
/

-- 2.B CON parámetros ------------------------------------------------------------------
DECLARE
  v_post_valentina NUMBER;
  v_detalle        NUMBER;
  v_solicitud      NUMBER;
BEGIN
  DBMS_OUTPUT.PUT_LINE('##### 2.B FUNCIONES CON PARÁMETROS #####');
  SELECT p.id_postulacion, p.id_detalle INTO v_post_valentina, v_detalle
    FROM Postulacion p JOIN Candidato c ON c.id_candidato = p.id_candidato
   WHERE c.email = 'valentina.rojas@correo.test';
  SELECT id_solicitud INTO v_solicitud FROM Solicitud_Cargo WHERE titulo = 'Equipo Comercial y Exportaciones';

  DBMS_OUTPUT.PUT_LINE('Estado de la postulación ' || v_post_valentina || ' : ' || fn_estado_actual(v_post_valentina));
  DBMS_OUTPUT.PUT_LINE('Estado de la postulación 999 : ' || NVL(fn_estado_actual(999), '(no existe)'));
  DBMS_OUTPUT.PUT_LINE('Promedio de Valentina        : ' || fn_promedio_evaluacion(v_post_valentina));
  DBMS_OUTPUT.PUT_LINE('Días para el cierre          : ' || fn_dias_para_cierre(v_solicitud));
  DBMS_OUTPUT.PUT_LINE('¿Oferta vigente hoy?         : ' || fn_es_oferta_vigente(v_detalle));
  DBMS_OUTPUT.PUT_LINE('¿Vigente dentro de 60 días?  : ' || fn_es_oferta_vigente(v_detalle, SYSDATE + 60));

  -- las funciones también se usan dentro de un SELECT
  FOR r IN (SELECT id_postulacion, fn_estado_actual(id_postulacion) AS estado,
                   NVL(TO_CHAR(fn_promedio_evaluacion(id_postulacion), 'FM990.00'), 'sin notas') AS promedio
              FROM Postulacion ORDER BY id_postulacion) LOOP
    DBMS_OUTPUT.PUT_LINE('  postulación ' || r.id_postulacion || ' | ' || RPAD(r.estado, 12) || ' | ' || r.promedio);
  END LOOP;
END;
/

-- =====================================================================================
-- 3. PACKAGES: PÚBLICO Y PRIVADO
-- =====================================================================================
DECLARE
  v_detalle  NUMBER;
  v_post     NUMBER;
  v_felipe   NUMBER;
  v_det_cal  NUMBER;
  v_pos      NUMBER;
  v_cand     VARCHAR2(200);
  v_nota     NUMBER;
  v_rc       SYS_REFCURSOR;
  v_dummy    NUMBER;
  v_cid      NUMBER;
BEGIN
  DBMS_OUTPUT.PUT_LINE('##### 3. PACKAGES #####');
  SELECT p.id_postulacion, p.id_detalle, p.id_candidato INTO v_post, v_detalle, v_cid
    FROM Postulacion p JOIN Candidato c ON c.id_candidato = p.id_candidato
   WHERE c.email = 'valentina.rojas@correo.test';

  -- elementos PÚBLICOS: constante, función sobrecargada
  DBMS_OUTPUT.PUT_LINE('Nota mínima de aprobación (constante pública): ' || pkg_reclutamiento.c_nota_minima_aprobacion);
  DBMS_OUTPUT.PUT_LINE('promedio(postulación)            = ' || pkg_reclutamiento.promedio(v_post));
  DBMS_OUTPUT.PUT_LINE('promedio(cargo, candidato) (sobrecarga) = ' ||
                       pkg_reclutamiento.promedio(v_detalle, v_cid));

  -- excepción pública capturada por su nombre
  BEGIN
    pkg_reclutamiento.postular(v_cid, v_detalle, v_dummy);
  EXCEPTION WHEN pkg_reclutamiento.e_ya_postulado THEN
    DBMS_OUTPUT.PUT_LINE('e_ya_postulado capturada: ' || SQLERRM);
  END;

  -- estado privado de sesión: el contador sube con cada postulación y NO se deshace con ROLLBACK
  SELECT id_candidato INTO v_felipe FROM Candidato WHERE email = 'felipe.araya@correo.test';
  SELECT d.id_detalle INTO v_det_cal FROM Detalle_Solicitud_Cargo d JOIN Cargo c ON c.id_cargo = d.id_cargo
   WHERE c.nombre_cargo = 'Supervisor/a de Calidad';
  DBMS_OUTPUT.PUT_LINE('Postulaciones en esta sesión (antes) : ' || pkg_reclutamiento.postulaciones_en_sesion);
  pkg_reclutamiento.postular(v_felipe, v_det_cal, v_pos);
  DBMS_OUTPUT.PUT_LINE('Felipe postuló, postulación ' || v_pos || ', estado: ' || fn_estado_actual(v_pos));
  ROLLBACK;
  DBMS_OUTPUT.PUT_LINE('Postulaciones en esta sesión (después, tras ROLLBACK): ' || pkg_reclutamiento.postulaciones_en_sesion);

  -- elemento PRIVADO: intentar usarlo desde afuera falla
  BEGIN
    EXECUTE IMMEDIATE 'BEGIN IF pkg_reclutamiento.oferta_vigente(1) THEN NULL; END IF; END;';
  EXCEPTION WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('Elemento privado -> ' || REPLACE(SUBSTR(SQLERRM, 1, 160), CHR(10), ' '));
  END;

  -- pkg_reportes: procedimientos públicos que imprimen y una función que devuelve un cursor
  DBMS_OUTPUT.PUT_LINE('--- pkg_reportes.reporte_por_estado');
  pkg_reportes.reporte_por_estado;
  DBMS_OUTPUT.PUT_LINE('--- pkg_reportes.reporte_postulante');
  pkg_reportes.reporte_postulante(v_post);
  DBMS_OUTPUT.PUT_LINE('--- pkg_reportes.reporte_ranking');
  pkg_reportes.reporte_ranking(v_detalle);
  DBMS_OUTPUT.PUT_LINE('--- pkg_reportes.ranking (SYS_REFCURSOR)');
  v_rc := pkg_reportes.ranking(v_detalle);
  LOOP
    FETCH v_rc INTO v_dummy, v_cand, v_nota;
    EXIT WHEN v_rc%NOTFOUND;
    DBMS_OUTPUT.PUT_LINE('  ' || v_dummy || '. ' || v_cand || '  ' || TO_CHAR(v_nota, 'FM990.00'));
  END LOOP;
  CLOSE v_rc;
END;
/

-- =====================================================================================
-- 4. TRIGGERS: FILA Y SENTENCIA
-- =====================================================================================

-- 4.A Fila vs sentencia: un UPDATE sobre todos los candidatos -------------------------------
DECLARE
  v_filas NUMBER;
BEGIN
  DBMS_OUTPUT.PUT_LINE('##### 4.A TRIGGERS DE FILA Y DE SENTENCIA #####');
  DELETE FROM Auditoria_Proceso;
  UPDATE Candidato SET direccion = direccion || ' ';
  v_filas := SQL%ROWCOUNT;
  DBMS_OUTPUT.PUT_LINE('Filas modificadas por el UPDATE: ' || v_filas);
  FOR r IN (SELECT nivel, COUNT(*) AS total FROM Auditoria_Proceso
             WHERE tabla = 'CANDIDATO' GROUP BY nivel ORDER BY nivel) LOOP
    DBMS_OUTPUT.PUT_LINE('  auditoría nivel ' || RPAD(r.nivel, 10) || ': ' || r.total || ' registro(s)');
  END LOOP;
  ROLLBACK;
END;
/

-- 4.B Fila con :OLD y :NEW: auditoría del cambio de email ---------------------------------------
DECLARE
  v_detalle VARCHAR2(400);
BEGIN
  DBMS_OUTPUT.PUT_LINE('##### 4.B TRIGGER DE FILA CON :OLD / :NEW #####');
  DELETE FROM Auditoria_Proceso;
  UPDATE Candidato SET email = 'valentina.r@correo.test' WHERE email = 'valentina.rojas@correo.test';
  SELECT detalle INTO v_detalle FROM Auditoria_Proceso WHERE nivel = 'FILA' AND ROWNUM = 1;
  DBMS_OUTPUT.PUT_LINE('Registro de auditoría: ' || v_detalle);
  ROLLBACK;
END;
/

-- 4.C Fila BEFORE: regla de negocio (nota baja requiere justificación) ------------------------------
DECLARE
  v_ent NUMBER;
BEGIN
  DBMS_OUTPUT.PUT_LINE('##### 4.C TRIGGER BEFORE DE FILA: REGLA DE NEGOCIO #####');
  SELECT en.id_entrevista INTO v_ent
    FROM Entrevista en JOIN Postulacion p ON p.id_postulacion = en.id_postulacion
    JOIN Candidato c ON c.id_candidato = p.id_candidato
   WHERE c.email = 'matias.soto@correo.test';
  BEGIN
    INSERT INTO Evaluacion (id_entrevista, id_empleado, calificacion, comentarios)
    SELECT v_ent, id_empleado, 30, 'mal' FROM Empleado WHERE email = 'analista@pisys.test';
  EXCEPTION WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('Nota 30 con comentario corto -> ' || SQLERRM);
  END;
  INSERT INTO Evaluacion (id_entrevista, id_empleado, calificacion, comentarios)
  SELECT v_ent, id_empleado, 30, '   No supera la prueba técnica.  ' FROM Empleado WHERE email = 'analista@pisys.test';
  DBMS_OUTPUT.PUT_LINE('Nota 30 con comentario válido -> guardada');
  ROLLBACK;
END;
/

-- 4.D Fila AFTER: la primera evaluación cambia el estado a "En Revisión" ---------------------------------
DECLARE
  v_post NUMBER;
  v_ent  NUMBER;
BEGIN
  DBMS_OUTPUT.PUT_LINE('##### 4.D TRIGGER AFTER DE FILA: CAMBIO AUTOMÁTICO DE ESTADO #####');
  SELECT p.id_postulacion, en.id_entrevista INTO v_post, v_ent
    FROM Postulacion p JOIN Candidato c ON c.id_candidato = p.id_candidato
    JOIN Entrevista en ON en.id_postulacion = p.id_postulacion
   WHERE c.email = 'matias.soto@correo.test';
  DBMS_OUTPUT.PUT_LINE('Estado antes de evaluar  : ' || fn_estado_actual(v_post));
  INSERT INTO Evaluacion (id_entrevista, id_empleado, calificacion, comentarios)
  SELECT v_ent, id_empleado, 78, 'Buen desempeño general.' FROM Empleado WHERE email = 'analista@pisys.test';
  DBMS_OUTPUT.PUT_LINE('Estado después de evaluar: ' || fn_estado_actual(v_post));
  ROLLBACK;
END;
/

-- 4.E Fila BEFORE entre tablas: no se adjuntan documentos a una postulación ya aprobada --------------------
DECLARE
  v_post NUMBER;
  v_eval NUMBER;
  v_blob BLOB;
BEGIN
  DBMS_OUTPUT.PUT_LINE('##### 4.E TRIGGER DE FILA ENTRE TABLAS #####');
  SELECT p.id_postulacion, ev.id_evaluacion INTO v_post, v_eval
    FROM Postulacion p JOIN Candidato c ON c.id_candidato = p.id_candidato
    JOIN Entrevista en ON en.id_postulacion = p.id_postulacion
    JOIN Evaluacion ev ON ev.id_entrevista = en.id_entrevista
   WHERE c.email = 'valentina.rojas@correo.test';
  SELECT TO_BLOB(UTL_RAW.CAST_TO_RAW('documento de prueba')) INTO v_blob FROM dual;

  INSERT INTO Documento (id_evaluacion, categoria, nombre_archivo, tipo_mime, tamano, contenido)
  VALUES (v_eval, 'Prueba técnica', 'prueba1.pdf', 'application/pdf', DBMS_LOB.GETLENGTH(v_blob), v_blob);
  DBMS_OUTPUT.PUT_LINE('Postulación en "' || fn_estado_actual(v_post) || '": documento adjuntado');

  pkg_reclutamiento.cambiar_estado(v_post, pkg_reclutamiento.c_estado_aprobado);
  DBMS_OUTPUT.PUT_LINE('Estado cambiado a: ' || fn_estado_actual(v_post));
  BEGIN
    INSERT INTO Documento (id_evaluacion, categoria, nombre_archivo, tipo_mime, tamano, contenido)
    VALUES (v_eval, 'Prueba técnica', 'prueba2.pdf', 'application/pdf', DBMS_LOB.GETLENGTH(v_blob), v_blob);
  EXCEPTION WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('Nuevo documento -> ' || SQLERRM);
  END;
  ROLLBACK;
END;
/

-- =====================================================================================
-- 5. ESTADO FINAL DE LOS OBJETOS
-- =====================================================================================
BEGIN
  DBMS_OUTPUT.PUT_LINE('##### OBJETOS CREADOS #####');
  FOR r IN (SELECT object_type, COUNT(*) AS total,
                   SUM(CASE WHEN status = 'VALID' THEN 1 ELSE 0 END) AS validos
              FROM user_objects
             WHERE object_type IN ('FUNCTION','PROCEDURE','PACKAGE','PACKAGE BODY','TRIGGER')
             GROUP BY object_type ORDER BY object_type) LOOP
    DBMS_OUTPUT.PUT_LINE(RPAD(r.object_type, 14) || r.validos || ' válidos de ' || r.total);
  END LOOP;
END;
/
