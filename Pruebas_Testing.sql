-- =====================================================================================
--  PISYS · EVA2 · Pruebas objeto por objeto
--  Requiere: pisys_oracle_completo.sql y PISYS_EVA2_DB.sql ya ejecutados (mismo usuario).
--  Cómo usar: ejecutar TODO con F5, o seleccionar un bloque y pulsar F5.
--  Cada bloque termina en ROLLBACK: los datos quedan intactos y se puede repetir.
--  Los ids de los datos base (postulación 1-3, solicitud 1-3, empleado 1-3, candidato 1-4)
--  asumen que corriste pisys_oracle_completo.sql sin cargar otros datos antes.
--  "Esperado" = salida calculada leyendo el código (no ejecutada en un Oracle real).
-- =====================================================================================
SET SERVEROUTPUT ON SIZE UNLIMITED;
SET DEFINE OFF;

-- =====================================================================================
-- 0. ¿ESTÁN TODOS LOS OBJETOS Y VÁLIDOS?
-- =====================================================================================
SELECT object_type, COUNT(*) AS total,
       SUM(CASE WHEN status = 'VALID' THEN 1 ELSE 0 END) AS validos
  FROM user_objects
 WHERE object_type IN ('FUNCTION','PROCEDURE','PACKAGE','PACKAGE BODY','TRIGGER')
 GROUP BY object_type ORDER BY object_type;
-- Esperado: FUNCTION 6/6 | PACKAGE 2/2 | PACKAGE BODY 2/2 | PROCEDURE 9/9 | TRIGGER 10/10
-- Si alguno no es VALID:
-- SELECT name, type, line, position, text FROM user_errors ORDER BY name, sequence;

-- =====================================================================================
-- 1. FUNCIONES (se prueban con SELECT ... FROM dual)
-- =====================================================================================
SELECT fn_total_ofertas_vigentes AS ofertas, fn_postulaciones_pendientes AS pendientes FROM dual;
-- Esperado: 3 | 2

SELECT fn_estado_actual(1) AS p1, fn_estado_actual(2) AS p2,
       NVL(fn_estado_actual(999), '(no existe)') AS p999 FROM dual;
-- Esperado: En Revisión | Postulado | (no existe)

SELECT fn_promedio_evaluacion(1) AS valentina, fn_promedio_evaluacion(2) AS matias FROM dual;
-- Esperado: 86,5 | (null)

SELECT fn_dias_para_cierre(1) AS con_plazo, fn_dias_para_cierre(2) AS sin_plazo FROM dual;
-- Esperado: 30 | (null)

SELECT fn_es_oferta_vigente(1) AS hoy, fn_es_oferta_vigente(1, SYSDATE + 60) AS en_60_dias FROM dual;
-- Esperado: 1 | 0

-- Las funciones también sirven dentro de una consulta normal
SELECT id_postulacion, fn_estado_actual(id_postulacion) AS estado,
       fn_promedio_evaluacion(id_postulacion) AS promedio
  FROM Postulacion ORDER BY id_postulacion;
-- Esperado: 1 En Revisión 86,5 | 2 Postulado (null) | 3 Postulado (null)

-- =====================================================================================
-- 2. PROCEDIMIENTOS
-- =====================================================================================

-- 2.1 sp_resumen_proceso (sin parámetros)
BEGIN
  sp_resumen_proceso;
END;
/
-- Esperado: Postulado 2 | En Revisión 1 | Rechazado 0 | Aprobado 0 | Ofertas vigentes 3 | Pendientes 2

-- 2.2 sp_cerrar_ofertas_vencidas (sin parámetros)
BEGIN
  sp_cerrar_ofertas_vencidas;                       -- 0 (nada vencido)
  UPDATE Solicitud_Cargo SET fecha_cierre = TRUNC(SYSDATE) - 1 WHERE id_solicitud = 1;
  sp_cerrar_ofertas_vencidas;                       -- 1 (la solicitud 1 venció)
  DBMS_OUTPUT.PUT_LINE('Ofertas vigentes ahora: ' || fn_total_ofertas_vigentes);   -- 1
  ROLLBACK;
END;
/

