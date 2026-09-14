import 'package:flutter_test/flutter_test.dart';
import 'package:unitec_os_app/services/whatsapp_contato.dart';

void main() {
  test('telefone brasileiro ganha DDI 55', () {
    expect(WhatsappContato.numero('(47) 99153-7403'), '5547991537403');
    expect(WhatsappContato.numero('(47)9153-7403'), '554791537403');
    expect(WhatsappContato.numero('5547991537403'), '5547991537403');
    expect(WhatsappContato.numero('—'), isNull);
  });
}
