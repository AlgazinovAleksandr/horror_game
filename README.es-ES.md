

# Vamos a codear un videojuego

Un juego de terror atmosférico en primera persona y 3D desarrollado en Godot 4. Eres el **Sujeto 47**. Esto es un experimento psicológico. Mantén la calma.

## Premisa

Despiertas en una habitación oscura. Una nota sobre la mesa te indica que eres parte de un experimento y que la entidad que podrías encontrar es un producto de tu propia mente. Seis niveles se interponen entre tú y la verdad. Toca las cosas equivocadas y el experimento terminará mal.

## Pilar de diseño: una irrealidad que escala

**El juego comienza con algo ordinario y humano, y se aleja de la realidad cuanto más avanzado esté el jugador.** Cada nivel debe ser más extraño y aterrador que el anterior: una habitación iluminada con una mesa y una vela → un laboratorio institucional → una casa → un pasillo de hotel → un espacio imposible → un sueño → geometría fracturada → un bucle que te devuelve al inicio. Los lugares, las reglas y los propios sentidos del jugador se degradan a lo largo de esa curva.

Esta es una restricción estricta para el nuevo contenido, no una nota de ambiente. Un nivel nuevo debe saber dónde se ubica en la curva y debe ser más extraño que su predecesor. Consulta `SCARY.md` §6 para ver el orden completo (y el único lugar donde la curva está marcada actualmente como rota).

## Jugabilidad

- **Exploración en primera persona** — camina a través de 6 ambientes que escalan en intensidad
- **Objetos detonadores** — ciertos objetos son trampas. Interactúa con ellos (presiona E) o míralos durante 3 segundos seguidos → screamer → el nivel se reinicia
- **Notas trampa (leer para morir)** — las notas trampa se abren como cualquier otra, pero el pánico sube rápidamente mientras la página está abierta y el texto se tiñe de rojo. Si la cierras a tiempo, escapas con los nervios de punta; si la lees hasta el final, el screamer te caza
- **Sistema de pánico** — mirar fijamente cualquier objeto etiquetado como `ScaryObject` llena una barra de pánico. La barra sube ~1,3× más rápido de lo que baja. Al llegar al límite → screamer. Retroalimentación visual: desenfoque + superposición con tinte rojo. Retroalimentación auditiva: latidos cuyo tono y volumen aumentan con el pánico
- **Correr tiene un costo** — Shift hace que corras ×1,6 más rápido, pero alimenta el pánico (~6/s) y bloquea la recuperación. La nota del pasillo te advierte: *Caminá. No corras.* Y es en serio
- **Linterna con batería** — actívate/desactívate con **F**. La carga de cada nivel dura ~4 minutos en estado encendido; la bombilla parpadea como advertencia y luego se apaga para el resto del nivel. Viene encendida por defecto: gestionala o quédala sin luz en los tramos oscuros
- **Sustos programados** (Niveles 2–3) — eventos únicos que disparan el pánico directamente: puertas que se cierran de golpe, pasos arriba, luces que se apagan al entrar a una habitación; la oscuridad hace que el pánico aumente a menos que la linterna esté encendida; la luz de la linterna lo calma 2,5× más rápido; las trampas de oso se disparan, te hacen daño y te frenan; el tramo final del pasillo es una zona de terror donde el pánico apenas disminuye
- **Sustos bruscos sobrevivibles** — algunos sustos parpadean y golpean, pero no matan: acerca tu cara a la ventana de la Casa y un **bosque** iluminado por la luna te ataca (`screamer_forest`); un **Gerente** del hotel te golpea una vez a mitad del pasillo; los **espejos de las esquinas** del pasillo muestran una criatura cuando pasas de largo una esquina. Cada uno dispara el pánico pero te permite recuperarte; solo el llenado completo de la barra es mortal
- **La aparición** (Niveles 1–2) — una figura pálida que se materializa frente a ti en un momento aleatorio. **No te asustes**: sigue caminando y se desvanece; *corre* y se abalanza sobre ti → screamer. El primer encuentro (en el Laboratorio) es sobrevivible para que aprendas la señal antes de que pueda matarte
- **Criaturas acechantes** (Nivel 6 — El Vacío) — figuras altas con ojos rojos que se congelan mientras las miras y avanzan en el instante en que desvías la vista (lógica de Weeping-Angel). Deja que una te alcance y se abalanzará → screamer. Mirarlas también alimenta el pánico, así que no puedes quedarte mirándolas para siempre
- **Notas** — busca y lee notas para recolectar pistas, códigos y tarjetas de acceso necesarias para desbloquear cada puerta de salida
- **Candado combinado** — la salida del Nivel 2 requiere un código de 3 dígitos de las notas de la caja fuerte. Cada intento fallido emite un zumbido y dispara el pánico: forzar el candado al azar es una forma de morir
- **Puertas internivel de KONTUR** (Nivel 5) — las respuestas de este nivel no están dentro de él. Cada una de sus ocho puertas tuvo pistas en niveles anteriores: una nota en el Laboratorio, una tarjeta de prueba de TV en la Casa, una placa de puerta en el Pasillo, un teléfono en los Backrooms. Un jugador que exploró avanza sin problemas; uno que se apresuró estará adivinando, y las malas respuestas aquí cuestan pánico que nunca se drena
- **Puertas traseras** — cada nivel tiene una puerta trasera (resplandor rojo sangre) que te devuelve al nivel anterior. Los objetos recolectados (tarjeta de acceso, código) se reinician al volver a entrar
- **Sin combate** — terror a través del ambiente, el sonido, la iluminación y la contención