-- 2.3 sp_programar_entrevista (IN, con DEFAULT y errores)
BEGIN
  sp_programar_entrevista(3, 2);                    -- Camila con Javier, fecha por defecto = mañana
  DBMS_OUTPUT.PUT_LINE('Estado de Camila: ' || fn_estado_actual(3));               -- En Revisión
  BEGIN sp_programar_entrevista(999, 2);
  EXCEPTION WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('Postulación 999 -> ' || SQLERRM); END;      -- ORA-20020
  BEGIN sp_programar_entrevista(3, 3, TRUNC(SYSDATE) + 2);
  EXCEPTION WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('Choque de agenda -> ' || SQLERRM); END;     -- ORA-20022
  BEGIN sp_programar_entrevista(3, 2, TRUNC(SYSDATE) - 5);
  EXCEPTION WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('Fecha pasada -> ' || SQLERRM); END;         -- ORA-20002 (trigger)
  ROLLBACK;
END;
/

-- 2.4 sp_registrar_evaluacion (IN + OUT)
DECLARE
  v_ent  NUMBER;
  v_eval NUMBER;
BEGIN
  sp_programar_entrevista(3, 2);
  SELECT id_entrevista INTO v_ent FROM Entrevista WHERE id_postulacion = 3;
  sp_registrar_evaluacion(v_ent, 2, 74, v_eval, 'Buen perfil técnico.');
  DBMS_OUTPUT.PUT_LINE('Id de la evaluación (OUT): ' || v_eval);                   -- un número nuevo
  DBMS_OUTPUT.PUT_LINE('Promedio de Camila: ' || fn_promedio_evaluacion(3));       -- 74
  BEGIN sp_registrar_evaluacion(v_ent, 2, 90, v_eval);
  EXCEPTION WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('Segunda evaluación -> ' || SQLERRM); END;   -- ORA-20023
  BEGIN sp_registrar_evaluacion(999999, 2, 80, v_eval);
  EXCEPTION WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('Entrevista inexistente -> ' || SQLERRM); END; -- ORA-20026
  ROLLBACK;
END;
/

-- 2.5 sp_normalizar_email (IN OUT)
DECLARE
  v_email VARCHAR2(100) := '   ANA.Perez@Mail.COM  ';
BEGIN
  sp_normalizar_email(v_email);
  DBMS_OUTPUT.PUT_LINE('Normalizado: [' || v_email || ']');                        -- [ana.perez@mail.com]
  v_email := 'correo-malo';
  BEGIN sp_normalizar_email(v_email);
  EXCEPTION WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('Email inválido -> ' || SQLERRM); END;       -- ORA-20024
END;
/

-- 2.6 sp_postular (script base)
DECLARE
  v_post NUMBER;
BEGIN
  sp_postular(4, 1, v_post);                        -- Felipe postula al cargo 1
  DBMS_OUTPUT.PUT_LINE('Postulación ' || v_post || ' estado: ' || fn_estado_actual(v_post));   -- Postulado
  BEGIN sp_postular(4, 1, v_post);
  EXCEPTION WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('Duplicada -> ' || SQLERRM); END;            -- ORA-20008
  ROLLBACK;
END;
/

-- 2.7 sp_cambiar_estado (script base). Estados: 1 Postulado, 2 En Revisión, 3 Rechazado, 4 Aprobado
BEGIN
  sp_cambiar_estado(1, 4);
  DBMS_OUTPUT.PUT_LINE('Estado de la postulación 1: ' || fn_estado_actual(1));             -- Aprobado
  BEGIN sp_cambiar_estado(1, 4);
  EXCEPTION WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('Mismo estado -> ' || SQLERRM); END;     -- ORA-20009
  ROLLBACK;
END;
/

-- 2.8 sp_publicar_solicitud (script base)
BEGIN
  sp_publicar_solicitud(2, 0);                      -- despublicar Aseguramiento de Calidad
  DBMS_OUTPUT.PUT_LINE('Ofertas vigentes: ' || fn_total_ofertas_vigentes);                 -- 2
  BEGIN sp_publicar_solicitud(3, 1);
  EXCEPTION WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('Sin cargos -> ' || SQLERRM); END;       -- ORA-20004 (trigger)
  BEGIN sp_publicar_solicitud(999, 1);
  EXCEPTION WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('No existe -> ' || SQLERRM); END;        -- ORA-20010
  ROLLBACK;
END;
/

-- 2.9 sp_postular_publico (script base): crea candidato + CV + postulación
DECLARE
  v_post NUMBER;
  v_cv   BLOB;
