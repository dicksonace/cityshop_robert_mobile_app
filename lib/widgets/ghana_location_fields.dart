import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Keep in sync with [App\Support\GhanaLocations] on the backend.
const kOtherCity = 'Other city';

const kGhanaRegionOrder = [
  'Greater Accra',
  'Ashanti',
  'Western',
  'Eastern',
  'Central',
  'Northern',
  'Upper East',
  'Upper West',
  'Volta',
  'Bono',
  'Western North',
  'Ahafo',
  'Bono East',
  'North East',
  'Savannah',
  'Oti',
];

const Map<String, List<String>> kGhanaCitiesByRegion = {
  'Greater Accra': [
    'Abeka', 'Ablekuma', 'Accra', 'Accra Central', 'Achimota', 'Adabraka', 'Adenta', 'Airport',
    'Amasaman', 'Ashaiman', 'Atomic', 'Avenor', 'Awoshie', 'Baatsona', 'Bubuashie', 'Cantonments',
    'Chorkor', 'Circle', 'Dansoman', 'Darkuman', 'Dawhenya', 'Dodowa', 'Dome', 'Dzorwulu',
    'East Legon', 'Gbawe', 'Haatso', 'Jamestown', 'Kanda', 'Kaneshie', 'Kasoa', 'Kokomlemle',
    'Korle Bu', 'Kwashieman', 'Labadi', 'Labone', 'Lapaz', 'Lashibi', 'Legon', 'Madina', 'Makola',
    'Mallam', 'Mamprobi', 'Mataheko', 'North Industrial Area', 'North Kaneshie', 'Nungua', 'Ofankor',
    'Osu', 'Oyarifa', 'Pokuase', 'Prampram', 'Ridge', 'Roman Ridge', 'Sakumono', 'Santa Maria',
    'South Industrial Area', 'Spintex', 'Spintex Road', 'Tema', 'Teshie', 'Teshie Nungua', 'Tesano',
    'Trasaco', 'Tudu', 'Usher Town', 'Weija', kOtherCity,
  ],
  'Ashanti': ['Kumasi', 'Obuasi', 'Ejisu', 'Konongo', 'Mampong', 'Bekwai', 'Offinso', kOtherCity],
  'Western': ['Takoradi', 'Sekondi', 'Tarkwa', 'Axim', kOtherCity],
  'Eastern': [
    'Aburi', 'Achiase', 'Adukrom', 'Akim Oda', 'Akosombo', 'Akropong', 'Akwatia', 'Akyem Hemang',
    'Amanokrom', 'Asamankese', 'Atimpoku', 'Begoro', 'Coaltar', 'Effiduase', 'Kibi', 'Koforidua',
    'Kpong', 'Mamfe', 'Mpraeso', 'New Tafo', 'Nkawkaw', 'Nkurakan', 'Nsawam', 'Oda', 'Oyoko',
    'Somanya', 'Suhum', kOtherCity,
  ],
  'Central': [
    'Abakrampa', 'Agona Swedru', 'Ajumako', 'Anomabo', 'Apam', 'Assin Fosu', 'Awutu Bereku',
    'Bremen Asikuma', 'Cape Coast', 'Dominase', 'Dunkwa-on-Offin', 'Elmina', 'Foso', 'Gomoa', 'Koaso',
    'Mankessim', 'Mumford', 'Nsuaem', 'Nyakrom', 'Saltpong', 'Twifo Praso', 'University of Cape Coast',
    'Winneba', 'Yamoransa', kOtherCity,
  ],
  'Northern': ['Tamale', 'Yendi', 'Savelugu', kOtherCity],
  'Upper East': [
    'Bawku', 'Binduri', 'Bolgatanga', 'Bongo', 'Garu', 'Navrongo', 'Paga', 'Pusiga', 'Pwalugu',
    'Telensi', 'Tempane', 'Tongo', 'Zebilla', 'Zuarungu', kOtherCity,
  ],
  'Upper West': ['Wa', 'Lawra', 'Nandom', 'Jirapa', kOtherCity],
  'Volta': ['Ho', 'Hohoe', 'Keta', 'Aflao', 'Kpandu', kOtherCity],
  'Bono': ['Sunyani', 'Berekum', 'Dormaa Ahenkro', 'Wenchi', kOtherCity],
  'Western North': [
    'Akontombra', 'Anhwinso', 'Asawinso', 'Bia', 'Bibiani', 'Bodi', 'Chirano', 'Dadieso', 'Debiso',
    'Enchi', 'Juaboso', 'Sefwi Awaso', 'Sefwi Bekwai', 'Sefwi Wiawso', kOtherCity,
  ],
  'Ahafo': [
    'Acherensua', 'Bechem', 'Duayaw Nkwanta', 'Goaso', 'Hwidiem', 'Kenyase', 'Kukuom', 'Mim',
    'Noberkwa', 'Sankore', 'Yamfo', kOtherCity,
  ],
  'Bono East': [
    'Abease', 'Amantin', 'Atebubu', 'Babatokuma', 'Jema', 'Kintampo', 'Kwame Danso', 'New Longoro',
    'Nkoranza', 'Nsuta', 'Prang', 'Techiman', 'Tuobodom', 'Yeji', kOtherCity,
  ],
  'North East': [
    'Bunkpurugu', 'Chereponi', 'Demon', 'Gambaga', 'Jimbale', 'Nakpanduri',
    'Nalerigu', 'Walewale', 'Wenchiki', 'Yunyoo', kOtherCity,
  ],
  'Savannah': [
    'Bole', 'Buipe', 'Canteen', 'Daboya', 'Damongo', 'Gbintiri', 'Grupe', 'Kalande',
    'Lungbunga', 'Salaga', 'Sawla', 'Tuna', 'Yapei', kOtherCity,
  ],
  'Oti': [
    'Akpafu', 'Brewaniase', 'Chinderi', 'Dambai', 'Jasikan', 'Kate krachi', 'Kpassa',
    'Krachi Nchumuru', 'Kwamekrom', 'Likpe', 'Lolobi', 'Nkwanta', 'Santrokofi',
    'Worawora', kOtherCity,
  ],
};

