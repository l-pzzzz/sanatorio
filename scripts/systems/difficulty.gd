extends Node
## Dificultad global (autoload "Difficulty"). 0 = Fácil, 1 = Media (la de siempre), 2 = Difícil.
## La elección se mantiene entre niveles.

const NAMES := ["FÁCIL", "MEDIA", "DIFÍCIL"]

const TABLE := {
	# --- murciélago
	"bat_vision":      [8.0, 11.0, 15.0],     # alcance de vista (m)
	"bat_angle":       [110.0, 130.0, 150.0], # cono de visión (grados)
	"bat_flash_mul":   [2.0, 2.0, 3.0],       # multiplicador de vista si llevas la linterna encendida
	"bat_speed_mul":   [0.8, 1.0, 1.12],      # velocidad al perseguir
	"bat_forget":      [4.0, 6.0, 12.0],      # segundos que busca antes de rendirse
	"bat_locker":      [0.0, 0.0, 0.6],       # prob. de abrir tu casillero si anda cerca
	"bat_see_hide":    [false, true, true],   # puede verte entrar al casillero
	# --- Eco
	"eco_hear_mul":    [0.7, 1.0, 1.3],       # radio de oído
	"eco_search":      [4.0, 6.0, 9.0],       # tiempo buscando donde oyó algo
	"eco_smell":       [0.0, 0.0, 1.6],       # distancia a la que te "huele" aunque estés quieto
	# --- aturdimiento
	"stun_mul":        [2.0, 1.0, 0.7],
	"stun_immunity":   [0.0, 5.5, 5.5],
	"flash_dodge":     [false, false, true],  # tras el primer flash ya no le afecta
	# --- recursos (dardos, botellas, bengalas)
	"supply_mul":      [1.6, 1.0, 0.6],
	# --- teletransporte entre pisos (0 = apagado)
	"tp_wait":         [0.0, 15.0, 8.0],      # segundos con el jugador en otro piso antes de aparecer
	"tp_cooldown":     [0.0, 40.0, 25.0],
	"eco_tp":          [false, false, true],  # el Eco también (solo si haces ruido arriba)
}

var level := 1


func get_value(key: String):
	return TABLE[key][level]


func level_name() -> String:
	return Lang.t(NAMES[level])