## Controles

| Tecla | Acción |
|-------|--------|
| WASD | Moverse |
| Ratón | Mirar |
| Shift | Correr (×1,6 de velocidad — acumula pánico mientras se mantiene presionada) |
| E | Interactuar (notas, puertas, tarjeta de acceso, candado) |
| F | Activar/desactivar linterna (batería: ~4 min por nivel) |
| Esc | Soltar cursor del ratón |

Un mensaje de ayuda que se desvanece con estos controles se muestra en la sala de introducción.

## Niveles

El juego se abre en un **Menú Principal** (`main_menu.tscn`). Presionar START carga la Sala de Introducción.

| Nivel | Entorno | Condición de victoria | Condición de derrota |
|-------|-------------|---------------|----------------|
| Menú Principal | Fondo atmosférico, pantalla de título | Presionar START | — |
| Introducción | Habitación oscura con una vela | Caminar a través de la puerta brillante | — |
| 1 — El Laboratorio | Ala institucional extensa — 10 habitaciones: recepción, salas de examen, archivos, una morgue sellada, una sala de observación con espejo unidireccional | **Restaurar energía** (activar 3 interruptores) para bajar el obturador de la morgue, tomar la tarjeta de acceso custodiada de la morgue oscura y usarla en la puerta de salida | Interactuar o mirar 3 s un objeto detonador; la aparición te ataca si corres; o se llena la barra de pánico |
| 2 — La Casa | Interior doméstico abandonado — 8 habitaciones en planta baja + descenso al sótano (puertas que se cierran de golpe, pasos arriba, un bosque iluminado por la luna detrás de la ventana, estática de TV, una caja de música) | Encontrar la llave del sótano, leer 3 notas seguras (la tercera está abajo en el sótano), ingresar el código de 3 dígitos en el candado | Leer una nota trampa hasta el final; se llena la barra de pánico (sustos, objetos malditos, sótano oscuro, códigos incorrectos) |
| 3 — El Pasillo | Pasillo de hotel encantado de ~320 m (inspirado en *The Corridor*, 2012); el Gerente y los espejos de las esquinas con criaturas te atacan a lo largo del camino | Nunca alcanzar la habitación 217 — el pasillo se queda a oscuras, tu luz muere y atraviesas el suelo hacia los Backrooms | Se llena la barra de pánico (eventos, oscuridad, trampas de oso, espejo/reloj/pinturas malditas, correr, la zona final de terror) |
| 4 — Los Backrooms | Laberinto amarillo liminal en tres zonas — el Vestíbulo (intersecciones en bucle, fluorescentes zumbando, un teléfono de disco que suena, puertas traseras ilusorias, el Sonriente en la oscuridad), la Extensión (una sala de pilares desproporcionada donde el sonido, no la vista, marca la salida real) y la Inundación (una ala inundada hasta los tobillos donde la salida solo se ve con la linterna apagada) | Superar las tres zonas — cada una termina en una pared con glitch que revela el camino a la siguiente | Giro incorrecto/muro incorrecto en el Vestíbulo/Extensión; quedarse quieto demasiado tiempo; iluminar al Sonriente o correr cerca de él; contestar el teléfono hasta el final; o se llena la barra de pánico |
| 5 — KONTUR | Una escalera soviética en decadencia que se esteriliza habitación por habitación hasta convertirse en un ala de contención clínica — ocho puertas, cada una con un verbo diferente (elegir, usar, recordar, abstenerse, ignorar, apagar, esperar, no mirar), cada respuesta escondida en algún nivel anterior | Atravesar las ocho puertas y luego llegar a la salida — permanece sellada hasta que se superen todas las puertas | Tres strikes por respuesta incorrecta, el mimético inmóvil en el pasaje, perder una de las tres puertas sin regreso (la ofrenda, el teléfono, el escolta), o se llena la barra de pánico. La puerta incorrecta en la Puerta 1 no te mata — te devuelve un nivel atrás, a los Backrooms |
| 6 — El Vacío | Geometría fracturada surrealista, pasillos en bucle, criaturas acechantes con ojos rojos, un suelo roto sobre el abismo | Encontrar la nota final, caminar hacia la salida | Una criatura te alcanza; caes al vacío; lees una nota trampa hasta el final; o se llena la barra de pánico |
| Final | Regresa a la sala de introducción — corrupta: vela apagada, latido rojo sangre, la salida tapiada, una nota iluminada | Leer la nota | — |

