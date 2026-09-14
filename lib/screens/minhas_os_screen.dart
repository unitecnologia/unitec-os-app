import 'package:flutter/material.dart';
import 'package:unitec_os_app/config/app_version.dart';
import 'package:unitec_os_app/models/ordem_servico.dart';
import 'package:unitec_os_app/screens/detalhe_os_screen.dart';
import 'package:unitec_os_app/screens/login_screen.dart';
import 'package:unitec_os_app/screens/nova_os_screen.dart';
import 'package:unitec_os_app/services/api_client.dart';
import 'package:unitec_os_app/services/auth_service.dart';
import 'package:unitec_os_app/services/os_service.dart';
import 'package:unitec_os_app/services/sync_service.dart';
import 'package:unitec_os_app/session/app_session.dart';
import 'package:unitec_os_app/theme/app_theme.dart';

class MinhasOsScreen extends StatefulWidget {
  const MinhasOsScreen({super.key});

  static const route = '/minhas-os';

  @override
  State<MinhasOsScreen> createState() => _MinhasOsScreenState();
}

class _MinhasOsScreenState extends State<MinhasOsScreen> {
  final _osService = OsService();
  final _auth = AuthService();
  final _sync = SyncService.instance;

  String _filtro = 'Todas';
  DateTime _filtroData = DateTime(
    DateTime.now().year,
    DateTime.now().month,
    DateTime.now().day,
  );
  List<OrdemServico> _todas = [];
  bool _carregando = true;
  String? _erro;

  List<OrdemServico> get _listaDoDia =>
      _todas.where((os) => _dataHoraNoDia(os.dataHora, _filtroData)).toList();

  List<OrdemServico> get _lista {
    if (_filtro == 'Todas') return _listaDoDia;
    return _listaDoDia.where((os) => os.status == _filtro).toList();
  }

  int _contar(String status) =>
      _listaDoDia.where((os) => os.status == status).length;

  String get _filtroDataLabel {
    final d = _filtroData.day.toString().padLeft(2, '0');
    final m = _filtroData.month.toString().padLeft(2, '0');
    return '$d/$m/${_filtroData.year}';
  }

  @override
  void initState() {
    super.initState();
    _sync.addListener(_onSyncChanged);
    _carregar(tentarSync: true);
  }

  @override
  void dispose() {
    _sync.removeListener(_onSyncChanged);
    super.dispose();
  }

  void _onSyncChanged() {
    if (!mounted) return;
    if (_sync.syncing) {
      setState(() {});
      return;
    }
    _carregar(tentarSync: false);
  }