/// Bundled city lists are the source of truth for region/city pickers.
Map<String, List<String>> ghanaCitiesCatalog({Map<String, List<String>>? remote}) {
  final catalog = kGhanaCitiesByRegion.map(
    (key, value) => MapEntry(key, List<String>.from(value)),
  );

  if (remote == null) {
    return catalog;
  }

  // Only accept unknown regions from the API; never replace bundled lists.
  for (final entry in remote.entries) {
    if (!catalog.containsKey(entry.key) && entry.value.isNotEmpty) {
      catalog[entry.key] = List<String>.from(entry.value);
    }
  }

  return catalog;
}

List<String> ghanaRegions({Map<String, List<String>>? citiesByRegion}) {
  final source = ghanaCitiesCatalog(remote: citiesByRegion);
  final ordered = kGhanaRegionOrder.where(source.containsKey).toList();
  for (final key in source.keys) {
    if (!ordered.contains(key)) {
      ordered.add(key);
    }
  }
  return ordered;
}

List<String> ghanaCitiesForRegion(
  String region, {
  Map<String, List<String>>? citiesByRegion,
}) {
  final source = ghanaCitiesCatalog(remote: citiesByRegion);
  return List<String>.from(source[region] ?? const []);
}

bool ghanaCityIsCustom(String region, String city, {Map<String, List<String>>? citiesByRegion}) {
  if (city.trim().isEmpty) return false;
  return !ghanaCitiesForRegion(region, citiesByRegion: citiesByRegion).contains(city);
}

/// Searchable region + city pickers used on signup and saved addresses.
class GhanaLocationFields extends StatefulWidget {
  const GhanaLocationFields({
    super.key,
    required this.region,
    required this.city,
    required this.onRegionChanged,
    required this.onCityChanged,
  });

  final String region;
  final String city;
  final ValueChanged<String> onRegionChanged;
  final ValueChanged<String> onCityChanged;

  @override
  State<GhanaLocationFields> createState() => _GhanaLocationFieldsState();
}

class _GhanaLocationFieldsState extends State<GhanaLocationFields> {
  final _customCity = TextEditingController();
  bool _usingCustomCity = false;

  Map<String, List<String>> get _citiesByRegion => ghanaCitiesCatalog();

  @override
  void initState() {
    super.initState();
    _syncCustomCity();
  }

