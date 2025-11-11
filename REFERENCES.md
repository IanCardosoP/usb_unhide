# Referencias y documentación

Este archivo recopila enlaces y comandos útiles para trabajar con **ClamAV / ClamTk**, **fatattr / dosfstools** y la familia **FAT / FAT32**. Incluye notas técnicas y ejemplos de uso en sistemas Debian/Ubuntu.

---

## ClamAV (motor antivirus)

* Documentación oficial de ClamAV (manual y guía de uso).

  * [https://docs.clamav.net/](https://docs.clamav.net/)
  * Uso típico (instalación y escaneo):

    ```bash
    sudo apt update
    sudo apt install -y clamav clamav-daemon clamav-freshclam
    sudo freshclam                 # actualizar firmas
    clamscan -r --infected /ruta/a/analizar
    ```

* Guía de uso (opciones comunes):

  * [https://docs.clamav.net/manual/Usage.html](https://docs.clamav.net/manual/Usage.html)

## ClamTk (interfaz gráfica para ClamAV)

* Repositorio y recursos del proyecto ClamTk:

  * [https://github.com/dave-theunsub/clamtk](https://github.com/dave-theunsub/clamtk)

* Ejemplo de instalación en Debian/Ubuntu:

  ```bash
  sudo apt update
  sudo apt install -y clamtk
  ```

* Notas: ClamTk es un frontend; las operaciones pesadas las realiza ClamAV (clamscan/clamd). Actualiza firmas con `freshclam` antes de escanear.

---

## fatattr (atributos FAT) y dosfstools

* `fatattr` (manpage): muestra y modifica atributos FAT (hidden, system, readonly, archive).

  * Ejemplo de manpage: [https://manpages.ubuntu.com/manpages/jammy/man1/fatattr.1.html](https://manpages.ubuntu.com/manpages/jammy/man1/fatattr.1.html)

* `dosfstools` (herramientas para sistemas FAT): contiene utilidades como `mkdosfs`, `dosfsck`, y está relacionado con herramientas de gestión FAT.

  * Repositorio: [https://github.com/dosfstools/dosfstools](https://github.com/dosfstools/dosfstools)

* Comandos prácticos `fatattr`:

  ```bash
  sudo fatattr /ruta/al/archivo        # muestra atributos
  sudo fatattr +h +s /ruta/al/archivo  # añade hidden + system
  sudo fatattr -h -s /ruta/al/archivo  # quita hidden + system
  ```

* Notas: usar `fatattr` requiere que la unidad esté montada como FAT/exFAT. En distros Debian/Ubuntu el paquete suele instalarse como parte del ecosistema de utilidades FAT; si no está disponible, instalar `dosfstools`.

---

## FAT / FAT32 (especificación y recursos técnicos)

* Especificación y documentación técnica (recursos históricos y de referencia):

  * Documentación técnica FAT/FAT32 (Microsoft / especificaciones históricas). Buscar "FAT32 specification" o "FAT spec" en el sitio de Microsoft o en archivos de documentación técnica.

* Artículo general (Wikipedia) con resumen técnico y límites:

  * [https://en.wikipedia.org/wiki/File_Allocation_Table](https://en.wikipedia.org/wiki/File_Allocation_Table)

* Notas técnicas importantes:

  * FAT guarda bits de atributo (H, S, R, A) en la entrada del directorio, separados del nombre de archivo. Por eso es posible que un archivo esté oculto por atributos sin que su nombre empiece por `.`.
  * FAT32 tiene limitaciones históricas en tamaños y en registros de directorio; para unidades modernas se usa exFAT cuando se necesita superar el límite de 4 GiB por archivo.

---

## NTFS (nota rápida)

* En NTFS los atributos de Windows se almacenan en metadatos que pueden exponerse en Linux vía `ntfs-3g` y atributos extendidos (`system.ntfs_attrib_be`). Para ver/ajustar en Linux se usan `getfattr`/`setfattr` o herramientas `ntfs-3g`.

* Recursos:

  * `ntfs-3g` proyecto y documentación: [https://www.tuxera.com/community/ntfs-3g/](https://www.tuxera.com/community/ntfs-3g/)

---

## Comandos útiles compendiados

* Listado con atributos FAT y `ls -ld` (recursivo seguro con nombres especiales):

  ```bash
  sudo find /mnt/usb -print0 | while IFS= read -r -d '' f; do
    attrs=$(sudo fatattr "$f" 2>/dev/null || echo "N/A")
    printf "%-10s " "${attrs:-N/A}"
    ls -ld -- "$f"
  done
  ```

* Aplicar y quitar atributos a un conjunto:

  ```bash
  sudo find /mnt/usb -type f -print0 | xargs -0 -I{} sudo fatattr +h +s "{}"
  sudo find /mnt/usb -type f -print0 | xargs -0 -I{} sudo fatattr -h -s "{}"
  ```

* Escaneo básico con ClamAV y guardar salida en log:

  ```bash
  sudo clamscan -r --infected --log=/home/usuario/clamav_scan.log /mnt/usb
  ```

---

## Recursos adicionales y lecturas recomendadas

* ClamAV docs: [https://docs.clamav.net/](https://docs.clamav.net/)
* ClamTk (proyecto): [https://github.com/dave-theunsub/clamtk](https://github.com/dave-theunsub/clamtk)
* fatattr manpage: [https://manpages.ubuntu.com/manpages/jammy/man1/fatattr.1.html](https://manpages.ubuntu.com/manpages/jammy/man1/fatattr.1.html)
* dosfstools repo: [https://github.com/dosfstools/dosfstools](https://github.com/dosfstools/dosfstools)
* FAT / FAT32 overview (Wikipedia): [https://en.wikipedia.org/wiki/File_Allocation_Table](https://en.wikipedia.org/wiki/File_Allocation_Table)
* ntfs-3g: [https://www.tuxera.com/community/ntfs-3g/](https://www.tuxera.com/community/ntfs-3g/)

---

