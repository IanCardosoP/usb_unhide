# usb_unhide — Recuperación y prueba para memorias USB infectadas (FAT/exFAT)
Limpieza de directorio despues de una infección común por malware. Util para restaurar usb drives fat32 y exFat de archivos .lnk y atributos ocultos.

Repositorio con dos scripts para **recuperar archivos ocultos en memorias USB formateadas en FAT/exFAT/msdos** y para **simular la «infección» típica** que hace accesos directos `.lnk` y oculta los originales con atributos Hidden/System.

> Importante: estos scripts **no son un antivirus**. No sustituyen un escaneo con herramientas especializadas (por ejemplo `clamtk`, `clamscan`, `maldet`, etc.). Siempre haz copia de seguridad y revisa manualmente los resultados antes de reutilizar una unidad.

<img width="1180" height="1306" alt="image" src="https://github.com/user-attachments/assets/1961682d-bfd5-4a9e-aae3-a88fe66b5bcb" />

---

## Contenido del repositorio

* `unhide_usb.sh` — Script principal para:

  * Crear backup comprimido de la USB en `~/USB-BACKUPS/<USB_NAME>.tar.gz`.
  * Registrar todo el proceso en `~/USB-BACKUPS/<USB_NAME>.log`.
  * Eliminar accesos directos `.lnk`.
  * Eliminar carpetas de papelera `.Trash*`.
  * Normalizar permisos.
  * Quitar atributos FAT `hidden` y `system` de archivos y directorios.
  * Renombrar objetos cuyo nombre comienza con `.` para quitar el `.` inicial (si corresponde).
  * Limpiar temporales.

* `simulate_infection.sh` — Script para pruebas que:

  * Crea un archivo `.lnk` por cada archivo y directorio (simula accesos directos maliciosos).
  * Aplica `fatattr +h +s` a los originales (oculta y marca como sistema).
  * Renombra los originales para que empiecen con `.` (punto), procesando depth-first para evitar romper la estructura.

---

## Requisitos

* Debian based GNU/Linux Distro
* `bash` (script POSIX)
* `sudo` para ejecutar con privilegios (se recomienda revisar primero)
* `tar` (instalado por defecto en la mayoría de distribuciones)
* `fatattr` (parte de `dosfstools` en muchas distros; el script intenta instalarlo si falta)

Instalación manual (si es necesario):

```bash
sudo apt update
sudo apt install -y tar dosfstools
```

---

## Precauciones y buenas prácticas

1. **Haz backup antes de cualquier cambio**. `unhide_usb.sh` crea una copia `.tar.gz` en `~/USB-BACKUPS/` antes de modificar la unidad.
2. Ejecuta los scripts en una unidad de prueba antes de usar en datos importantes.
3. No ejecutes los scripts en unidades no FAT/NTFS sin adaptaciones.
4. Revisa el log (`~/USB-BACKUPS/<USB_NAME>.log`) antes de sobrescribir o eliminar nada a mano.
5. Los scripts requieren `sudo` para operar sobre metadatos de la unidad montada; el script hace esfuerzos para escribir backups y logs en el home del usuario que ejecutó `sudo` (usa `SUDO_USER`).
6. Utilizar `-d, --dry-run` Para simular operaciones sin hacer cambios `sudo ./usb_unhide.sh -d /punto/de/montaje`
---

## Uso: `unhide_usb.sh`

### Ejecución

```bash
sudo ./unhide_usb.sh /media/usuario/NOMBRE_USB
```

### Flujo operativo

1. Valida el argumento (ruta de montaje).
2. Detecta tipo de sistema de archivos con `findmnt`.
3. Crea `~/USB-BACKUPS/<USB_NAME>.tar.gz`.
4. Guarda registro en `~/USB-BACKUPS/<USB_NAME>.log`.
5. Elimina `*.lnk` encontrados.
6. Lista todos los ficheros y muestra atributos FAT (`fatattr`) antes de modificar.
7. Normaliza permisos.
8. Quita atributos FAT `hidden` y `system` con `fatattr -h -s`.
9. Renombra elementos cuyo nombre empieza con `.` quitando el `.` inicial (si no existe conflicto).
10. Lista nuevamente atributos FAT y genera resumen en el log.
11. Elimina temporales usados por el script.

### Ejemplo de ejecución y archivos generados

* Backup: `/home/tu_usuario/USB-BACKUPS/mi_usb.tar.gz`
* Log: `/home/tu_usuario/USB-BACKUPS/mi_usb.log`

Dentro del log encontrarás secciones del tipo:

```
Listado de todos los archivos y directorios con sus atributos FAT:
--------------------------------------------------------------
hs  a   /media/tu_usuario/mi_usb/.archivo_oculto.txt
    a   /media/tu_usuario/mi_usb/documento.pdf
--------------------------------------------------------------
[OK] Atributos eliminados: /media/tu_usuario/mi_usb/.archivo_oculto.txt
[RENOMBRADO] /media/tu_usuario/mi_usb/.archivo_oculto.txt -> /media/tu_usuario/mi_usb/archivo_oculto.txt
...
=== RESUMEN FINAL ===
Copia de seguridad: /home/tu_usuario/USB-BACKUPS/mi_usb.tar.gz
Archivos .lnk eliminados: 4
Archivos/directorios restaurados: 12
```

---

## Uso: `simulate_infection.sh` (para pruebas)

> Úsalo solo en una copia/USB de prueba. Este script **modifica** nombres y atributos.

### Ejecución

```bash
sudo ./simulate_infection.sh /media/usuario/NOMBRE_USB
```

### Qué hace

