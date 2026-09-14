/// Vínculo da OS local com a OS criada no ERP.
///
/// O UUID enviado é sempre o `local_uuid` de nascimento. Não se gera outro no sync.
class OsCreateVinculo {
  const OsCreateVinculo({
    required this.serverId,
    required this.numeroOficial,
  });

  final int serverId;
  final String numeroOficial;

  /// `201` e `200` têm o mesmo significado para o app: a OS já existe no ERP.
  static OsCreateVinculo? lerResposta(Map<String, dynamic> json) {
    final data = json['data'];
    if (data is! Map) return null;

    final rawId = data['id'];
    final serverId = rawId is int ? rawId : int.tryParse('$rawId');
    final numero = '${data['numero_os'] ?? ''}'.trim();
    if (serverId == null || serverId <= 0 || numero.isEmpty) return null;

    return OsCreateVinculo(serverId: serverId, numeroOficial: numero);
  }

  /// Monta o POST sem inventar UUID. [localUuid] é o da OS que já existe no aparelho.
  static Map<String, dynamic> corpo({
    required String localUuid,
    required String deviceUuid,
    required Map<String, dynamic> campos,
  }) {
    return {
      ...campos,
      'app_local_uuid': localUuid,
      'device_uuid': deviceUuid,
    };
  }
}
