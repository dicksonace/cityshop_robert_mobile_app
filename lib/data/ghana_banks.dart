/// Ghana bank options for wallet withdrawals (buyer + seller).
class GhanaBank {
  const GhanaBank(this.id, this.label);
  final String id;
  final String label;
}

const ghanaBanks = <GhanaBank>[
  GhanaBank('absa', 'ABSA'),
  GhanaBank('access', 'Access Bank'),
  GhanaBank('adb', 'ADB'),
  GhanaBank('adehyeman', 'ADEHYEMAN'),
  GhanaBank('advans', 'ADVANS GHANA'),
  GhanaBank('affinity', 'AFFINITY'),
  GhanaBank('arb_apex', 'ARB APEX BANK'),
  GhanaBank('bank_of_africa', 'BANK of Africa'),
  GhanaBank('bayport', 'Bayport S&L'),
  GhanaBank('bestpoint', 'BESTPOINT'),
  GhanaBank('bog', 'BoG'),
  GhanaBank('cal', 'CAL Bank'),
  GhanaBank('cbg', 'CBG'),
  GhanaBank('ecobank', 'Ecobank'),
  GhanaBank('fidelity', 'Fidelity Bank'),
  GhanaBank('firstbank', 'FirstBank'),
  GhanaBank('fnb', 'FNB'),
  GhanaBank('gcb', 'GCB'),
  GhanaBank('gtbank', 'GT Bank'),
  GhanaBank('letshego', 'LETSHEGO'),
  GhanaBank('nib', 'NIB'),
  GhanaBank('omnibsic', 'OMNIBSIC'),
  GhanaBank('opportunity', 'Opportunity Int. S&L'),
  GhanaBank('prudential', 'Prudential Bank'),
  GhanaBank('service_integrity', 'Service Integrity S&L'),
  GhanaBank('sinapi_aba', 'Sinapi ABA'),
  GhanaBank('societe_generale', 'SOCIETE GENERALE'),
  GhanaBank('stanbic', 'Stanbic'),
  GhanaBank('standard_chartered', 'Standard Chartered'),
  GhanaBank('transflow', 'TransFlow'),
  GhanaBank('uba', 'UBA'),
  GhanaBank('umb', 'UMB'),
  GhanaBank('zenith', 'Zenith Bank'),
];

String ghanaBankLabel(String? id) {
  if (id == null || id.isEmpty) return 'Bank';
  for (final bank in ghanaBanks) {
    if (bank.id == id) return bank.label;
  }
  return id.replaceAll('_', ' ');
}

bool isGhanaBank(String? id) => ghanaBanks.any((b) => b.id == id);

String payoutNetworkLabel(String? network) {
  if (network == null || network.isEmpty) return '—';
  switch (network) {
    case 'mtn':
      return 'MTN Mobile Money';
    case 'telecel':
      return 'Telecel Cash';
    case 'airteltigo':
      return 'AirtelTigo Money';
    default:
      return isGhanaBank(network) ? ghanaBankLabel(network) : network.replaceAll('_', ' ');
  }
}
