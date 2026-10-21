class_name ItemInfo
extends RefCounted
## Nombres y colores de los objetos del juego (un solo lugar para editarlos).

const NAMES := {
	"linterna": "Linterna",
	"llave_enfermeria": "Llave de la enfermería",
	"llave_laboratorio": "Llave del laboratorio",
	"llave_maquinas": "Llave de la sala de máquinas",
	"fusible": "Fusible",
	"llave_caldera": "Llave de la sala de calderas",
	"llave_camara": "Llave de la cámara fría",
	"llave_bombas": "Llave de la sala de bombas",
	"pistola": "Pistola de dardos",
	"dardos": "Dardos",
	"botella": "Botella",
	"bengala": "Bengala",
	"fusible_ascensor": "Fusible del ascensor",
	"llave_drenaje": "Llave del drenaje",
	"llave_filtros": "Llave de los filtros",
	"llave_valvulas": "Llave de las válvulas",
	"bidon_combustible": "Bidón de combustible",
	"hacha": "Hacha oxidada",
}

const COLORS := {
	"linterna": Color(1.0, 0.85, 0.35),
	"llave_enfermeria": Color(0.4, 0.9, 1.0),
	"llave_laboratorio": Color(0.6, 1.0, 0.5),
	"llave_maquinas": Color(1.0, 0.5, 0.9),
	"fusible": Color(1.0, 0.55, 0.15),
	"llave_caldera": Color(1.0, 0.45, 0.2),
	"llave_camara": Color(0.5, 0.8, 1.0),
	"llave_bombas": Color(0.9, 0.9, 0.3),
	"pistola": Color(0.4, 1.0, 0.55),
	"dardos": Color(0.4, 1.0, 0.55),
	"botella": Color(0.55, 0.9, 0.7),
	"bengala": Color(1.0, 0.25, 0.2),
	"fusible_ascensor": Color(0.35, 0.6, 1.0),
	"llave_drenaje": Color(0.5, 1.0, 0.7),
	"llave_filtros": Color(0.9, 0.7, 1.0),
	"llave_valvulas": Color(1.0, 0.6, 0.3),
	"bidon_combustible": Color(1.0, 0.3, 0.1),
	"hacha": Color(1.0, 0.75, 0.35),
}


## Tecla con la que se usa cada herramienta (se muestra en el inventario).
const HINTS := {"pistola": "[clic izq.]", "botella": "[G]", "bengala": "[Q]", "hacha": "[E] en las raíces"}


static func display_name(id: String) -> String:
	return Lang.t(str(NAMES.get(id, id)))


static func color_of(id: String) -> Color:
	return COLORS.get(id, Color.WHITE)