  Future<void> _carregar({bool tentarSync = false}) async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final lista = await _osService.listarMinhas(tentarSync: tentarSync);
      if (!mounted) return;
      setState(() {
        _todas = lista;
        _carregando = false;
      });
    } on ApiException catch (e) {
      final lista = await _osService.listarMinhas(tentarSync: false);
      if (!mounted) return;
      setState(() {
        _todas = lista;
        _erro = lista.isEmpty ? e.message : null;
        _carregando = false;
      });
      if (e.statusCode == 401 && lista.isEmpty) {
        await _sair();
      }
    } catch (_) {
      final lista = await _osService.listarMinhas(tentarSync: false);
      if (!mounted) return;
      setState(() {
        _todas = lista;
        _erro = lista.isEmpty ? 'Falha ao carregar as OS.' : null;
        _carregando = false;
      });
    }
  }

  Future<void> _sincronizar() async {
    final result = await _sync.tentarSincronizar();
    await _carregar(tentarSync: false);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.ok
              ? (result.pending > 0
                  ? 'Sync parcial: ${result.pending} pendente(s).'
                  : 'Sincronizado (${result.pulled} OS).')
              : (result.message ?? 'Falha ao sincronizar.'),
        ),
      ),
    );
  }

  Future<void> _sair() async {
    await _auth.logout();
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed(LoginScreen.route);
  }

  Future<void> _escolherData() async {
    final escolhida = await showDatePicker(
      context: context,
      initialDate: _filtroData,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (escolhida == null || !mounted) return;
    setState(() {
      _filtroData = DateTime(escolhida.year, escolhida.month, escolhida.day);
    });
  }

  Color _corStatus(String status) {
    switch (status) {
      case 'Pendente':
        return const Color(0xFFB45309);
      case 'Em andamento':
        return AppTheme.primaryBlue;
      case 'Em faturamento':
        return const Color(0xFF9A3412);
      case 'Finalizada':
        return const Color(0xFF15803D);
      default:
        return AppTheme.muted;
    }
  }

  @override
  Widget build(BuildContext context) {
    final pending = _sync.pending;
    final online = _sync.online;
    final verificando = _sync.verificando;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Olá, ${AppSession.usuario}'),
            Text(
              'Unitec OS • v${AppVersion.label}',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Colors.white70,
              ),
            ),
          ],
        ),
        actions: [
          if (pending > 0)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Center(
                child: Text(
                  '$pending',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: Color(0xFFB45309),
                  ),
                ),
              ),
            ),
          IconButton(
            tooltip: verificando
                ? 'Verificando se o ERP responde'
                : online
                    ? 'Sincronizar'
                    : 'ERP offline — toque para tentar de novo',
            onPressed: _sync.syncing || verificando ? null : _sincronizar,
            icon: _sync.syncing || verificando
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : Icon(online ? Icons.sync : Icons.cloud_off_outlined),
          ),
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _carregando ? null : () => _carregar(tentarSync: true),
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Sair',
            onPressed: _sair,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppTheme.primaryBlue,
        foregroundColor: Colors.white,
        onPressed: () async {
          await Navigator.of(context).pushNamed(NovaOsScreen.route);
          if (mounted) _carregar(tentarSync: false);
        },
        icon: const Icon(Icons.add),
        label: const Text('Nova OS'),
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : _erro != null && _todas.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_erro!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        ElevatedButton(
                          onPressed: () => _carregar(tentarSync: true),
                          child: const Text('Tentar novamente'),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () => _carregar(tentarSync: true),
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
                    children: [
                      if (!online || verificando || pending > 0)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Material(
                            color: const Color(0xFFFFF7ED),
                            borderRadius: BorderRadius.circular(8),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              child: Text(
                                verificando
                                    ? 'Verificando se o ERP responde…'
                                    : !online
                                        ? (_sync.semRede
                                            ? 'Sem internet — as OS ficam salvas neste celular.'
                                            : 'Internet no celular, mas o ERP não respondeu. Trabalho local continua.')
                                        : '$pending alteração(ões) aguardando sync.',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFFB45309),
                                ),
                              ),
                            ),
                          ),
                        ),
                      Row(
                        children: [
                          Expanded(
                            child: _ResumoCard(
                              titulo: 'Pendentes',
                              valor: _contar('Pendente').toString(),
                              cor: const Color(0xFFB45309),
                              ativo: _filtro == 'Pendente',
                              onTap: () => setState(() {
                                _filtro = _filtro == 'Pendente' ? 'Todas' : 'Pendente';
                              }),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _ResumoCard(
                              titulo: 'Em andamento',
                              valor: _contar('Em andamento').toString(),
                              cor: AppTheme.primaryBlue,
                              ativo: _filtro == 'Em andamento',
                              onTap: () => setState(() {
                                _filtro =
                                    _filtro == 'Em andamento' ? 'Todas' : 'Em andamento';
                              }),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _ResumoCard(
                              titulo: 'Faturamento',
                              valor: _contar('Em faturamento').toString(),
                              cor: const Color(0xFF9A3412),
                              ativo: _filtro == 'Em faturamento',
                              onTap: () => setState(() {
                                _filtro = _filtro == 'Em faturamento'
                                    ? 'Todas'
                                    : 'Em faturamento';
                              }),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _ResumoCard(
                              titulo: 'Finalizadas',
                              valor: _contar('Finalizada').toString(),
                              cor: const Color(0xFF15803D),
                              ativo: _filtro == 'Finalizada',
                              onTap: () => setState(() {
                                _filtro =
                                    _filtro == 'Finalizada' ? 'Todas' : 'Finalizada';
                              }),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Material(
                        color: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: const BorderSide(color: AppTheme.border),
                        ),
                        child: InkWell(
                          onTap: _escolherData,
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.calendar_today_outlined,
                                  size: 18,
                                  color: AppTheme.primaryBlue,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  _filtroDataLabel,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.text,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (_lista.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 40),
                          child: Center(
                            child: Text(
                              'Nenhuma OS nesta data.',
                              style: TextStyle(color: AppTheme.muted),
                            ),
                          ),
                        )
                      else
                        ..._lista.map((os) {
                          final detalhe = os.equipamento.trim().isNotEmpty
                              ? os.equipamento.trim()
                              : os.servico.trim();
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Card(
                              child: InkWell(
                                borderRadius: BorderRadius.circular(10),
                                onTap: () async {
                                  await Navigator.of(context).pushNamed(
                                    DetalheOsScreen.route,
                                    arguments: os.key,
                                  );
                                  if (mounted) _carregar(tentarSync: false);
                                },
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            'OS ${os.numeroExibicao}',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w800,
                                              fontSize: 13,
                                              color: AppTheme.text,
                                            ),
                                          ),
                                          if (os.pendingSync) ...[
                                            const SizedBox(width: 4),
                                            const Icon(
                                              Icons.cloud_upload_outlined,
                                              size: 14,
                                              color: Color(0xFFB45309),
                                            ),
                                          ],
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 1,
                                            ),
                                            decoration: BoxDecoration(
                                              color: _corStatus(os.status)
                                                  .withValues(alpha: 0.12),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              os.status,
                                              style: TextStyle(
                                                color: _corStatus(os.status),
                                                fontWeight: FontWeight.w700,
                                                fontSize: 10,
                                              ),
                                            ),
                                          ),
                                          const Spacer(),
                                          Text(
                                            _horaLista(os.dataHora),
                                            style: const TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: AppTheme.muted,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        os.cliente,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13,
                                        ),
                                      ),
                                      if (detalhe.isNotEmpty) ...[
                                        const SizedBox(height: 1),
                                        Text(
                                          detalhe,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: AppTheme.muted,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        }),
                    ],
                  ),
                ),
    );
  }
}

