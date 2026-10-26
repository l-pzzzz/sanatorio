# SANATORIO

Terror en primera persona (Godot 4.7) · First-person horror game (Godot 4.7)

[Español](#español) · [English](#english)

---

## Español

### Jugar
- **UN JUGADOR**: elige dificultad y juega los 3 niveles.
- **MULTIJUGADOR (red local)**: hasta 4 jugadores en la misma red Wi-Fi/LAN.
  1. Uno elige **MULTIJUGADOR (RED LOCAL) → CREAR PARTIDA** (es el anfitrión; en su PC viven las criaturas).
  2. Los demás eligen **UNIRSE A UNA PARTIDA**: la partida aparece sola en la lista. Si no aparece, escriben la IP que muestra el anfitrión.
  3. El anfitrión elige nivel y dificultad y pulsa **EMPEZAR PARTIDA**.
  - Las llaves, fusibles, hacha, bidones y la pistola son **del equipo**: si uno lo recoge, todos lo tienen. Los dardos, botellas y bengalas son personales.
  - Si te atrapan, pasas a **espectador**; si caen todos, se pierde el nivel. Solo el anfitrión cambia o reinicia el nivel.
  - Puertos: UDP/TCP **24680** (juego) y UDP **24681** (búsqueda de partidas). Si el cortafuegos de Windows pregunta, permite el acceso en redes privadas.

### Micrófono (importante en lugares ruidosos, como una feria)
Las criaturas **te oyen por el micrófono**. En **MICRÓFONO** (menú principal o menú de pausa, tecla ESC):
1. Baja la **sensibilidad** si hay mucho ruido (a menos sensibilidad, hay que hablar más fuerte).
2. Activa el **MODO AMBIENTE RUIDOSO (FERIA)**: exige más margen sobre el ruido de fondo, la voz tiene que durar un instante y un ruido continuo se toma como ambiente.
3. Pulsa **RECALIBRAR** y quédate en silencio unos segundos (3 s en modo ruidoso).
4. Comprueba la barra: si la línea de umbral queda por encima del ruido de la sala y solo la cruzas cuando hablas, está bien.
5. Si el micrófono molesta, desactívalo: las criaturas seguirán oyendo pasos, puertas y objetos.

### Móvil (Android)
- Hay controles táctiles (joystick, botones de acción, saltar, agacharse, linterna...).
- Para exportar: instala las plantillas de exportación y el SDK de Android en Godot, crea el preset **Android** (hay una plantilla en `export/android_preset.cfg`) con los permisos de **micrófono** e **internet**, y exporta el APK.
- La primera vez Android pide permiso de micrófono. Para jugar en red, el móvil y el anfitrión deben estar en la misma Wi-Fi; si la partida no aparece en la lista, escribe la IP.

---

## English

### Playing
- **SINGLE PLAYER**: pick a difficulty and play the 3 levels.
- **MULTIPLAYER (local network)**: up to 4 players on the same Wi-Fi/LAN.
  1. One player picks **MULTIPLAYER (LAN) → HOST GAME** (the host; the creatures run on the host's PC).
  2. The others pick **JOIN A GAME**: the game shows up in the list by itself. If it doesn't, type the IP address the host sees.
  3. The host chooses level and difficulty and presses **START GAME**.
  - Keys, fuses, the axe, fuel canisters and the dart gun are **shared by the team**: when one player picks one up, everyone has it. Darts, bottles and flares are personal.
  - If you get caught you become a **spectator**; if everyone is caught the level is lost. Only the host can change or restart the level.
  - Ports: UDP/TCP **24680** (game) and UDP **24681** (game discovery). If the Windows firewall asks, allow access on private networks.

### Microphone (important in noisy places, like a fair)
The creatures **hear you through the microphone**. Open **MICROPHONE** (main menu or pause menu, ESC key):
1. Lower the **sensitivity** when it is loud (less sensitive = you must speak louder).
2. Turn on **NOISY-ROOM MODE (FAIR)**: it asks for more margin over the background noise, your voice has to last a moment, and a constant noise is treated as ambience.
3. Press **RECALIBRATE** and stay quiet for a few seconds (3 s in noisy mode).
4. Check the bar: the threshold line should sit above the room noise and you should only cross it when you talk.
5. If the microphone is a nuisance, turn it off: creatures still hear footsteps, doors and objects.

### Mobile (Android)
- Touch controls are included (joystick, action, jump, crouch, flashlight...).
- To export: install the export templates and the Android SDK in Godot, create the **Android** preset (a template is in `export/android_preset.cfg`) with the **microphone** and **internet** permissions, and export the APK.
- Android asks for microphone permission the first time. To play online, the phone and the host must be on the same Wi-Fi; if the game doesn't appear in the list, type the IP.
