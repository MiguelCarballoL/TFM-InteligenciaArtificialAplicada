/**
 * Name: TFM_Autobuses
 * Descripción: Sistema multiagente con arquitectura BDI para la 
 * 				simulación de la sustitución por autobuses de la 
 * 				línea 6 de metro de Madrid.
 * Roles: Autobús, Pasajero, Parada, Mapa.
 */

model TFM_Autobuses

// Inicialización global
global {
	// Carga de archivos con calles y paradas
	file shape_calles <- shape_file("../includes/red_calles_def.shp", "EPSG:23030");
	file shape_paradas <- shape_file("../includes/paradas_lineas_def.shp", "EPSG:23030");

	geometry shape <- envelope(shape_calles);

	// Grafo de la red de calles
	graph red_viaria;

	// Parámetros de simulación
	float step <- 1 #s;
	int ciclo <- 0;
	float max_tiempo_simulacion <- 3600 #s;
	bool fin_simulacion <- false;

	// Parámetros de autobuses
	// Paradas donde aparecerá un bus al inicio
	list<string> paradas_inicio_A <- ["3644", "15525", "5296", "51143"];
	list<string> paradas_inicio_B <- ["2481"];
	int capacidad_maxima_bus <- 86;
	float velocidad_bus <- 40.0 #km / #h;
	float frecuencia_creacion_buses <- 600 #s;
	float tiempo_ultimo_bus <- 0.0 #s;

	// Parámetros de pasajeros
	float frecuencia_creacion_pasajeros <- 120 #s;
	float tiempo_ultimo_pasajero <- 0 #s;
	int pasajeros_por_oleada <- 5;
	float tiempo_max_espera_pasajero <- 900 #s;
	int total_pasajeros_generados <- 0;
	int total_pasajeros_llegados <- 0;
	int total_pasajeros_abandonados <- 0;

	// Parámetros del mapa
	float prob_bloqueo_carretera <- 0.0005;
	float prob_trafico_carretera <- 0.005;

	// Definición de líneas
	// Línea 1
	list<string> orden_linea_A <- ["3644", "4100", "4802", "3720", "5972", "4614", "51197", "782", "5296", "51142", "5394", "2697", "51196", "51144", "3278", "1688", "51140", "15525", "1687", "5316", "1414", "2692", "2696", "4678", "51143", "786", "3829", "51141", "4962", "51200", "1437", "3742", "4101", "3737"];
	// Línea 2
	list<string> orden_linea_B <- ["2481", "51144", "5141", "51033", "2710", "1414", "4284"];

	list<parada> ruta_linea_A;
	list<parada> ruta_linea_B;

	map<string, list<parada>> lineas_map;
	map<parada, list<parada>> mapa_accesibilidad;

	// Logs
	bool console_logs <- true;
	
	string modo_test <- "";  // Vacío = simulación normal. Cada test asigna su nombre.

	// Inicialización
	init {
		// Crear el Directory Facilitator
		create species: df number: 1;

		// Crear calles y paradas desde shapefiles
		create calle from: shape_calles;
		create parada from: shape_paradas;

		// Construir el grafo de la red de calles
		red_viaria <- as_edge_graph(calle);

		// Construir las rutas ordenadas para cada línea
		ruta_linea_A <- construir_ruta(orden_linea_A);
		ruta_linea_B <- construir_ruta(orden_linea_B);

		lineas_map <- ["LineaA"::ruta_linea_A, "LineaB"::ruta_linea_B];

		do precomputar_accesibilidad;

		// Crear el agente Mapa
		create agente_mapa number: 1;

		// Crear autobuses iniciales según las listas de paradas configuradas
		int id_counter <- 0;

		// LineaA: un bus por cada parada indicada en paradas_inicio_A
		loop parada_id over: paradas_inicio_A {
			parada target_parada <- ruta_linea_A first_with (each.id_parada = parada_id);
			if (target_parada != nil) {
				int idx <- ruta_linea_A index_of target_parada;
				int sig <- (idx = length(ruta_linea_A) - 1) ? 0 : (idx + 1);
				create autobus {
					id_bus <- id_counter;
					linea <- "LineaA";
					ruta <- list<parada>(ruta_linea_A);
					capacidad_maxima <- capacidad_maxima_bus;
					plazas_disponibles <- capacidad_maxima;
					velocidad_maxima <- velocidad_bus;
					location <- target_parada.location;
					index_siguiente_parada <- sig;
					parada_destino <- ruta[sig];
					ask df { bool r <- register("Autobus", myself); }
				}
				id_counter <- id_counter + 1;
			}
		}

		// LineaB: un bus por cada parada indicada en paradas_inicio_B
		loop parada_id over: paradas_inicio_B {
			parada target_parada <- ruta_linea_B first_with (each.id_parada = parada_id);
			if (target_parada != nil) {
				int idx <- ruta_linea_B index_of target_parada;
				int sig <- (idx = length(ruta_linea_B) - 1) ? 0 : (idx + 1);
				create autobus {
					id_bus <- id_counter;
					linea <- "LineaB";
					ruta <- list<parada>(ruta_linea_B);
					capacidad_maxima <- capacidad_maxima_bus;
					plazas_disponibles <- capacidad_maxima;
					velocidad_maxima <- velocidad_bus;
					location <- target_parada.location;
					index_siguiente_parada <- sig;
					parada_destino <- ruta[sig];
					ask df { bool r <- register("Autobus", myself); }
				}
				id_counter <- id_counter + 1;
			}
		}

		if console_logs {
			write "=== Sistema inicializado ===";
			write "Paradas LineaA: " + length(ruta_linea_A);
			write "Paradas LineaB: " + length(ruta_linea_B);
			write "Autobuses creados: " + length(autobus);
		}
	}

	// Funciones auxiliares
	list<parada> construir_ruta(list<string> ids_paradas) {
		list<parada> ruta <- [];
		loop id_buscado over: ids_paradas {
			parada p <- first(parada where (each.id_parada = id_buscado));
			if (p != nil) {
				ruta << p;
			}
		}
		return ruta;
	}

	action precomputar_accesibilidad {
		list<parada> todas_paradas <- remove_duplicates(ruta_linea_A + ruta_linea_B);
		loop origen over: todas_paradas {
			list<parada> destinos_alcanzables <- [];
			// Conexiones directas
			loop nombre_linea over: lineas_map.keys {
				list<parada> paradas_linea <- lineas_map[nombre_linea];
				if (origen in paradas_linea) {
					int pos_origen <- paradas_linea index_of origen;
					if (pos_origen < length(paradas_linea) - 1) {
						loop j from: (pos_origen + 1) to: (length(paradas_linea) - 1) {
							if !(paradas_linea[j] in destinos_alcanzables) {
								destinos_alcanzables << paradas_linea[j];
							}
						}
					}
				}
			}
			// Conexiones con transbordo
			loop l1 over: lineas_map.keys {
				list<parada> paradas_l1 <- lineas_map[l1];
				if (origen in paradas_l1) {
					int pos_origen_l1 <- paradas_l1 index_of origen;
					loop l2 over: lineas_map.keys where (each != l1) {
						list<parada> paradas_l2 <- lineas_map[l2];
						loop parada_transbordo over: paradas_l1 {
							if (parada_transbordo in paradas_l2) and (parada_transbordo != origen) {
								int pos_transbordo_l1 <- paradas_l1 index_of parada_transbordo;
								if (pos_transbordo_l1 > pos_origen_l1) {
									int pos_transbordo_l2 <- paradas_l2 index_of parada_transbordo;
									if (pos_transbordo_l2 < length(paradas_l2) - 1) {
										loop k from: (pos_transbordo_l2 + 1) to: (length(paradas_l2) - 1) {
											if !(paradas_l2[k] in destinos_alcanzables) {
												destinos_alcanzables << paradas_l2[k];
											}
										}
									}
								}
							}
						}
					}
				}
			}
			mapa_accesibilidad[origen] <- destinos_alcanzables;
		}
	}

	// Generación periódice de autobuses
	reflex crear_autobuses when: !fin_simulacion and (time > 0) and (time - tiempo_ultimo_bus >= frecuencia_creacion_buses) {
		tiempo_ultimo_bus <- time;
		int id_base <- length(autobus);
		if (length(ruta_linea_A) > 1) {
			create autobus {
				id_bus <- id_base;
				linea <- "LineaA";
				ruta <- list<parada>(ruta_linea_A);
				capacidad_maxima <- capacidad_maxima_bus;
				plazas_disponibles <- capacidad_maxima;
				velocidad_maxima <- velocidad_bus;
				location <- ruta_linea_A[0].location;
				index_siguiente_parada <- 1;
				parada_destino <- ruta[index_siguiente_parada];
				ask df {
					bool r <- register("Autobus", myself);
				}
			}
		}
		if (length(ruta_linea_B) > 1) {
			create autobus {
				id_bus <- id_base + 1;
				linea <- "LineaB";
				ruta <- list<parada>(ruta_linea_B);
				capacidad_maxima <- capacidad_maxima_bus;
				plazas_disponibles <- capacidad_maxima;
				velocidad_maxima <- velocidad_bus;
				location <- ruta_linea_B[0].location;
				index_siguiente_parada <- 1;
				parada_destino <- ruta[index_siguiente_parada];
				ask df {
					bool r <- register("Autobus", myself);
				}
			}
		}
		if console_logs { write "[BUSES] Nuevos autobuses creados en el ciclo " + time; }
	}

	// Generación periódica de pasajeros
	reflex crear_pasajeros when: !fin_simulacion and (time - tiempo_ultimo_pasajero >= frecuencia_creacion_pasajeros) {
		tiempo_ultimo_pasajero <- time;
		list<parada> todas_paradas_con_ruta <- remove_duplicates(ruta_linea_A + ruta_linea_B);

		loop i from: 1 to: pasajeros_por_oleada {
			parada p_origen <- one_of(todas_paradas_con_ruta where (mapa_accesibilidad[each] != nil and length(mapa_accesibilidad[each]) > 0));
			if (p_origen != nil) {
				parada p_destino <- one_of(mapa_accesibilidad[p_origen]);
				create pasajero {
					id_pasajero <- total_pasajeros_generados;
					parada_origen <- p_origen;
					parada_actual <- p_origen;
					destino_final <- p_destino;
					location <- p_origen.location;
					tiempo_llegada_parada <- time;
					do calcular_itinerario;
					ask df {
						bool r <- register("Pasajero", myself);
					}
				}
				total_pasajeros_generados <- total_pasajeros_generados + 1;
			}
		}
		if console_logs { write "[PASAJEROS] Generados " + pasajeros_por_oleada + " pasajeros. Total: " + total_pasajeros_generados; }
	}

	// Contador de ciclos
	reflex contar {
		ciclo <- ciclo + 1;
	}

	// Fin de simulación por tiempo agotado
	reflex fin when: time >= max_tiempo_simulacion {
		fin_simulacion <- true;
		write "=== Simulación finalizada ===";
		write "Ciclos totales: " + ciclo;
		write "Pasajeros generados: " + total_pasajeros_generados;
		write "Pasajeros que llegaron a destino: " + total_pasajeros_llegados;
		write "Pasajeros que abandonaron: " + total_pasajeros_abandonados;
		write "Autobuses activos: " + length(autobus where (!each.ruta_completada));
		if (modo_test != "") {
			write "=== TEST FALLIDO ===";
		}
		do pause;
	}

}


