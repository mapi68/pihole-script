#!/usr/bin/env bash
#
# Confronta le liste di blocco di Pi-hole e dà consigli su cosa tenere o togliere.
# Lingua predefinita: inglese. Con --it i testi sono in italiano.
# Uso, opzioni e formati supportati: ./pihole-overlap-audit.bash --help

# Lingua: letta subito, così vale anche per --help e per gli errori.
lingua=en
for a in "$@"; do
    if [ "$a" = "--" ]; then break; fi
    if [ "$a" = "--it" ]; then lingua=it; fi
done

if [ "${BASH_VERSINFO[0]}" -lt 4 ]; then
    if [ "$lingua" = "it" ]; then
        echo "Serve bash 4 o successivo (questo è bash $BASH_VERSION)." >&2
    else
        echo "Bash 4 or later is required (this is bash $BASH_VERSION)." >&2
    fi
    exit 1
fi

set -euo pipefail
export LC_ALL=C

# Soglie usate per i consigli finali (modificabili)
SOGLIA_RIMUOVI=90       # % della lista già coperta dalle altre: sopra, conviene toglierla
SOGLIA_VALUTA=70        # % della lista già coperta dalle altre: sopra, vale la pena valutare
SOGLIA_UNICI_TRASCURABILI=100  # domini unici: sotto, con copertura almeno SOGLIA_VALUTA, si può togliere
SOGLIA_SIMILI=50        # % reciproca tra due liste: sopra, le liste sono molto simili
SOGLIA_EVIDENZIA=30     # % tra due liste: sopra, la sovrapposizione viene evidenziata in tabella
SOGLIA_CONTENUTA=80     # % di una lista presente in un'altra: sopra, è quasi un suo sottoinsieme
SOGLIA_GRANDE=1000000   # domini: sopra, la lista pesa parecchio in RAM e in aggiornamento
SOGLIA_GENERALISTA=100000  # domini: sopra, la lista è una generalista di grandi dimensioni
SOGLIA_PICCOLA=1000     # domini: sotto, la lista è molto piccola
SOGLIA_POCHI_UNICI=1000 # domini unici: sotto, il contributo della lista è marginale

# --- testi mostrati a schermo ---
# m NOME "testo italiano" "testo inglese": definisce la variabile NOME nella lingua scelta.
# Nei testi usati con printf, %s e %d devono restare nello stesso ordine nelle due lingue.
m() { if [ "$lingua" = "it" ]; then printf -v "$1" '%s' "$2"; else printf -v "$1" '%s' "$3"; fi; }

# opzioni, errori e raccolta delle liste
m M_UNKNOWN_OPT "Opzione sconosciuta: %s (vedi --help)\n" "Unknown option: %s (see --help)\n"
m M_NEED2 "Servono almeno 2 liste valide da confrontare." "At least 2 valid lists are needed to compare."
m M_PIHOLE_FOUND "Liste di Pi-hole trovate in %s: %s.\n" "Pi-hole lists found in %s: %s.\n"
m M_STATE_OK "%d attive, %d ignorate perché disabilitate" "%d active, %d ignored because disabled"
m M_STATE_UNK "%d (stato attivo/disabilitato non verificabile)" "%d (enabled/disabled status could not be checked)"
m M_NO_DIR "Directory Pi-hole non trovata in questo ambiente (%s): procedo con le liste locali." "Pi-hole directory not found in this environment (%s): using local lists."
m M_NO_LISTS "Nessuna lista di Pi-hole trovata in %s (se non riesci a leggerla, prova con sudo)." "No Pi-hole lists found in %s (if you cannot read it, try sudo)."
m M_SCRIPT_DIR "Cerco le liste nella cartella dello script (%s).\n\n" "Looking for lists in the script folder (%s).\n\n"
m M_NOT_FOUND "Non trovato: %s\n" "Not found: %s\n"
m M_DENIED "Permesso negato su %s: prova a lanciare lo script con sudo.\n" "Permission denied on %s: try running the script with sudo.\n"
m M_IGNORED "Ignorato %s: non contiene domini riconoscibili." "Ignored %s: no recognizable domains."
m M_SQL_OPTION "gravity.db non usato (opzione --no-sqlite): analizzo tutte le liste trovate, anche quelle disabilitate." "gravity.db not used (--no-sqlite option): analyzing all the lists found, including disabled ones."
m M_SQL_MISSING "sqlite3 non è installato: non posso sapere quali liste sono disabilitate, le analizzo tutte." "sqlite3 is not installed: cannot tell which lists are disabled, analyzing all of them."
m M_SQL_NODB "gravity.db non trovato (%s): non posso sapere quali liste sono disabilitate, le analizzo tutte." "gravity.db not found (%s): cannot tell which lists are disabled, analyzing all of them."
m M_SQL_DENIED "gravity.db non leggibile (%s): prova con sudo. Intanto analizzo tutte le liste trovate, anche quelle disabilitate." "gravity.db is not readable (%s): try sudo. Meanwhile analyzing all the lists found, including disabled ones."
m M_MISSING "list.%s (%s) è abilitata ma non ha un file scaricato%s: lancia pihole -g." "list.%s (%s) is enabled but has no downloaded file%s: run pihole -g."
m M_MISSING_FAILED " (download non riuscito, nessuna copia locale)" " (download failed, no local copy)"
m M_SQL_EMPTY "gravity.db non ha restituito liste attive: analizzo tutte le liste trovate." "gravity.db returned no enabled lists: analyzing all the lists found."

# categorie stimate
m M_CAT_GEN "Generica" "Generic"
m M_CAT_PHISH "Phishing/frodi" "Phishing/fraud"
m M_CAT_MAL "Malware/sicurezza" "Malware/security"
m M_CAT_PRIV "Privacy" "Privacy"
m M_CAT_TRK "Tracker" "Trackers"
m M_CAT_ADS "Pubblicità" "Advertising"

