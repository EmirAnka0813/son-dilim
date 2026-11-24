#!/usr/bin/env bash
# SON DILIM — TUM TESTLERI CALISTIRIR
#
# Her test ayri process'te calisir; "SONUC: g/t" satirindan sonuc okunur.
# Kullanim:
#   bash tools/run_all_tests.sh
#   GODOT=/path/to/godot bash tools/run_all_tests.sh
set -uo pipefail

GODOT="${GODOT:-$HOME/tools/godot/Godot_v4.4-stable_win64_console.exe}"
PROJE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJE" || exit 1

TESTLER=(test_balance test_flow test_perf test_start_flow test_playable
         test_character test_game_logic test_camera_3d test_final)

TOPLAM_GECEN=0
TOPLAM_TOPLAM=0
HATALI=()

echo "======================================================================"
echo "SON DILIM — TUM TESTLER"
echo "Godot: $GODOT"
echo "======================================================================"

for t in "${TESTLER[@]}"; do
  script="res://tools/$t.gd"
  [ -f "tools/$t.gd" ] || { echo "  [SKIP] $t (dosya yok)"; HATALI+=("$t (dosya yok)"); continue; }

  out=$(timeout 180 "$GODOT" --headless --path . --script "$script" 2>&1)
  satir=$(printf '%s\n' "$out" | grep -oE 'SONUÇ: [0-9]+/[0-9]+' | tail -1)

  if [ -z "$satir" ]; then
    echo "  [HANG] $t  -> SONUÇ satiri yok"
    HATALI+=("$t (SONUÇ yok / timeout)")
    continue
  fi

  g=$(printf '%s' "$satir" | sed -E 's/.*: ([0-9]+)\/.*/\1/')
  n=$(printf '%s' "$satir" | sed -E 's/.*\/([0-9]+)$/\1/')
  TOPLAM_GECEN=$((TOPLAM_GECEN + g))
  TOPLAM_TOPLAM=$((TOPLAM_TOPLAM + n))

  if [ "$g" -eq "$n" ] && [ "$n" -gt 0 ]; then
    printf "  [ OK ] %-18s %d/%d\n" "$t" "$g" "$n"
  else
    printf "  [FAIL] %-18s %d/%d\n" "$t" "$g" "$n"
    HATALI+=("$t ($g/$n)")
  fi
done

echo ""
echo "======================================================================"
echo "GENEL SONUÇ: $TOPLAM_GECEN/$TOPLAM_TOPLAM"
if [ ${#HATALI[@]} -eq 0 ]; then
  echo "Tüm testler geçti."
  echo "======================================================================"
  exit 0
fi
echo "Sorunlu testler: ${HATALI[*]}"
echo "======================================================================"
exit 1