// Directory Facilitator (df)
species df {
	list<pair> yellow_pages <- [];

	bool register(string the_role, agent the_agent) {
		add the_role::the_agent to: yellow_pages;
		return true;
	}

	list search(string the_role) {
		list<agent> found_ones <- [];
		loop i from: 0 to: (length(yellow_pages) - 1) {
			pair candidate <- yellow_pages at i;
			if (candidate.key = the_role) {
				add item: candidate.value to: found_ones;
			}
		}
		return found_ones;
	}
}


// Definición de calle
species calle {
	bool bloqueada <- false;
	bool con_trafico <- false;
	rgb color <- #gray;

	aspect default {
		draw shape color: color width: 2.0;
	}
}


// Definición de agente mapa
species agente_mapa skills: [fipa] {

	// Simula bloqueos aleatorios de carreteras
	reflex bloquear_carretera when: !fin_simulacion {
		bool bloquear <- flip(prob_bloqueo_carretera);
		if (bloquear) {
			calle c <- one_of(calle where (!each.bloqueada));
			if (c != nil) {
				ask c {
					bloqueada <- true;
					color <- #red;
				}
				// Reconstruir el grafo sin la calle bloqueada
				red_viaria <- as_edge_graph(calle where (!each.bloqueada));
				list<autobus> buses_activos <- autobus where (!each.ruta_completada);
				loop b over: buses_activos {
					do start_conversation to: [b] protocol: 'no-protocol' performative: 'inform' contents: ["carretera_bloqueada", c];
				}
				if console_logs { write "[MAPA] Carretera bloqueada: " + c; }
			}
		}
	}

	// Simula tráfico aleatorio en carreteras
	reflex generar_trafico when: !fin_simulacion {
		bool trafico <- flip(prob_trafico_carretera);
		if (trafico) {
			calle c <- one_of(calle where (!each.bloqueada and !each.con_trafico));
			if (c != nil) {
				ask c {
					con_trafico <- true;
					color <- #orange;
				}
				list<autobus> buses_activos <- autobus where (!each.ruta_completada);
				loop b over: buses_activos {
					do start_conversation to: [b] protocol: 'no-protocol' performative: 'inform' contents: ["carretera_trafico", c];
				}
				if console_logs { write "[MAPA] Tráfico en carretera: " + c; }
			}
		}
	}

	aspect default {
		// El mapa no tiene representación visual propia
	}
}