# tabelle e riepilogo
m M_NONE "nessuna." "none."
m M_H_PERLIST "Domini per lista (senza duplicati interni, categoria stimata):" "Domains per list (no internal duplicates, estimated category):"
m M_H_PAIRS "Doppioni tra coppie di liste (ordinati per numero di domini in comune):" "Overlap between pairs of lists (sorted by number of shared domains):"
m M_C_A "LISTA A" "LIST A"
m M_C_B "LISTA B" "LIST B"
m M_C_SHARED "COMUNI" "SHARED"
m M_C_PA "% DI A" "% OF A"
m M_C_PB "% DI B" "% OF B"
m M_TOT "Domini distinti in totale: %d\n" "Distinct domains in total: %d\n"
m M_MULTI "Presenti in più liste: %d (%s%%)\n" "Present in more than one list: %d (%s%%)\n"
m M_SUM "Domini sommando tutte le liste: %d %s(Pi-hole li deduplica, ma scarica e analizza tutto a ogni aggiornamento)%s\n" "Domains summing all lists: %d %s(Pi-hole deduplicates them, but downloads and parses everything on every update)%s\n"
m M_H_UNIQ "Contributo unico di ogni lista (domini che non compaiono in nessun'altra):" "Unique contribution of each list (domains that appear in no other list):"
m M_C_LIST "LISTA" "LIST"
m M_C_DOMAINS "DOMINI" "DOMAINS"
m M_C_UNIQUE "UNICI" "UNIQUE"
m M_C_COVERED "% COPERTA" "% COVERED"

# consigli
m M_BANNER "=============================== CONSIGLI ===============================" "================================ ADVICE ================================"
m L_PROTECT "[PROTEGGI]" "[PROTECT] "
m L_REMOVE "[RIMUOVI] " "[REMOVE]  "
m L_REVIEW "[VALUTA]  " "[REVIEW]  "
m L_KEEP "[TIENI]   " "[KEEP]    "
m M_S1 "1. Valutazione di ogni lista rispetto a tutte le altre insieme:" "1. Assessment of each list against all the others combined:"
m M_S1_PROTECT "%s [%s]: coperta al %s%%, porta %d domini unici. Categoria specialistica: verifica la fonte prima di disattivarla." "%s [%s]: covered %s%%, brings %d unique domains. Specialist category: check the source before disabling it."
m M_S1_REMOVE "%s: coperta al %s, porta solo %d domini unici (%s%% del totale)." "%s: covered %s, brings only %d unique domains (%s%% of the total)."
m M_S1_REVIEW "%s: coperta al %s, togliendola perderesti %d domini unici (%s%% del totale)." "%s: covered %s, removing it would lose %d unique domains (%s%% of the total)."
m M_S1_KEEP "%s: coperta solo al %s, porta %d domini unici." "%s: covered only %s, brings %d unique domains."
m M_S2 "2. Simulazione di rimozione (copertura almeno %s%%, oppure %s%% con meno di %s domini unici):" "2. Removal simulation (coverage of at least %s%%, or %s%% with fewer than %s unique domains):"
m M_S2_NONE "  Nessuna lista è abbastanza ridondante: nessuna rimozione è davvero sicura." "  No list is redundant enough: no removal is really safe."
m M_S2_REMOVE "  - togli %s\n" "  - remove %s\n"
m M_S2_LOST "  Domini bloccati persi: %d su %d (%s).\n" "  Blocked domains lost: %d of %d (%s).\n"
m M_S2_DL "  Domini da scaricare e analizzare a ogni aggiornamento: %d, dopo la pulizia %d (-%s%%).\n" "  Domains to download and parse on every update: %d, after cleanup %d (-%s%%).\n"
m M_S3 "3. Liste quasi interamente contenute in un'altra (almeno %s%%):" "3. Lists almost entirely contained in another (at least %s%%):"
m M_S3_LINE "  %s è contenuta al %s%% in %s.\n" "  %s is %s%% contained in %s.\n"
m M_S4 "4. Coppie molto simili (sovrapposizione reciproca di almeno %s%%):" "4. Very similar pairs (mutual overlap of at least %s%%):"
m M_S4_LINE "  %s e %s: %s%% / %s%% in comune. Valuta di tenerne una sola.\n" "  %s and %s: %s%% / %s%% shared. Consider keeping only one.\n"
m M_S5 "5. Liste con un contributo marginale:" "5. Lists with a marginal contribution:"
m M_S5_SPEC "  %s [%s]: contributo numerico ridotto, ma categoria specialistica; non valutare solo i doppioni.\n" "  %s [%s]: small numerical contribution, but a specialist category; do not judge by overlap alone.\n"
m M_S5_SMALL "  %s: solo %d domini. Il vantaggio numerico può essere limitato; valuta lo scopo della fonte.\n" "  %s: only %d domains. The numerical benefit may be limited; consider the purpose of the source.\n"
m M_S5_FEW "  %s: solo %d domini unici su %d. Aggiunge poco rispetto alle altre.\n" "  %s: only %d unique domains out of %d. It adds little compared to the others.\n"
m M_S6 "6. Efficienza delle liste (quota di domini che solo loro bloccano):" "6. List efficiency (share of domains that only they block):"
m M_S6_BEST "  Più efficiente: %s (domini unici: %s%%).\n" "  Most efficient: %s (unique domains: %s%%).\n"
m M_S6_WORST "  Meno efficiente: %s (domini unici: %s%%).\n" "  Least efficient: %s (unique domains: %s%%).\n"
m M_S6_SAME "  Tutte le liste hanno la stessa quota di domini unici (%s%%).\n" "  All lists have the same share of unique domains (%s%%).\n"
m M_S7 "7. Liste pesanti (oltre %s domini):" "7. Heavy lists (over %s domains):"
m M_S7_LINE "  %s: %d domini. Se l'aggiornamento (pihole -g) è lento o la RAM scarseggia, cerca una versione più leggera.\n" "  %s: %d domains. If the update (pihole -g) is slow or RAM is tight, look for a lighter version.\n"
m M_S8 "8. Dimensione delle liste e rischio di falsi positivi (oltre %s domini):" "8. List size and false-positive risk (over %s domains):"
m M_S8_COUNT "  Liste ampie: %d (generiche: %d, specialistiche riconosciute: %d).\n" "  Large lists: %d (generic: %d, recognized specialist: %d).\n"
m M_S8_MANY "  Più liste generiche ampie possono aumentare i falsi positivi: controlla il Query Log e usa una allowlist per le eccezioni necessarie." "  Several large generic lists can increase false positives: check the Query Log and use an allowlist for the exceptions you need."
m M_S8_ONE "  Controlla il Query Log dopo gli aggiornamenti; la sola dimensione non dimostra che la lista causi falsi positivi." "  Check the Query Log after updates; size alone does not prove that the list causes false positives."
m M_S8_SPEC "  Le feed specialistiche possono avere un valore di sicurezza distinto: non valutarle solo per dimensione o sovrapposizione." "  Specialist feeds may have a distinct security value: do not judge them by size or overlap alone."
m M_S9 "9. Cosa fare adesso:" "9. What to do now:"
m M_S9_1 "  1. Dall'interfaccia web di Pi-hole, nella sezione delle liste, disattiva (non eliminare) queste liste:" "  1. In the Pi-hole web interface, in the lists section, disable (do not delete) these lists:"
m M_S9_2 "  2. Aggiorna il gravity con: pihole -g" "  2. Update gravity with: pihole -g"
m M_S9_3 "  3. Per qualche giorno guarda il Query Log: se un sito che ti serve viene bloccato, riattiva la lista." "  3. Watch the Query Log for a few days: if a site you need gets blocked, re-enable the list."
m M_S9_4 "  4. Se non ci sono problemi, elimina definitivamente le liste disattivate." "  4. If there are no problems, delete the disabled lists for good."
m M_S9_TRY "  Nessuna rimozione sicura. Se vuoi snellire, prova a disattivare una lista alla volta, partendo da:\n       %s (coperta al %s)\n" "  No removal is safe. To slim things down, try disabling one list at a time, starting with:\n       %s (covered %s)\n"
m M_S9_THEN "  Poi lancia pihole -g e controlla il Query Log per qualche giorno." "  Then run pihole -g and check the Query Log for a few days."
m M_S9_OK "  %sLa configurazione è già efficiente%s: ogni lista porta domini che le altre non hanno. Nessuna azione necessaria.\n" "  %sThe setup is already efficient%s: every list brings domains the others do not have. No action needed.\n"
m M_S9_RERUN "Dopo ogni modifica puoi rilanciare questo script per verificare il nuovo equilibrio." "After any change you can run this script again to check the new balance."
m M_NOTE "Nota: la categoria è stimata da nome, titolo e indirizzo della lista, non dal contenuto. Controlla sempre la fonte e i possibili falsi positivi prima di modificare la configurazione." "Note: the category is estimated from the list name, title and address, not from the content. Always check the source and possible false positives before changing the configuration."

