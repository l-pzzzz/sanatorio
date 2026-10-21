extends Node
## Idioma del juego (autoload "Lang"). Español por defecto; inglés opcional.
## Uso: Lang.t("texto en español") devuelve el texto en el idioma activo.
## Si un texto no tiene traducción, se muestra tal cual (en español).
## Para formatos con %d / %s traduce la plantilla y luego formatea:
##     Lang.t("Recogiste: %s") % nombre
## La elección se guarda en user://settings.cfg (sección "game", clave "language").

signal changed

const CONFIG_PATH := "user://settings.cfg"
const LANGS := ["es", "en"]

var code := "es"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var config := ConfigFile.new()
	if config.load(CONFIG_PATH) == OK:
		var saved := str(config.get_value("game", "language", "es"))
		if saved in LANGS:
			code = saved


func is_english() -> bool:
	return code == "en"


func set_language(new_code: String) -> void:
	if new_code not in LANGS or new_code == code:
		return
	code = new_code
	var config := ConfigFile.new()
	config.load(CONFIG_PATH)   # conserva otros ajustes (pantalla completa, etc.)
	config.set_value("game", "language", code)
	config.save(CONFIG_PATH)
	changed.emit()


func toggle() -> void:
	set_language("en" if code == "es" else "es")


func t(text: String) -> String:
	if code == "en" and EN.has(text):
		return str(EN[text])
	return text