// Definición de agente parada
species parada skills: [fipa] {
	// Atributo del shapefile que identifica a la parada
	string id_parada <- "" update: id_parada;

	// Estado interno
	bool ocupada <- false;
	autobus bus_ocupante <- nil;
	list<autobus> cola_autobuses <- [];
	int num_pasajeros_esperando <- 0;
	list<pasajero> pasajeros_en_parada <- [];

	// Tiempos estimados de llegada: clave = "linea_idbus", valor = segundos restantes
	map<string, float> tiempos_eta;

	init {
		id_parada <- string(read("parada"));
	}

	// Decrementar ETAs cada step y eliminar las que lleguen a 0
	reflex actualizar_etas when: length(tiempos_eta) > 0 {
		list<string> claves_a_borrar <- [];
		loop clave over: tiempos_eta.keys {
			tiempos_eta[clave] <- tiempos_eta[clave] - step;
			if (tiempos_eta[clave] <= 0.0) {
				claves_a_borrar << clave;
			}
		}
		loop clave over: claves_a_borrar {
			remove key: clave from: tiempos_eta;
		}
	}

	reflex receive_request when: !empty(requests) {
		loop r over: requests {
			list content <- list(r.contents);

			if (content[0] = "solicitud_acceso") {
				// Solicitud de acceso a parada
				autobus bus_solicitante <- r.sender;
				if (!ocupada) {
					ocupada <- true;
					bus_ocupante <- bus_solicitante;
					do agree message: r contents: ["acceso_concedido"];
					if console_logs { write "[PARADA " + id_parada + "] Acceso concedido a " + bus_solicitante; }
				} else {
					cola_autobuses << bus_solicitante;
					do refuse message: r contents: ["acceso_denegado_cola"];
					if console_logs { write "[PARADA " + id_parada + "] Bus " + bus_solicitante + " en cola"; }
				}

			} else if (content[0] = "solicitar_pasajeros") {
				// Solicitud de información de subida de pasajeros
				if (num_pasajeros_esperando > 0) {
					do agree message: r contents: ["hay_pasajeros", num_pasajeros_esperando];
				} else {
					do refuse message: r contents: ["no_hay_pasajeros"];
				}

			} else if (content[0] = "solicitud_eta") {
				// Solicitud de tiempo estimado de llegada
				if (length(tiempos_eta) > 0) {
					do agree message: r contents: ["tiempos_eta", tiempos_eta];
				} else {
					do refuse message: r contents: ["sin_tiempos_eta"];
				}
			}
		}
	}

	// Recibir informs de pasajeros y autobuses
	reflex receive_inform when: !empty(informs) {
		loop i over: informs {
			list content <- list(i.contents);

			if (content[0] = "pasajero_llega") {
				// Información de llegada a la parada
				pasajero p <- i.sender;
				if !(p in pasajeros_en_parada) {
					pasajeros_en_parada << p;
					num_pasajeros_esperando <- num_pasajeros_esperando + 1;
				}

			} else if (content[0] = "pasajero_abandona") {
				// Información de abandono de la parada
				pasajero p <- i.sender;
				pasajeros_en_parada <- pasajeros_en_parada - p;
				num_pasajeros_esperando <- max(0, num_pasajeros_esperando - 1);

			} else if (content[0] = "pasajero_sube_bus") {
				// Pasajero informa que ha subido a un bus
				pasajero p <- i.sender;
				pasajeros_en_parada <- pasajeros_en_parada - p;
				num_pasajeros_esperando <- max(0, num_pasajeros_esperando - 1);

			} else if (content[0] = "bus_libera_parada") {
				// Comunicar disponibilidad
				ocupada <- false;
				bus_ocupante <- nil;
				if (length(cola_autobuses) > 0) {
					autobus siguiente_bus <- cola_autobuses[0];
					cola_autobuses <- cola_autobuses - siguiente_bus;
					ocupada <- true;
					bus_ocupante <- siguiente_bus;
					do start_conversation to: [siguiente_bus] protocol: 'no-protocol' performative: 'inform' contents: ["parada_disponible"];
					if console_logs { write "[PARADA " + id_parada + "] Disponible -> " + siguiente_bus; }
				}

			} else if (content[0] = "eta_update") {
				// Información de tiempo estimado de llegada
				string clave_eta <- string(content[1]);
				float tiempo_eta <- float(content[2]);
				tiempos_eta[clave_eta] <- tiempo_eta;

			} else if (content[0] = "bus_llega_parada") {
				// Eliminar ETA de este bus al llegar
				string clave_eta <- string(content[1]);
				remove key: clave_eta from: tiempos_eta;
			}

			do end_conversation message: i contents: [];
		}
	}

	aspect default {
		rgb color_parada <- #red;
		if (ocupada) { color_parada <- #blue; }
		if (num_pasajeros_esperando > 10) { color_parada <- #yellow; }
		draw circle(15) color: color_parada border: #black;
	}
}


// Definición de agente autobús
species autobus skills: [moving, fipa] control: simple_bdi {
	// Identificación
	int id_bus;
	string linea;

	// Creencias BDI
	predicate creencia_en_ruta <- new_predicate("en_ruta");
	predicate creencia_en_parada <- new_predicate("en_parada");
	predicate creencia_acceso_parada <- new_predicate("acceso_parada");
	predicate creencia_bajada_completada <- new_predicate("bajada_completada");
	predicate creencia_subida_completada <- new_predicate("subida_completada");
	predicate creencia_ruta_finalizada <- new_predicate("ruta_finalizada");
	predicate creencia_esperando_cola <- new_predicate("esperando_cola");
	predicate creencia_recalcular_ruta <- new_predicate("recalcular_ruta");

	// Deseos BDI
	predicate deseo_completar_ruta <- new_predicate("completar_ruta");
	predicate deseo_gestionar_parada <- new_predicate("gestionar_parada");

	// Estado del autobús
	int capacidad_maxima;
	int plazas_disponibles;
	float velocidad_maxima;
	float velocidad_actual <- 0.0;
	float aceleracion <- 1.2; // 1.2 m/s^2
	bool arrancando <- false;
	bool ruta_completada <- false;

	list<parada> ruta;
	int index_siguiente_parada;
	parada parada_destino;
	parada parada_actual_bus;

	list<pasajero> pasajeros_a_bordo <- [];

	// Control de CFP de subida
	int respuestas_cfp_esperadas <- 0;
	bool cfp_enviado <- false;

	// Control de CFP de bajada
	list<pasajero> pasajeros_quieren_bajar <- [];
	int respuestas_bajada_esperadas <- 0;
	bool cfp_bajada_enviado <- false;

	// Inicialización
	init {
		do add_belief(creencia_en_ruta);
		do add_desire(deseo_completar_ruta);
	}

	// Reglas BDI
	rule belief: creencia_en_parada new_desire: deseo_gestionar_parada;

	plan plan_completar_ruta intention: deseo_completar_ruta {
		if (ruta_completada) {
			do remove_intention(deseo_completar_ruta, true);
		} else if (has_belief(creencia_esperando_cola)) {
			// Esperando a que la parada notifique disponibilidad
		} else if (has_belief(creencia_en_parada)) {
			do add_subintention(get_current_intention(), deseo_gestionar_parada, true);
			do current_intention_on_hold();
		} else {
			// Aceleración progresiva al arrancar de una parada
			float vel_tope <- velocidad_maxima;
			// Si la calle actual tiene tráfico, la velocidad máxima se reduce a la mitad
			list<calle> calles_cercanas <- calle at_distance 5.0 #m;
			if (length(calles_cercanas where each.con_trafico) > 0) {
				vel_tope <- velocidad_maxima / 2.0;
			}
			velocidad_actual <- min(velocidad_actual + aceleracion * step, vel_tope);
			if (velocidad_actual > vel_tope) { velocidad_actual <- vel_tope; }

			// Comprobar si la parada es alcanzable, si no lo es, saltarla
			path camino <- path_between(red_viaria, location, parada_destino.location);
			if (camino = nil) {
				if console_logs { write "[BUS " + id_bus + " " + linea + "] Parada " + parada_destino.id_parada + " inalcanzable, saltando"; }
				do avanzar_ruta;
				do informar_eta;
			} else {
			// Moverse hacia la siguiente parada
			do goto target: parada_destino on: red_viaria speed: velocidad_actual;

			// Comprobar si hemos llegado
			if (location distance_to parada_destino.location < 5.0 #m) {
				parada_actual_bus <- parada_destino;

				// Informar a la parada que el bus ha llegado (eliminar su ETA)
				string clave_eta <- linea + "_" + id_bus;
				do start_conversation to: [parada_actual_bus] protocol: 'no-protocol' performative: 'inform' contents: ["bus_llega_parada", clave_eta];

				// Comprobar si hay pasajeros que bajar o subir en esta parada
				bool hay_bajada <- length(pasajeros_a_bordo where (each.siguiente_destino = parada_actual_bus)) > 0;
				bool hay_subida <- parada_actual_bus.num_pasajeros_esperando > 0;

				if (hay_bajada or hay_subida) {
					// Parar en la parada
					do add_belief(creencia_en_parada);
					do start_conversation to: [parada_actual_bus] protocol: 'fipa-request' performative: 'request' contents: ["solicitud_acceso"];
					if console_logs { write "[BUS " + id_bus + " " + linea + "] Llegada a " + parada_actual_bus.id_parada; }
				} else {
					// Saltar parada porque no hay nadie que bajar ni subir
					if console_logs { write "[BUS " + id_bus + " " + linea + "] Salta parada " + parada_actual_bus.id_parada + " (sin pasajeros)"; }
					do avanzar_ruta;
					do informar_eta;
				}
			}
			} // fin else camino alcanzable
		}
	}

	plan plan_gestionar_parada intention: deseo_gestionar_parada {
		if (has_belief(creencia_acceso_parada)) {
			// Bajada de pasajeros
			if (!has_belief(creencia_bajada_completada)) {
				if (!cfp_bajada_enviado) {
					do proceso_bajada_cfp;
					cfp_bajada_enviado <- true;
				}
				if (cfp_bajada_enviado and respuestas_bajada_esperadas <= 0) {
					do add_belief(creencia_bajada_completada);
				}
			}

			// Subida de pasajeros
			if (has_belief(creencia_bajada_completada) and !has_belief(creencia_subida_completada)) {
				if (!cfp_enviado) {
					do proceso_subida_cfp;
					cfp_enviado <- true;
				}
				if (cfp_enviado and respuestas_cfp_esperadas <= 0) {
					do add_belief(creencia_subida_completada);
				}
			}

			// Completar gestión de parada
			if (has_belief(creencia_bajada_completada) and has_belief(creencia_subida_completada)) {
				// Liberar parada
				do start_conversation to: [parada_actual_bus] protocol: 'no-protocol' performative: 'inform' contents: ["bus_libera_parada"];

				// Limpiar creencias
				do remove_belief(creencia_en_parada);
				do remove_belief(creencia_acceso_parada);
				do remove_belief(creencia_bajada_completada);
				do remove_belief(creencia_subida_completada);
				do remove_belief(creencia_esperando_cola);
				cfp_enviado <- false;
				respuestas_cfp_esperadas <- 0;
				
				cfp_bajada_enviado <- false;
				respuestas_bajada_esperadas <- 0;
				pasajeros_quieren_bajar <- [];

				// Reiniciar velocidad al arrancar de la parada
				velocidad_actual <- 0.0;
				arrancando <- true;

				// Avanzar a la siguiente parada
				do avanzar_ruta;

				// Informar ETAs
				do informar_eta;

				do remove_intention(deseo_gestionar_parada, true);
			}
		}
	}

	// Acciones
	// Permitir bajada y bajada de pasajeros
	action proceso_bajada_cfp {
		if (length(pasajeros_quieren_bajar) > 0) {
			respuestas_bajada_esperadas <- length(pasajeros_quieren_bajar);
			loop p over: pasajeros_quieren_bajar {
				do start_conversation to: [p] protocol: 'fipa-contract-net' performative: 'cfp' contents: ["quieres_bajar", parada_actual_bus];
			}
			if console_logs { write "[BUS " + id_bus + " " + linea + "] CFP bajada a " + length(pasajeros_quieren_bajar) + " pasajeros en " + parada_actual_bus.id_parada; }
		} else {
			respuestas_bajada_esperadas <- 0;
		}
	}

	// Permitir subida y subida de pasajeros
	action proceso_subida_cfp {
		list<pasajero> pasajeros_esperando <- pasajero where (each.parada_actual = parada_actual_bus and each.esperando_en_parada and !each.en_autobus and !each.destino_alcanzado);

		if (length(pasajeros_esperando) > 0 and plazas_disponibles > 0) {
			respuestas_cfp_esperadas <- length(pasajeros_esperando);
			loop p over: pasajeros_esperando {
				do start_conversation to: [p] protocol: 'fipa-contract-net' performative: 'cfp' contents: ["quieres_subir", ruta, linea, self];
			}
			if console_logs { write "[BUS " + id_bus + " " + linea + "] CFP a " + length(pasajeros_esperando) + " pasajeros en " + parada_actual_bus.id_parada; }
		} else {
			respuestas_cfp_esperadas <- 0;
		}
	}

	// Avanzar a la siguiente parada
	action avanzar_ruta {
		index_siguiente_parada <- index_siguiente_parada + 1;
		if (index_siguiente_parada < length(ruta)) {
			parada_destino <- ruta[index_siguiente_parada];
		} else {
			// Volver al inicio de la ruta
			index_siguiente_parada <- 0;
			parada_destino <- ruta[0];
		}
	}

	// Informar tiempo estimado de llegada
	// Envía ETA a las 10 paradas siguientes de la ruta
	action informar_eta {
		string clave_eta <- linea + "_" + id_bus;
		float distancia_acumulada <- 0.0;
		point pos_anterior <- location;
		int max_eta <- min(10, length(ruta) - index_siguiente_parada);
		loop i from: 0 to: (max_eta - 1) {
			int idx <- index_siguiente_parada + i;
			distancia_acumulada <- distancia_acumulada + (pos_anterior distance_to ruta[idx].location);
			float tiempo_estimado <- distancia_acumulada / velocidad_maxima;
			do start_conversation to: [ruta[idx]] protocol: 'no-protocol' performative: 'inform' contents: ["eta_update", clave_eta, tiempo_estimado];
			pos_anterior <- ruta[idx].location;
		}
	}

	// Recalcular ruta cuando una carretera se bloquea
	action recalcular_ruta {
		if console_logs { write "[BUS " + id_bus + " " + linea + "] Recalculando ruta por bloqueo"; }
	}

	// Recibir propuestas de pasajeros
	reflex receive_propose when: !empty(proposes) {
		loop p over: proposes {
			list content <- list(p.contents);
			if (content[0] = "quiero_subir") {
				respuestas_cfp_esperadas <- respuestas_cfp_esperadas - 1;
				// Verificar capacidad
				if (plazas_disponibles > 0) {
					plazas_disponibles <- plazas_disponibles - 1;
					pasajero pas <- p.sender;
					pasajeros_a_bordo << pas;
					do accept_proposal message: p contents: ["subida_aceptada"];
					if console_logs { write "[BUS " + id_bus + " " + linea + "] Pasajero " + pas.id_pasajero + " sube. Plazas: " + plazas_disponibles; }
				} else {
					do reject_proposal message: p contents: ["autobus_lleno"];
					if console_logs { write "[BUS " + id_bus + " " + linea + "] Rechazado: bus lleno"; }
				}
			} else if (content[0] = "quiero_bajar") {
				respuestas_bajada_esperadas <- respuestas_bajada_esperadas - 1;
				pasajero pas <- p.sender;
				pasajeros_a_bordo <- pasajeros_a_bordo - pas;
				plazas_disponibles <- plazas_disponibles + 1;
				pasajeros_quieren_bajar <- pasajeros_quieren_bajar - pas;
				do accept_proposal message: p contents: ["bajada_aceptada"];
				if console_logs { write "[BUS " + id_bus + " " + linea + "] Pasajero " + pas.id_pasajero + " baja en " + parada_actual_bus.id_parada + ". Plazas: " + plazas_disponibles; }
			}
		}
	}

	// Recibir rechazos de pasajeros o de la parada
	reflex receive_refuses when: !empty(refuses) {
		loop r over: refuses {
			list content <- list(r.contents);
			if (content[0] = "no_quiero_subir") {
				respuestas_cfp_esperadas <- respuestas_cfp_esperadas - 1;
			} else if (content[0] = "acceso_denegado_cola") {
				// Esperar en cola porque la parada está ocupada
				do add_belief(creencia_esperando_cola);
				if console_logs { write "[BUS " + id_bus + " " + linea + "] En cola en parada " + parada_actual_bus.id_parada; }
			}
		}
	}

	// Recibir agrees de la parada para acceder
	reflex receive_agrees when: !empty(agrees) {
		loop a over: agrees {
			list content <- list(a.contents);
			if (content[0] = "acceso_concedido") {
				do add_belief(creencia_acceso_parada);
			}
		}
	}

	// Recibir informs del mapa o de la parada o de pasajeros
	reflex receive_inform when: !empty(informs) {
		loop i over: informs {
			list content <- list(i.contents);
			if (content[0] = "carretera_bloqueada") {
				do recalcular_ruta;
			} else if (content[0] = "carretera_trafico") {
				// La velocidad se ajusta dinámicamente al pasar por la calle congestionada
				if console_logs { write "[BUS " + id_bus + " " + linea + "] Notificado de tráfico en carretera"; }
			} else if (content[0] = "parada_disponible") {
				// La parada notifica que está libre
				do remove_belief(creencia_esperando_cola);
				do add_belief(creencia_acceso_parada);
				if console_logs { write "[BUS " + id_bus + " " + linea + "] Parada disponible, operando"; }
			} else if (content[0] = "quiero_bajar_siguiente") {
				// Pasajero notifica que quiere bajar en la siguiente parada
				pasajero pas <- i.sender;
				if (!(pas in pasajeros_quieren_bajar)) {
					pasajeros_quieren_bajar << pas;
				}
				if console_logs { write "[BUS " + id_bus + " " + linea + "] Pasajero " + pas.id_pasajero + " solicita bajar en próxima parada"; }
			}
			do end_conversation message: i contents: [];
		}
	}

	// Aspecto visual
	aspect default {
		if (!ruta_completada) {
			draw circle(25) color: #blue border: #black;
		}
	}
}


// Definición de agente pasajero
species pasajero skills: [fipa] control: simple_bdi {
	// Identificación
	int id_pasajero;
	float tiempo_inicio <- time;

	// Creencias BDI
	predicate creencia_esperando <- new_predicate("esperando_bus");
	predicate creencia_en_bus <- new_predicate("en_autobus");
	predicate creencia_parada_notificada <- new_predicate("parada_notificada");
	predicate creencia_destino_alcanzado_pred <- new_predicate("destino_alcanzado");

	// Deseos BDI
	predicate deseo_llegar_parada <- new_predicate("llegar_parada");

	// Estado
	parada parada_origen;
	parada parada_actual;
	parada destino_final;
	parada siguiente_destino;

	list<parada> itinerario_destinos <- [];
	list<string> lineas_validas <- [];

	autobus bus_actual <- nil;
	bool en_autobus <- false;
	bool esperando_en_parada <- true;
	bool destino_alcanzado <- false;
	float tiempo_llegada_parada;
	float tiempo_total <- 0.0;
	float tiempo_espera <- 0.0;
	float ultima_solicitud_eta <- 0.0;
	bool bajada_notificada <- false;

	// Inicialización
	init {
		do add_belief(creencia_esperando);
		do add_desire(deseo_llegar_parada);
	}

	// Reglas BDI
	rule belief: creencia_esperando when: not has_belief(creencia_parada_notificada) new_desire: deseo_llegar_parada;

	plan plan_llegar_parada intention: deseo_llegar_parada {
		if (parada_actual != nil and !has_belief(creencia_parada_notificada)) {
			// Comunicar presencia en parada
			do start_conversation to: [parada_actual] protocol: 'no-protocol' performative: 'inform' contents: ["pasajero_llega"];
			do add_belief(creencia_parada_notificada);

			// Solicitar ETA
			do start_conversation to: [parada_actual] protocol: 'fipa-request' performative: 'request' contents: ["solicitud_eta"];

			if console_logs { write "[PASAJERO " + id_pasajero + "] En parada " + parada_actual.id_parada + " -> destino " + destino_final.id_parada; }
		}
		do remove_intention(deseo_llegar_parada);
		do remove_desire(deseo_llegar_parada);
	}

	// Acciones
	// Calcula el itinerario directo o con transbordo
	action calcular_itinerario {
		itinerario_destinos <- [];
		lineas_validas <- [];

		// Intentar ruta directa
		loop nombre_linea over: lineas_map.keys {
			list<parada> paradas_linea <- lineas_map[nombre_linea];
			if (parada_origen in paradas_linea) and (destino_final in paradas_linea) {
				int pos_origen <- paradas_linea index_of parada_origen;
				int pos_destino <- paradas_linea index_of destino_final;
				if (pos_destino > pos_origen) {
					itinerario_destinos <- [destino_final];
					siguiente_destino <- destino_final;
					lineas_validas << nombre_linea;
					return;
				}
			}
		}

		// Si no hay ruta directa, buscar transbordo
		loop l1 over: lineas_map.keys {
			list<parada> paradas_l1 <- lineas_map[l1];
			if (parada_origen in paradas_l1) {
				int pos_origen_l1 <- paradas_l1 index_of parada_origen;
				loop l2 over: lineas_map.keys where (each != l1) {
					list<parada> paradas_l2 <- lineas_map[l2];
					if (destino_final in paradas_l2) {
						int pos_destino_l2 <- paradas_l2 index_of destino_final;
						loop pt over: paradas_l1 {
							if (pt in paradas_l2) and (pt != parada_origen) {
								int pos_pt_l1 <- paradas_l1 index_of pt;
								int pos_pt_l2 <- paradas_l2 index_of pt;
								if (pos_pt_l1 > pos_origen_l1) and (pos_destino_l2 > pos_pt_l2) {
									itinerario_destinos <- [pt, destino_final];
									siguiente_destino <- pt;
									lineas_validas << l1;
									return;
								}
							}
						}
					}
				}
			}
		}

		// Fallback
		if (length(itinerario_destinos) = 0) {
			itinerario_destinos <- [destino_final];
			siguiente_destino <- destino_final;
		}
	}

	// Recibir CFP del autobús
	reflex receive_cfps when: !empty(cfps) {
		loop c over: cfps {
			list content <- list(c.contents);
			if (content[0] = "quieres_bajar") {
				// Confirmar que quiero bajar
				do propose message: c contents: ["quiero_bajar"];
				if console_logs { write "[PASAJERO " + id_pasajero + "] Confirma bajada en " + siguiente_destino.id_parada; }
			} else if (content[0] = "quieres_subir") {
				list<parada> ruta_bus <- content[1];
				string linea_bus <- string(content[2]);

				// Verificar si el bus lleva al siguiente destino
				bool destino_en_ruta <- false;
				if (siguiente_destino in ruta_bus) {
					int pos_parada_actual_bus <- -1;
					loop idx from: 0 to: (length(ruta_bus) - 1) {
						if (ruta_bus[idx] = parada_actual) {
							pos_parada_actual_bus <- idx;
						}
					}
					int pos_destino_bus <- -1;
					loop idx from: 0 to: (length(ruta_bus) - 1) {
						if (ruta_bus[idx] = siguiente_destino) {
							pos_destino_bus <- idx;
						}
					}
					if (pos_destino_bus > pos_parada_actual_bus) and (pos_parada_actual_bus >= 0) {
						destino_en_ruta <- true;
					}
				}

				if (destino_en_ruta and esperando_en_parada and !en_autobus) {
					do propose message: c contents: ["quiero_subir", itinerario_destinos];
					if console_logs { write "[PASAJERO " + id_pasajero + "] Quiere subir a bus " + c.sender + " (" + linea_bus + ")"; }
				} else {
					do refuse message: c contents: ["no_quiero_subir"];
				}
			}
		}
	}

	// Recibir accept_proposal del autobús
	reflex receive_accept when: !empty(accept_proposals) {
		loop a over: accept_proposals {
			list content <- list(a.contents);
			if (content[0] = "subida_aceptada") {
				bus_actual <- a.sender;
				en_autobus <- true;
				esperando_en_parada <- false;
				bajada_notificada <- false;
				tiempo_espera <- time - tiempo_llegada_parada;

				do remove_belief(creencia_esperando);
				do remove_belief(creencia_parada_notificada);
				do add_belief(creencia_en_bus);

				// Informar a la parada
				do start_conversation to: [parada_actual] protocol: 'no-protocol' performative: 'inform' contents: ["pasajero_sube_bus"];

				if console_logs { write "[PASAJERO " + id_pasajero + "] Sube al bus. Espera: " + tiempo_espera + "s"; }
			} else if (content[0] = "bajada_aceptada") {
				// Bajada aceptada por el bus
				autobus bus_bajada <- a.sender;
				parada parada_bajada <- bus_bajada.parada_actual_bus;

				do remove_belief(creencia_en_bus);
				en_autobus <- false;
				bus_actual <- nil;

				if (length(itinerario_destinos) > 1) {
					// Quitar el destino actual y esperar otro bus
					itinerario_destinos <- itinerario_destinos - itinerario_destinos[0];
					siguiente_destino <- itinerario_destinos[0];
					location <- parada_bajada.location;
					parada_actual <- parada_bajada;
					esperando_en_parada <- true;
					tiempo_llegada_parada <- time;
					do add_belief(creencia_esperando);
					do remove_belief(creencia_parada_notificada);
					do start_conversation to: [parada_bajada] protocol: 'no-protocol' performative: 'inform' contents: ["pasajero_llega"];
					if console_logs { write "[PASAJERO " + id_pasajero + "] Baja para transbordo en " + parada_bajada.id_parada; }
				} else {
					// Destino final
					destino_alcanzado <- true;
					tiempo_total <- time - tiempo_inicio;
					total_pasajeros_llegados <- total_pasajeros_llegados + 1;
					if console_logs { write "[PASAJERO " + id_pasajero + "] Llega a destino " + parada_bajada.id_parada; }
				}
			}
		}
	}

	// Recibir reject_proposal del autobús porque está lleno
	reflex receive_reject when: !empty(reject_proposals) {
		loop r over: reject_proposals {
			list content <- list(r.contents);
			if (content[0] = "autobus_lleno") {
				if console_logs { write "[PASAJERO " + id_pasajero + "] Bus lleno, sigue esperando"; }
			}
		}
	}

	// Recibir agrees de la parada (ETAs)
	// Si el menor ETA supera el tiempo máximo de espera del pasajero, abandona la parada
	reflex receive_agrees when: !empty(agrees) {
		loop a over: agrees {
			list content <- list(a.contents);
			if (content[0] = "tiempos_eta") {
				map<string, float> etas <- content[1];
				if (length(etas) > 0 and esperando_en_parada and !destino_alcanzado) {
					float menor_eta <- min(etas.values);
					if (menor_eta > tiempo_max_espera_pasajero) {
						esperando_en_parada <- false;
						do start_conversation to: [parada_actual] protocol: 'no-protocol' performative: 'inform' contents: ["pasajero_abandona"];
						total_pasajeros_abandonados <- total_pasajeros_abandonados + 1;
						destino_alcanzado <- true;
						if console_logs { write "[PASAJERO " + id_pasajero + "] Abandona parada " + parada_actual.id_parada + " por ETA (" + menor_eta + "s) > tiempo máx espera"; }
					}
				}
			}
		}
	}

	// Solicitar ETA cada 30s periódicamente mientras espera
	reflex solicitar_eta_periodica when: esperando_en_parada and !destino_alcanzado and (parada_actual != nil) and (time - ultima_solicitud_eta >= 30 #s) {
		ultima_solicitud_eta <- time;
		do start_conversation to: [parada_actual] protocol: 'fipa-request' performative: 'request' contents: ["solicitud_eta"];
	}

	
	// Avisar al bus de que quiero bajar en la siguiente parada
	reflex avisar_bajada when: en_autobus and (bus_actual != nil) and !destino_alcanzado and !bajada_notificada {
		if (bus_actual.parada_destino = siguiente_destino) {
			bajada_notificada <- true;
			do start_conversation to: [bus_actual] protocol: 'no-protocol' performative: 'inform' contents: ["quiero_bajar_siguiente"];
			if console_logs { write "[PASAJERO " + id_pasajero + "] Avisa al bus " + bus_actual.id_bus + " que quiere bajar en " + siguiente_destino.id_parada; }
		}
	}

	// Seguir al autobús cuando está a bordo
	reflex seguir_bus when: en_autobus and (bus_actual != nil) {
		location <- bus_actual.location;
	}

	// Abandonar parada si espera demasiado
	reflex abandonar_parada when: esperando_en_parada and (time - tiempo_llegada_parada > tiempo_max_espera_pasajero) and !destino_alcanzado {
		esperando_en_parada <- false;
		do start_conversation to: [parada_actual] protocol: 'no-protocol' performative: 'inform' contents: ["pasajero_abandona"];
		total_pasajeros_abandonados <- total_pasajeros_abandonados + 1;
		destino_alcanzado <- true;
		if console_logs { write "[PASAJERO " + id_pasajero + "] Abandona parada " + parada_actual.id_parada + " por espera excesiva"; }
	}

	// Aspecto visual
	aspect default {
		if (esperando_en_parada and !destino_alcanzado) {
			draw circle(8) color: #green border: #black;
		}
	}
}


// Experimentos
// Simulación general
experiment SimulacionAutobuses type: gui {
	parameter "Paradas inicio LineaA (IDs)" var: paradas_inicio_A;
	parameter "Paradas inicio LineaB (IDs)" var: paradas_inicio_B;
	parameter "Capacidad máxima bus" var: capacidad_maxima_bus min: 20 max: 150 init: 86;
	parameter "Velocidad bus (km/h)" var: velocidad_bus min: 10.0 max: 80.0 init: 40.0;
	parameter "Frecuencia creación buses (s)" var: frecuencia_creacion_buses min: 120.0 max: 1800.0 init: 600.0;
	parameter "Pasajeros por oleada" var: pasajeros_por_oleada min: 1 max: 20 init: 5;
	parameter "Frecuencia creación pasajeros (s)" var: frecuencia_creacion_pasajeros min: 30.0 max: 600.0 init: 120.0;
	parameter "Tiempo máx. espera pasajero (s)" var: tiempo_max_espera_pasajero min: 60.0 max: 3600.0 init: 900.0;
	parameter "Prob. bloqueo carretera" var: prob_bloqueo_carretera min: 0.0 max: 0.01 init: 0.0005;
	parameter "Prob. tráfico carretera" var: prob_trafico_carretera min: 0.0 max: 0.1 init: 0.005;
	parameter "Tiempo simulación (s)" var: max_tiempo_simulacion min: 600.0 max: 7200.0 init: 3600.0;
	parameter "Mostrar logs en consola" var: console_logs init: true;

	output synchronized: false {
		display "Mapa de Madrid" type: opengl {
			species calle aspect: default;
			species parada aspect: default;
			species autobus aspect: default;
			species pasajero aspect: default;
		}

		display "Estadísticas" type: 2d refresh: every(10 #cycles) {
			chart "Pasajeros" type: series {
				data "Generados" value: total_pasajeros_generados color: #blue;
				data "En destino" value: total_pasajeros_llegados color: #green;
				data "Abandonaron" value: total_pasajeros_abandonados color: #red;
				data "Esperando" value: length(pasajero where (each.esperando_en_parada and !each.destino_alcanzado)) color: #orange;
				data "En autobús" value: length(pasajero where each.en_autobus) color: #purple;
			}
		}

		display "Autobuses" type: 2d refresh: every(10 #cycles) {
			chart "Ocupación de autobuses" type: series {
				data "Plazas ocupadas total" value: sum(autobus collect (each.capacidad_maxima - each.plazas_disponibles)) color: #blue;
				data "Autobuses activos" value: length(autobus where (!each.ruta_completada)) color: #green;
			}
		}
	}
}

// Test: Bus lleva un pasajero a su destino
// Un autobús en 3644 debe recoger al pasajero en 4100 y llevarlo a 3720.
experiment Test_Bus_Lleva_Pasajero type: gui {
	parameter "modo_test" var: modo_test init: "test_bus_lleva_pasajero";
	parameter "Paradas inicio LineaA" var: paradas_inicio_A init: ["3644"];
	parameter "Paradas inicio LineaB" var: paradas_inicio_B init: [];
	parameter "Frecuencia creación buses" var: frecuencia_creacion_buses init: 99999.0;
	parameter "Frecuencia creación pasajeros" var: frecuencia_creacion_pasajeros init: 99999.0;
	parameter "Pasajeros por oleada" var: pasajeros_por_oleada init: 0;
	parameter "Prob. bloqueo" var: prob_bloqueo_carretera init: 0.0;
	parameter "Prob. tráfico" var: prob_trafico_carretera init: 0.0;
	parameter "Tiempo máx. espera" var: tiempo_max_espera_pasajero init: 9999.0;
	parameter "Tiempo simulación" var: max_tiempo_simulacion init: 3600.0;
	parameter "Logs" var: console_logs init: true;

	output synchronized: false {
		display "Mapa Test" type: opengl {
			species calle aspect: default;
			species parada aspect: default;
			species autobus aspect: default;
			species pasajero aspect: default;
		}

		display "Estadísticas" type: 2d refresh: every(10 #cycles) {
			chart "Pasajeros" type: series {
				data "Generados" value: total_pasajeros_generados color: #blue;
				data "En destino" value: total_pasajeros_llegados color: #green;
				data "Abandonaron" value: total_pasajeros_abandonados color: #red;
				data "Esperando" value: length(pasajero where (each.esperando_en_parada and !each.destino_alcanzado)) color: #orange;
				data "En autobús" value: length(pasajero where each.en_autobus) color: #purple;
			}
		}

		display "Autobuses" type: 2d refresh: every(10 #cycles) {
			chart "Ocupación de autobuses" type: series {
				data "Plazas ocupadas total" value: sum(autobus collect (each.capacidad_maxima - each.plazas_disponibles)) color: #blue;
				data "Autobuses activos" value: length(autobus where (!each.ruta_completada)) color: #green;
			}
		}
	}
}

global {
	bool test_pasajero_creado <- false;

	reflex test_crear_pasajero when: modo_test = "test_bus_lleva_pasajero" and !test_pasajero_creado and (time = 1 #s) {
		test_pasajero_creado <- true;
		parada p_origen <- ruta_linea_A first_with (each.id_parada = "4100");
		parada p_destino <- ruta_linea_A first_with (each.id_parada = "3720");
		if (p_origen != nil and p_destino != nil) {
			create pasajero {
				id_pasajero <- 0;
				parada_origen <- p_origen;
				parada_actual <- p_origen;
				destino_final <- p_destino;
				location <- p_origen.location;
				tiempo_llegada_parada <- time;
				do calcular_itinerario;
				ask df { bool r <- register("Pasajero", myself); }
			}
			total_pasajeros_generados <- 1;
			write "=== TEST: Pasajero creado en parada 4100 con destino 3720 ===";
		}
	}

	reflex test_verificar_pasajero when: modo_test = "test_bus_lleva_pasajero" and test_pasajero_creado {
		if (total_pasajeros_llegados >= 1) {
			write "=== TEST SUPERADO: El pasajero ha llegado a su destino (3720) en " + time + " ===";
			do pause;
		}
	}
}

// Test: Bus lleva un pasajero a su destino haciendo un transbordo
// Bus A en 2697, Bus B en 2710, pasajero en 51196 con destino 5141.
// El pasajero debe tomar LineaA hasta 51144, hacer transbordo, y luego LineaB hasta 5141.
experiment Test_Transbordo type: gui {
	parameter "modo_test" var: modo_test init: "test_transbordo";
	parameter "Paradas inicio LineaA" var: paradas_inicio_A init: ["2697"];
	parameter "Paradas inicio LineaB" var: paradas_inicio_B init: ["2710"];
	parameter "Frecuencia creación buses" var: frecuencia_creacion_buses init: 99999.0;
	parameter "Frecuencia creación pasajeros" var: frecuencia_creacion_pasajeros init: 99999.0;
	parameter "Pasajeros por oleada" var: pasajeros_por_oleada init: 0;
	parameter "Prob. bloqueo" var: prob_bloqueo_carretera init: 0.0;
	parameter "Prob. tráfico" var: prob_trafico_carretera init: 0.0;
	parameter "Tiempo máx. espera" var: tiempo_max_espera_pasajero init: 9999.0;
	parameter "Tiempo simulación" var: max_tiempo_simulacion init: 3600.0;
	parameter "Logs" var: console_logs init: true;

	output synchronized: false {
		display "Mapa Test" type: opengl {
			species calle aspect: default;
			species parada aspect: default;
			species autobus aspect: default;
			species pasajero aspect: default;
		}

		display "Estadísticas" type: 2d refresh: every(10 #cycles) {
			chart "Pasajeros" type: series {
				data "Generados" value: total_pasajeros_generados color: #blue;
				data "En destino" value: total_pasajeros_llegados color: #green;
				data "Abandonaron" value: total_pasajeros_abandonados color: #red;
				data "Esperando" value: length(pasajero where (each.esperando_en_parada and !each.destino_alcanzado)) color: #orange;
				data "En autobús" value: length(pasajero where each.en_autobus) color: #purple;
			}
		}

		display "Autobuses" type: 2d refresh: every(10 #cycles) {
			chart "Ocupación de autobuses" type: series {
				data "Plazas ocupadas total" value: sum(autobus collect (each.capacidad_maxima - each.plazas_disponibles)) color: #blue;
				data "Autobuses activos" value: length(autobus where (!each.ruta_completada)) color: #green;
			}
		}
	}
}

global {
	bool test_transbordo_creado <- false;

	reflex test_crear_transbordo when: modo_test = "test_transbordo" and !test_transbordo_creado and (time = 1 #s) {
		test_transbordo_creado <- true;
		parada p_origen <- ruta_linea_A first_with (each.id_parada = "51196");
		parada p_destino <- ruta_linea_B first_with (each.id_parada = "5141");
		if (p_origen != nil and p_destino != nil) {
			create pasajero {
				id_pasajero <- 0;
				parada_origen <- p_origen;
				parada_actual <- p_origen;
				destino_final <- p_destino;
				location <- p_origen.location;
				tiempo_llegada_parada <- time;
				do calcular_itinerario;
				ask df { bool r <- register("Pasajero", myself); }
			}
			total_pasajeros_generados <- 1;
			write "=== TEST TRANSBORDO: Pasajero en 51196 con destino 5141 ===";
		}
	}

	reflex test_verificar_transbordo when: modo_test = "test_transbordo" and test_transbordo_creado {
		if (total_pasajeros_llegados >= 1) {
			write "=== TEST TRANSBORDO SUPERADO: El pasajero llegó a 5141 en " + time + " ===";
			do pause;
		}
	}
}

// Test: Pasajeros abandonan parada cuando el ETA es excedido
// Bus en 3644. Pasajero en 5394 abandona por ETA alto.
// Pasajero en 3737 abandona por timeout sin ETA.
experiment Test_Abandono_Parada type: gui {
	parameter "modo_test" var: modo_test init: "test_abandono";
	parameter "Paradas inicio LineaA" var: paradas_inicio_A init: ["3644"];
	parameter "Paradas inicio LineaB" var: paradas_inicio_B init: [];
	parameter "Velocidad bus (km/h)" var: velocidad_bus init: 10.0;
	parameter "Frecuencia creación buses" var: frecuencia_creacion_buses init: 99999.0;
	parameter "Frecuencia creación pasajeros" var: frecuencia_creacion_pasajeros init: 99999.0;
	parameter "Pasajeros por oleada" var: pasajeros_por_oleada init: 0;
	parameter "Prob. bloqueo" var: prob_bloqueo_carretera init: 0.0;
	parameter "Prob. tráfico" var: prob_trafico_carretera init: 0.0;
	parameter "Tiempo máx. espera" var: tiempo_max_espera_pasajero init: 180.0;
	parameter "Tiempo simulación" var: max_tiempo_simulacion init: 3600.0;
	parameter "Logs" var: console_logs init: true;

	output synchronized: false {
		display "Mapa Test" type: opengl {
			species calle aspect: default;
			species parada aspect: default;
			species autobus aspect: default;
			species pasajero aspect: default;
		}

		display "Estadísticas" type: 2d refresh: every(10 #cycles) {
			chart "Pasajeros" type: series {
				data "Generados" value: total_pasajeros_generados color: #blue;
				data "En destino" value: total_pasajeros_llegados color: #green;
				data "Abandonaron" value: total_pasajeros_abandonados color: #red;
				data "Esperando" value: length(pasajero where (each.esperando_en_parada and !each.destino_alcanzado)) color: #orange;
				data "En autobús" value: length(pasajero where each.en_autobus) color: #purple;
			}
		}

		display "Autobuses" type: 2d refresh: every(10 #cycles) {
			chart "Ocupación de autobuses" type: series {
				data "Plazas ocupadas total" value: sum(autobus collect (each.capacidad_maxima - each.plazas_disponibles)) color: #blue;
				data "Autobuses activos" value: length(autobus where (!each.ruta_completada)) color: #green;
			}
		}
	}
}

global {
	bool test_abandono_creado <- false;
	int test_abandono_pasajeros_abandonados <- 0;
	bool test_abandono_p1 <- false;  // Pasajero 5394 abandonó por ETA
	bool test_abandono_p2 <- false;  // Pasajero 3737 abandonó por timeout

	reflex test_crear_abandono when: modo_test = "test_abandono" and !test_abandono_creado and (time = 1 #s) {
		test_abandono_creado <- true;
		parada p1_origen <- ruta_linea_A first_with (each.id_parada = "5394");
		parada p2_origen <- ruta_linea_A first_with (each.id_parada = "3737");
		parada p1_destino <- ruta_linea_A first_with (each.id_parada = "51144");
		parada p2_destino <- ruta_linea_A first_with (each.id_parada = "3644");
		if (p1_origen != nil and p2_origen != nil) {
			create pasajero {
				id_pasajero <- 0;
				parada_origen <- p1_origen;
				parada_actual <- p1_origen;
				destino_final <- p1_destino;
				location <- p1_origen.location;
				tiempo_llegada_parada <- time;
				do calcular_itinerario;
				ask df { bool r <- register("Pasajero", myself); }
			}
			create pasajero {
				id_pasajero <- 1;
				parada_origen <- p2_origen;
				parada_actual <- p2_origen;
				destino_final <- p2_destino;
				location <- p2_origen.location;
				tiempo_llegada_parada <- time;
				do calcular_itinerario;
				ask df { bool r <- register("Pasajero", myself); }
			}
			total_pasajeros_generados <- 2;
			write "=== TEST ABANDONO: Pasajero 0 en 5394 (abandonará por ETA), Pasajero 1 en 3737 (abandonará por timeout) ===";
		}
	}

	reflex test_verificar_abandono when: modo_test = "test_abandono" and test_abandono_creado {
		// Detectar abandonos individuales
		loop p over: pasajero where (each.destino_alcanzado and !each.en_autobus) {
			if (p.id_pasajero = 0 and !test_abandono_p1) {
				test_abandono_p1 <- true;
				write "=== TEST ABANDONO: Pasajero 0 (parada 5394) ha abandonado en " + time + " ===";
			}
			if (p.id_pasajero = 1 and !test_abandono_p2) {
				test_abandono_p2 <- true;
				write "=== TEST ABANDONO: Pasajero 1 (parada 3737) ha abandonado en " + time + " ===";
			}
		}
		if (test_abandono_p1 and test_abandono_p2) {
			write "=== TEST ABANDONO SUPERADO: Ambos pasajeros abandonaron ===";
			do pause;
		}
	}
}

// Test: Conservar velocidad al saltar parada
// Bus en 3644 sin pasajeros. Al llegar a 4100, que está vacía,
// debe saltarla sin detenerse, conservando velocidad > 0.
experiment Test_Conservar_Velocidad type: gui {
	parameter "modo_test" var: modo_test init: "test_conservar_velocidad";
	parameter "Paradas inicio LineaA" var: paradas_inicio_A init: ["3644"];
	parameter "Paradas inicio LineaB" var: paradas_inicio_B init: [];
	parameter "Frecuencia creación buses" var: frecuencia_creacion_buses init: 99999.0;
	parameter "Frecuencia creación pasajeros" var: frecuencia_creacion_pasajeros init: 99999.0;
	parameter "Pasajeros por oleada" var: pasajeros_por_oleada init: 0;
	parameter "Prob. bloqueo" var: prob_bloqueo_carretera init: 0.0;
	parameter "Prob. tráfico" var: prob_trafico_carretera init: 0.0;
	parameter "Tiempo máx. espera" var: tiempo_max_espera_pasajero init: 9999.0;
	parameter "Tiempo simulación" var: max_tiempo_simulacion init: 3600.0;
	parameter "Logs" var: console_logs init: true;

	output synchronized: false {
		display "Mapa Test" type: opengl {
			species calle aspect: default;
			species parada aspect: default;
			species autobus aspect: default;
			species pasajero aspect: default;
		}

		display "Estadísticas" type: 2d refresh: every(10 #cycles) {
			chart "Pasajeros" type: series {
				data "Generados" value: total_pasajeros_generados color: #blue;
				data "En destino" value: total_pasajeros_llegados color: #green;
				data "Abandonaron" value: total_pasajeros_abandonados color: #red;
				data "Esperando" value: length(pasajero where (each.esperando_en_parada and !each.destino_alcanzado)) color: #orange;
				data "En autobús" value: length(pasajero where each.en_autobus) color: #purple;
			}
		}

		display "Autobuses" type: 2d refresh: every(10 #cycles) {
			chart "Ocupación de autobuses" type: series {
				data "Plazas ocupadas total" value: sum(autobus collect (each.capacidad_maxima - each.plazas_disponibles)) color: #blue;
				data "Autobuses activos" value: length(autobus where (!each.ruta_completada)) color: #green;
			}
		}
	}
}

global {
	bool test_vel_parada_saltada <- false;
	float test_vel_tiempo_salto <- 0.0;

	// Cuando el bus supere la parada 4100, esperar 1s y comprobar velocidad
	reflex test_verificar_velocidad when: modo_test = "test_conservar_velocidad" and !test_vel_parada_saltada {
		if (test_vel_tiempo_salto > 0.0) {
			if (time >= test_vel_tiempo_salto + 1 #s) {
				test_vel_parada_saltada <- true;
				autobus b <- first(autobus);
				if (b.velocidad_actual > 5.0) {
					write "=== TEST CONSERVAR VELOCIDAD SUPERADO: Bus saltó parada 4100 con velocidad " + b.velocidad_actual + " m/s en " + time + " ===";
				} else {
					write "=== TEST CONSERVAR VELOCIDAD FALLIDO: Bus se detuvo al saltar parada 4100 ===";
				}
				do pause;
			}
		} else {
			loop b over: autobus {
				if (b.index_siguiente_parada > 1) {
					test_vel_tiempo_salto <- time;
				}
			}
		}
	}
}

// Test: Capacidad máxima del bus
// Bus con capacidad 50 en 3644. 51 pasajeros en 4100 con destino 4802.
// Tras pasar por la parada: 50 en el bus, 1 esperando en la parada.
experiment Test_Capacidad_Maxima type: gui {
	parameter "modo_test" var: modo_test init: "test_capacidad";
	parameter "Paradas inicio LineaA" var: paradas_inicio_A init: ["3644"];
	parameter "Paradas inicio LineaB" var: paradas_inicio_B init: [];
	parameter "Capacidad máxima bus" var: capacidad_maxima_bus init: 50;
	parameter "Frecuencia creación buses" var: frecuencia_creacion_buses init: 99999.0;
	parameter "Frecuencia creación pasajeros" var: frecuencia_creacion_pasajeros init: 99999.0;
	parameter "Pasajeros por oleada" var: pasajeros_por_oleada init: 0;
	parameter "Prob. bloqueo" var: prob_bloqueo_carretera init: 0.0;
	parameter "Prob. tráfico" var: prob_trafico_carretera init: 0.0;
	parameter "Tiempo máx. espera" var: tiempo_max_espera_pasajero init: 9999.0;
	parameter "Tiempo simulación" var: max_tiempo_simulacion init: 3600.0;
	parameter "Logs" var: console_logs init: true;

	output synchronized: false {
		display "Mapa Test" type: opengl {
			species calle aspect: default;
			species parada aspect: default;
			species autobus aspect: default;
			species pasajero aspect: default;
		}

		display "Estadísticas" type: 2d refresh: every(10 #cycles) {
			chart "Pasajeros" type: series {
				data "Generados" value: total_pasajeros_generados color: #blue;
				data "En destino" value: total_pasajeros_llegados color: #green;
				data "Abandonaron" value: total_pasajeros_abandonados color: #red;
				data "Esperando" value: length(pasajero where (each.esperando_en_parada and !each.destino_alcanzado)) color: #orange;
				data "En autobús" value: length(pasajero where each.en_autobus) color: #purple;
			}
		}

		display "Autobuses" type: 2d refresh: every(10 #cycles) {
			chart "Ocupación de autobuses" type: series {
				data "Plazas ocupadas total" value: sum(autobus collect (each.capacidad_maxima - each.plazas_disponibles)) color: #blue;
				data "Autobuses activos" value: length(autobus where (!each.ruta_completada)) color: #green;
			}
		}
	}
}

global {
	bool test_cap_creado <- false;
	bool test_cap_verificado <- false;
	float test_cap_tiempo_paso <- 0.0;

	reflex test_crear_capacidad when: modo_test = "test_capacidad" and !test_cap_creado and (time = 1 #s) {
		test_cap_creado <- true;
		parada p_origen <- ruta_linea_A first_with (each.id_parada = "4100");
		parada p_destino <- ruta_linea_A first_with (each.id_parada = "4802");
		if (p_origen != nil and p_destino != nil) {
			loop i from: 0 to: 50 {
				create pasajero {
					id_pasajero <- i;
					parada_origen <- p_origen;
					parada_actual <- p_origen;
					destino_final <- p_destino;
					location <- p_origen.location;
					tiempo_llegada_parada <- time;
					do calcular_itinerario;
					ask df { bool r <- register("Pasajero", myself); }
				}
				// Notificar a la parada
				ask p_origen {
					num_pasajeros_esperando <- num_pasajeros_esperando + 1;
				}
			}
			total_pasajeros_generados <- 51;
			write "=== TEST CAPACIDAD: 51 pasajeros creados en parada 4100 con destino 4802 ===";
		}
	}

	// Verificar 1 segundo después de que el bus haya pasado por 4100
	reflex test_verificar_capacidad when: modo_test = "test_capacidad" and test_cap_creado and !test_cap_verificado {
		if (test_cap_tiempo_paso > 0.0) {
			if (time >= test_cap_tiempo_paso + 1 #s) {
				test_cap_verificado <- true;
				autobus b <- first(autobus);
				int en_bus <- length(b.pasajeros_a_bordo);
				int en_parada <- length(pasajero where (each.esperando_en_parada and !each.destino_alcanzado));
				write "=== TEST CAPACIDAD: Pasajeros en bus = " + en_bus + ", Esperando en parada = " + en_parada + " ===";
				if (en_bus = 50 and en_parada = 1) {
					write "=== TEST CAPACIDAD SUPERADO ===";
				} else {
					write "=== TEST CAPACIDAD FALLIDO: Se esperaban 50 en bus y 1 en parada ===";
				}
				do pause;
			}
		} else {
			loop b over: autobus {
				if (b.index_siguiente_parada > 1) {
					test_cap_tiempo_paso <- time;
				}
			}
		}
	}
}

// Test: Cola de buses en parada
// 2 buses con capacidad 20 en 3644, 21 pasajeros en 4100 con destino 4802.
// Bus 1 recoge 20, bus 2 espera en cola y luego recoge al pasajero 21.
experiment Test_Cola_Buses type: gui {
	parameter "modo_test" var: modo_test init: "test_cola_buses";
	parameter "Paradas inicio LineaA" var: paradas_inicio_A init: ["3644", "3644"];
	parameter "Paradas inicio LineaB" var: paradas_inicio_B init: [];
	parameter "Capacidad máxima bus" var: capacidad_maxima_bus init: 20;
	parameter "Frecuencia creación buses" var: frecuencia_creacion_buses init: 99999.0;
	parameter "Frecuencia creación pasajeros" var: frecuencia_creacion_pasajeros init: 99999.0;
	parameter "Pasajeros por oleada" var: pasajeros_por_oleada init: 0;
	parameter "Prob. bloqueo" var: prob_bloqueo_carretera init: 0.0;
	parameter "Prob. tráfico" var: prob_trafico_carretera init: 0.0;
	parameter "Tiempo máx. espera" var: tiempo_max_espera_pasajero init: 9999.0;
	parameter "Tiempo simulación" var: max_tiempo_simulacion init: 3600.0;
	parameter "Logs" var: console_logs init: true;

	output synchronized: false {
		display "Mapa Test" type: opengl {
			species calle aspect: default;
			species parada aspect: default;
			species autobus aspect: default;
			species pasajero aspect: default;
		}

		display "Estadísticas" type: 2d refresh: every(10 #cycles) {
			chart "Pasajeros" type: series {
				data "Generados" value: total_pasajeros_generados color: #blue;
				data "En destino" value: total_pasajeros_llegados color: #green;
				data "Abandonaron" value: total_pasajeros_abandonados color: #red;
				data "Esperando" value: length(pasajero where (each.esperando_en_parada and !each.destino_alcanzado)) color: #orange;
				data "En autobús" value: length(pasajero where each.en_autobus) color: #purple;
			}
		}

		display "Autobuses" type: 2d refresh: every(10 #cycles) {
			chart "Ocupación de autobuses" type: series {
				data "Plazas ocupadas total" value: sum(autobus collect (each.capacidad_maxima - each.plazas_disponibles)) color: #blue;
				data "Autobuses activos" value: length(autobus where (!each.ruta_completada)) color: #green;
			}
		}
	}
}

global {
	bool test_cola_creado <- false;
	bool test_cola_verificado <- false;
	float test_cola_tiempo_paso <- -1.0;

	reflex test_crear_cola when: modo_test = "test_cola_buses" and !test_cola_creado and (time = 1 #s) {
		test_cola_creado <- true;
		parada p_origen <- ruta_linea_A first_with (each.id_parada = "4100");
		parada p_destino <- ruta_linea_A first_with (each.id_parada = "4802");
		if (p_origen != nil and p_destino != nil) {
			loop i from: 0 to: 20 {
				create pasajero {
					id_pasajero <- i;
					parada_origen <- p_origen;
					parada_actual <- p_origen;
					destino_final <- p_destino;
					location <- p_origen.location;
					tiempo_llegada_parada <- time;
					do calcular_itinerario;
					ask df { bool r <- register("Pasajero", myself); }
				}
				ask p_origen {
					num_pasajeros_esperando <- num_pasajeros_esperando + 1;
				}
			}
			total_pasajeros_generados <- 21;
			write "=== TEST COLA: 21 pasajeros creados en parada 4100 con destino 4802 ===";
		}
	}

	// Ambos buses deben haber superado la parada 4100 y tener 20 y 1 pasajeros
	reflex test_verificar_cola when: modo_test = "test_cola_buses" and test_cola_creado and !test_cola_verificado {
		// Esperar a que ambos buses hayan superado la parada 4100 y pase 1 segundo
		if (test_cola_tiempo_paso >= 0) {
			if (time >= test_cola_tiempo_paso + 1 #s) {
				test_cola_verificado <- true;
				list<autobus> buses <- list(autobus);
				list<int> pasajeros_por_bus <- buses collect length(each.pasajeros_a_bordo);
				int total_en_buses <- sum(pasajeros_por_bus);
				int en_parada <- length(pasajero where (each.esperando_en_parada and !each.destino_alcanzado));
				write "=== TEST COLA: Pasajeros por bus = " + pasajeros_por_bus + ", En parada = " + en_parada + " ===";
				if (total_en_buses = 21 and en_parada = 0 and (20 in pasajeros_por_bus) and (1 in pasajeros_por_bus)) {
					write "=== TEST COLA SUPERADO: Bus 1 recogió 20, Bus 2 recogió 1 ===";
				} else {
					write "=== TEST COLA FALLIDO: Se esperaban [20, 1] pasajeros en buses y 0 en parada ===";
				}
				do pause;
			}
		} else {
			list<autobus> buses <- autobus where (each.index_siguiente_parada > 1);
			if (length(buses) = 2) {
				test_cola_tiempo_paso <- time;
			}
		}
	}
}

// Test: Generación periódica
// Sin buses ni pasajeros al inicio. Frecuencia de 10s para ambos, 10 pasajeros por oleada.
// En el segundo 11 debe haber 2 buses (1 LineaA + 1 LineaB) y 10 pasajeros.
experiment Test_Generacion_Periodica type: gui {
	parameter "modo_test" var: modo_test init: "test_generacion";
	parameter "Paradas inicio LineaA" var: paradas_inicio_A init: [];
	parameter "Paradas inicio LineaB" var: paradas_inicio_B init: [];
	parameter "Frecuencia creación buses" var: frecuencia_creacion_buses init: 10.0;
	parameter "Frecuencia creación pasajeros" var: frecuencia_creacion_pasajeros init: 10.0;
	parameter "Pasajeros por oleada" var: pasajeros_por_oleada init: 10;
	parameter "Prob. bloqueo" var: prob_bloqueo_carretera init: 0.0;
	parameter "Prob. tráfico" var: prob_trafico_carretera init: 0.0;
	parameter "Tiempo máx. espera" var: tiempo_max_espera_pasajero init: 9999.0;
	parameter "Tiempo simulación" var: max_tiempo_simulacion init: 3600.0;
	parameter "Logs" var: console_logs init: true;

	output synchronized: false {
		display "Mapa Test" type: opengl {
			species calle aspect: default;
			species parada aspect: default;
			species autobus aspect: default;
			species pasajero aspect: default;
		}

		display "Estadísticas" type: 2d refresh: every(10 #cycles) {
			chart "Pasajeros" type: series {
				data "Generados" value: total_pasajeros_generados color: #blue;
				data "En destino" value: total_pasajeros_llegados color: #green;
				data "Abandonaron" value: total_pasajeros_abandonados color: #red;
				data "Esperando" value: length(pasajero where (each.esperando_en_parada and !each.destino_alcanzado)) color: #orange;
				data "En autobús" value: length(pasajero where each.en_autobus) color: #purple;
			}
		}

		display "Autobuses" type: 2d refresh: every(10 #cycles) {
			chart "Ocupación de autobuses" type: series {
				data "Plazas ocupadas total" value: sum(autobus collect (each.capacidad_maxima - each.plazas_disponibles)) color: #blue;
				data "Autobuses activos" value: length(autobus where (!each.ruta_completada)) color: #green;
			}
		}
	}
}

global {
	reflex test_verificar_generacion when: modo_test = "test_generacion" and (time = 11 #s) {
		int num_buses <- length(autobus);
		int num_pasajeros <- total_pasajeros_generados;
		write "=== TEST GENERACIÓN: Buses = " + num_buses + ", Pasajeros generados = " + num_pasajeros + " ===";
		if (num_buses = 2 and num_pasajeros >= 10) {
			write "=== TEST GENERACIÓN SUPERADO ===";
		} else {
			write "=== TEST GENERACIÓN FALLIDO: Se esperaban 2 buses y 10 pasajeros ===";
		}
		do pause;
	}
}
// Test: Tráfico reduce velocidad
// Bus en 3644. Las calles cercanas a la parada 4100 tienen tráfico.
// Se comprueba que al llegar ahí el bus va a la mitad de la velocidad máxima.
experiment Test_Trafico_Velocidad type: gui {
	parameter "modo_test" var: modo_test init: "test_trafico_velocidad";
	parameter "Paradas inicio LineaA" var: paradas_inicio_A init: ["3644"];
	parameter "Paradas inicio LineaB" var: paradas_inicio_B init: [];
	parameter "Frecuencia creación buses" var: frecuencia_creacion_buses init: 99999.0;
	parameter "Frecuencia creación pasajeros" var: frecuencia_creacion_pasajeros init: 99999.0;
	parameter "Pasajeros por oleada" var: pasajeros_por_oleada init: 0;
	parameter "Prob. bloqueo" var: prob_bloqueo_carretera init: 0.0;
	parameter "Prob. tráfico" var: prob_trafico_carretera init: 0.0;
	parameter "Tiempo máx. espera" var: tiempo_max_espera_pasajero init: 9999.0;
	parameter "Tiempo simulación" var: max_tiempo_simulacion init: 3600.0;
	parameter "Logs" var: console_logs init: true;

	output synchronized: false {
		display "Mapa Test" type: opengl {
			species calle aspect: default;
			species parada aspect: default;
			species autobus aspect: default;
			species pasajero aspect: default;
		}

		display "Estadísticas" type: 2d refresh: every(10 #cycles) {
			chart "Pasajeros" type: series {
				data "Generados" value: total_pasajeros_generados color: #blue;
				data "En destino" value: total_pasajeros_llegados color: #green;
				data "Abandonaron" value: total_pasajeros_abandonados color: #red;
				data "Esperando" value: length(pasajero where (each.esperando_en_parada and !each.destino_alcanzado)) color: #orange;
				data "En autobús" value: length(pasajero where each.en_autobus) color: #purple;
			}
		}

		display "Autobuses" type: 2d refresh: every(10 #cycles) {
			chart "Ocupación de autobuses" type: series {
				data "Plazas ocupadas total" value: sum(autobus collect (each.capacidad_maxima - each.plazas_disponibles)) color: #blue;
				data "Autobuses activos" value: length(autobus where (!each.ruta_completada)) color: #green;
			}
		}
	}
}

global {
	bool test_trafico_setup <- false;
	bool test_trafico_verificado <- false;

	// Marcar con tráfico todas las calles cercanas a la parada 4100
	reflex test_trafico_init when: modo_test = "test_trafico_velocidad" and !test_trafico_setup and (time = 1 #s) {
		test_trafico_setup <- true;
		parada p4100 <- ruta_linea_A first_with (each.id_parada = "4100");
		if (p4100 != nil) {
			list<calle> calles_cercanas <- calle where (each.shape distance_to p4100.location < 50.0 #m);
			loop c over: calles_cercanas {
				ask c {
					con_trafico <- true;
					color <- #orange;
				}
			}
			write "=== TEST TRÁFICO: " + length(calles_cercanas) + " calles con tráfico cerca de parada 4100 ===";
		}
	}

	// Cuando el bus esté cerca de la parada 4100, su velocidad debe ser menor o igual que velocidad_maxima/2
	reflex test_trafico_check when: modo_test = "test_trafico_velocidad" and test_trafico_setup and !test_trafico_verificado {
		autobus b <- first(autobus);
		if (b != nil) {
			parada p4100 <- ruta_linea_A first_with (each.id_parada = "4100");
			if (p4100 != nil and b.location distance_to p4100.location < 50.0 #m and b.velocidad_actual > 0) {
				test_trafico_verificado <- true;
				float vel_esperada <- b.velocidad_maxima / 2.0;
				float vel_real <- b.velocidad_actual;
				write "=== TEST TRÁFICO: Vel. actual = " + vel_real + " m/s, Vel. esperada (máx/2) = " + vel_esperada + " m/s ===";
				if (vel_real <= vel_esperada + 0.01) {
					write "=== TEST TRÁFICO SUPERADO: Bus circula a la mitad de velocidad por tráfico ===";
				} else {
					write "=== TEST TRÁFICO FALLIDO: Bus supera la velocidad esperada ===";
				}
				do pause;
			}
		}
	}
}

// Test: Calles bloqueadas
// Bus en 4614. Se bloquean todas las calles de acceso a la parada 51197.
// Se comprueba que el bus la evita y alcanza la parada siguiente, 782.
experiment Test_Calles_Bloqueadas type: gui {
	parameter "modo_test" var: modo_test init: "test_calles_bloqueadas";
	parameter "Paradas inicio LineaA" var: paradas_inicio_A init: ["4614"];
	parameter "Paradas inicio LineaB" var: paradas_inicio_B init: [];
	parameter "Frecuencia creación buses" var: frecuencia_creacion_buses init: 99999.0;
	parameter "Frecuencia creación pasajeros" var: frecuencia_creacion_pasajeros init: 99999.0;
	parameter "Pasajeros por oleada" var: pasajeros_por_oleada init: 0;
	parameter "Prob. bloqueo" var: prob_bloqueo_carretera init: 0.0;
	parameter "Prob. tráfico" var: prob_trafico_carretera init: 0.0;
	parameter "Tiempo máx. espera" var: tiempo_max_espera_pasajero init: 9999.0;
	parameter "Tiempo simulación" var: max_tiempo_simulacion init: 3600.0;
	parameter "Logs" var: console_logs init: true;

	output synchronized: false {
		display "Mapa Test" type: opengl {
			species calle aspect: default;
			species parada aspect: default;
			species autobus aspect: default;
			species pasajero aspect: default;
		}

		display "Estadísticas" type: 2d refresh: every(10 #cycles) {
			chart "Pasajeros" type: series {
				data "Generados" value: total_pasajeros_generados color: #blue;
				data "En destino" value: total_pasajeros_llegados color: #green;
				data "Abandonaron" value: total_pasajeros_abandonados color: #red;
				data "Esperando" value: length(pasajero where (each.esperando_en_parada and !each.destino_alcanzado)) color: #orange;
				data "En autobús" value: length(pasajero where each.en_autobus) color: #purple;
			}
		}

		display "Autobuses" type: 2d refresh: every(10 #cycles) {
			chart "Ocupación de autobuses" type: series {
				data "Plazas ocupadas total" value: sum(autobus collect (each.capacidad_maxima - each.plazas_disponibles)) color: #blue;
				data "Autobuses activos" value: length(autobus where (!each.ruta_completada)) color: #green;
			}
		}
	}
}

global {
	bool test_bloqueo_setup <- false;
	bool test_bloqueo_verificado <- false;
	int test_bloqueo_calles_bloqueadas <- 0;

	// Bloquear todas las calles cercanas a la parada 51197
	reflex test_bloqueo_init when: modo_test = "test_calles_bloqueadas" and !test_bloqueo_setup and (time = 1 #s) {
		test_bloqueo_setup <- true;
		parada p51197 <- ruta_linea_A first_with (each.id_parada = "51197");
		if (p51197 != nil) {
			list<calle> calles_cercanas <- calle where (each.shape distance_to p51197.location < 50.0 #m);
			test_bloqueo_calles_bloqueadas <- length(calles_cercanas);
			loop c over: calles_cercanas {
				ask c {
					bloqueada <- true;
					color <- #red;
				}
			}
			// Reconstruir el grafo sin las calles bloqueadas
			red_viaria <- as_edge_graph(calle where (!each.bloqueada));
			write "=== TEST BLOQUEO: " + test_bloqueo_calles_bloqueadas + " calles bloqueadas cerca de parada 51197 ===";
		}
	}

	// El bus debe llegar a la parada 782
	reflex test_bloqueo_check when: modo_test = "test_calles_bloqueadas" and test_bloqueo_setup and !test_bloqueo_verificado {
		autobus b <- first(autobus);
		parada p782 <- ruta_linea_A first_with (each.id_parada = "782");
		if (b != nil and p782 != nil and b.location distance_to p782.location < 5.0 #m) {
			test_bloqueo_verificado <- true;
			write "=== TEST BLOQUEO: Bus llegó a parada 782 evitando la parada 51197 bloqueada ===";
			write "=== TEST BLOQUEO SUPERADO: Bus evitó las " + test_bloqueo_calles_bloqueadas + " calles bloqueadas y siguió su ruta ===";
			do pause;
		}
	}
}
