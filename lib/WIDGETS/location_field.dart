import 'package:flutter/material.dart';

import '../MODELS/picked_location.dart';
import '../SCREENS/location_picker_page.dart';
import '../UTILS/app_theme.dart';

/// Kolom alamat yang diisi dengan memilih lokasi di peta. Ketuk kolom untuk
/// membuka peta. Alamat tetap bisa diedit di halaman peta.
///
/// [controller] menyimpan teks alamat; [location] adalah titik petanya
/// (null bila belum dipilih). Perubahan dikabarkan lewat [onChanged].
class LocationField extends StatelessWidget {
  const LocationField({
    super.key,
    required this.controller,
    required this.location,
    required this.onChanged,
    this.label = 'Alamat pengiriman (opsional)',
    this.validator,
    this.maxLines = 2,
  });

  final TextEditingController controller;
  final PickedLocation? location;
  final ValueChanged<PickedLocation?> onChanged;
  final String label;
  final FormFieldValidator<String>? validator;
  final int maxLines;

  Future<void> _pick(BuildContext context) async {
    final result = await Navigator.of(context).push<PickedLocation>(
      MaterialPageRoute(
        builder: (_) => LocationPickerPage(initial: location),
      ),
    );
    if (result == null) return;
    controller.text = result.address;
    onChanged(result);
  }

  @override
  Widget build(BuildContext context) {
    final pinned = location != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          controller: controller,
          readOnly: true,
          maxLines: maxLines,
          minLines: 1,
          validator: validator,
          onTap: () => _pick(context),
          decoration: InputDecoration(
            labelText: label,
            hintText: 'Ketuk untuk pilih lokasi di peta',
            prefixIcon: const Icon(Icons.location_on_outlined),
            suffixIcon: IconButton(
              tooltip: 'Pilih di peta',
              icon: const Icon(Icons.map_outlined),
              onPressed: () => _pick(context),
            ),
            border: const OutlineInputBorder(),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6, left: 4),
          child: Row(
            children: [
              Icon(
                pinned ? Icons.check_circle : Icons.info_outline,
                size: 14,
                color: pinned ? AppColors.success : AppColors.muted,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  pinned
                      ? 'Titik peta tersimpan (${location!.coordinateLabel})'
                      : 'Pilih lokasi lewat peta agar alamat akurat.',
                  style: const TextStyle(color: AppColors.muted, fontSize: 11.5),
                ),
              ),
              if (pinned)
                TextButton(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                  ),
                  onPressed: () {
                    controller.clear();
                    onChanged(null);
                  },
                  child: const Text('Hapus', style: TextStyle(fontSize: 12)),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