BEGIN
  SELECT TO_BLOB(UTL_RAW.CAST_TO_RAW('CV de prueba')) INTO v_cv FROM dual;
  sp_postular_publico('Luis', 'Perez', 'luis.perez@mail.com', '+56900000000', 'Puerto Montt',
                      1, 'cv_luis.pdf', 'application/pdf', v_cv, v_post);
  FOR r IN (SELECT origen FROM Candidato WHERE LOWER(email) = 'luis.perez@mail.com') LOOP
    DBMS_OUTPUT.PUT_LINE('Origen del candidato: ' || r.origen);                            -- Postulación web
  END LOOP;
  DBMS_OUTPUT.PUT_LINE('Estado: ' || fn_estado_actual(v_post));                          -- Postulado
  ROLLBACK;
END;
/

-- =====================================================================================
-- 3. PACKAGES
-- =====================================================================================

-- 3.1 pkg_reclutamiento: público (constante, sobrecarga, excepción) y privado
DECLARE
  v_post NUMBER;
BEGIN
  DBMS_OUTPUT.PUT_LINE('Constante pública: ' || pkg_reclutamiento.c_nota_minima_aprobacion);   -- 70
  DBMS_OUTPUT.PUT_LINE('promedio(1)      = ' || pkg_reclutamiento.promedio(1));                -- 86,5
  DBMS_OUTPUT.PUT_LINE('promedio(1, 1)   = ' || pkg_reclutamiento.promedio(1, 1));             -- 86,5 (sobrecarga)

  pkg_reclutamiento.postular(4, 1, v_post);
  DBMS_OUTPUT.PUT_LINE('Contador de sesión: ' || pkg_reclutamiento.postulaciones_en_sesion);   -- sube en 1
  BEGIN pkg_reclutamiento.postular(4, 1, v_post);
  EXCEPTION WHEN pkg_reclutamiento.e_ya_postulado THEN
    DBMS_OUTPUT.PUT_LINE('e_ya_postulado -> ' || SQLERRM); END;                              -- ORA-20008

  pkg_reclutamiento.decidir(1);                     -- promedio 86,5 >= 70
  DBMS_OUTPUT.PUT_LINE('decidir(1) -> ' || fn_estado_actual(1));                           -- Aprobado
  BEGIN pkg_reclutamiento.decidir(2);
  EXCEPTION WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('Sin evaluaciones -> ' || SQLERRM); END;    -- ORA-20025
  BEGIN pkg_reclutamiento.cambiar_estado(2, 'Inexistente');
  EXCEPTION WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('Estado inexistente -> ' || SQLERRM); END;  -- ORA-20030

  ROLLBACK;
  DBMS_OUTPUT.PUT_LINE('Contador tras ROLLBACK: ' || pkg_reclutamiento.postulaciones_en_sesion);  -- NO baja

  -- Elemento PRIVADO: desde afuera no existe
  BEGIN
    EXECUTE IMMEDIATE 'BEGIN IF pkg_reclutamiento.oferta_vigente(1) THEN NULL; END IF; END;';
  EXCEPTION WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('Privado -> ' || REPLACE(SUBSTR(SQLERRM, 1, 150), CHR(10), ' '));  -- PLS-00302
  END;
END;
/

-- 3.2 pkg_reportes: procedimientos públicos + función con SYS_REFCURSOR
BEGIN
  pkg_reportes.reporte_por_estado;
  pkg_reportes.reporte_postulante(1);
  pkg_reportes.reporte_ranking(1);
END;
/
-- Esperado reporte_postulante(1): Valentina Rojas | valentina.rojas@correo.test | Ejecutivo/a de
-- Ventas Internacionales | En Revisión | Promedio 86.50 | Documentos 1

VAR rc REFCURSOR
EXEC :rc := pkg_reportes.ranking(1)
PRINT rc
-- Esperado: 1 | Valentina Rojas | 86,5

-- =====================================================================================
-- 4. TRIGGERS
-- =====================================================================================

