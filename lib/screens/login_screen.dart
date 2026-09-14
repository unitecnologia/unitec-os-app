import 'dart:async';

import 'package:flutter/material.dart';
import 'package:unitec_os_app/config/api_config.dart';
import 'package:unitec_os_app/config/app_version.dart';
import 'package:unitec_os_app/screens/minhas_os_screen.dart';
import 'package:unitec_os_app/services/api_client.dart';
import 'package:unitec_os_app/services/auth_service.dart';
import 'package:unitec_os_app/services/sync_service.dart';
import 'package:unitec_os_app/session/app_session.dart';
import 'package:unitec_os_app/theme/app_theme.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  static const route = '/login';

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _auth = AuthService();
  final _url = TextEditingController(text: ApiConfig.erpBaseUrl);
  final _usuario = TextEditingController();
  final _senha = TextEditingController();

  bool _manterConectado = false;
  bool _carregando = false;
  bool _aparelhoAprovado = false;
  String? _pairingCode;
  String? _statusAparelho;
  String? _erro;

  List<EmpresaOption> _empresas = [];
  EmpresaOption? _empresa;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _url.dispose();
    _usuario.dispose();
    _senha.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _carregando = true;
      _erro = null;
      _manterConectado = AppSession.manterConectado;
    });

    if (AppSession.isLoggedIn && AppSession.manterConectado) {
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed(MinhasOsScreen.route);
      return;
    }

    try {
      final anterior = ApiConfig.erpBaseUrl;
      final found = await _auth.discoverDevServer(preferred: _url.text);
      if (found == null) {
        ApiConfig.setErpBaseUrl(anterior);
        _url.text = ApiConfig.erpBaseUrl;
        if (AppSession.isLoggedIn) {
          if (!mounted) return;
          setState(() {
            _carregando = false;
            _erro =
                'ERP offline. Você pode continuar com os dados locais '
                '(Entrar offline abaixo) ou aguardar a conexão.';
          });
          return;
        }
        setState(() {
          _erro =
              'ERP não respondeu.\n'
              'Toque na engrenagem para conferir a URL do servidor.';
          _carregando = false;
        });
        return;
      }
      _url.text = found;
      ApiConfig.setErpBaseUrl(found);
      await ApiConfig.saveUrl();
      await _registrarAparelho();
    } on ApiException catch (e) {
      setState(() {
        _erro = e.message;
        _carregando = false;
      });
    } catch (e) {
      setState(() {
        _erro = 'Falha ao conectar no ERP.\n$e';
        _carregando = false;
      });
    }
  }

  Future<void> _registrarAparelho() async {
    await DeviceIdentity.ensureReady();

    var status = await _auth.deviceStatus();
    if (status.status == 'desconhecido' || status.status == 'revogado') {
      status = await _auth.registerDevice();
    } else {
      status = await _auth.registerDevice();
    }

    await DeviceIdentity.setApproved(status.approved);

    if (!mounted) return;
    setState(() {
      _pairingCode = status.pairingCode;
      _statusAparelho = status.status;
      _aparelhoAprovado = status.approved;
      _carregando = false;
    });

    if (status.approved) {
      await _carregarEmpresas();
    } else {
      _iniciarPolling();
    }
  }

  void _iniciarPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (!SyncService.instance.podeTentarErp) return;
      try {
        final status = await _auth.deviceStatus();
        if (!mounted) return;
        setState(() {
          _pairingCode = status.pairingCode ?? _pairingCode;
          _statusAparelho = status.status;
          _aparelhoAprovado = status.approved;
        });
        if (status.approved) {
          await DeviceIdentity.setApproved(true);
          _poll?.cancel();
          await _carregarEmpresas();
        }
      } catch (_) {}
    });
  }

  Future<void> _carregarEmpresas() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final empresas = await _auth.listarEmpresas();
      if (!mounted) return;
      setState(() {
        _empresas = empresas;
        _empresa = empresas.length == 1 ? empresas.first : null;
        AppSession.empresaNome = _empresa?.nome;
        _carregando = false;
      });
    } on ApiException catch (e) {
      setState(() {
        _erro = e.message;
        _carregando = false;
      });
    } catch (_) {
      setState(() {
        _erro = 'Falha ao carregar empresas.';
        _carregando = false;
      });
    }
  }

  Future<void> _entrar() async {
    final usuario = _usuario.text.trim();
    final senha = _senha.text;
    final empresa = _empresa;

    if (!_aparelhoAprovado) {
      _toast('Aguarde a autorização do aparelho no ERP.');
      return;
    }
    if (empresa == null) {
      _toast('Selecione a empresa.');
      return;
    }
    if (usuario.isEmpty || senha.isEmpty) {
      _toast('Informe usuário e senha.');
      return;
    }

    setState(() => _carregando = true);
    final anterior = ApiConfig.erpBaseUrl;
    try {
      ApiConfig.setErpBaseUrl(_url.text);
      await _auth.login(
        usuario: usuario,
        senha: senha,
        empresaId: empresa.id,
      );
      AppSession.manterConectado = _manterConectado;
      AppSession.empresaNome = empresa.nome;
      await ApiConfig.saveUrl();
      await AppSession.persist();
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed(MinhasOsScreen.route);
    } on ApiException catch (e) {
      if (e.isOffline) {
        ApiConfig.setErpBaseUrl(anterior);
        _url.text = ApiConfig.erpBaseUrl;
        _toast('ERP não respondeu. A URL anterior foi mantida.');
      } else {
        _toast(e.message);
      }
    } catch (_) {
      ApiConfig.setErpBaseUrl(anterior);
      _url.text = ApiConfig.erpBaseUrl;
      _toast('ERP não respondeu. A URL anterior foi mantida.');
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _abrirConfiguracao() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 4,
            bottom: MediaQuery.viewInsetsOf(ctx).bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Configuração do servidor',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.text,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _url,
                enabled: !_carregando,
                decoration: InputDecoration(
                  labelText: 'URL do ERP',
                  hintText: 'https://abc.trycloudflare.com',
                  prefixIcon: const Icon(Icons.dns_outlined),
                  helperText:
                      'Endereço externo e túnel Cloudflare usam HTTPS.\n'
                      'Ex.: https://abc.trycloudflare.com',
                ),
                keyboardType: TextInputType.url,
                onSubmitted: (_) async {
                  Navigator.of(ctx).pop();
                  await _bootstrap();
                },
              ),
              const SizedBox(height: 8),
              Text(
                'Conectando em: ${ApiConfig.erpBaseUrl}',
                style: const TextStyle(fontSize: 12, color: AppTheme.muted),
              ),
              const SizedBox(height: 6),
              Text(
                'Versão ${AppVersion.label}',
                style: const TextStyle(fontSize: 12, color: AppTheme.muted),
              ),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: _carregando
                    ? null
                    : () async {
                        Navigator.of(ctx).pop();
                        await _bootstrap();
                      },
                icon: const Icon(Icons.sync),
                label: const Text('Conectar / atualizar aparelho'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'UNI SISTEMAS',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppTheme.primaryBlue,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Unitec OS',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppTheme.primaryBlueDark,
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Versão ${AppVersion.label}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppTheme.muted,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 22),
                      if (_erro != null) ...[
                        Text(
                          _erro!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Color(0xFFB45309)),
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (AppSession.isLoggedIn && !_aparelhoAprovado) ...[
                        ElevatedButton(
                          onPressed: _carregando
                              ? null
                              : () {
                                  Navigator.of(context)
                                      .pushReplacementNamed(MinhasOsScreen.route);
                                },
                          child: const Text('Continuar offline'),
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (!_aparelhoAprovado) ...[
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              children: [
                                const Text(
                                  'Aguardando autorização do aparelho',
                                  style: TextStyle(fontWeight: FontWeight.w800),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Código: ${_pairingCode ?? '—'}',
                                  style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w800,
                                    color: AppTheme.primaryBlue,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Aparelho: ${DeviceIdentity.shortId}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.muted,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Status: ${_statusAparelho ?? 'pendente'}',
                                  style: const TextStyle(color: AppTheme.muted),
                                ),
                                const SizedBox(height: 6),
                                const Text(
                                  'No ERP: Terminais → aba Aparelhos → Autorizar (F2).\n'
                                  'Valida 1 vez. O código não muda ao sair e voltar.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 12, color: AppTheme.muted),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ] else ...[
                        DropdownButtonFormField<EmpresaOption>(
                          key: ValueKey(_empresa?.id ?? 'empresa-none'),
                          initialValue: _empresa,
                          decoration: const InputDecoration(
                            labelText: 'Empresa',
                            prefixIcon: Icon(Icons.business_outlined),
                          ),
                          items: _empresas
                              .map(
                                (e) => DropdownMenuItem(
                                  value: e,
                                  child: Text(e.nome, overflow: TextOverflow.ellipsis),
                                ),
                              )
                              .toList(),
                          onChanged: _carregando
                              ? null
                              : (v) => setState(() {
                                    _empresa = v;
                                    AppSession.empresaNome = v?.nome;
                                  }),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _usuario,
                          enabled: !_carregando,
                          decoration: const InputDecoration(
                            labelText: 'Usuário',
                            prefixIcon: Icon(Icons.person_outline),
                          ),
                          textInputAction: TextInputAction.next,
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _senha,
                          enabled: !_carregando,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'Senha',
                            prefixIcon: Icon(Icons.lock_outline),
                          ),
                          onSubmitted: (_) {
                            if (!_carregando) _entrar();
                          },
                        ),
                        const SizedBox(height: 8),
                        CheckboxListTile(
                          value: _manterConectado,
                          onChanged: _carregando
                              ? null
                              : (v) => setState(() => _manterConectado = v ?? false),
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          dense: true,
                          title: const Text(
                            'Manter conectado',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                          ),
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton(
                          onPressed: _carregando ? null : _entrar,
                          child: _carregando
                              ? const SizedBox(
                                  height: 22,
                                  width: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.4,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text('Entrar'),
                        ),
                      ],
                      if (_carregando && !_aparelhoAprovado && _erro == null) ...[
                        const SizedBox(height: 16),
                        const Center(child: CircularProgressIndicator()),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: IconButton(
                tooltip: 'Configuração do servidor',
                onPressed: _carregando ? null : _abrirConfiguracao,
                icon: const Icon(Icons.settings_outlined),
                color: AppTheme.primaryBlue,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