# --- aiuto e opzioni ---
mostra_aiuto() {
    local s=${0##*/}
    if [ "$lingua" = "it" ]; then
        cat <<USO
Confronta le liste di blocco di Pi-hole: mostra la percentuale di domini in
comune tra ogni coppia di liste e dà consigli finali su cosa tenere o togliere.

Uso:
  $s [opzioni] [cartella/ | lista1 lista2 ...]

  Senza percorsi: liste scaricate da Pi-hole; se non ce ne sono, i file
                  della cartella dello script.
  Con cartella:   i .txt, .list e .hosts al suo interno.
  Con file:       solo quelli indicati (almeno 2).

Opzioni:
  -h, --help   mostra questo aiuto
  --it         mostra i testi in italiano (predefinito: inglese)
  --color      forza i colori anche se l'output è rediretto (utile con less -R)
  --no-color   disattiva i colori
  --no-clear   non pulisce lo schermo all'avvio
  --no-sqlite  non legge gravity.db: analizza tutte le liste trovate, anche
               quelle disabilitate, e prende i nomi solo dai file

Liste di Pi-hole:
  Senza percorsi lo script cerca list.*.domains in /etc/pihole e in
  /etc/pihole/listsCache (per un'altra cartella imposta PIHOLE_DIR).
  Per leggerle potrebbe servire sudo. Se sqlite3 è installato, legge anche
  gravity.db per ignorare le liste disabilitate e mostrare il nome di ognuna.
  Segnala anche le liste abilitate che non hanno ancora un file scaricato.
  Per non usarlo: --no-sqlite.

Formati supportati:
  domini semplici, hosts (127.0.0.1 dominio), Adblock (||dominio^).
  Commenti, regole cosmetiche e righe di eccezione (@@) vengono ignorati.

Colori:
  verde, giallo e rosso indicano solo lo stato (tieni, valuta, rimuovi) e gli
  avvisi; il resto usa solo grassetto e testo attenuato.

Soglie (modificabili all'inizio dello script):
  rimuovi       lista coperta almeno al ${SOGLIA_RIMUOVI}% dalle altre
  valuta        lista coperta almeno al ${SOGLIA_VALUTA}% dalle altre
  trascurabile  meno di ${SOGLIA_UNICI_TRASCURABILI} domini unici (con copertura almeno ${SOGLIA_VALUTA}%)
  simili        sovrapposizione reciproca di almeno ${SOGLIA_SIMILI}%
  contenuta     lista presente per almeno ${SOGLIA_CONTENUTA}% in un'altra

Note:
  La categoria è stimata da nome, titolo e indirizzo della lista: non è una
  verifica della fonte. Le liste di phishing, malware, privacy e tracker non
  vengono mai proposte per la rimozione automatica. Controlla sempre la fonte
  prima di modificare la configurazione.
USO
    else
        cat <<USO
Compares Pi-hole blocklists: shows the percentage of domains shared by every
pair of lists and gives final advice on what to keep or remove.

Usage:
  $s [options] [folder/ | list1 list2 ...]

  No paths:      lists downloaded by Pi-hole; if there are none, the files
                 in the script's folder.
  With a folder: the .txt, .list and .hosts files inside it.
  With files:    only those given (at least 2).

Options:
  -h, --help   show this help
  --it         show all text in Italian (default: English)
  --color      force colors even when the output is redirected (useful with less -R)
  --no-color   disable colors
  --no-clear   do not clear the screen at startup
  --no-sqlite  do not read gravity.db: analyze all the lists found, including
               disabled ones, and take the names from the files only

Pi-hole lists:
  With no paths the script looks for list.*.domains in /etc/pihole and in
  /etc/pihole/listsCache (set PIHOLE_DIR to use another folder).
  Reading them may require sudo. If sqlite3 is installed, it also reads
  gravity.db to skip disabled lists and show the name of each one.
  It also reports enabled lists that have no downloaded file yet.
  Use --no-sqlite to skip this.

Supported formats:
  plain domains, hosts (127.0.0.1 domain), Adblock (||domain^).
  Comments, cosmetic rules and exception lines (@@) are ignored.

Colors:
  green, yellow and red only indicate status (keep, review, remove) and
  warnings; everything else uses bold and dim text only.

Thresholds (editable at the top of the script):
  remove        list covered at least ${SOGLIA_RIMUOVI}% by the others
  review        list covered at least ${SOGLIA_VALUTA}% by the others
  negligible    fewer than ${SOGLIA_UNICI_TRASCURABILI} unique domains (with coverage of at least ${SOGLIA_VALUTA}%)
  similar       mutual overlap of at least ${SOGLIA_SIMILI}%
  contained     list present for at least ${SOGLIA_CONTENUTA}% in another one

Notes:
  The category is estimated from the list name, title and address: it is not
  a check of the source. Phishing, malware, privacy and tracker lists are never
  proposed for automatic removal. Always check the source before changing
  your configuration.
USO
    fi
}

colori=auto
pulisci=si
usa_sqlite=si
args=()
while [ "$#" -gt 0 ]; do
    case "$1" in
        -h|--help) mostra_aiuto; exit 0 ;;
        --it) ;;  # già gestita all'inizio
        --color) colori=si ;;
        --no-color) colori=no ;;
        --no-clear) pulisci=no ;;
        --no-sqlite) usa_sqlite=no ;;
        --) shift; args+=("$@"); break ;;
        -?*) printf "$M_UNKNOWN_OPT" "$1" >&2; exit 2 ;;
        *) args+=("$1") ;;
    esac
    shift
