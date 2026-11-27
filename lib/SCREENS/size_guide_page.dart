import 'package:flutter/material.dart';

import '../UTILS/app_theme.dart';
import '../WIDGETS/ui_kit.dart';

/// Panduan ukuran (angka perkiraan; selalu cek label pada produk).
class SizeGuidePage extends StatefulWidget {
  const SizeGuidePage({super.key});

  @override
  State<SizeGuidePage> createState() => _SizeGuidePageState();
}

class _SizeGuidePageState extends State<SizeGuidePage> {
  int _tab = 0;

  static const _tabs = ['Pria', 'Wanita', 'Anak'];

  static const _headers = <List<String>>[
    ['Ukuran', 'Dada (cm)', 'Pinggang (cm)', 'Tinggi (cm)'],
    ['Ukuran', 'Dada (cm)', 'Pinggang (cm)', 'Pinggul (cm)'],
    ['Ukuran', 'Usia', 'Tinggi (cm)', 'Dada (cm)'],
  ];

  static const _rows = <List<List<String>>>[
    [
      ['S', '88 - 92', '73 - 77', '165 - 170'],
      ['M', '93 - 97', '78 - 82', '170 - 175'],
      ['L', '98 - 102', '83 - 87', '175 - 180'],
      ['XL', '103 - 107', '88 - 94', '178 - 183'],
      ['XXL', '108 - 114', '95 - 101', '180 - 185'],
    ],
    [
      ['XS', '78 - 82', '60 - 64', '85 - 89'],
      ['S', '83 - 87', '65 - 69', '90 - 94'],
      ['M', '88 - 92', '70 - 74', '95 - 99'],
      ['L', '93 - 98', '75 - 80', '100 - 105'],
      ['XL', '99 - 104', '81 - 86', '106 - 111'],
    ],
    [
      ['100', '3 - 4 th', '95 - 105', '54 - 56'],
      ['110', '4 - 5 th', '105 - 115', '56 - 58'],
      ['120', '6 - 7 th', '115 - 125', '60 - 63'],
      ['130', '8 - 9 th', '125 - 135', '64 - 67'],
      ['140', '10 - 11 th', '135 - 145', '68 - 72'],
      ['150', '12 - 13 th', '145 - 155', '73 - 78'],
    ],
  ];

  @override
  Widget build(BuildContext context) {
    final headers = _headers[_tab];
    final rows = _rows[_tab];

    return Scaffold(
      appBar: AppBar(title: const Text('PANDUAN UKURAN')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
              children: [
                SegmentedButton<int>(
                  segments: [
                    for (var i = 0; i < _tabs.length; i++)
                      ButtonSegment<int>(value: i, label: Text(_tabs[i])),
                  ],
                  selected: {_tab},
                  onSelectionChanged: (value) =>
                      setState(() => _tab = value.first),
                ),
                const SizedBox(height: 16),
                SurfaceCard(
                  padding: EdgeInsets.zero,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Table(
                      columnWidths: const {0: FixedColumnWidth(72)},
                      border: const TableBorder(
                        horizontalInside: BorderSide(color: AppColors.line),
                      ),
                      children: [
                        TableRow(
                          decoration: const BoxDecoration(color: AppColors.ink),
                          children: [
                            for (final h in headers) _cell(h, header: true),
                          ],
                        ),
                        for (final row in rows)
                          TableRow(
                            children: [
                              for (var i = 0; i < row.length; i++)
                                _cell(row[i], bold: i == 0),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const SurfaceCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Cara mengukur',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                      SizedBox(height: 8),
                      _Tip(
                        icon: Icons.straighten,
                        text: 'Dada: ukur bagian terlebar, pita sejajar lantai.',
                      ),
                      _Tip(
                        icon: Icons.accessibility_new,
                        text: 'Pinggang: ukur bagian terkecil, di atas pusar.',
                      ),
                      _Tip(
                        icon: Icons.height,
                        text: 'Bila di antara dua ukuran, pilih yang lebih '
                            'besar untuk potongan longgar.',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Tabel ini panduan umum untuk tugas aplikasi dan bukan '
                  'tabel resmi UNIQLO. Selalu cek label ukuran pada produk.',
                  style: TextStyle(color: AppColors.muted, fontSize: 11.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _cell(String text, {bool header = false, bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      child: Text(
        text,
        style: TextStyle(
          fontSize: header ? 11.5 : 13,
          fontWeight: header || bold ? FontWeight.w800 : FontWeight.w500,
          color: header ? Colors.white : AppColors.ink,
        ),
      ),
    );
  }
}

class _Tip extends StatelessWidget {
  const _Tip({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.red),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 12.5, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}
