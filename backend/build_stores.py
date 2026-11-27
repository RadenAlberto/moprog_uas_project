#!/usr/bin/env python3
"""Membuat stores_seed.json (+ assets/data/stores.json) dari daftar gerai UNIQLO Indonesia.

Sumber: daftar outlet UNIQLO (PDF Bank Danamon, 78 gerai, alamat & telepon) dan
BizLocationDB (koordinat, 50 gerai pertama), per 13 Nov 2026. Gerai tanpa
koordinat tetap bisa dibuka di Google Maps lewat nama + kota.
Format baris:  mal | kota | provinsi | alamat | telepon | lat | lng
"""
import json
from pathlib import Path

ROWS = """
Lotte Shopping Avenue|Jakarta Selatan|DKI Jakarta|Lotte Shopping Avenue (Ciputra World) GF & 1F, Jl. Prof. Dr. Satrio No.8, Jakarta 12950|021-50110280||
Mall Taman Anggrek|Jakarta Barat|DKI Jakarta|Mal Taman Anggrek UGF, Jl. Let. Jend. S. Parman Kav.21, Slipi 11470|021-50111075|-6.17725|106.79276
Grand Indonesia|Jakarta Pusat|DKI Jakarta|Grand Indonesia East Mall LGF, Jl. MH Thamrin No.1, 10310|021-50676883|-6.19518|106.82020
Plaza Indonesia|Jakarta Pusat|DKI Jakarta|Plaza Indonesia, Jl. M.H. Thamrin Kav. 28-30, Gondangdia, Menteng 10310||-6.19360|106.82195
Gandaria City|Jakarta Selatan|DKI Jakarta|Gandaria City UGF, Jl. Sultan Iskandar Muda, 12240|021-50233526|-6.24471|106.78355
Pondok Indah Mall 1|Jakarta Selatan|DKI Jakarta|Pondok Indah Mall 1 2F, Jl. Metro Pondok Indah 12310|021-50110870|-6.26510|106.78455
Pondok Indah Mall 3|Jakarta Selatan|DKI Jakarta|Pondok Indah Mall 3, Jl. Sultan Iskandar Muda No.28E, Pd. Pinang 12240|021-50110912||
PIK Avenue|Jakarta Utara|DKI Jakarta|PIK Avenue Mall 1F, Jl. Pantai Indah Kapuk Boulevard, Penjaringan|021-50322714|-6.10930|106.73976
Lippo Mall Puri|Jakarta Barat|DKI Jakarta|Lippo Mall Puri, Kembangan 11610|021-30212008|-6.18801|106.73876
Lippo Mall Kemang|Jakarta Selatan|DKI Jakarta|Lippo Mall Kemang GF, Jl. Pangeran Antasari, Mampang Prapatan 12150|021-50111358|-6.26149|106.81261
Senayan City|Jakarta Pusat|DKI Jakarta|Senayan City 3F, Jl. Asia Afrika Lot 19, Gelora, Tanah Abang 10270|021-50111030|-6.22734|106.79721
Mall of Indonesia|Jakarta Utara|DKI Jakarta|Mall of Indonesia GF, Jl. Boulevard Barat Raya, Kelapa Gading Barat 14240|021-50322715|-6.15106|106.88989
La Piazza Mal Kelapa Gading|Jakarta Utara|DKI Jakarta|Jl. Boulevard Raya, Kelapa Gading Timur 14240|021-50420230|-6.15924|106.90716
Neo Soho (Central Park)|Jakarta Barat|DKI Jakarta|Neo Soho GF, Jl. Letjen S. Parman Kav.28, Tanjung Duren Selatan 11470|021-50860736|-6.17525|106.79009
Emporium Pluit Mall|Jakarta Utara|DKI Jakarta|Emporium Mall UG, Jl. Pluit Selatan Raya, Penjaringan 14440|021-50322716||
Mal Ciputra Jakarta|Jakarta Barat|DKI Jakarta|Jl. Arteri S. Parman, Grogol Petamburan, UG Unit 16A-18|021-5661212||
Green Sedayu Mall|Jakarta Barat|DKI Jakarta|Jl. Taman Palem Lestari No.2, Cengkareng Barat 11730|021-50111362||
AEON Mall Tanjung Barat|Jakarta Selatan|DKI Jakarta|Jl. Raya Tanjung Barat No.163, Jagakarsa 12530|021-50102830|-6.30570|106.84040
AEON Mall Jakarta Garden City|Jakarta Timur|DKI Jakarta|Jl. Jakarta Garden City Boulevard No.1, Cakung 13910|021-50112310|-6.16173|106.96601
AEON Mall BSD City|Kabupaten Tangerang|Banten|AEON Mall BSD City 1F, Jl. Grand Boulevard BSD City|021-50111602|-6.30485|106.64368
Supermal Karawaci|Kabupaten Tangerang|Banten|Supermal Karawaci GF, Jl. Boulevard Diponegoro No.105, Bencongan 15810|021-50233691|-6.22676|106.60703
One District Puri|Kota Tangerang|Banten|One District Puri GF, Jl. Metland Boulevard Kav. B1-3, Karang Tengah 15159|021-50420202|-6.19732|106.70272
Summarecon Mall Serpong|Kabupaten Tangerang|Banten|Unit 1F-D2, Jl. Boulevard Raya Gading Serpong, Kelapa Dua 15810|021-50323410||
Living World Alam Sutera|Tangerang Selatan|Banten|Jl. Alam Sutera Boulevard Kav.21, Pakulonan, Serpong Utara 15325|021-50112022|-6.24438|106.65310
Bintaro Jaya Xchange Mall|Tangerang Selatan|Banten|Bintaro Jaya CBD Blok O, Jl. Sektor VII No.2 15227|021-31182704||
Mal Ciputra Tangerang|Kabupaten Tangerang|Banten|Jl. Citra Raya Boulevard No.01, Panongan 15710|021-50420201||
Grand Galaxy Park|Bekasi|Jawa Barat|Grand Galaxy Park 1F, Jl. Grand Galaxy Boulevard No.1, Jaka Setia 17147|021-82754471||
Grand Kota Bintang|Bekasi|Jawa Barat|Jl. KH. Noer Ali No.1G, Jakasampurna 17145|021-50420227||
Pakuwon Mall Bekasi|Bekasi|Jawa Barat|Jl. Raya Pekayon No.002, Pekayon Jaya 17148|021-50420225|-6.25588|106.98706
Summarecon Mall Bekasi|Bekasi|Jawa Barat|Sentra Summarecon Bekasi, Jl. Boulevard Ahmad Yani, Marga Mulya 17142|021-30620244|-6.22613|107.00108
Harapan Indah Avenue|Bekasi|Jawa Barat|Jl. Raya Kota Harapan Indah, Medan Satria 17214|021-50200710||
AEON Mall Deltamas|Kabupaten Bekasi|Jawa Barat|Jl. Ganesha Boulevard, Kota Deltamas, Cikarang Pusat 17530|021-31182722|-6.35194|107.19545
Margocity|Depok|Jawa Barat|Margocity, Jl. Margonda Raya No.358, Beji 16423|021-50322713||
Trans Studio Mall Cibubur|Depok|Jawa Barat|Jl. Alternatif Cibubur No.230, Harjamukti, Cimanggis 16454|021-50322810|-6.37571|106.90178
AEON Mall Sentul City|Kabupaten Bogor|Jawa Barat|AEON Mall Sentul City, Jl. MH. Thamrin, Babakan Madang 16810|021-50323280||
Cibinong City Mall|Kabupaten Bogor|Jawa Barat|GF-1/II, Jl. Tegar Beriman No.1, Cibinong 16914|021-50111012||
Living World Kota Wisata Cibubur|Kabupaten Bogor|Jawa Barat|Jl. Boulevard Kota Wisata, Ciangsana, Gunung Putri 16968|021-50208121|-6.36971|106.95915
Botani Square Mall|Bogor|Jawa Barat|Jl. Raya Pajajaran No.40, Tugu Kujang, Bogor Tengah 16127|021-50872433|-6.60124|106.80704
23 Paskal|Bandung|Jawa Barat|23 Paskal Shopping Mall, Jl. Pasir Kaliki No.25-27, Andir 40181|022-21010125|-6.91532|107.59609
Paris Van Java|Bandung|Jawa Barat|Paris Van Java 1F, Jl. Sukajadi No.131-139, Sukajadi 40162|022-21010127|-6.88901|107.59581
Trans Studio Mall Bandung|Bandung|Jawa Barat|Jl. Gatot Subroto No.289, Cibangkong, Batununggal 40273|022-21030800||
Heritage Bandung|Bandung|Jawa Barat|GF & 1F, Jl. LL.RE. Martadinata No.65, Citarum, Bandung Wetan|022-21010882||
Festival Citylink Bandung|Bandung|Jawa Barat|Jl. Peta No.241, Suka Asih, Bojongloa Kaler 40232|022-21010129||
Summarecon Mall Bandung|Bandung|Jawa Barat|Jl. Grand Bulevar No.1, Rancabolang, Gedebage 40295|022-21010885|-6.95507|107.69725
Cirebon Superblock|Cirebon|Jawa Barat|Komp. Chelsea Blue Ruko 9-10, Jl. DR. Cipto Mangunkusumo No.26, Kesambi 45131|022-21010150|-6.71822|108.55033
Pakuwon Mall Surabaya|Surabaya|Jawa Timur|Jl. Mayjen Yono Suwoyo, Babatan, Wiyung 60213|031-21001734|-7.28770|112.67531
Tunjungan Plaza 3|Surabaya|Jawa Timur|Jl. Basuki Rahmat No.8-12, Kedungdoro, Tegalsari 60261|031-21001741|-7.26324|112.73956
Galaxy Mall 3|Surabaya|Jawa Timur|Galaxy Mall 1F, Jl. Dharmahusada Indah Timur No.35-37, Mulyorejo 60115|031-33601254|-7.27639|112.77989
Ciputra World Surabaya|Surabaya|Jawa Timur|Ciputra World Surabaya, Gunung Sari, Dukuhpakis|031-33600973||
Pakuwon City Mall|Surabaya|Jawa Timur|Pakuwon City Mall 3, Jl. Raya Laguna KJW Putih Tambak No.2, Mulyorejo 60112|031-33601012|-7.27617|112.80333
Unimas District Waru|Sidoarjo|Jawa Timur|Jl. Raya Waru No.2, Krajan Kulon, Waru 61256|031-33601030|-7.36599|112.72853
Lippo Plaza Sidoarjo|Sidoarjo|Jawa Timur|Jl. Jati Raya No.1, Jati 61226|031-33102060|-7.44602|112.69836
Mal Olympic Garden (MOG) Malang|Malang|Jawa Timur|Mal Olympic Garden, Kota Malang (dibuka 2026; alamat lengkap belum terverifikasi)|||
DP Mall|Semarang|Jawa Tengah|DP Mall GF, Jl. Pemuda No.150, Sekayu, Semarang Tengah 50132|024-40010210|-6.98342|110.41248
Queen City Mall Semarang|Semarang|Jawa Tengah|Jl. Pemuda No.27-31, Pandansari, Semarang Tengah 50139|024-40010211||
23 Semarang Shopping Center|Semarang|Jawa Tengah|23 Semarang Shopping Center, Kota Semarang (dibuka 2026; alamat lengkap belum terverifikasi)|||
Solo Paragon Mall|Surakarta|Jawa Tengah|Jl. Yosodipuro No.133, Mangkubumen, Banjarsari 57139|0271-3100201|-7.56145|110.80943
Pakuwon Mall Solo Baru|Sukoharjo|Jawa Tengah|Jl. Ir. Soekarno, Madegondo, Grogol 57552|0271-3100200||
Hartono Mall Yogyakarta (Pakuwon Mall Jogja)|Sleman|DI Yogyakarta|Hartono Mall 1F, Jl. Ring Road Utara, Condongcatur, Depok 55281|0274-8000032||
Plaza Ambarrukmo|Sleman|DI Yogyakarta|Jl. Laksda Adisucipto No.80, Caturtunggal, Depok 55281|0274-8000033||
Mal Bali Galeria|Badung|Bali|Mall Bali Galeria 2F, Jl. By Pass Ngurah Rai, Simpang Dewa Ruci, Kuta 80361|0361-3352038|-8.72287|115.18290
Beachwalk (Sheraton Gate)|Badung|Bali|Unit L1 #F-1A, Jl. Pantai Kuta, Kuta 80361|0361-3352039||
Level 21 Mall|Denpasar|Bali|Jl. Teuku Umar No.1, Dauh Puri Klod, Denpasar Barat 80113|0361-3354644||
Living World Denpasar|Denpasar|Bali|GF, Jl. Gatot Subroto Timur, Tonja, Denpasar Utara 80235|0361-3354690||
Icon Bali Mall|Denpasar|Bali|UG, Jl. Danau Tamblingan No.27, Sanur, Denpasar Selatan 80228|0361-3352100||
Lombok Epicentrum Mall|Mataram|Nusa Tenggara Barat|LG Floor, Jl. Sriwijaya No.333, Punia|0361-3352040||
Sun Plaza|Medan|Sumatera Utara|Sun Plaza GF, Jl. KH. Zainul Arifin No.7, Medan Polonia 20152|061-50300558|3.58216|98.67148
Deli Park Mall|Medan|Sumatera Utara|Deli Park Mall UG & 1F, Jl. Putri Hijau No.1, Kesawan 20111|061-50112360|3.59456|98.67495
Living World Pekanbaru|Pekanbaru|Riau|1F, Jl. Soekarno-Hatta, Tengkerang Barat, Marpoyan Damai 28292|0761-9001270|0.50024|101.42019
Basko City Mall|Padang|Sumatera Barat|Jl. Manunggal 3, Kalumbuk, Kuranji 25171||-0.91617|100.39794
Jambi Town Square|Jambi|Jambi|1F, Jl. Kapt. A. Bakaruddin No.88, Simpang III Sipin, Kota Baru 36125|0741-8100810|-1.61746|103.59721
Palembang Icon|Palembang|Sumatera Selatan|Jl. POM IX, Lorok Pakjo, Ilir Barat I 30137|0711-2010212|-2.97902|104.74571
Mal Boemi Kedaton|Bandar Lampung|Lampung|GF, Jl. Teuku Umar No.1, Kedaton 35132|0888-1330500|-5.38207|105.25731
Grand Batam Mall|Batam|Kepulauan Riau|Grand Batam Mall GF & L1, Jl. Pembangunan, Batu Selicin, Lubuk Baja 29444|0778-2100318|1.13548|104.00795
K Square Batam|Batam|Kepulauan Riau|Jl. Jenderal Sudirman No.25-35, Sukajadi, Batam Kota 29432||1.10112|104.03662
Gaia Bumi Raya City|Kubu Raya|Kalimantan Barat|Jl. Arteri Supadio, Sungai Raya 78121|0561-8001410|-0.07673|109.36936
Duta Mall Banjarmasin|Banjarmasin|Kalimantan Selatan|2F, Jl. A. Yani KM 3, Banjarmasin Tengah 70123|0511-2001306||
Big Mall Samarinda|Samarinda|Kalimantan Timur|Jl. Untung Suropati No.08, Karang Asam Ulu, Sungai Kunjang 75243|0541-2781573||
Pentacity Mall Balikpapan|Balikpapan|Kalimantan Timur|GF, Jl. Jenderal Sudirman No.47|0889-79116879||
Trans Studio Mall Makassar|Makassar|Sulawesi Selatan|Trans Studio Mall 1F, Maccini Sombala, Tamalate 90224|0411-7400217|-5.15938|119.39437
Nipah Mall|Makassar|Sulawesi Selatan|Nipah Mall LG, Jl. Poros Makassar-Maros No.23, Panakkukang 90231|0411-7400218|-5.13904|119.45004
Manado Town Square|Manado|Sulawesi Utara|Unit A.1, Jl. Piere Tendean Boulevard, Sario 95114|0431-2001610|1.47231|124.83181
"""

PROV_ID = {'DKI Jakarta': 'JKT'}


def main():
    here = Path(__file__).resolve().parent
    stores = []
    for i, line in enumerate(l for l in ROWS.strip().splitlines() if l.strip()):
        mall, city, prov, addr, phone, lat, lng = [p.strip() for p in line.split('|')]
        stores.append({
            'id': 'ID%03d' % (i + 1),
            'name': 'UNIQLO ' + mall,
            'mall': mall,
            'city': city,
            'province': prov,
            'address': addr,
            'phone': phone,
            'lat': float(lat) if lat else None,
            'lng': float(lng) if lng else None,
            'open_hour': 10,
            'close_hour': 22,
        })
    ids = {s['name'] for s in stores}
    assert len(ids) == len(stores), 'nama toko ganda'
    text = json.dumps({'stores': stores}, ensure_ascii=False, indent=1)
    (here / 'stores_seed.json').write_text(text, encoding='utf8')
    (here.parent / 'assets' / 'data' / 'stores.json').write_text(text, encoding='utf8')
    print(len(stores), 'toko;', sum(1 for s in stores if s['lat'] is not None), 'dengan koordinat;',
          len({s['province'] for s in stores}), 'provinsi')


if __name__ == '__main__':
    main()