* Recorre el árbol y crea `nombre.ext.lnk` por cada archivo y directorio `nombre.ext`.
* Aplica `fatattr +h +s` a los originales.
* Renombra los originales para que comiencen con punto (`.nombre.ext`).
* Procesa renombrado depth-first para evitar romper rutas.

### Ejemplo (antes y después)

Antes:

```
/media/usuario/mi_usb/ejemplo.txt
/media/usuario/mi_usb/docs/manual.pdf
```

Después de la simulación:

```
/media/usuario/mi_usb/ejemplo.txt.lnk
/media/usuario/mi_usb/.ejemplo.txt    (ejemplo.txt marcado +h +s)
...
/media/usuario/mi_usb/docs/manual.pdf.lnk
/media/usuario/mi_usb/docs/.manual.pdf
```

---

## Cómo verificar atributos y listar con atributos

Para listar atributos FAT junto con permisos y ruta, puedes usar este comando:

```bash
sudo find /media/usuario/NOMBRE_USB -print0 | while IFS= read -r -d '' f; do
  attrs=$(sudo fatattr "$f" 2>/dev/null || echo "N/A")
  printf "%-10s " "${attrs:-N/A}"
  ls -ld -- "$f"
done
```

Salida típica:

```
hs        -rw-r--r-- 1 user user 1234 Nov 10 12:00 /media/usuario/mi_usb/.oculto.txt
          drwxr-xr-x 2 user user 4096 Nov 10 12:00 /media/usuario/mi_usb/docs
```

Significado habitual (`fatattr`):

* `h` = hidden
* `s` = system
* `r` = read-only
* `a` = archive

---

## Notas técnicas importantes

* `fatattr` usa sintaxis `+h`, `-h`, `+s`, `-s` para añadir/quitar atributos. Asegúrate de usar minúsculas para añadir/quitar (`+h`, `-h`) en lugar de mayúsculas por error.
* En FAT/exFAT los atributos son metadatos independientes del nombre del archivo. Por tanto un archivo puede estar oculto por atributo H sin que su nombre empiece con `.`.
* En sistemas tipo Unix (ext4, etc.), el nombre que empieza por `.` es lo que comúnmente lo oculta. FAT/exFAT difiere en esto.
* Si ejecutas el script con `sudo`, las referencias a `HOME` dentro del entorno cambian a `/root`. Por ello el script usa `SUDO_USER` y `eval echo "~$SUDO_USER"` para escribir backups y logs en el home del usuario que ejecutó `sudo`.

---

## Reversión manual (comandos útiles)

Si quieres revertir la simulación (eliminar `.lnk`, quitar atributos y des-renombrar), algunos comandos útiles:

1. Quitar atributos `+h +s` de todo recursivamente:

```bash
sudo find /media/usuario/NOMBRE_USB -print0 | while IFS= read -r -d '' f; do
  sudo fatattr -h -s "$f" 2>/dev/null || true
done
```

2. Eliminar todos los `.lnk`:

```bash
sudo find /media/usuario/NOMBRE_USB -type f -iname '*.lnk' -delete
```

3. Renombrar archivos que empiezan con `.` quitando el primer punto (cuidado con conflictos):

```bash
cd /media/usuario/NOMBRE_USB
sudo find . -depth -name '.*' -print0 | while IFS= read -r -d '' f; do
  new="${f#./.}"            # quita './.' -> 'archivo'
  if [ ! -e "$new" ]; then
    sudo mv "$f" "$new"
  else
    echo "Skip: $f -> $new (ya existe)"
  fi
done
```

Nota: testea primero listando lo que haría sin ejecutar `mv` (por ejemplo, reemplaza `sudo mv` por `echo mv`).

---

## Solución de problemas comunes

* **Los atributos `hs` no se quitan**: revisa que en el script use `fatattr -h -s <ruta>` (minúsculas) para quitar atributos. `fatattr -H -S` no quita los atributos.
* **Backups creados en `/root`**: si ejecutas con `sudo` y el script usa `$HOME`, verás `/root`. El repo usa `SUDO_USER` para apuntar al home del usuario invocante.
* **Nombres con espacios**: los scripts usan `find -print0` y `read -r -d ''` para manejar nombres con espacios y caracteres especiales.
* **No hay `fatattr`**: instala `dosfstools` o `fatattr` mediante `sudo apt install dosfstools`.

---

## Seguridad y limitaciones

* Estos scripts manipulan metadatos y nombres en la unidad. Si la unidad está realmente comprometida, **formatearla** y restaurar desde backup limpio suele ser la opción más segura.
* Algunos malwares copian ejecutables fuera de vista; revisar manualmente los ficheros y escanear con un antivirus es obligatorio antes de reutilizar la USB en Windows.
* No ejecutar estos scripts sin entender lo que hacen. Prueba siempre en copias.

---

## Ejemplo completo de flujo de prueba

1. Monta la USB en `/media/usuario/avidaDrive`.
2. Simula infección (en la USB de prueba):

```bash
sudo ./simulate_infection.sh /media/usuario/avidaDrive
```

3. Revisa atributos:

```bash
sudo find /media/usuario/avidaDrive -print0 | while IFS= read -r -d '' f; do printf "%-10s " "$(sudo fatattr "$f" 2>/dev/null || echo "N/A")"; ls -ld -- "$f"; done | less -R
```

4. Ejecuta recuperación:

```bash
sudo ./unhide_usb.sh /media/usuario/avidaDrive
```

5. Revisa log y backup en `~/USB-BACKUPS/avidaDrive.log` y `~/USB-BACKUPS/avidaDrive.tar.gz`.

---