## Stack

- **Motor:** Godot 4.6 (renderizador Forward+)
- **Lenguaje:** GDScript
- **Herramientas 3D:** Blender → `.glb` → Godot
- **Plataforma:** `.app` nativo de macOS (Apple Silicon M3)

## Ejecutar el juego

1. Abrir Godot 4
2. Importar el proyecto: `File > Open Project` → seleccionar `game/`
3. Presionar **F5** para ejecutar

## Fuentes de activos

- **Texturas:** PolyHaven, AmbientCG (CC0 PBR)
- **Audio:** Freesound.org (CC0), MusicGen de Meta (HuggingFace)
- **Modelos 3D:** Blender, Mixamo (personajes/animaciones gratuitos)
- **Imágenes:** Gemini a través de la habilidad nano-banana-pro

## Documentación del proyecto

| Archivo | Contenido |
|---------|-----------|
| [`GAME_MECHANICS_IDEAS.md`](GAME_MECHANICS_IDEAS.md) | **El backlog de ideas en vivo: comienza aquí para saber "qué debemos construir a continuación".** Estado auditado de desarrollo de cada idea aceptada (con evidencia `file:line`), los defectos en vivo, nuevas ideas con bocetos de implementación, el registro de rechazos y el orden de construcción. Consolida y reemplaza al archivado `drafts/REPORT.md` + `drafts/IDEA_HISTORY.md`. |
| [`SCARY.md`](SCARY.md) | La especificación autorizada de diseño de terror: el diagnóstico, once refactorizaciones con costo (P1–P11), la renovación de la arquitectura de audio, tres niveles nuevos, once antipatrones y una hoja de ruta por fases. |
| [`DUNGEON_NIGHTMARES.md`](DUNGEON_NIGHTMARES.md) | Especificación de diseño completa para un nuevo nivel (THE NIGHTMARE), más un dossier sobre los juegos *Dungeon Nightmares* que adapta. |
| [`COMMENTS.md`](COMMENTS.md) | Retrospectiva del desarrollador: decisiones de diseño, opciones técnicas y observaciones realizadas durante la construcción. Cubre filosofía de terror, arquitectura de niveles, patrones de Godot utilizados y lo que funcionó mejor de lo esperado. Punto de partida para un informe técnico. |
| [`ISSUES_SOLUTIONS.md`](ISSUES_SOLUTIONS.md) | Errores difíciles de diagnosticar con análisis completo de causa raíz. Cada entrada: síntoma → causa raíz → solución → archivos modificados. Cubre el disparo doble de eventos de entrada de Godot, errores comunes con anclajes de UI, casos límite de geometría de raycasting y el problema de Gemini API con JPEG-as-PNG. |
| [`TEXTURES.md`](TEXTURES.md) | Registro de cada textura: nombre de archivo, descripción visual, nivel/nodos a los que aplica y estado de generación (`done` / `to_be_added`). Consulta de referencia antes de cualquier sesión de generación de texturas. |

## Problemas conocidos

**nano-banana-pro genera datos JPEG con extensión `.png`.** Después de generar cualquier imagen, conviértela a un PNG real o Godot fallará silenciosamente al importarla:
```bash
sips -s format png path/to/image.png --out path/to/image.png
```

**Las imágenes de screamer se cargan desde `game/assets/textures/screamers/` al iniciar.** Cualquier archivo `.png` que se coloque en esa carpeta se recopilará automáticamente mediante el escaneo `DirAccess` en `screamer.gd` — no se necesita cambiar código para añadir nuevas variantes de screamer.

**Los archivos de audio nuevos necesitan un paso de importación de Godot.** Si un archivo `.wav`/`.ogg` no tiene un archivo `.import` coincidente en el mismo directorio, Godot no lo cargará. Abre el editor y deja que finalice el escaneo del sistema de archivos (o ejecuta `Godot --headless --path game --import`) después de añadir los activos de audio.

**Los efectos de sonido del Pasillo y la Casa se generan proceduralmente.** `tools/make_sfx.py` (Python puro stdlib) sintetiza `clock_chime.wav`, `glass_shatter.wav`, `beartrap_snap.wav`, `door_slam.wav` y `whispers.wav` en `game/assets/audio/level_3_corridor/`; `tools/make_sfx_house.py` sintetiza `lock_buzz.wav` y `footsteps_above.wav` en `game/assets/audio/level_2_house/`; `tools/make_sfx_backrooms.py` sintetiza los efectos de los Backrooms; y `tools/make_sfx_extra.py` sintetiza los efectos de expansión del Laboratorio/La Casa (`pipe_groan`, `apparition_drone` → `shared/`; `breaker_throw` → `level_1_lab/`; `tv_static`, `music_box`, `water_drip` → `level_2_house/`). Vuelve a ejecutarlo para regenerar; reemplaza cualquier archivo con una grabación de Freesound CC0 para mayor fidelidad.
