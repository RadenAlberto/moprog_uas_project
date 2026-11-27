# Laporan pelatihan model UNIQLO PLUS

Versi: `2026.11.18-080806`  |  Dilatih: 2026-11-18T08:08:06.426170+00:00

## 1. Data yang dipakai (bukti)

| ID | Nama | Jenis | Baris | SHA-256 | Dipakai untuk |
|---|---|---|---|---|---|
| synthetic-personas | Simulasi pengguna (teori analisis warna personal) | **synthetic** | 90000 | `100987ea59f7f644` | tone_color |

## 2. Komponen model dan sumbernya

| Komponen | Sumber |
|---|---|
| tone_color | trained:synthetic |
| color_pair | prior:theory |

Keterangan sumber: `prior:theory` = aturan teori (BELUM dilatih), `trained:synthetic` = dilatih dari simulasi (bootstrap), `+feedback` = juga memakai umpan balik pengguna nyata, `trained:real` = dilatih dari dataset nyata.

## 3. Metrik

### tone_color
- train_rows_synthetic: 72000
- train_rows_real: 0
- test_rows: 18000
- auc_learned: 0.6937
- auc_theory_only: 0.6945
- auc_global_mean: 0.5
- logloss_learned: 0.5562
- logloss_global_mean: 0.6117

### color_pair
- rows: 0
- note: Belum ada data outfit nyata; memakai aturan roda warna.
