# PoC — Recuperación de Shizuku vía LADB (sin PC)

**Fecha:** 2026-09-13
**Dispositivo:** Xiaomi Mi 10 (umi) · HyperOS · Android aarch64
**Entorno de ejecución:** Termux en el propio dispositivo + transporte LADB (adbd local)
**Alcance:** PoC mínimo de recuperación de Shizuku. Watchdog: NO implementado (fuera de alcance, por diseño).

---

## OBSERVACIÓN

Estado inicial verificado mecánicamente antes de tocar nada:

| Chequeo | Resultado |
|---|---|
| Transporte ADB (LADB) | `localhost:38639` → estado **device** (sin PC) |
| Identidad del shell adb | `uid=2000(shell) gid=2000(shell)` · `context=u:r:shell:s0` |
| Starter | `/data/local/tmp/shizuku` — 16.680 bytes, ejecutable, propietario `shell` |
| Servidor | `shizuku_server` **UP**, PID **12057**, usuario `shell` |
| rish | `~/bin/rish` + `rish_shizuku.dex` (kit exportado), patrón `rish -c "cmd"` |

Contexto previo: el 2026-09-12 se demostró manualmente el ciclo 5704 → 12057. Al comenzar
este PoC el servidor seguía vivo con el PID 12057 (el de la demostración manual).

## HIPÓTESIS

Si `shizuku_server` muere, un shell UID 2000 alcanzable desde LADB puede relanzarlo
ejecutando el starter nativo `/data/local/tmp/shizuku`, **sin PC, sin root y sin tocar
app_process/CLASSPATH**. El éxito solo es demostrable con evidencia mecánica (proceso
nuevo, PID distinto del anterior, estable en el tiempo) **más** una prueba funcional
post-recuperación vía rish.

## ACCIÓN

1. Crear `~/ladb-shizuku-recovery/` con tres scripts POSIX autónomos:
   - `doctor.sh` — 5 chequeos en cadena: adb client → transporte (serial dinámico,
     nunca hardcodeado) → identidad uid 2000 → starter → estado del server + prueba rish.
     Códigos: `0`=UP, `1`=DOWN/transporte, `2`=DEGRADED (up pero rish bloqueado).
   - `recover.sh` — si el server está DOWN: lanza el starter vía adb (nohup, background),
     espera aparición (N0, ~20 s), estabilidad temporal N1/N2/N3 (mismo PID), criterio de
     cambio de PID (nuevo ≠ OLD) y prueba funcional `rish -c "id"`. Idempotente: si está
     UP, no hace nada.
   - `verify.sh` — server presente + prueba rish. Códigos: `0`=UP+FUNCTIONAL, `1`=DOWN, `2`=UP pero rish bloqueado.
2. Ejecutar `doctor.sh` → server UP → el paso 6 del objetivo ("si está DOWN") no aplicaba.
3. Con aprobación explícita del usuario: **ciclo forzado** para ejercitar la rama DOWN:
   - `rish -c "kill -9 12057"` (kill solo vía rish; adb shell UID 2000 no puede, uid distinto)
   - Confirmación de ausencia por `ps`
   - `recover.sh` → `verify.sh`
4. Registrar evidencia en `~/ladb-shizuku-recovery/evidence.txt` y `oldpid.txt`.

## EVIDENCIA

Transcripciones reales de la misma sesión:

