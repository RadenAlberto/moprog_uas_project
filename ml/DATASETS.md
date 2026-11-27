# Sumber data machine learning UNIQLO PLUS

Dokumen ini adalah **bukti data**. Tiap pelatihan menulis `artifacts/REPORT.md` berisi
dataset yang benar-benar dipakai (jumlah baris + SHA-256) dan metrik hasilnya.
Aplikasi dan panel admin menampilkan sumber tiap komponen (`prior:theory`,
`trained:synthetic`, `trained:real`).

> Saya (pembuat kode) tidak bisa mengunduh dataset Kaggle dari lingkungan kerja saya
> (tidak ada akses internet dan Kaggle butuh login). Karena itu:
> * yang **sudah dilatih** di model bawaan: `tone_color` dari simulasi pengguna (bootstrap, berlabel *synthetic*);
> * yang **menunggu data asli Anda**: `face_shape`, `skin_depth`, `color_pair`, `color_market`.
>   Unduh sekali, jalankan satu perintah (di bawah), lalu unggah `model.json` lewat panel admin.

## Dataset yang dipakai

| Komponen | Dataset | Isi | Tautan | Cara pakai |
|---|---|---|---|---|
| Bentuk wajah (`face_shape`) | Kaggle "Face Shape Classification" (Niten Lama / lucifierx) - ±5.000 foto selebriti wanita, 5 kelas: Heart, Oblong, Oval, Round, Square | foto | https://www.kaggle.com/datasets/lucifierx/face-shape-classification | `--faces <folder>` |
| Kedalaman kulit (`skin_depth`) | Foto berlabel **Monk Skin Tone** (MST-E, 1.515 foto, 10 tingkat, subjek memberi izin) atau Skin Tone in The Wild (CC BY 4.0) | foto + label MST | https://skintone.google , https://arxiv.org/abs/2603.02475 | `--skin-csv labels.csv` |
| Warna pasar (`color_market`) | Kaggle "Fashion Product Images Dataset" (44 ribu produk; kolom `baseColour`, `gender`, `usage`, `season`) | `styles.csv` (tanpa gambar) | https://www.kaggle.com/datasets/paramaggarwal/fashion-product-images-dataset | `--styles styles.csv` |
| Warna cocok / matching (`color_pair`) | Polyvore Outfits (21.889 outfit; gambar item ada di halaman Kaggle tidak resmi yang ditautkan repo) | outfit + gambar | https://github.com/xthan/polyvore-dataset | `scripts/extract_polyvore_pairs.py` lalu `--pairs` |
| Selera pengguna (`tone_color`, popularitas) | **Umpan balik pengguna aplikasi** (like/tidak cocok/keranjang) + profil kulit mereka | tabel `feedback`, `style_profiles` di server | - | `--db backend/uniqlo_plus.sqlite3` atau tombol *Latih ulang* di panel admin |

Cek lisensi masing-masing dataset di halamannya sebelum dipakai di luar tugas kuliah.

### Tentang "ras"
Model **tidak menebak ras** dari foto. Menebak ras dari wajah tidak akurat, bias, dan
bermasalah secara etika. Yang dipakai untuk rekomendasi warna adalah **warna kulit**
(kedalaman: terang/sedang/gelap, skala Monk) dan **undertone** (hangat/dingin/netral).

## Cara menjalankan (di komputer Anda)

```
cd ml
pip install -r requirements.txt

# 1) Bentuk wajah: arahkan ke folder yang LANGSUNG berisi 5 subfolder kelas
#    (Heart, Oblong, Oval, Round, Square). Folder lain diabaikan.
# 2) Warna pasar dari styles.csv
# 3) (opsional) foto berlabel MST:  labels.csv berkolom path,mst
python train.py --styles data/raw/styles.csv --faces data/raw/faceshape/training_set ^
                --skin-csv data/raw/mst/labels.csv --db ../backend/uniqlo_plus.sqlite3 --export-assets
```
(`^` = lanjut baris di CMD Windows; di macOS/Linux pakai `\`.)

Hasil: `ml/artifacts/model.json` + `REPORT.md`, dan `assets/data/ml_model.json`
(bawaan aplikasi bila server mati). Untuk server: panel admin -> **Model ML** ->
*Unggah model* -> *Aktifkan*. HP pengguna mengunduh model aktif otomatis.

## Alur data -> aplikasi

```
dataset  --train.py-->  model.json  --server /api/ml/model-->  aplikasi (Dart)
feedback pengguna --(retrain)--^                         ^-- tiap pengguna tetap belajar sendiri (SGD di HP)
```

Perbedaan pengalaman tiap pengguna datang dari: profil (wajah, kulit, tubuh, kebutuhan);
model personal on-device (bobot, afinitas kategori dan warna) yang bergeser tiap kali
menekan Cocok/Kurang cocok; dan popularitas yang dihitung per **segmen** (kulit x gender)
dari pengguna yang mirip.