-- 4.1 Sentencia vs fila en Candidato (trg_candidato_aud_stmt y trg_candidato_aud_fila)
BEGIN
  DELETE FROM Auditoria_Proceso;
  UPDATE Candidato SET direccion = direccion || ' ';             -- 4 filas, 1 sentencia
  FOR r IN (SELECT nivel, COUNT(*) AS total FROM Auditoria_Proceso
             WHERE tabla = 'CANDIDATO' GROUP BY nivel ORDER BY nivel) LOOP
    DBMS_OUTPUT.PUT_LINE(RPAD(r.nivel, 10) || r.total);
  END LOOP;
  -- Esperado: FILA 4 | SENTENCIA 1
  ROLLBACK;
END;
/

-- 4.2 Fila con :OLD y :NEW (cambio de email)
DECLARE
  v_detalle VARCHAR2(400);
BEGIN
  DELETE FROM Auditoria_Proceso;
  UPDATE Candidato SET email = 'valentina.r@correo.test' WHERE id_candidato = 1;
  SELECT detalle INTO v_detalle FROM Auditoria_Proceso WHERE nivel = 'FILA' AND ROWNUM = 1;
  DBMS_OUTPUT.PUT_LINE(v_detalle);
  -- Esperado: id_candidato=1 | email: valentina.rojas@correo.test -> valentina.r@correo.test
  ROLLBACK;
END;
/

-- 4.3 Triggers de Evaluacion: nota baja (BEFORE fila), cambio de estado (AFTER fila),
--     limpieza de comentarios y auditoría de sentencia
DECLARE
  v_ent NUMBER;
  v_com VARCHAR2(4000);
BEGIN
  DELETE FROM Auditoria_Proceso;
  SELECT id_entrevista INTO v_ent FROM Entrevista WHERE id_postulacion = 2;     -- Matías
  BEGIN
    INSERT INTO Evaluacion (id_entrevista, id_empleado, calificacion, comentarios) VALUES (v_ent, 3, 30, 'mal');
  EXCEPTION WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('Nota 30 + comentario corto -> ' || SQLERRM); END;   -- ORA-20040
  DBMS_OUTPUT.PUT_LINE('Estado antes : ' || fn_estado_actual(2));                -- Postulado
  INSERT INTO Evaluacion (id_entrevista, id_empleado, calificacion, comentarios)
  VALUES (v_ent, 3, 78, '   Buen desempeno general.   ');
  DBMS_OUTPUT.PUT_LINE('Estado después: ' || fn_estado_actual(2));               -- En Revisión
  SELECT comentarios INTO v_com FROM Evaluacion WHERE id_entrevista = v_ent;
  DBMS_OUTPUT.PUT_LINE('Comentario guardado: [' || v_com || ']');                -- sin espacios
  FOR r IN (SELECT tabla, nivel, COUNT(*) AS total FROM Auditoria_Proceso
             WHERE tabla = 'EVALUACION' GROUP BY tabla, nivel) LOOP
    DBMS_OUTPUT.PUT_LINE('Auditoría ' || r.tabla || ' ' || r.nivel || ': ' || r.total);   -- SENTENCIA 1
  END LOOP;
  ROLLBACK;
END;
/

-- 4.4 trg_documento_validar: no se adjuntan documentos si la postulación ya está cerrada
DECLARE
  v_eval NUMBER;
  v_blob BLOB;
BEGIN
  SELECT ev.id_evaluacion INTO v_eval
    FROM Evaluacion ev JOIN Entrevista en ON en.id_entrevista = ev.id_entrevista
   WHERE en.id_postulacion = 1;
  SELECT TO_BLOB(UTL_RAW.CAST_TO_RAW('documento de prueba')) INTO v_blob FROM dual;
  INSERT INTO Documento (id_evaluacion, categoria, nombre_archivo, tipo_mime, tamano, contenido)
  VALUES (v_eval, 'Prueba técnica', 'p1.pdf', 'application/pdf', DBMS_LOB.GETLENGTH(v_blob), v_blob);
  DBMS_OUTPUT.PUT_LINE('En "' || fn_estado_actual(1) || '": documento adjuntado');   -- En Revisión
  pkg_reclutamiento.cambiar_estado(1, 'Aprobado');
  BEGIN
    INSERT INTO Documento (id_evaluacion, categoria, nombre_archivo, tipo_mime, tamano, contenido)
    VALUES (v_eval, 'Prueba técnica', 'p2.pdf', 'application/pdf', DBMS_LOB.GETLENGTH(v_blob), v_blob);
  EXCEPTION WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('Tras aprobar -> ' || SQLERRM); END;   -- ORA-20041
  ROLLBACK;