/// O dia já está no filtro. Na lista mostra só o horário.
String _horaLista(String dataHora) {
  final partes = dataHora.trim().split(RegExp(r'\s+'));
  if (partes.length >= 2 && partes.last.contains(':')) return partes.last;
  return dataHora;
}

/// Compara `dataHora` (`dd/MM/yyyy HH:mm` ou `dd/MM HH:mm`) com o dia filtrado.
bool _dataHoraNoDia(String dataHora, DateTime dia) {
  final partesEspaco = dataHora.trim().split(RegExp(r'\s+'));
  if (partesEspaco.isEmpty) return false;
  final parteData = partesEspaco.first;
  if (parteData.isEmpty) return false;

  final partes = parteData.split('/');
  if (partes.length < 2 || partes.length > 3) return false;

  final diaOs = int.tryParse(partes[0]);
  final mesOs = int.tryParse(partes[1]);
  if (diaOs == null || mesOs == null) return false;
  if (diaOs != dia.day || mesOs != dia.month) return false;

  if (partes.length == 3) {
    final anoOs = int.tryParse(partes[2]);
    if (anoOs == null || anoOs != dia.year) return false;
  }

  return true;
}

class _ResumoCard extends StatelessWidget {
  const _ResumoCard({
    required this.titulo,
    required this.valor,
    required this.cor,
    required this.ativo,
    required this.onTap,
  });

  final String titulo;
  final String valor;
  final Color cor;
  final bool ativo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: ativo ? cor : AppTheme.border,
          width: ativo ? 1.6 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          child: Column(
            children: [
              Text(
                valor,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: cor,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                titulo,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