done
set -- "${args[@]+"${args[@]}"}"

# Pulisci solo un terminale interattivo: nei log/file rediretti evita
# di inserire sequenze ANSI non leggibili.
if [ "$pulisci" = "si" ] && [ -t 1 ]; then
    clear 2>/dev/null || printf '\033[2J\033[H'
fi

if [ "$colori" = "si" ] || { [ "$colori" = "auto" ] && [ -t 1 ]; }; then
    BOLD=$'\033[1m'; DIM=$'\033[2m'; RESET=$'\033[0m'
    ROSSO=$'\033[31m'; VERDE=$'\033[32m'; GIALLO=$'\033[33m'
else
    BOLD=""; DIM=""; RESET=""; ROSSO=""; VERDE=""; GIALLO=""
fi

# --- funzioni di supporto ---

# confronti numerici con decimali e percentuali
ge() { awk -v a="$1" -v b="$2" 'BEGIN { exit !(a >= b) }'; }
gt() { awk -v a="$1" -v b="$2" 'BEGIN { exit !(a >  b) }'; }
perc() { awk -v a="$1" -v b="$2" 'BEGIN { printf "%.2f", b ? a*100/b : 0 }'; }

# Una lista si può togliere se è coperta almeno al SOGLIA_RIMUOVI% dalle altre,
# oppure se è coperta almeno al SOGLIA_VALUTA% e porta meno di
# SOGLIA_UNICI_TRASCURABILI domini unici (togliendola se ne perdono pochissimi).
# Argomenti: % coperta, domini unici
rimovibile() {
    ge "$1" "$SOGLIA_RIMUOVI" || { ge "$1" "$SOGLIA_VALUTA" && [ "$2" -lt "$SOGLIA_UNICI_TRASCURABILI" ]; }
}

# colore in base alla % già coperta dalle altre liste (secondo argomento opzionale: domini unici)
colore_cop() {
    if rimovibile "$1" "${2:-999999999}"; then printf '%s' "$ROSSO"
    elif ge "$1" "$SOGLIA_VALUTA"; then printf '%s' "$GIALLO"
    else printf '%s' "$VERDE"
    fi
}

# formattazione
pcol() { printf '%s%s%%%s' "$(colore_cop "$1" "${2:-999999999}")" "$1" "$RESET"; }
titolo_sez() { printf '%s%s%s\n' "$BOLD" "$1" "$RESET"; }
nessuna() { printf '  %s%s%s\n' "$DIM" "$M_NONE" "$RESET"; }
avviso() { printf '%s%s%s\n' "$GIALLO" "$1" "$RESET"; }

# Riga di verdetto: colore, etichetta, formato, argomenti del formato
verdetto() {
    local colore=$1 etichetta=$2 formato=$3
    shift 3
    printf '  %s%s%s ' "$BOLD$colore" "$etichetta" "$RESET"
    printf "$formato\n" "$@"
}

verifica_numero_liste() {
    if [ "$1" -lt 2 ]; then
        echo "$M_NEED2" >&2
        exit 1
    fi
}

# --- liste di Pi-hole ---
DIR_SCRIPT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
DIR_PIHOLE=${PIHOLE_DIR:-/etc/pihole}
GRAVITY_DB="$DIR_PIHOLE/gravity.db"
modo_pihole=0
files=()

# Liste scaricate da Pi-hole: list.<id>.<dominio>.domains
# (v5 in /etc/pihole, v6 in /etc/pihole/listsCache)
trova_liste_pihole() {
    local d
    for d in "$DIR_PIHOLE" "$DIR_PIHOLE/listsCache"; do
        if [ -d "$d" ]; then
            find "$d" -maxdepth 1 -type f -name '*.domains' -regex '.*/list\.[0-9]+\..*' 2>/dev/null
        fi
    done | sort -V
}