END;
/

-- 4.5 trg_historial_inmutable (script base)
BEGIN
  BEGIN UPDATE Historial_Estado_Postulacion SET id_estado = 1;
  EXCEPTION WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('UPDATE historial -> ' || SQLERRM); END;     -- ORA-20001
  BEGIN DELETE FROM Historial_Estado_Postulacion;
  EXCEPTION WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('DELETE historial -> ' || SQLERRM); END;     -- ORA-20001
END;
/

-- 4.6 trg_entrevista_fecha (script base)
BEGIN
  INSERT INTO Entrevista (id_empleado, id_postulacion, fecha_entrevista) VALUES (1, 3, TRUNC(SYSDATE) - 1);
EXCEPTION WHEN OTHERS THEN
  DBMS_OUTPUT.PUT_LINE('Entrevista en el pasado -> ' || SQLERRM);                            -- ORA-20002
END;
/

-- 4.7 trg_solicitud_publicar (script base)
BEGIN
  BEGIN UPDATE Solicitud_Cargo SET publicada = 1, fecha_publicacion = SYSTIMESTAMP WHERE id_solicitud = 3;
  EXCEPTION WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('Sin cargos -> ' || SQLERRM); END;           -- ORA-20004
  INSERT INTO Detalle_Solicitud_Cargo (id_solicitud, id_cargo, descripcion)
    SELECT 3, id_cargo, 'prueba' FROM Cargo WHERE nombre_cargo LIKE 'Jefe%';
  BEGIN UPDATE Solicitud_Cargo SET publicada = 1, fecha_publicacion = SYSTIMESTAMP WHERE id_solicitud = 3;
  EXCEPTION WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('Cargo sin requisitos -> ' || SQLERRM); END; -- ORA-20005
  BEGIN
    INSERT INTO Solicitud_Cargo (titulo, id_evaluador, publicada, fecha_publicacion) VALUES ('x', 2, 1, SYSTIMESTAMP);
  EXCEPTION WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('Insert publicada -> ' || SQLERRM); END;     -- ORA-20003
  ROLLBACK;
END;
/

-- 4.8 trg_postulacion_oferta (script base): solo se postula a ofertas publicadas y vigentes
BEGIN
  UPDATE Solicitud_Cargo SET fecha_cierre = TRUNC(SYSDATE) - 1 WHERE id_solicitud = 1;
  BEGIN INSERT INTO Postulacion (id_candidato, id_detalle) VALUES (4, 1);
  EXCEPTION WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('Oferta vencida -> ' || SQLERRM); END;       -- ORA-20007
  UPDATE Solicitud_Cargo SET publicada = 0, fecha_publicacion = NULL WHERE id_solicitud = 1;
  BEGIN INSERT INTO Postulacion (id_candidato, id_detalle) VALUES (4, 1);
  EXCEPTION WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('Oferta no publicada -> ' || SQLERRM); END;  -- ORA-20006
  ROLLBACK;
END;
/

-- =====================================================================================
-- 5. FLUJO INTEGRADO: postulación -> entrevista -> evaluación -> decisión -> reporte
-- =====================================================================================
DECLARE
  v_post NUMBER;
  v_ent  NUMBER;
  v_eval NUMBER;
BEGIN
  pkg_reclutamiento.postular(4, 1, v_post);                       -- Felipe postula
  DBMS_OUTPUT.PUT_LINE('1) Estado: ' || fn_estado_actual(v_post));                -- Postulado
  sp_programar_entrevista(v_post, 2);                             -- entrevista mañana con Javier
  DBMS_OUTPUT.PUT_LINE('2) Estado: ' || fn_estado_actual(v_post));                -- En Revisión
  SELECT id_entrevista INTO v_ent FROM Entrevista WHERE id_postulacion = v_post;
  sp_registrar_evaluacion(v_ent, 2, 90, v_eval, 'Excelente entrevista.');
  DBMS_OUTPUT.PUT_LINE('3) Promedio: ' || fn_promedio_evaluacion(v_post));        -- 90
  pkg_reclutamiento.decidir(v_post);
  DBMS_OUTPUT.PUT_LINE('4) Estado: ' || fn_estado_actual(v_post));                -- Aprobado
  pkg_reportes.reporte_postulante(v_post);
  ROLLBACK;
END;
/