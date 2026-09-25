#!/bin/bash
# Generates synthetic Swedish test utterances of about 5, 10, 30, 60 and 120 seconds for the iOS
# benchmark harness (#65), using the macOS voice "Alva". The files are written to
# iOS/Benchmark/Utterances/ (git-ignored) and bundled into the app at build time.
#
# Synthetic speech is fine for timing and memory, which depend on audio length, but it is not a
# substitute for real speech when judging accuracy. Record real utterances too (see Docs/benchmark.md).
set -euo pipefail

cd "$(dirname "$0")"
OUT=Utterances
VOICE=Alva
mkdir -p "$OUT"

if ! say -v '?' | grep -q "^$VOICE "; then
    echo "The Swedish voice $VOICE is not installed (System Settings → Accessibility → Spoken Content)." >&2
    exit 1
fi

# Original text written for this benchmark.
SENTENCES=(
    "Hej, jag vill boka en tid hos tandläkaren nästa vecka."
    "Kan vi ses vid stationen klockan halv åtta i morgon bitti?"
    "Glöm inte att köpa mjölk, bröd och ett paket kaffe på vägen hem."
    "Mötet om budgeten flyttas till torsdag eftermiddag."
    "Jag har läst igenom rapporten och har några frågor om det tredje kapitlet."
    "Vädret ser ut att bli soligt under helgen, så vi kan grilla på lördag."
    "Barnen ska på simskola efter skolan, så jag hämtar dem vid fem."
    "Tack för en trevlig kväll, maten var verkligen god."
    "Skicka gärna över presentationen innan lunch så att jag hinner titta på den."
    "Tåget från Göteborg är försenat med ungefär tjugo minuter."
    "Vi behöver bestämma oss för vilken färg vi ska måla köket i."
    "Jag springer en runda i skogen innan det blir mörkt."
    "Kom ihåg att vattna blommorna medan vi är bortresta."
    "Bibliotekets öppettider har ändrats och de stänger nu klockan sju."
    "Det nya projektet startar i januari och pågår till och med juni."
    "Min syster fyller fyrtio år i maj och vi planerar en överraskningsfest."
    "Kan du påminna mig om att ringa försäkringsbolaget i morgon?"
    "Vi har fått in tre nya ansökningar till tjänsten som projektledare."
    "Cykeln behöver nya bromsar och en ordentlig tvätt."
    "Jag tror att vi ska välja den billigare lösningen den här gången."
    "Efter semestern blev det svårt att komma tillbaka in i rutinerna."
    "Soppan behöver koka i ungefär en halvtimme till."
    "Styrelsen godkände förslaget med knapp majoritet."
    "Vi ses på fredag, och ta gärna med dig en tröja eftersom det blir kallt på kvällen."
    "Hyran höjs med två procent från och med nästa månad."
    "Jag har bokat ett bord för fyra personer på restaurangen vid torget."
    "Uppdateringen av systemet görs under natten mellan söndag och måndag."
    "Hunden behöver gå ut en sista gång innan vi lägger oss."
    "Hör av dig om du vill ha skjuts till flygplatsen."
    "Kursen i spanska börjar igen efter jul, på tisdagar klockan sex."
    "Priset på el har gått ner den senaste tiden, men det kan ändras snabbt."
    "Jag lämnar nyckeln hos grannen så att hantverkarna kommer in."
    "Vi borde städa förrådet innan vintern kommer."
    "Läkaren sa att jag ska vila foten i minst två veckor."
    "Konserten i parken ställdes in på grund av regnet."
    "Skriv upp alla idéer på tavlan så går vi igenom dem tillsammans."
    "Paketet ska levereras till ombudet i matbutiken."
    "Min farfar berättade ofta om när han arbetade på varvet."
    "Vi har ont om tid, så låt oss fokusera på de viktigaste punkterna."
    "Det var länge sedan vi åkte skidor, vi borde göra det i vinter."
    "Kan någon ta anteckningar under mötet i dag?"
    "Jag behöver byta däck på bilen innan det blir halt."
    "Ett stort tack till alla som hjälpte till med flytten."
    "Planen är att vara klara med renoveringen till sommaren."
    "Jag återkommer med ett svar så snart jag har pratat med min chef."
)

duration() {
    afinfo "$1" | awk '/estimated duration/ { print $3 }'
}

TMP=$(mktemp -d -t sorla-utterances)
trap 'rm -rf "$TMP"' EXIT

# Each sentence is timed once; a clip is the run of consecutive sentences closest to its target length.
LENGTHS=()
for index in "${!SENTENCES[@]}"; do
    say -v "$VOICE" --file-format=WAVE --data-format=LEI16@48000 -o "$TMP/sentence.wav" "${SENTENCES[$index]}"
    LENGTHS+=("$(duration "$TMP/sentence.wav")")
done

make_clip() {
    local target=$1
    local name
    name=$(printf "sv-%03ds" "$target")
    local window
    window=$(printf "%s\n" "${LENGTHS[@]}" | awk -v t="$target" '
        { d[NR - 1] = $1; n = NR }
        END {
            best = -1
            for (i = 0; i < n; i++) {
                sum = 0
                for (j = i; j < n; j++) {
                    sum += d[j]
                    diff = sum - t; if (diff < 0) diff = -diff
                    if (best < 0 || diff < best) { best = diff; from = i; to = j }
                    if (sum > t) break
                }
            }
            print from, to
        }')
    local from=${window% *}
    local to=${window#* }
    local text=""
    for ((index = from; index <= to; index++)); do
        text="$text ${SENTENCES[$index]}"
    done
    say -v "$VOICE" --file-format=WAVE --data-format=LEI16@48000 -o "$OUT/$name.wav" "$text"
    printf "%s.wav  %6.1f s  sentences %d–%d\n" "$name" "$(duration "$OUT/$name.wav")" "$((from + 1))" "$((to + 1))"
}

for target in 5 10 30 60 120; do
    make_clip "$target"
done