id_da_file() {
    local b=${1##*/}
    b=${b#list.}
    printf '%s' "${b%%.*}"
}

# Motivo per cui gravity.db non si può usare (nessun output se è utilizzabile)
motivo_sqlite() {
    if [ "$usa_sqlite" = "no" ]; then echo "option"
    elif ! command -v sqlite3 > /dev/null 2>&1; then echo "missing"
    elif [ ! -e "$GRAVITY_DB" ]; then echo "nodb"
    elif [ ! -r "$GRAVITY_DB" ]; then echo "denied"
    fi
}

sqlite_disponibile() { [ -z "$(motivo_sqlite)" ]; }

# Spiega perché lo stato attivo/disabilitato non è stato verificato
avviso_sqlite() {
    case "$(motivo_sqlite)" in
        option) printf '%s%s%s\n' "$DIM" "$M_SQL_OPTION" "$RESET" ;;
        missing) avviso "$M_SQL_MISSING" ;;
        nodb) avviso "$(printf "$M_SQL_NODB" "$GRAVITY_DB")" ;;
        denied) avviso "$(printf "$M_SQL_DENIED" "$GRAVITY_DB")" ;;
        *) avviso "$M_SQL_EMPTY" ;;
    esac
}

# ID delle liste attive (non disabilitate), se gravity.db è leggibile
ids_attivi() {
    sqlite_disponibile || return 1
    sqlite3 "$GRAVITY_DB" "SELECT id FROM adlist WHERE enabled=1 AND type=0;" 2> /dev/null \
        || sqlite3 "$GRAVITY_DB" "SELECT id FROM adlist WHERE enabled=1;" 2> /dev/null
}

# Indirizzo e commento di una lista, dato il suo id: "indirizzo|commento"
info_adlist() {
    sqlite_disponibile || return 0
    [[ "$1" =~ ^[0-9]+$ ]] || return 0
    sqlite3 "$GRAVITY_DB" "SELECT address, coalesce(comment, '') FROM adlist WHERE id=$1;" \
        2> /dev/null || true
}

# Esito dell'ultimo download di una lista (colonna status di adlist), se disponibile
stato_adlist() {
    sqlite_disponibile || return 0
    [[ "$1" =~ ^[0-9]+$ ]] || return 0
    sqlite3 "$GRAVITY_DB" "SELECT status FROM adlist WHERE id=$1;" 2> /dev/null || true
}