const EN := {
	# ------------------------------------------------------------ menú
	"ELIGE LA DIFICULTAD": "CHOOSE DIFFICULTY",
	"FÁCIL": "EASY",
	"MEDIA": "MEDIUM",
	"DIFÍCIL": "HARD",
	"Idioma: Español": "Language: English",
	"El murciélago ve menos, es más lento y se rinde pronto. Más dardos, botellas y bengalas. No te persigue a otros pisos.":
		"The bat sees less, is slower and gives up quickly. More darts, bottles and flares. It won't follow you to other floors.",
	"La experiencia normal. El murciélago te sigue entre pisos tras unos segundos.":
		"The normal experience. The bat follows you between floors after a few seconds.",
	"Ve desde lejos, corre más y no te olvida. Revisa casilleros. El Eco te huele de cerca. Pocos recursos.":
		"Sees from far away, runs faster and doesn't forget you. Checks lockers. The Echo smells you up close. Few resources.",

	# ------------------------------------------------------ objetivos
	"Recoge la linterna de tu habitación": "Pick up the flashlight in your room",
	"Encuentra la llave de la enfermería y abre la puerta": "Find the infirmary key and open the door",
	"Toma el fusible del ascensor (está en la enfermería)": "Take the elevator fuse (it's in the infirmary)",
	"Repara el ascensor del ala este (panel junto a la cabina)": "Repair the east wing elevator (panel next to the cab)",
	"Sube al segundo piso (escalera o ascensor)": "Go up to the second floor (stairs or elevator)",
	"Abre el laboratorio con la llave del 2.º piso": "Open the laboratory with the 2nd floor key",
	"Toma la llave de máquinas y abre esa sala (ala este)": "Take the machine room key and open that room (east wing)",
	"Aturde a la criatura una vez (pistola, trampa o bengala)": "Stun the creature once (dart gun, trap or flare)",
	"Reúne los fusibles": "Gather the fuses",
	"Instala los fusibles en el generador": "Install the fuses in the generator",
	"¡Baja en el ascensor y corre a la puerta principal!": "Take the elevator down and run to the main door!",
	"Recoge la linterna: la tubería quedó a oscuras": "Pick up the flashlight: the pipe is pitch dark",
	"Encuentra la llave del drenaje (oeste) y abre la cámara de filtros (noroeste)": "Find the drain key (west) and open the filter chamber (northwest)",
	"Toma el hacha oxidada de la cámara de filtros": "Take the rusty axe from the filter chamber",
	"RUTA FÁCIL: corta la barrera del túnel de raíces (noreste) con el hacha y escapa": "EASY ROUTE: cut the root tunnel barrier (northeast) with the axe and escape",
	"RUTA DIFÍCIL: corta las raíces del centro, baja por el túnel y destruye el CORAZÓN a hachazos": "HARD ROUTE: cut the roots in the center, go down the tunnel and destroy the HEART with the axe",
	"...consigue 2 bidones de combustible (%d/2)": "...get 2 fuel canisters (%d/2)",
	"...enciende el incinerador y ¡sal por el túnel noreste antes de que el fuego te alcance!": "...light the incinerator and get out through the northeast tunnel before the fire catches you!",
	"Recoge la linterna que se te cayó en la escalera": "Pick up the flashlight you dropped on the stairs",
	"Encuentra la llave de las calderas y abre esa sala (norte)": "Find the boiler key and open that room (north)",
	"Toma el fusible del ascensor (calderas)": "Take the elevator fuse (boiler room)",
	"Repara el ascensor (panel junto a la cabina, al suroeste)": "Repair the elevator (panel next to the cab, southwest)",
	"Sube a las galerías del piso de arriba (escalera este o ascensor)": "Go up to the galleries on the upper floor (east stairs or elevator)",
	"Abre la cámara fría con la llave de las galerías": "Open the cold room with the galleries key",
	"Toma la llave de bombas y abre esa sala (galerías oeste)": "Take the pump key and open that room (west galleries)",
	"Aturde al espécimen una vez (pistola, trampa o botella + trampa)": "Stun the specimen once (dart gun, trap or bottle + trap)",
	"Instala los fusibles en el panel de bombas": "Install the fuses in the pump panel",
	"¡Baja y corre a la compuerta de evacuación!": "Go down and run to the evacuation hatch!",
	"Reúne los %d fusibles (%d/%d)": "Gather the %d fuses (%d/%d)",

	# ------------------------------------------------- intro / HUD / final
	"SANATORIO SANTA MARTA": "SANTA MARTA SANATORIUM",
	"Despiertas en una habitación del ala oeste. No hay energía y algo vuela por los pasillos.\nSolo oye lo que haces: no hables ni camines normal (Ctrl para ir agachado). Si te persigue, escóndete en un casillero. Encuentra la forma de escapar.":
		"You wake up in a room in the west wing. There is no power and something is flying through the halls.\nIt only hears what you do: don't talk or walk normally (Ctrl to crouch). If it chases you, hide in a locker. Find a way to escape.",
	"NIVEL 2: LOS SÓTANOS": "LEVEL 2: THE BASEMENTS",
	"La puerta principal no daba a la calle: bajaba a los sótanos. Algo sin ojos escucha cada paso. Si oyes un chasquido grave, quédate INMÓVIL. Los charcos delatan tus pasos; los casilleros y los tanques sirven de escondite. Esta vez hay dos pisos y herramientas para aturdirlo.":
		"The main door didn't lead to the street: it went down to the basements. Something without eyes listens to every step. If you hear a low click, stay STILL. Puddles give away your steps; lockers and tanks work as hiding places. This time there are two floors and tools to stun it.",
	"[Tab] Mostrar misiones": "[Tab] Show missions",
	"Linterna [F]: %s": "Flashlight [F]: %s",
	"ENCENDIDA": "ON",
	"apagada": "off",
	"¡ESCAPASTE!\nTiempo: %02d:%02d": "YOU ESCAPED!\nTime: %02d:%02d",
	"Enter para continuar": "Press Enter to continue",
	"Enter para volver a empezar": "Press Enter to start over",
	"¡SAL! %02d:%02d": "GET OUT! %02d:%02d",
	"EL MURCIÉLAGO TE ATRAPÓ": "THE BAT CAUGHT YOU",
	"EL MURCIÉLAGO TE DEVORÓ": "THE BAT DEVOURED YOU",
	"EL ECO TE DEVORÓ": "THE ECHO DEVOURED YOU",
	"EL ECO ESCUCHÓ TU RESPIRACIÓN": "THE ECHO HEARD YOU BREATHING",
	"EL FUEGO TE ALCANZÓ": "THE FIRE CAUGHT YOU",
	"La raíz late... las criaturas saben dónde estás.": "The root pulses... the creatures know where you are.",
	"¡Energía restaurada! La alarma las atrae. Ahora decide: ESCAPAR por el conducto del sur, o conseguir 2 bidones y quemarlo todo en el incinerador de la raíz.":
		"Power restored! The alarm draws them in. Now decide: ESCAPE through the south duct, or get 2 canisters and burn it all in the root incinerator.",
	"¡Energía restaurada! Sonó la alarma y la criatura corre hacia allá. ¡Baja y corre a la salida!":
		"Power restored! The alarm went off and the creature is running toward it. Go down and run to the exit!",
	"¡El corazón cae! La raíz se resquebraja y toda la estructura tiembla... Ahora el fuego sí prenderá: lleva 2 bidones al incinerador (centro).":
		"The heart falls! The root cracks and the whole structure trembles... Now the fire will catch: take 2 canisters to the incinerator (center).",
	"¡LA RAÍZ ARDE! El fuego se propaga por todo el nivel. ¡CORRE al túnel del noreste y sal antes de que te alcance!":
		"THE ROOT IS BURNING! The fire is spreading through the whole level. RUN to the northeast tunnel and get out before it catches you!",

	# --------------------------------------------------------- objetos
	"Linterna": "Flashlight",
	"Llave de la enfermería": "Infirmary key",
	"Llave del laboratorio": "Laboratory key",
	"Llave de la sala de máquinas": "Machine room key",
	"Fusible": "Fuse",
	"Llave de la sala de calderas": "Boiler room key",
	"Llave de la cámara fría": "Cold room key",
	"Llave de la sala de bombas": "Pump room key",
	"Pistola de dardos": "Dart gun",
	"Dardos": "Darts",
	"Botella": "Bottle",
	"Bengala": "Flare",
	"Fusible del ascensor": "Elevator fuse",
	"Llave del drenaje": "Drain key",
	"Llave de los filtros": "Filter key",
	"Llave de las válvulas": "Valve key",
	"Bidón de combustible": "Fuel canister",
	"Hacha oxidada": "Rusty axe",
	"[clic izq.]": "[left click]",
	"[E] en las raíces": "[E] on the roots",
	"[E] Recoger: %s": "[E] Pick up: %s",
	"Recogiste: %s": "Picked up: %s",
	"+%d dardos": "+%d darts",
	"Linterna: F para encender o apagar. Cuidado: la luz también te delata.": "Flashlight: F to turn it on or off. Careful: the light also gives you away.",
	"Pistola de dardos: clic izquierdo dispara y ATURDE a la criatura unos segundos. Te dejo %d dardos.": "Dart gun: left click fires and STUNS the creature for a few seconds. I'm leaving you %d darts.",
	"Bidón de combustible (%d). El incinerador de la sala de la raíz necesita 2.": "Fuel canister (%d). The incinerator in the root room needs 2.",
	"Hacha oxidada: corta las raíces gruesas (puerta del túnel o del corazón). [E] sobre ellas.": "Rusty axe: cuts thick roots (tunnel or heart door). [E] on them.",
	"Botella x%d: [G] la lanzas; el ruido distrae a la criatura.": "Bottle x%d: [G] to throw it; the noise distracts the creature.",
	"Bengala: [Q] ciega unos segundos al murciélago que tengas enfrente. El Eco no ve, no le afecta.": "Flare: [Q] blinds the bat in front of you for a few seconds. The Echo can't see, so it's unaffected.",

	# ----------------------------------------------------- herramientas
	"Sin dardos. Busca una caja de dardos.": "Out of darts. Look for a box of darts.",
	"¡Le diste! Está aturdida unos segundos.": "Direct hit! It's stunned for a few seconds.",
	"Ya se está recuperando: no le hace efecto.": "It's already recovering: no effect.",
	"¡La luz lo cegó!": "The light blinded it!",
	"La bengala ilumina... pero no había nada que cegar.": "The flare lights up the area... but there was nothing to blind.",

	# ---------------------------------------------------- interacciones
	"[E] Salir del escondite   (no hagas ruido)": "[E] Leave hiding spot   (stay quiet)",
	"[E] Leer nota": "[E] Read note",
	"el tanque": "the tank",
	"el casillero": "the locker",
	"[E] Salir de %s": "[E] Leave %s",
	"[E] Esconderte en %s": "[E] Hide in %s",
	"[E] Panel del ascensor (sin energía)": "[E] Elevator panel (no power)",
	"Ascensor en movimiento...": "Elevator moving...",
	"[E] Llamar al ascensor": "[E] Call the elevator",
	"[E] Usar el ascensor": "[E] Use the elevator",
	"Fusible instalado. El ascensor tiene energía otra vez.": "Fuse installed. The elevator has power again.",
	"Sin energía. Falta el fusible del ascensor (búscalo por el edificio).": "No power. The elevator fuse is missing (look for it around the building).",
	"El ascensor ya está aquí.": "The elevator is already here.",
	"[E] Instalar fusibles (%d/%d)": "[E] Install fuses (%d/%d)",
	"El generador necesita %d fusibles. Instalados: %d/%d.": "The generator needs %d fuses. Installed: %d/%d.",
	"Fusibles instalados: %d/%d. Faltan %d.": "Fuses installed: %d/%d. %d to go.",
	"Palanca de trampa (se recarga: %d s)": "Trap lever (recharging: %d s)",
	"[E] Accionar palanca (activa una trampa cercana)": "[E] Pull lever (activates a nearby trap)",
	"La palanca todavía se está recargando.": "The lever is still recharging.",
	"La palanca no responde (no tiene trampa conectada).": "The lever does not respond (no trap connected).",
	"¡Trampa activada! Cualquier criatura que pise la zona de franjas quedará aturdida.": "Trap activated! Any creature that steps on the striped zone will be stunned.",
	"puerta principal": "main door",
	"compuerta de evacuación": "evacuation hatch",
	"salida a la superficie": "exit to the surface",
	"[E] Cortar las raíces con el hacha": "[E] Cut the roots with the axe",
	"Raíces gruesas bloquean el paso: necesitas un hacha": "Thick roots block the way: you need an axe",
	"[E] Abrir %s": "[E] Open %s",
	"[E] Abrir con la llave": "[E] Unlock with the key",
	"%s (sin energía)": "%s (no power)",
	"Puerta cerrada: falta %s": "Door locked: missing %s",
	"La cerradura eléctrica no responde. Hay que restaurar la energía.": "The electric lock does not respond. Power must be restored.",
	"Está cerrada con llave. Necesitas: %s.": "It's locked. You need: %s.",
	"Incinerador (sin energía)": "Incinerator (no power)",
	"Incinerador: la raíz sigue viva (destruye su corazón)": "Incinerator: the root is still alive (destroy its heart)",
	"Incinerador: faltan bidones (%d/%d)": "Incinerator: missing canisters (%d/%d)",
	"[E] ENCENDER el incinerador (quemarlo todo)": "[E] LIGHT the incinerator (burn everything)",
	"El incinerador no tiene energía. Instala primero los fusibles en el generador.": "The incinerator has no power. Install the fuses in the generator first.",
	"Las raíces son demasiado fuertes: el fuego no prende. Baja por el túnel del centro y destruye el CORAZÓN a hachazos.": "The roots are too strong: the fire won't catch. Go down the center tunnel and destroy the HEART with the axe.",
	"Necesita %d bidones de combustible (llevas %d). Hay uno en las esporas (norte) y otro en las raíces del sur.": "It needs %d fuel canisters (you have %d). There is one in the spores (north) and another in the roots to the south.",
	"¡Incinerador encendido! Aguanta %d segundos: el ruido atrae a las dos criaturas. Cuando prenda, el fuego se propaga: ¡tendrás que salir por el túnel del noreste!": "Incinerator lit! Hold out for %d seconds: the noise attracts both creatures. Once it catches, the fire spreads: you'll have to get out through the northeast tunnel!",
	"Incinerador: %d s…": "Incinerator: %d s…",
	"[E] Golpear el corazón con el hacha": "[E] Strike the heart with the axe",
	"El corazón de la raíz late... necesitas un hacha": "The root's heart beats... you need an axe",
	"Con las manos no vas a lograr nada. Necesitas el hacha.": "You won't get anywhere with your bare hands. You need the axe.",
	"El suelo vibra... la raíz se retuerce. Sigue golpeando.": "The ground vibrates... the root writhes. Keep striking.",
	"CORAZÓN": "HEART",
	"Pantalla completa no disponible: el juego está incrustado en el editor.\nDesactiva \"Embed Game\" o exporta el juego (.exe).": "Fullscreen is not available: the game is embedded in the editor.\nDisable \"Embed Game\" or export the game (.exe).",

	# ---------------------------------------------------- cinemática
	"Corriste hasta la puerta principal.": "You ran to the main door.",
	"Por fin. La calle.": "At last. The street.",
	"Pero detrás de la reja no había calle.": "But behind the gate there was no street.",
	"Santa Marta nunca terminó en la superficie.": "Santa Marta never ended at the surface.",
	"Algo aquí abajo escucha cada paso.": "Something down here hears every step.",
	"NIVEL 2\nLOS SÓTANOS": "LEVEL 2\nTHE BASEMENTS",
	"Enter: saltar": "Enter: skip",

	# ---------------------------------------------------------- notas
	"(nota sin texto)": "(blank note)",
	"Receta de la enfermería:\nEl fusible del ascensor del ala este quedó guardado aquí. Y la pistola de dardos es del guardia: no mata, pero ATURDE a esa cosa unos segundos. Clic izquierdo para disparar.":
		"Infirmary prescription:\nThe east wing elevator fuse was left here. And the dart gun is the guard's: it doesn't kill, but it STUNS that thing for a few seconds. Left click to fire.",
	"Diario del paciente 12:\n\"Me trajeron de noche. Dicen que es por mi descanso, pero oigo aletear detrás de las paredes. Nunca duermen.\"":
		"Patient 12's diary:\n\"They brought me in at night. They say it's for my rest, but I hear flapping behind the walls. They never sleep.\"",
	"Cartel del ascensor:\n\"Ala este, 2.º piso: sala de máquinas y generador. FUERA DE SERVICIO: falta el fusible especial. Ojo: la cabina hace ruido al moverse.\"":
		"Elevator sign:\n\"East wing, 2nd floor: machine room and generator. OUT OF ORDER: the special fuse is missing. Careful: the cab is noisy when it moves.\"",
	"Nota de mantenimiento:\n\"Instalé una palanca en el patio central. Si esa cosa pisa las franjas amarillas del suelo y alguien tira de la palanca, se queda paralizada unos segundos. Se recarga sola.\"":
		"Maintenance note:\n\"I installed a lever in the central courtyard. If that thing steps on the yellow stripes on the floor and someone pulls the lever, it freezes for a few seconds. It recharges by itself.\"",
	"Nota del Dr. Vega:\n\"La criatura responde al sonido. Una botella lanzada [G] la hace correr hacia donde cae. Las bengalas [Q] la ciegan un instante: úsalas de frente.\"":
		"Dr. Vega's note:\n\"The creature responds to sound. A thrown bottle [G] makes it run to where it lands. Flares [Q] blind it for a moment: use them head-on.\"",
	"Informe del laboratorio:\n\"La llave de las máquinas está en esta sala. El ala este del segundo piso NO tiene escalera: solo se llega en el ascensor.\"":
		"Laboratory report:\n\"The machine room key is in this room. The east wing of the second floor has NO stairs: you can only get there by elevator.\"",
	"Hoja de la sala de máquinas:\n\"Aquí quedó un fusible. Faltan otros dos repartidos por el edificio: un fusible en el almacén de la planta baja y otro en el laboratorio. El generador necesita TRES.\"":
		"Machine room sheet:\n\"One fuse was left here. Two more are scattered around the building: one in the ground floor storeroom and another in the laboratory. The generator needs THREE.\"",
	"Nota pegada al generador:\n\"Si lo enciende, la alarma de la cocina (ala oeste, planta baja) sonará y ESO la atraerá hacia allá. Aproveche para bajar en el ascensor y correr a la puerta principal.\"":
		"Note stuck to the generator:\n\"If you turn it on, the kitchen alarm (west wing, ground floor) will sound and THAT will draw it over there. Take the chance to go down in the elevator and run to the main door.\"",
	"Nota pegada al generador:\n\"Si lo enciende, la alarma del ala oeste sonará y ESO la atraerá hacia allá. Aproveche para correr a la puerta principal.\"":
		"Note stuck to the generator:\n\"If you turn it on, the west wing alarm will sound and THAT will draw it over there. Take the chance to run to the main door.\"",
	"Nota de la enfermera jefe:\n\"Guardé la llave del laboratorio en el botiquín. Y recuerde: el generador necesita TRES fusibles, ni uno menos.\"":
		"Head nurse's note:\n\"I put the laboratory key in the medicine cabinet. And remember: the generator needs THREE fuses, not one less.\"",
	"Informe del Dr. Vega:\n\"La criatura responde al sonido. Hablar, caminar normal, incluso respirar fuerte la atrae. Muévase agachado y, si lo persigue, escóndase en un casillero: pero adentro ni respire. La llave de máquinas está en el laboratorio.\"":
		"Dr. Vega's report:\n\"The creature responds to sound. Talking, walking normally, even breathing hard attracts it. Move crouched and, if it chases you, hide in a locker: but don't even breathe inside. The machine room key is in the laboratory.\"",
	"Aviso para el personal:\n\"La llave de la enfermería se quedó en la sala de pacientes. No entre solo a esa ala. Al Dr. Vega lo oímos gritar.\"":
		"Staff notice:\n\"The infirmary key was left in the patients' room. Do not enter that wing alone. We heard Dr. Vega scream.\"",
	"Registro de mantenimiento:\nLas bombas se averiaron cuando eso empezó a anidar en la cámara central. Necesitan TRES fusibles: uno en los filtros (norte), otro en la cámara fría y otro en la propia sala de bombas.":
		"Maintenance log:\nThe pumps broke down when that thing began nesting in the central chamber. They need THREE fuses: one in the filters (north), another in the cold room and another in the pump room itself.",
	"Nota del técnico:\nEl fusible del ascensor quedó en las calderas, junto a la pistola de dardos del guardia: aturde al espécimen unos segundos. Sin ese fusible el ascensor del ala oeste no anda.":
		"Technician's note:\nThe elevator fuse was left in the boiler room, next to the guard's dart gun: it stuns the specimen for a few seconds. Without that fuse the west wing elevator won't run.",
	"Libreta del Dr. Vega:\nEl espécimen que bajó del sanatorio es CIEGO: se guía por el sonido. Los charcos lo delatan, chapotear es como gritarle. Una botella lanzada [G] lo manda lejos a investigar. Las bengalas no le hacen nada.":
		"Dr. Vega's notebook:\nThe specimen that came down from the sanatorium is BLIND: it navigates by sound. Puddles give you away, splashing is like shouting at it. A thrown bottle [G] sends it far away to investigate. Flares do nothing to it.",
	"Inscripción en la pared:\nLA PUERTA PRINCIPAL NO DABA A LA CALLE. Solo hay una salida: la compuerta de evacuación, al fondo del ala este (sur). Necesita energía.":
		"Inscription on the wall:\nTHE MAIN DOOR DID NOT LEAD TO THE STREET. There is only one way out: the evacuation hatch, at the end of the east wing (south). It needs power.",
	"Hoja de la sala de bombas:\nEl panel está al fondo. Cuando lo enciendas sonará la alarma de los filtros (norte) y el espécimen irá hacia allá. Baja en el ascensor y corre a la compuerta.":
		"Pump room sheet:\nThe panel is at the back. When you turn it on, the filter alarm (north) will sound and the specimen will go there. Take the elevator down and run to the hatch.",
	"Etiqueta de la cámara fría:\nLa llave de la sala de bombas está aquí dentro. Y la palanca del salón este electrifica el suelo marcado con franjas: si el espécimen lo pisa, queda paralizado un buen rato.":
		"Cold room label:\nThe pump room key is in here. And the lever in the east hall electrifies the floor marked with stripes: if the specimen steps on it, it is paralyzed for quite a while.",
}