```
== doctor ==
[1/5] adb client ............ OK (/data/data/com.termux/files/usr/bin/adb)
[2/5] LADB transport ........ OK (serial=localhost:38639)
[3/5] shell identity ........ OK (uid=2000 shell)
[4/5] starter binary ........ OK (/data/local/tmp/shizuku)
[5/5] shizuku_server ........ UP (PID 12057, user shell)
      rish functional probe . OK (rish -c id -> uid=2000 shell)
VERDICT: UP — full chain verified                    → exit 0

== kill (ciclo forzado, aprobado) ==
OLD_PID=12057
rish -c "kill -9 12057" → exit 255 (esperado: el transporte rish muere con el server)
ps → CONFIRMED: shizuku_server absent                → DOWN real

== recover ==
shizuku_server .............. DOWN (observed)
starter ..................... present (/data/local/tmp/shizuku)
action ...................... launching starter via adb (backgrounded)
N0 .......................... new PID = 7793
N1 .......................... PID = 7793
N2 .......................... PID = 7793
N3 .......................... PID = 7793
stability ................... OK (same PID at N0..N3)
pid-change .................. OK (12057 -> 7793)
functional (rish -c id) ..... OK (uid=2000(shell) ... context=u:r:shell:s0)
VERDICT: RECOVERY VERIFIED (mechanical + functional)  → exit 0

== verify ==
shizuku_server .............. UP (PID 7793, user shell)
rish functional probe ....... OK (rish -c id -> uid=2000 shell)
VERDICT: UP + FUNCTIONAL                              → exit 0
```

Criterios de recuperación (skill shizuku-rikka v1.1.0) — todos cumplidos:

| Criterio | Estado |
|---|---|
| Serial ADB dinámico detectado (no hardcodeado) | OK |
| Ausencia del server observada mecánicamente | OK (`ps`) |
| Ejecución del starter observada | OK (proceso apareció tras lanzarlo) |
| Nuevo PID ≠ OLD_PID | OK (7793 ≠ 12057) |
| Estabilidad temporal N0/N1/N2/N3 | OK |
| Prueba funcional post-recovery vía rish | OK (`uid=2000(shell)`) |

## CONCLUSIÓN

- **Criterio de éxito CUMPLIDO:** LADB → UID 2000 → starter → `shizuku_server` → verificación exitosa.
- Esta ejecución además **cierra la brecha del watchdog 2026-09-12**: aquel demostró solo la
  recuperación mecánica (`SHIZUKU_FUNCTIONAL_RECOVERY = NOT_TESTED`); aquí la prueba rish
  post-recovery pasó, por lo que queda verificado **mechanical + functional** en una sola sesión.
- **Restricciones respetadas:** no se modificó Buffy; no se instaló ninguna app; no se usó root;
  no se usó PC; no se tocó app_process/CLASSPATH; sin arquitectura innecesaria (3 scripts planos);
  experimento reversible (no se borró ni sobreescribió nada; el ciclo kill/relanzar es el mismo
  que la demostración manual 5704→12057).
- **Watchdog: NO implementado** (paso 9 del objetivo, por diseño).

### Notas de operación (lecciones del PoC)

1. `rish` exige `RISH_APPLICATION_ID` y `MANAGER_APPLICATION_ID` en el entorno; sin ellas
   **aborta sin ejecutar nada** (ocurrió en el primer intento de kill).
2. El `exit 255` de rish tras matar el server **no es un fallo**: es el transporte muriendo
   con el servidor. La verdad de ground es `ps`, no el exit code.
3. `adb shell` (UID 2000) **no puede** matar al server (uid distinto): matar solo vía rish.
4. El puerto de LADB (38639) **puede cambiar** si LADB se reinicia (fallback observado antes:
   37685). Los scripts detectan el serial dinámicamente — nunca hardcodear el endpoint.
5. El patrón del kit rish exportado es siempre `rish -c "cmd"`; sin `-c` el server trata el
   comando como path de script y muere con exit 127 (`RISH: exited with 127`).

### Artefactos

| Archivo | Contenido |
|---|---|
| `~/ladb-shizuku-recovery/doctor.sh` | Chequeo de cadena completa |
| `~/ladb-shizuku-recovery/recover.sh` | Recuperación con criterio mecánico + funcional |
| `~/ladb-shizuku-recovery/verify.sh` | Verificación final |
| `~/ladb-shizuku-recovery/evidence.txt` | Evidencia en texto plano |
| `~/ladb-shizuku-recovery/oldpid.txt` | `OLD_PID=12057` |
| `/sdcard/Download/poc_ladb_shizuku_recovery.md` | Este reporte |
| `/sdcard/Download/poc_ladb_shizuku_recovery.txt` | Versión texto plano |