# Avvisa per ogni lista abilitata nel database ma senza file scaricato (array "mancanti")
segnala_mancanti() {
    local id indirizzo commento esito motivo
    for id in "${mancanti[@]+"${mancanti[@]}"}"; do
        indirizzo=""; commento=""
        IFS='|' read -r indirizzo commento < <(info_adlist "$id") || true
        indirizzo=${indirizzo#*://}
        if [ "${#indirizzo}" -gt 60 ]; then indirizzo="${indirizzo:0:57}..."; fi
        esito=$(stato_adlist "$id")
        motivo=""
        if [ "$esito" = "4" ]; then motivo=$M_MISSING_FAILED; fi
        avviso "$(printf "$M_MISSING" "$id" "$indirizzo" "$motivo")"
    done
}

if [ "$#" -eq 0 ]; then
    while IFS= read -r f; do files+=("$f"); done < <(trova_liste_pihole)

    # Liste abilitate nel database e, tra queste, quelle senza file scaricato
    verificato=0
    attivi=""
    mancanti=()
    if attivi=$(ids_attivi) && [ -n "$attivi" ]; then
        verificato=1
        declare -A con_file=()
        for f in "${files[@]+"${files[@]}"}"; do con_file[$(id_da_file "$f")]=1; done
        while IFS= read -r id; do
            if [[ "$id" =~ ^[0-9]+$ ]] && [ -z "${con_file[$id]:-}" ]; then mancanti+=("$id"); fi
        done <<< "$attivi"
    fi

    if [ "${#files[@]}" -gt 0 ]; then
        modo_pihole=1
        if [ "$verificato" -eq 1 ]; then
            filtrate=()
            ignorate=0
            for f in "${files[@]}"; do
                if grep -qx "$(id_da_file "$f")" <<< "$attivi"; then
                    filtrate+=("$f")
                else
                    ignorate=$((ignorate + 1))
                fi
            done
            files=("${filtrate[@]+"${filtrate[@]}"}")
            stato=$(printf "$M_STATE_OK" "${#files[@]}" "$ignorate")
        else
            stato=$(printf "$M_STATE_UNK" "${#files[@]}")
        fi
        printf "$M_PIHOLE_FOUND" "$DIR_PIHOLE" "$stato"
        if [ "$verificato" -eq 0 ]; then avviso_sqlite; fi
        segnala_mancanti
        echo
    else
        if [ ! -d "$DIR_PIHOLE" ]; then
            avviso "$(printf "$M_NO_DIR" "$DIR_PIHOLE")"
        else
            avviso "$(printf "$M_NO_LISTS" "$DIR_PIHOLE")"
        fi
        segnala_mancanti
        printf "$M_SCRIPT_DIR" "$DIR_SCRIPT"
        set -- "$DIR_SCRIPT"
    fi
fi

# --- raccolta dei file indicati ---
for arg in "$@"; do
    if [ -d "$arg" ]; then
        while IFS= read -r f; do files+=("$f"); done < <(
            find "$arg" -maxdepth 1 -type f \( -name '*.txt' -o -name '*.list' -o -name '*.hosts' \) | sort)
    elif [ -f "$arg" ]; then
        files+=("$arg")
    else
        printf "$M_NOT_FOUND" "$arg" >&2
        exit 1
    fi
done

# Evita che lo stesso file passato più volte falsi le statistiche.
if [ "${#files[@]}" -gt 1 ]; then
    declare -A visti=()
    unici_files=()
    for f in "${files[@]}"; do
        percorso=$(realpath -m -- "$f" 2>/dev/null || printf '%s' "$f")
        if [ -z "${visti[$percorso]:-}" ]; then
            visti[$percorso]=1
            unici_files+=("$f")
        fi
    done
    files=("${unici_files[@]}")
fi

verifica_numero_liste "${#files[@]}"

for f in "${files[@]}"; do
    if [ ! -r "$f" ]; then
        printf "$M_DENIED" "$f" >&2
        exit 1
    fi
done

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# --- lettura delle liste ---

# Normalizzazione: un dominio per riga, minuscolo, senza duplicati
normalizza() {
    tr -d '\r' < "$1" | awk '
        {
            line = tolower($0)
            sub(/^[ \t]+/, "", line)
            if (line == "" || line ~ /^[#!\[]/ || line ~ /^@@/) next
            if (line ~ /^[^ \t#]+#[@?$%]*#/) next  # regole cosmetiche Adblock (##, #@#, ...)
            sub(/[ \t]*#.*$/, "", line)            # commenti a fine riga
            if (line ~ /^(0\.0\.0\.0|127\.0\.0\.1|::1?)[ \t]+/) {
                sub(/^[^ \t]+[ \t]+/, "", line)    # prefisso hosts
            }
            sub(/^\|\|/, "", line)                 # sintassi adblock
            sub(/[\^\/$].*$/, "", line)            # ^, percorso, modificatori
            sub(/[ \t].*$/, "", line)
            if (line ~ /^[0-9.]+$/) next           # indirizzi IP, non domini
            if (line ~ /^[a-z0-9._*-]+$/ && line ~ /\./) print line
        }' | sort -u
}

# Nome originale della lista, ricavato dall'intestazione del file
# ("! Title: ..." nelle liste Adblock, prima riga di commento nelle altre).
titolo_lista() {
    head -n 40 "$1" | tr -d '\r' | awk '
        function pulisci(t) {
            gsub(/[[:cntrl:]]/, " ", t)
            sub(/[ \t#]+$/, "", t)
            sub(/ (-|\|) .*/, "", t)          # taglia dopo " - " o " | "
            if (length(t) > 40) t = substr(t, 1, 37) "..."
            return t
        }
        !trovato && match($0, /^[!#][ \t]*[Tt]itle:[ \t]*/) {
            print pulisci(substr($0, RLENGTH + 1)); trovato = 1; exit
        }
        !fallback && /^[!#]/ {
            t = $0
            sub(/^[!# \t]+/, "", t)
            if (t ~ /[A-Za-z]/ && t !~ /^(Version|Last|Updated|Expires|Homepage|License|Description)/)
                fallback = pulisci(t)
        }
        END { if (!trovato && fallback != "") print fallback }'
}

# Classificazione euristica del testo dato (nome, titolo, indirizzo, commento).
# Imposta CATEGORIA e PROTEGGI. Non verifica la reputazione della fonte:
# serve a evitare consigli ciechi sulle liste specialistiche.
classifica() {
    local t=${1,,}
    local re_phishing='(phishing|scam|fraud|credential|brand.?abuse)'
    local re_malware='(malware|ransomware|botnet|exploit|threat|virus|trojan|security|urlhaus|abuse.ch)'
    local re_privacy='(privacy|fingerprint|fingerprinting|anti.?tracking|tracking.?protection)'
    local re_tracker='(tracker|tracking|analytics|telemetry|metrics)'
    local re_pubblicita='(advert|ad.?block|(^|[^a-z])ads([^a-z]|$)|adserver|easylist|pubblicit)'
    CATEGORIA="$M_CAT_GEN"
    PROTEGGI=0
    if [[ "$t" =~ $re_phishing ]]; then CATEGORIA="$M_CAT_PHISH"; PROTEGGI=1
    elif [[ "$t" =~ $re_malware ]]; then CATEGORIA="$M_CAT_MAL"; PROTEGGI=1
    elif [[ "$t" =~ $re_privacy ]]; then CATEGORIA="$M_CAT_PRIV"; PROTEGGI=1
    elif [[ "$t" =~ $re_tracker ]]; then CATEGORIA="$M_CAT_TRK"; PROTEGGI=1
    elif [[ "$t" =~ $re_pubblicita ]]; then CATEGORIA="$M_CAT_ADS"
    fi
}

names=()
counts=()
categorie=()
protezioni=()
j=0
ignorati=0
for i in "${!files[@]}"; do
    f=${files[i]}
    nome=${f##*/}
    normalizza "$f" > "$tmp/$j.txt"
    conta=$(wc -l < "$tmp/$j.txt")
    if [ "$conta" -eq 0 ]; then
        avviso "$(printf "$M_IGNORED" "$nome")"
        ignorati=$((ignorati + 1))
        continue
    fi
    titolo=$(titolo_lista "$f" || true)
    indirizzo=""
    commento=""
    if [ "$modo_pihole" -eq 1 ]; then
        id=$(id_da_file "$f")
        IFS='|' read -r indirizzo commento < <(info_adlist "$id") || true
        if [ -z "$titolo" ]; then
            titolo=${commento:-${indirizzo#*://}}
            if [ "${#titolo}" -gt 45 ]; then titolo="${titolo:0:42}..."; fi
        fi
        nome="list.$id"
    fi
    if [ -n "$titolo" ]; then names[j]="$nome ($titolo)"; else names[j]="$nome"; fi

    classifica "$titolo $indirizzo $commento ${f##*/}"
    categorie[j]=$CATEGORIA
    protezioni[j]=$PROTEGGI
    counts[j]=$conta
    j=$((j + 1))
done
n=$j
if [ "$ignorati" -gt 0 ]; then echo; fi
verifica_numero_liste "$n"

# larghezza della colonna dei nomi
w=10
for nm in "${names[@]}"; do
    if [ "${#nm}" -gt "$w" ]; then w=${#nm}; fi
done

tutte=()
somma=0
for ((i = 0; i < n; i++)); do
    tutte+=("$i")
    somma=$((somma + counts[i]))
done

# =====================================================================
# CONFRONTO A COPPIE
# =====================================================================
titolo_sez "$M_H_PERLIST"
for ((i = 0; i < n; i++)); do
    printf "  %-*s %8d  [%s]\n" "$w" "${names[i]}" "${counts[i]}" "${categorie[i]}"
done
echo

# Campi: nome A, nome B, comuni, % di A, % di B
: > "$tmp/risultati.tsv"
for ((i = 0; i < n; i++)); do
    for ((j = i + 1; j < n; j++)); do
        comuni=$(comm -12 "$tmp/$i.txt" "$tmp/$j.txt" | wc -l)
        pa=$(perc "$comuni" "${counts[i]}")
        pb=$(perc "$comuni" "${counts[j]}")
        printf "%s\t%s\t%d\t%s\t%s\n" "${names[i]}" "${names[j]}" "$comuni" "$pa" "$pb" >> "$tmp/risultati.tsv"
    done
done

titolo_sez "$M_H_PAIRS"
printf "%s%-*s %-*s %8s %10s %10s%s\n" "$BOLD" "$w" "$M_C_A" "$w" "$M_C_B" "$M_C_SHARED" "$M_C_PA" "$M_C_PB" "$RESET"
sort -t$'\t' -k3,3nr "$tmp/risultati.tsv" | awk -F'\t' -v w="$w" \
    -v R="$ROSSO" -v Y="$GIALLO" -v D="$DIM" -v Z="$RESET" \
    -v V="$SOGLIA_SIMILI" -v S="$SOGLIA_EVIDENZIA" '
    function col(p) { return (p + 0 >= V) ? R : (p + 0 >= S) ? Y : (p + 0 == 0) ? D : "" }
    { printf "%-*s %-*s %8d %s%9s%%%s %s%9s%%%s\n", w, $1, w, $2, $3, col($4), $4, Z, col($5), $5, Z }'

# --- riepilogo globale ---
echo
read -r tot_unici in_piu < <(sort -m "$tmp"/[0-9]*.txt | uniq -c | awk '{ t++; if ($1 > 1) d++ } END { print t + 0, d + 0 }')
printf "$M_TOT" "$tot_unici"
printf "$M_MULTI" "$in_piu" "$(perc "$in_piu" "$tot_unici")"
printf "$M_SUM" "$somma" "$DIM" "$RESET"

# =====================================================================
# CONTRIBUTO UNICO
# =====================================================================

# Per l'insieme di liste indicato (indici), stampa "indice domini_unici",
# dove "unici" sono i domini presenti solo in quella lista.
unici_per_lista() {
    local k paths=()
    for k in "$@"; do paths+=("$tmp/$k.txt"); done
    sort -m "${paths[@]}" | uniq -u > "$tmp/singoli.txt"
    for k in "$@"; do
        echo "$k $(comm -12 "$tmp/$k.txt" "$tmp/singoli.txt" | wc -l)"
    done
}

echo
titolo_sez "$M_H_UNIQ"
printf "%s%-*s %10s %10s %14s%s\n" "$BOLD" "$w" "$M_C_LIST" "$M_C_DOMAINS" "$M_C_UNIQUE" "$M_C_COVERED" "$RESET"
declare -A cop_lista unici_lista
while read -r k u; do
    cop=$(perc $((counts[k] - u)) "${counts[k]}")
    cop_lista[$k]=$cop
    unici_lista[$k]=$u
    printf "%-*s %10d %10d %s%13s%%%s\n" "$w" "${names[k]}" "${counts[k]}" "$u" "$(colore_cop "$cop")" "$cop" "$RESET"
done < <(unici_per_lista "${tutte[@]}")

# =====================================================================
# CONSIGLI
# =====================================================================
echo
printf '%s%s%s\n' "$BOLD" "$M_BANNER" "$RESET"

# 1) verdetto per singola lista
echo
titolo_sez "$M_S1"
for k in "${tutte[@]}"; do
    cop=${cop_lista[$k]}
    u=${unici_lista[$k]}
    pt=$(perc "$u" "$tot_unici")
    if [ "${protezioni[k]}" -eq 1 ]; then
        verdetto "$VERDE" "$L_PROTECT" "$M_S1_PROTECT" "${names[k]}" "${categorie[k]}" "$cop" "$u"
    elif rimovibile "$cop" "$u"; then
        verdetto "$ROSSO" "$L_REMOVE" "$M_S1_REMOVE" "${names[k]}" "$(pcol "$cop" "$u")" "$u" "$pt"
    elif ge "$cop" "$SOGLIA_VALUTA"; then
        verdetto "$GIALLO" "$L_REVIEW" "$M_S1_REVIEW" "${names[k]}" "$(pcol "$cop" "$u")" "$u" "$pt"
    else
        verdetto "$VERDE" "$L_KEEP" "$M_S1_KEEP" "${names[k]}" "$(pcol "$cop" "$u")" "$u"
    fi
done

# 2) simulazione: rimozione progressiva delle liste ridondanti
# Dopo ogni rimozione i contributi unici vengono ricalcolati, perché togliere
# una lista cambia quanto sono "uniche" le altre.
attive=("${tutte[@]}")
rimosse=()
persi=0
while [ "${#attive[@]}" -gt 1 ]; do
    best=-1
    bestcop=0
    bestu=0
    while read -r k u; do
        # Non proporre la rimozione automatica di liste specialistiche riconosciute.
        if [ "${protezioni[k]}" -eq 1 ]; then continue; fi
        cop=$(perc $((counts[k] - u)) "${counts[k]}")
        if rimovibile "$cop" "$u" && gt "$cop" "$bestcop"; then
            best=$k; bestcop=$cop; bestu=$u
        fi
    done < <(unici_per_lista "${attive[@]}")
    if [ "$best" -lt 0 ]; then break; fi
    rimosse+=("$best")
    persi=$((persi + bestu))
    nuove=()
    for k in "${attive[@]}"; do
        if [ "$k" != "$best" ]; then nuove+=("$k"); fi
    done
    attive=("${nuove[@]}")
done

echo
titolo_sez "$(printf "$M_S2" "$SOGLIA_RIMUOVI" "$SOGLIA_VALUTA" "$SOGLIA_UNICI_TRASCURABILI")"
if [ "${#rimosse[@]}" -eq 0 ]; then
    echo "$M_S2_NONE"
else
    togli=0
    for k in "${rimosse[@]}"; do
        printf "$M_S2_REMOVE" "${names[k]}"
        togli=$((togli + counts[k]))
    done
    printf "$M_S2_LOST" "$persi" "$tot_unici" "$(pcol "$(perc "$persi" "$tot_unici")")"
    printf "$M_S2_DL" "$somma" "$((somma - togli))" "$(perc "$togli" "$somma")"
fi

# 3) una lista quasi interamente contenuta in un'altra
echo
titolo_sez "$(printf "$M_S3" "$SOGLIA_CONTENUTA")"
trovate=0
while IFS=$'\t' read -r a b _ pa pb; do
    if ge "$pa" "$SOGLIA_CONTENUTA"; then
        printf "$M_S3_LINE" "$a" "$pa" "$b"
        trovate=1
    fi
    if ge "$pb" "$SOGLIA_CONTENUTA"; then
        printf "$M_S3_LINE" "$b" "$pb" "$a"
        trovate=1
    fi
done < "$tmp/risultati.tsv"
if [ "$trovate" -eq 0 ]; then nessuna; fi

# 4) coppie molto simili
echo
titolo_sez "$(printf "$M_S4" "$SOGLIA_SIMILI")"
trovate=0
while IFS=$'\t' read -r a b _ pa pb; do
    if ge "$pa" "$SOGLIA_SIMILI" && ge "$pb" "$SOGLIA_SIMILI"; then
        printf "$M_S4_LINE" "$a" "$b" "$pa" "$pb"
        trovate=1
    fi
done < "$tmp/risultati.tsv"
if [ "$trovate" -eq 0 ]; then nessuna; fi

# 5) liste con contributo marginale (poche in totale o con pochi domini unici)
echo
titolo_sez "$M_S5"
trovate=0
for k in "${tutte[@]}"; do
    if [ "${protezioni[k]}" -eq 1 ]; then
        if [ "${counts[k]}" -lt "$SOGLIA_PICCOLA" ] || [ "${unici_lista[$k]}" -lt "$SOGLIA_POCHI_UNICI" ]; then
            printf "$M_S5_SPEC" "${names[k]}" "${categorie[k]}"
            trovate=1
        fi
    elif [ "${counts[k]}" -lt "$SOGLIA_PICCOLA" ]; then
        printf "$M_S5_SMALL" "${names[k]}" "${counts[k]}"
        trovate=1
    elif [ "${unici_lista[$k]}" -lt "$SOGLIA_POCHI_UNICI" ]; then
        printf "$M_S5_FEW" "${names[k]}" "${unici_lista[$k]}" "${counts[k]}"
        trovate=1
    fi
done
if [ "$trovate" -eq 0 ]; then nessuna; fi

# 6) efficienza delle liste (quota di domini unici)
echo
titolo_sez "$M_S6"
migliore=-1; peggiore=-1; qm=0; qp=0
for k in "${tutte[@]}"; do
    q=$(perc "${unici_lista[$k]}" "${counts[k]}")
    if [ "$migliore" -lt 0 ] || gt "$q" "$qm"; then migliore=$k; qm=$q; fi
    if [ "$peggiore" -lt 0 ] || gt "$qp" "$q"; then peggiore=$k; qp=$q; fi
done
if [ "$migliore" -ne "$peggiore" ]; then
    printf "$M_S6_BEST" "${names[migliore]}" "$qm"
    printf "$M_S6_WORST" "${names[peggiore]}" "$qp"
else
    printf "$M_S6_SAME" "$qm"
fi

# 7) liste pesanti
echo
titolo_sez "$(printf "$M_S7" "$SOGLIA_GRANDE")"
trovate=0
for k in "${tutte[@]}"; do
    if [ "${counts[k]}" -gt "$SOGLIA_GRANDE" ]; then
        printf "$M_S7_LINE" "${names[k]}" "${counts[k]}"
        trovate=1
    fi
done
if [ "$trovate" -eq 0 ]; then nessuna; fi

# 8) dimensione delle liste e rischio di falsi positivi
# La dimensione da sola non prova che una lista sia aggressiva: distinguiamo
# le liste generiche dalle feed specialistiche riconosciute.
echo
titolo_sez "$(printf "$M_S8" "$SOGLIA_GENERALISTA")"
ampie=0
ampie_generiche=0
ampie_specialistiche=0
for k in "${tutte[@]}"; do
    if [ "${counts[k]}" -gt "$SOGLIA_GENERALISTA" ]; then
        ampie=$((ampie + 1))
        if [ "${protezioni[k]}" -eq 1 ]; then
            ampie_specialistiche=$((ampie_specialistiche + 1))
        else
            ampie_generiche=$((ampie_generiche + 1))
        fi
    fi
done
if [ "$ampie" -gt 0 ]; then
    printf "$M_S8_COUNT" "$ampie" "$ampie_generiche" "$ampie_specialistiche"
    if [ "$ampie_generiche" -ge 2 ]; then
        echo "$M_S8_MANY"
    elif [ "$ampie_generiche" -eq 1 ]; then
        echo "$M_S8_ONE"
    fi
    if [ "$ampie_specialistiche" -gt 0 ]; then
        echo "$M_S8_SPEC"
    fi
else
    nessuna
fi

# 9) piano d'azione
echo
titolo_sez "$M_S9"
if [ "${#rimosse[@]}" -gt 0 ]; then
    echo "$M_S9_1"
    for k in "${rimosse[@]}"; do printf '       - %s\n' "${names[k]}"; done
    echo "$M_S9_2"
    echo "$M_S9_3"
    echo "$M_S9_4"
else
    valuta=-1; vc=0
    for k in "${tutte[@]}"; do
        if [ "${protezioni[k]}" -eq 1 ]; then continue; fi
        if ge "${cop_lista[$k]}" "$SOGLIA_VALUTA" && { [ "$valuta" -lt 0 ] || gt "${cop_lista[$k]}" "$vc"; }; then
            valuta=$k; vc=${cop_lista[$k]}
        fi
    done
    if [ "$valuta" -ge 0 ]; then
        printf "$M_S9_TRY" "${names[valuta]}" "$(pcol "$vc")"
        echo "$M_S9_THEN"
    else
        printf "$M_S9_OK" "$VERDE" "$RESET"
    fi
fi
printf '  %s%s%s\n' "$DIM" "$M_S9_RERUN" "$RESET"

echo
printf '%s%s%s\n' "$DIM" "$M_NOTE" "$RESET"
