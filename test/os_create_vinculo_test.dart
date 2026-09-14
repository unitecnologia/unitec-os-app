import 'package:flutter_test/flutter_test.dart';
import 'package:unitec_os_app/services/os_create_vinculo.dart';

void main() {
  const localUuid = '11111111-1111-4111-8111-111111111111';
  const deviceUuid = 'android-aparelho-a';

  test('criação e retry usam o mesmo app_local_uuid', () {
    final campos = {'cliente': 'JOAO', 'numero': '100'};

    final primeiro = OsCreateVinculo.corpo(
      localUuid: localUuid,
      deviceUuid: deviceUuid,
      campos: campos,
    );
    final retry = OsCreateVinculo.corpo(
      localUuid: localUuid,
      deviceUuid: deviceUuid,
      campos: campos,
    );

    expect(primeiro['app_local_uuid'], localUuid);
    expect(retry['app_local_uuid'], primeiro['app_local_uuid']);
    expect(retry['device_uuid'], deviceUuid);
    expect(retry.containsKey('numero_os'), isFalse);
  });

  test('201 e 200 devolvem o mesmo server_id e numero oficial', () {
    final criada = OsCreateVinculo.lerResposta({
      'data': {'id': 150, 'numero_os': '150'},
    });
    final existente = OsCreateVinculo.lerResposta({
      'data': {'id': 150, 'numero_os': '150'},
    });

    expect(criada, isNotNull);
    expect(existente, isNotNull);
    expect(existente!.serverId, criada!.serverId);
    expect(existente.numeroOficial, '150');
    expect(existente.numeroOficial.startsWith('OFF-'), isFalse);
  });

  test('resposta sem id ou numero oficial não vincula', () {
    expect(OsCreateVinculo.lerResposta({'data': {'numero_os': '150'}}), isNull);
    expect(OsCreateVinculo.lerResposta({'data': {'id': 150}}), isNull);
  });
}
