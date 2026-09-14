import 'package:flutter_test/flutter_test.dart';
import 'package:unitec_os_app/config/erp_url.dart';

void main() {
  test('túnel sem protocolo vira https', () {
    expect(
      ErpUrl.normalize('abc.trycloudflare.com'),
      'https://abc.trycloudflare.com',
    );
    expect(
      ErpUrl.normalize('http://abc.trycloudflare.com'),
      'https://abc.trycloudflare.com',
    );
    expect(
      ErpUrl.normalize('nome.cfargotunnel.com'),
      'https://nome.cfargotunnel.com',
    );
    expect(
      ErpUrl.normalize('minimercadoayalamatriz.unierp.uk'),
      'https://minimercadoayalamatriz.unierp.uk',
    );
  });

  test('unierp.uk com :8000 remove a porta', () {
    expect(
      ErpUrl.normalize('https://minimercadoayalamatriz.unierp.uk:8000'),
      'https://minimercadoayalamatriz.unierp.uk',
    );
    expect(
      ErpUrl.normalize('minimercadoayalamatriz.unierp.uk:8000'),
      'https://minimercadoayalamatriz.unierp.uk',
    );
  });

  test('túnel fora não troca a URL por localhost', () {
    const tunel = 'https://abc.trycloudflare.com';
    final candidatos = ErpUrl.candidatosProva(atual: tunel);

    expect(candidatos, [tunel]);
    expect(candidatos, isNot(contains('http://10.0.2.2:8000')));
    expect(candidatos, isNot(contains('http://127.0.0.1:8000')));
    expect(
      ErpUrl.aposTeste(anterior: tunel, tentada: tunel, respondeu: false),
      tunel,
    );
  });

  test('unierp.uk não cai para IP local', () {
    const tunel = 'https://minimercadoayalamatriz.unierp.uk';
    final candidatos = ErpUrl.candidatosProva(
      atual: 'http://192.168.0.10:8000',
      preferida: '$tunel:8000',
    );

    expect(candidatos, [tunel]);
    expect(ErpUrl.ehNuvemUrl(tunel), isTrue);
    expect(ErpUrl.ehPublicaUrl(tunel), isTrue);
  });

  test('URL nova inválida restaura a anterior válida', () {
    const anterior = 'https://abc.trycloudflare.com';
    const invalida = 'tunel-errado.trycloudflare.com';

    expect(
      ErpUrl.aposTeste(anterior: anterior, tentada: invalida, respondeu: false),
      anterior,
    );
    expect(
      ErpUrl.aposTeste(anterior: anterior, tentada: invalida, respondeu: true),
      'https://tunel-errado.trycloudflare.com',
    );
  });

  test('internet sem túnel deixa o ERP offline sem apagar a URL', () {
    expect(
      ErpUrl.avaliar(temInternet: true, apiRespondeu: false),
      ErpAlcance.offline,
    );
    expect(
      ErpUrl.avaliar(temInternet: false, apiRespondeu: null),
      ErpAlcance.offline,
    );
    expect(
      ErpUrl.avaliar(temInternet: true, apiRespondeu: true),
      ErpAlcance.online,
    );
    expect(
      ErpUrl.avaliar(temInternet: true, apiRespondeu: null),
      ErpAlcance.verificando,
    );
  });

  test('endereço local continua http', () {
    expect(ErpUrl.normalize('10.0.2.2:8000'), 'http://10.0.2.2:8000');
    expect(ErpUrl.normalize('127.0.0.1:8000'), 'http://127.0.0.1:8000');
  });
}
