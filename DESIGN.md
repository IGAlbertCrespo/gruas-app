# gruas_app — App móvil (Flutter)

App de conductores y jefes de tráfico de Grúas Salvador. Habla con el módulo Odoo
`gruas_mobile_api` por REST, con identidad de dispositivo por keypair P-256.

> **Estado**: primer borrador funcional completo (fase 1: identidad + asistencia + tareas).
> Escrito con cuidado pero **no compilado** aquí (sin SDK Flutter / pub.dev en el entorno).
> Verificación estática hecha: balance de llaves + resolución de imports relativos.

---

## Decisiones de diseño (tomadas de forma autónoma)

| Tema | Decisión | Por qué |
|---|---|---|
| Estado | **Riverpod** | Inyección y test sencillos; providers cacheados evitan ciclos. |
| Navegación raíz | **Gate por fase de sesión** (no go_router) | El estado de la sesión decide la pantalla; menos acoplamiento. |
| HTTP | **Dio** + interceptor | Auto-refresh del token en 401 y reintento transparente. |
| Cripto | **Interfaz `DeviceIdentityService`** + impl `secp256r1` | Aísla el plugin; si su API cambia, se toca 1 fichero. |
| Token | En `flutter_secure_storage`; la **privada NO** (vive en hardware) | La privada nunca sale del Keystore/Secure Enclave. |
| Entornos | **Build flavors** (`main_staging` / `main_production`) | Producción no puede apuntar a staging por error. |
| Multi-cliente | **QR de aprovisionamiento** (`{url, db}`) | Resuelto en el alta; cambiar de cliente = re-emparejar. |
| Offline | **Cola con `offline_uuid`** + `/attendance/sync` | Reaprovecha la idempotencia del backend. |
| Rol jefe | Toggle **Mías/Todas** en tareas; "Todas" = **solo lectura** | Coherente con que el jefe edite desde Odoo web. |

### Sobre la cripto (lo más delicado)
- Curva **P-256 (secp256r1)**, único denominador común con respaldo hardware en iOS+Android.
- Por defecto, plugin `secp256r1` (firma sin fricción → TTL 1h con refresco silencioso).
- Alternativa lista: `biometric_signature` (gating biométrico → subir TTL a una jornada).
  Solo habría que reemplazar `secp256r1_identity_service.dart`.

---

## Mapa de pantallas (el "mock")

```
[Splash] ──► (lee almacenamiento)
   │
   ├─ sin perfil ───────► [Aprovisionar / QR]  ── escanea {url, db} ─┐
   │                                                                  │
   ├─ sin keypair ──────► [Registrar dispositivo] ── genera keypair ─┤
   │                                                                  │
   ├─ no aprobado ──────► [Pendiente de aprobación] ◄────────────────┘
   │                          │ "Ya me han aprobado"
   └─ token OK ─────────► [HOME SHELL]
                              ├── (tab) Asistencia
                              └── (tab) Tareas ──► [Detalle] ──► [Hoja] / [Firma] / [Etapa]
```

**Asistencia** — tarjeta de estado (Sin fichar / Trabajando / En pausa) con horas
trabajadas, pausas y efectivas; botón principal Fichar entrada/salida; pausa con
selector de tipo; bloquea la salida si hay pausa activa; captura geolocalización.

**Tareas (lista)** — tarjetas con etapa (chip), cliente, ruta carga→descarga, fecha,
indicador de firma. El jefe ve un selector **Mías/Todas**.

**Tarea (detalle)** — datos del servicio, direcciones de carga/descarga, hoja de
trabajo; barra inferior con Hoja / Firmar / Etapa (oculta si es lectura del jefe).

**Hoja de trabajo** — horas reales/facturar, albarán, observaciones, switches de
cambio de producto / aplicar mínimo, firmante.

**Firma** — pad de firma + nombre; sube PNG en base64.

**Banda de entorno** — barra naranja "STAGING" visible solo en el flavor de staging.

---

## Pendiente de verificar / completar en tu entorno

1. **Generar las carpetas nativas**: el proyecto trae solo `lib/` y `pubspec.yaml`.
   Ejecutar `flutter create .` en la raíz para generar `android/` e `ios/`, y luego:
   - Configurar **flavors** (`staging`, `production`) con applicationId/bundleId distintos.
   - Permisos: **cámara** (QR), **ubicación** (fichaje). iOS: usage descriptions en Info.plist.
   - Android `minSdkVersion` ≥ 23 (Keystore/biometría).
2. **API del plugin `secp256r1`**: confirmar nombres de método y, sobre todo, que la
   firma se devuelve en **DER** y la pública en **SPKI** (lo que espera el backend).
   Único fichero a tocar: `lib/features/identity/secp256r1_identity_service.dart`.
3. `flutter pub get` + `dart analyze` (no ejecutables aquí) para fijar versiones exactas.
4. Endpoint QR: el contenido esperado del QR es `{"url": "...", "db": "...", "label": "..."}`.

---

## Estructura

```
lib/
  app.dart                      Gate de navegación por fase de sesión
  main_staging.dart / main_production.dart   Entrypoints por flavor
  core/
    env/        environment.dart, connection_profile.dart
    network/    api_client.dart, auth_interceptor.dart, api_exception.dart
    storage/    secure_store.dart
    theme/      app_theme.dart
    providers.dart              Inyección de dependencias (Riverpod)
  features/
    identity/   device_identity_service.dart (+ secp256r1 impl)
    auth/       repository, controller, models, screens/
    attendance/ repository, models, offline_queue, screens/
    tasks/      repository, models, providers, screens/
  shared/widgets/  home_shell.dart, env_banner.dart
```