  @override
  void didUpdateWidget(covariant GhanaLocationFields oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.region != widget.region || oldWidget.city != widget.city) {
      _syncCustomCity();
    }
  }

  void _syncCustomCity() {
    final custom = ghanaCityIsCustom(widget.region, widget.city, citiesByRegion: _citiesByRegion);
    _usingCustomCity = custom || widget.city == kOtherCity;
    _customCity.text = custom ? widget.city : '';
  }

  @override
  void dispose() {
    _customCity.dispose();
    super.dispose();
  }

  Future<void> _pickRegion() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _LocationPickerSheet(
        title: 'Region',
        searchHint: 'Search region',
        options: ghanaRegions(citiesByRegion: _citiesByRegion),
        selected: widget.region,
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _usingCustomCity = false;
      _customCity.clear();
    });
    widget.onRegionChanged(picked);
    widget.onCityChanged('');
  }

  Future<void> _pickCity() async {
    if (widget.region.trim().isEmpty) return;
    final options = ghanaCitiesForRegion(widget.region, citiesByRegion: _citiesByRegion);
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _LocationPickerSheet(
        title: 'City / Town',
        searchHint: 'Search city / town',
        options: options,
        selected: _usingCustomCity ? kOtherCity : widget.city,
      ),
    );
    if (picked == null || !mounted) return;
    if (picked == kOtherCity) {
      setState(() => _usingCustomCity = true);
      widget.onCityChanged('');
      return;
    }
    setState(() => _usingCustomCity = false);
    widget.onCityChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final regionLabel = widget.region.trim().isEmpty ? 'Select region' : widget.region;
    final cityLabel = widget.region.trim().isEmpty
        ? 'Select region first'
        : _usingCustomCity
            ? kOtherCity
            : widget.city.trim().isEmpty
                ? 'Select city / town'
                : widget.city;

    return Column(
      children: [
        _PickerField(
          label: 'Region',
          value: regionLabel,
          icon: Icons.map_outlined,
          enabled: true,
          onTap: _pickRegion,
        ),
        _PickerField(
          label: 'City / Town',
          value: cityLabel,
          icon: Icons.location_city_outlined,
          enabled: widget.region.trim().isNotEmpty,
          onTap: _pickCity,
        ),
        if (_usingCustomCity && widget.region.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Your city / town', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 6),
                TextField(
                  controller: _customCity,
                  decoration: const InputDecoration(
                    hintText: 'Type your city or town',
                    prefixIcon: Icon(Icons.edit_location_alt_outlined),
                  ),
                  onChanged: widget.onCityChanged,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _PickerField extends StatelessWidget {
  const _PickerField({
    required this.label,
    required this.value,
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final muted = value == 'Select region' ||
        value == 'Select city / town' ||
        value == 'Select region first';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(height: 6),
          InkWell(
            onTap: enabled ? onTap : null,
            borderRadius: BorderRadius.circular(12),
            child: InputDecorator(
              decoration: InputDecoration(
                prefixIcon: Icon(icon),
                suffixIcon: const Icon(Icons.keyboard_arrow_down_rounded),
                enabled: enabled,
              ),
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 16,
                  color: muted ? AppColors.textMuted : AppColors.textPrimary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LocationPickerSheet extends StatefulWidget {
  const _LocationPickerSheet({
    required this.title,
    required this.searchHint,
    required this.options,
    required this.selected,
  });

  final String title;
  final String searchHint;
  final List<String> options;
  final String selected;

  @override
  State<_LocationPickerSheet> createState() => _LocationPickerSheetState();
}

class _LocationPickerSheetState extends State<_LocationPickerSheet> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.text.trim().toLowerCase();
    final matches = widget.options
        .where((item) => q.isEmpty || item.toLowerCase().contains(q))
        .toList();
    final height = MediaQuery.sizeOf(context).height * 0.72;

    return SafeArea(
      child: SizedBox(
        height: height,
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFE5E7EB),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  widget.title,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                controller: _query,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: widget.searchHint,
                  prefixIcon: const Icon(Icons.search),
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: matches.length,
                itemBuilder: (context, index) {
                  final item = matches[index];
                  final selected = item == widget.selected;
                  return ListTile(
                    title: Text(
                      item,
                      style: TextStyle(
                        fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                      ),
                    ),
                    trailing: selected
                        ? const Icon(Icons.check_rounded, color: AppColors.accent)
                        : null,
                    onTap: () => Navigator.pop(context, item),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
